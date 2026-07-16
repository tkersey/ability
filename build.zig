// zlinter-disable require_doc_comment
const builtin = @import("builtin");
const package = @import("build.zig.zon");
const std = @import("std");
const zlinter = @import("zlinter");

const CoreModules = struct {
    boundary_build_metadata: *std.Build.Module,
    portable_core: *std.Build.Module,
    lowered_machine: *std.Build.Module,
    prompt_contract: *std.Build.Module,
    frontend: *std.Build.Module,
    effect_ir: *std.Build.Module,
    helper_body_ir: *std.Build.Module,
    internal_kernel: *std.Build.Module,
    internal_program_plan: *std.Build.Module,
    loaded_execution: *std.Build.Module,
    interpreter: *std.Build.Module,
    lowering_api: *std.Build.Module,
    parity_scenarios: *std.Build.Module,
};

const TestArgs = struct {
    filters: []const []const u8,
    passthrough: []const []const u8,
};

fn resolveExistingAbsolutePrefix(b: *std.Build, absolute_path: []const u8) []const u8 {
    std.debug.assert(std.Io.Dir.path.isAbsolute(absolute_path));
    var missing_components: std.ArrayList([]const u8) = .empty;
    defer missing_components.deinit(b.allocator);

    var existing_path = absolute_path;
    while (true) {
        const resolved = std.Io.Dir.realPathFileAbsoluteAlloc(
            b.graph.io,
            existing_path,
            b.allocator,
        ) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => {
                const component = std.Io.Dir.path.basename(existing_path);
                const parent = std.Io.Dir.path.dirname(existing_path) orelse
                    std.process.fatal("unable to resolve existing ancestor of '{s}'", .{absolute_path});
                if (component.len == 0) {
                    std.process.fatal("unable to resolve existing ancestor component of '{s}'", .{absolute_path});
                }
                missing_components.append(b.allocator, component) catch |append_err|
                    std.process.fatal("unable to retain unresolved path component: {s}", .{@errorName(append_err)});
                existing_path = parent;
                continue;
            },
            else => std.process.fatal(
                "unable to resolve existing ancestor of '{s}': {s}",
                .{ absolute_path, @errorName(err) },
            ),
        };

        var parts: std.ArrayList([]const u8) = .empty;
        defer parts.deinit(b.allocator);
        parts.append(b.allocator, resolved) catch |err|
            std.process.fatal("unable to retain resolved path prefix: {s}", .{@errorName(err)});
        var index = missing_components.items.len;
        while (index > 0) {
            index -= 1;
            parts.append(b.allocator, missing_components.items[index]) catch |err|
                std.process.fatal("unable to retain resolved path suffix: {s}", .{@errorName(err)});
        }
        return b.pathResolve(parts.items);
    }
}

fn canonicalizeBuildOwnedCachePath(b: *std.Build, cache_path: []const u8) []const u8 {
    const absolute_cache_path = if (std.Io.Dir.path.isAbsolute(cache_path))
        cache_path
    else
        b.pathResolve(&.{ b.graph.cache.cwd, cache_path });

    return resolveExistingAbsolutePrefix(b, absolute_cache_path);
}

fn canonicalizeBuildOwnedCacheRoots(b: *std.Build) void {
    // Generated LazyPaths carry this spelling into no-follow oracle readers.
    // Canonicalize only the two build-owned cache carriers; receiver-supplied
    // paths retain their original admission semantics.
    if (b.cache_root.path) |path| {
        b.cache_root.path = canonicalizeBuildOwnedCachePath(b, path);
    }
    if (b.graph.global_cache_root.path) |path| {
        b.graph.global_cache_root.path = canonicalizeBuildOwnedCachePath(b, path);
    }
}

const ExactInstallTreeStep = struct {
    step: std.Build.Step,
    source_dir: std.Build.LazyPath,
    destination_path: []const u8,
    protected_path: []const u8,

    const FileIdentity = struct {
        device: u128,
        inode: u128,
    };

    const public_dir_permissions: std.Io.Dir.Permissions = if (std.Io.Dir.Permissions.has_executable_bit)
        .fromMode(0o755)
    else
        .default_dir;

    const public_file_permissions: std.Io.File.Permissions = if (std.Io.File.Permissions.has_executable_bit)
        .fromMode(0o644)
    else
        .default_file;

    const private_dir_permissions: std.Io.Dir.Permissions = if (std.Io.Dir.Permissions.has_executable_bit)
        .fromMode(0o700)
    else
        .default_dir;

    const maximum_cleanup_depth: usize = 32;
    const max_cleanup_open_directories: usize = maximum_cleanup_depth + 1;
    const maximum_cleanup_entries: usize = 4096;

    const CleanupBudget = struct {
        remaining_entries: usize = maximum_cleanup_entries,

        fn consumeEntry(budget: *@This()) !void {
            if (budget.remaining_entries == 0) {
                return error.OracleCleanupWorkLimitExceeded;
            }
            budget.remaining_entries -= 1;
        }
    };

    const CleanupTraversal = struct {
        protected_identities: []const FileIdentity,
        current_depth: usize,
        budget: *CleanupBudget,
    };

    fn create(
        b: *std.Build,
        source_dir: std.Build.LazyPath,
        destination_path: []const u8,
        protected_path: []const u8,
    ) *@This() {
        std.debug.assert(std.Io.Dir.path.isAbsolute(destination_path));
        std.debug.assert(std.Io.Dir.path.isAbsolute(protected_path));
        const exact_tree = b.allocator.create(@This()) catch |err|
            std.process.fatal("unable to allocate exact install-tree step: {s}", .{@errorName(err)});
        exact_tree.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "replace exact emitted Boundary oracle tree",
                .owner = b,
                .makeFn = make,
            }),
            .source_dir = source_dir.dupe(b),
            .destination_path = b.dupePath(destination_path),
            .protected_path = b.dupePath(protected_path),
        };
        source_dir.addStepDependencies(&exact_tree.step);
        return exact_tree;
    }

    fn pathComponentEql(lhs: []const u8, rhs: []const u8) bool {
        return if (builtin.os.tag == .windows)
            std.ascii.eqlIgnoreCase(lhs, rhs)
        else
            std.mem.eql(u8, lhs, rhs);
    }

    fn pathContainsOrEquals(ancestor: []const u8, descendant: []const u8) bool {
        var ancestor_components = std.Io.Dir.path.componentIterator(ancestor);
        var descendant_components = std.Io.Dir.path.componentIterator(descendant);
        const ancestor_root = ancestor_components.root() orelse return false;
        const descendant_root = descendant_components.root() orelse return false;
        if (!pathComponentEql(ancestor_root, descendant_root)) return false;

        while (ancestor_components.next()) |ancestor_component| {
            const descendant_component = descendant_components.next() orelse return false;
            if (!pathComponentEql(ancestor_component.name, descendant_component.name)) return false;
        }
        return true;
    }

    fn directoryIdentity(dir: std.Io.Dir) !FileIdentity {
        return switch (builtin.os.tag) {
            .windows => windowsDirectoryIdentity(dir),
            .linux => linuxDirectoryIdentity(dir),
            .wasi => wasiDirectoryIdentity(dir),
            else => posixDirectoryIdentity(dir),
        };
    }

    fn identityMatchesAny(identity: FileIdentity, identities: []const FileIdentity) bool {
        for (identities) |candidate| {
            if (std.meta.eql(identity, candidate)) return true;
        }
        return false;
    }

    fn testFileIdentityComparison() !void {
        const identity = FileIdentity{ .device = 7, .inode = 11 };
        try std.testing.expect(std.meta.eql(identity, identity));
        try std.testing.expect(!std.meta.eql(identity, .{ .device = 7, .inode = 12 }));
    }

    fn testLinuxStatxIdentityObservation() !void {
        const cwd = std.Io.Dir.cwd();
        const first = try linuxDirectoryIdentity(cwd);
        const second = try linuxDirectoryIdentity(cwd);
        try std.testing.expect(std.meta.eql(first, second));
    }

    fn windowsDirectoryIdentity(dir: std.Io.Dir) !FileIdentity {
        const windows = std.os.windows;
        var io_status = std.mem.zeroes(windows.IO_STATUS_BLOCK);
        var volume_info = std.mem.zeroes(windows.FILE.FS_VOLUME_INFORMATION);
        switch (windows.ntdll.NtQueryVolumeInformationFile(
            dir.handle,
            &io_status,
            &volume_info,
            @sizeOf(windows.FILE.FS_VOLUME_INFORMATION),
            .Volume,
        )) {
            .SUCCESS, .BUFFER_OVERFLOW => {},
            else => return error.OracleFileIdentityUnavailable,
        }

        var internal_info = std.mem.zeroes(windows.FILE.INTERNAL_INFORMATION);
        switch (windows.ntdll.NtQueryInformationFile(
            dir.handle,
            &io_status,
            &internal_info,
            @sizeOf(windows.FILE.INTERNAL_INFORMATION),
            .Internal,
        )) {
            .SUCCESS => {},
            else => return error.OracleFileIdentityUnavailable,
        }
        return .{
            .device = volume_info.VolumeSerialNumber,
            .inode = @as(u64, @bitCast(internal_info.IndexNumber)),
        };
    }

    fn linuxDirectoryIdentity(dir: std.Io.Dir) !FileIdentity {
        const linux = std.os.linux;
        var statx = std.mem.zeroes(linux.Statx);
        while (true) switch (linux.errno(linux.statx(
            dir.handle,
            "",
            linux.AT.EMPTY_PATH,
            linux.STATX.BASIC_STATS,
            &statx,
        ))) {
            .SUCCESS => return linuxStatxIdentity(statx),
            .INTR => continue,
            // Zig 0.16 intentionally omits Linux stat/fstat types. Without a
            // supported same-representation fallback, publication fails
            // closed when statx is unavailable or denied.
            .NOSYS, .PERM, .ACCES => return error.OracleFileIdentityUnavailable,
            else => return error.OracleFileIdentityUnavailable,
        };
    }

    fn linuxStatxIdentity(statx: std.os.linux.Statx) !FileIdentity {
        if (!statx.mask.INO) return error.OracleFileIdentityUnavailable;
        return .{
            .device = (@as(u128, statx.dev_major) << 32) | statx.dev_minor,
            .inode = statx.ino,
        };
    }

    fn wasiDirectoryIdentity(dir: std.Io.Dir) !FileIdentity {
        const wasi = std.os.wasi;
        var stat = std.mem.zeroes(wasi.filestat_t);
        if (wasi.fd_filestat_get(dir.handle, &stat) != .SUCCESS) {
            return error.OracleFileIdentityUnavailable;
        }
        return .{
            .device = stat.dev,
            .inode = stat.ino,
        };
    }

    fn posixDirectoryIdentity(dir: std.Io.Dir) !FileIdentity {
        var stat = std.mem.zeroes(std.c.Stat);
        while (true) switch (std.c.errno(std.c.fstat(dir.handle, &stat))) {
            .SUCCESS => return .{
                .device = @intCast(stat.dev),
                .inode = @intCast(stat.ino),
            },
            .INTR => continue,
            else => return error.OracleFileIdentityUnavailable,
        };
    }

    const ResolvedDestinationDir = struct {
        dir: std.Io.Dir,
        followed_link: bool,
    };

    fn openDestinationDir(parent: std.Io.Dir, io: std.Io, name: []const u8) !ResolvedDestinationDir {
        const dir = parent.openDir(io, name, .{
            .iterate = false,
            .follow_symlinks = false,
        }) catch |open_err| switch (open_err) {
            error.NotDir, error.SymLinkLoop => return .{
                .dir = try parent.openDir(io, name, .{
                    .iterate = false,
                    .follow_symlinks = true,
                }),
                .followed_link = true,
            },
            else => return open_err,
        };
        return .{ .dir = dir, .followed_link = false };
    }

    fn discardPreparedDestinationDir(
        parent: std.Io.Dir,
        io: std.Io,
        private_name: []const u8,
        private_identity: FileIdentity,
        private_dir: std.Io.Dir,
    ) !void {
        private_dir.close(io);
        try cleanupEmptyContainerName(parent, io, private_name, private_identity);
    }

    fn preserveDestinationSetupPrimaryError(
        private_name: []const u8,
        primary_error: anyerror,
        cleanup_result: anyerror!void,
    ) anyerror {
        cleanup_result catch |cleanup_error| std.debug.print(
            "exact oracle destination setup failed with {s}; cleanup of private directory '{s}' also failed with {s} and residue may remain\n",
            .{ @errorName(primary_error), private_name, @errorName(cleanup_error) },
        );
        return primary_error;
    }

    const darwin_rename = struct {
        extern "c" fn renameatx_np(
            old_dir: std.posix.fd_t,
            old_path: [*:0]const u8,
            new_dir: std.posix.fd_t,
            new_path: [*:0]const u8,
            flags: c_uint,
        ) c_int;
    };

    fn darwinRenameDirectoryPreserve(
        old_dir: std.Io.Dir,
        old_name: []const u8,
        new_dir: std.Io.Dir,
        new_name: []const u8,
    ) std.Io.Dir.RenamePreserveError!void {
        const old_path = try std.posix.toPosixPath(old_name);
        const new_path = try std.posix.toPosixPath(new_name);
        while (true) switch (std.c.errno(darwin_rename.renameatx_np(
            old_dir.handle,
            &old_path,
            new_dir.handle,
            &new_path,
            0x00000004, // RENAME_EXCL
        ))) {
            .SUCCESS => return,
            .INTR => continue,
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .BUSY => return error.FileBusy,
            .DQUOT => return error.DiskQuota,
            .ISDIR => return error.IsDir,
            .IO => return error.HardwareFailure,
            .LOOP => return error.SymLinkLoop,
            .MLINK => return error.LinkQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .EXIST, .NOTEMPTY => return error.PathAlreadyExists,
            .ROFS => return error.ReadOnlyFileSystem,
            .XDEV => return error.CrossDevice,
            .NODEV => return error.NoDevice,
            .OPNOTSUPP => return error.OperationUnsupported,
            .ILSEQ => return error.BadPathName,
            else => |err| return std.posix.unexpectedErrno(err),
        };
    }

    fn renameDirectoryPreserve(
        old_dir: std.Io.Dir,
        old_name: []const u8,
        new_dir: std.Io.Dir,
        new_name: []const u8,
        io: std.Io,
    ) std.Io.Dir.RenamePreserveError!void {
        if (comptime builtin.os.tag.isDarwin()) {
            return darwinRenameDirectoryPreserve(old_dir, old_name, new_dir, new_name);
        }
        return switch (builtin.os.tag) {
            .linux, .windows => old_dir.renamePreserve(old_name, new_dir, new_name, io),
            else => error.OperationUnsupported,
        };
    }

    fn isDestinationCollisionError(err: anyerror) bool {
        return switch (err) {
            error.PathAlreadyExists, error.DirNotEmpty => true,
            else => false,
        };
    }

    fn renameEntryNoReplace(
        old_dir: std.Io.Dir,
        old_name: []const u8,
        new_dir: std.Io.Dir,
        new_name: []const u8,
        io: std.Io,
    ) !void {
        renameDirectoryPreserve(old_dir, old_name, new_dir, new_name, io) catch |err| switch (err) {
            error.PathAlreadyExists, error.DirNotEmpty => return error.OraclePublicationConflict,
            error.AccessDenied, error.IsDir, error.NotDir => {
                _ = new_dir.statFile(io, new_name, .{ .follow_symlinks = false }) catch return err;
                return error.OraclePublicationConflict;
            },
            else => return err,
        };
    }

    const PreparedDestinationDir = struct {
        name: []const u8,
        identity: FileIdentity,
        dir: std.Io.Dir,
    };

    fn installPreparedDestinationDir(
        parent: std.Io.Dir,
        io: std.Io,
        name: []const u8,
        prepared: PreparedDestinationDir,
    ) !ResolvedDestinationDir {
        renameDirectoryPreserve(parent, prepared.name, parent, name, io) catch |rename_err| {
            if (isDestinationCollisionError(rename_err)) {
                const receiver_dir = openDestinationDir(parent, io, name) catch |open_err| {
                    return preserveDestinationSetupPrimaryError(
                        prepared.name,
                        open_err,
                        discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir),
                    );
                };
                discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir) catch |cleanup_err| {
                    receiver_dir.dir.close(io);
                    return cleanup_err;
                };
                return receiver_dir;
            }
            switch (rename_err) {
                error.AccessDenied => {
                    if (builtin.os.tag != .windows) {
                        return preserveDestinationSetupPrimaryError(
                            prepared.name,
                            rename_err,
                            discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir),
                        );
                    }
                    _ = parent.statFile(io, name, .{ .follow_symlinks = false }) catch {
                        return preserveDestinationSetupPrimaryError(
                            prepared.name,
                            rename_err,
                            discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir),
                        );
                    };
                    const receiver_dir = openDestinationDir(parent, io, name) catch {
                        return preserveDestinationSetupPrimaryError(
                            prepared.name,
                            rename_err,
                            discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir),
                        );
                    };
                    discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir) catch |cleanup_err| {
                        receiver_dir.dir.close(io);
                        return cleanup_err;
                    };
                    return receiver_dir;
                },
                else => {
                    return preserveDestinationSetupPrimaryError(
                        prepared.name,
                        rename_err,
                        discardPreparedDestinationDir(parent, io, prepared.name, prepared.identity, prepared.dir),
                    );
                },
            }
        };
        return .{ .dir = prepared.dir, .followed_link = false };
    }

    fn createDestinationDir(parent: std.Io.Dir, io: std.Io, name: []const u8) !ResolvedDestinationDir {
        var private_name_buffer: [80]u8 = undefined;
        var attempt: usize = 0;
        while (attempt < 16) : (attempt += 1) {
            var random_integer: u64 = 0;
            io.random(@ptrCast(&random_integer));
            const private_name = try std.fmt.bufPrint(
                &private_name_buffer,
                ".boundary-oracle-parent-{x}",
                .{random_integer},
            );
            parent.createDir(io, private_name, private_dir_permissions) catch |create_err| switch (create_err) {
                error.PathAlreadyExists => continue,
                else => return create_err,
            };
            const private_dir = parent.openDir(io, private_name, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |open_err| {
                return preserveDestinationSetupPrimaryError(
                    private_name,
                    open_err,
                    parent.deleteDir(io, private_name),
                );
            };
            const private_identity = directoryIdentity(private_dir) catch |identity_err| {
                private_dir.close(io);
                return preserveDestinationSetupPrimaryError(
                    private_name,
                    identity_err,
                    parent.deleteDir(io, private_name),
                );
            };
            if (std.Io.Dir.Permissions.has_executable_bit) {
                private_dir.setPermissions(io, public_dir_permissions) catch |permissions_err| {
                    return preserveDestinationSetupPrimaryError(
                        private_name,
                        permissions_err,
                        discardPreparedDestinationDir(parent, io, private_name, private_identity, private_dir),
                    );
                };
            }
            return installPreparedDestinationDir(
                parent,
                io,
                name,
                .{
                    .name = private_name,
                    .identity = private_identity,
                    .dir = private_dir,
                },
            );
        }
        return error.OracleDestinationNameExhausted;
    }

    fn openOrCreateDestinationDir(parent: std.Io.Dir, io: std.Io, name: []const u8) !ResolvedDestinationDir {
        return openDestinationDir(parent, io, name) catch |open_err| switch (open_err) {
            error.FileNotFound => createDestinationDir(parent, io, name),
            else => return open_err,
        };
    }

    fn directoryIsWithinIdentity(
        dir: std.Io.Dir,
        io: std.Io,
        ancestor_identity: FileIdentity,
    ) !bool {
        var cursor = try dir.openDir(io, ".", .{ .follow_symlinks = false });
        defer cursor.close(io);

        var depth: usize = 0;
        while (depth < 4096) : (depth += 1) {
            const cursor_identity = try directoryIdentity(cursor);
            if (std.meta.eql(cursor_identity, ancestor_identity)) return true;

            const parent = try cursor.openDir(io, "..", .{ .follow_symlinks = false });
            const parent_identity = directoryIdentity(parent) catch |err| {
                parent.close(io);
                return err;
            };
            if (std.meta.eql(parent_identity, cursor_identity)) {
                parent.close(io);
                return false;
            }
            cursor.close(io);
            cursor = parent;
        }
        return error.OraclePathDepthExceeded;
    }

    fn copyFileNoFollow(source: std.Io.Dir, destination: std.Io.Dir, io: std.Io, name: []const u8) !void {
        const source_file = try source.openFile(io, name, .{
            .allow_directory = false,
            .follow_symlinks = false,
        });
        var source_reader: std.Io.File.Reader = .init(source_file, io, &.{});
        defer source_reader.file.close(io);
        const stat = try source_reader.file.stat(io);
        if (stat.kind != .file) return error.UnsupportedOracleTreeEntry;
        source_reader.size = stat.size;

        var atomic_file = try destination.createFileAtomic(io, name, .{
            .permissions = public_file_permissions,
            .replace = false,
        });
        defer atomic_file.deinit(io);
        var buffer: [1024]u8 = undefined;
        var destination_writer = atomic_file.file.writer(io, &buffer);
        _ = destination_writer.interface.sendFileAll(&source_reader, .unlimited) catch |err| switch (err) {
            error.ReadFailed => return source_reader.err.?,
            error.WriteFailed => return destination_writer.err.?,
        };
        try destination_writer.flush();
        if (std.Io.File.Permissions.has_executable_bit) {
            try atomic_file.file.setPermissions(io, public_file_permissions);
        }
        try atomic_file.link(io);
    }

    fn sourceEntryKindNoFollow(
        source: std.Io.Dir,
        io: std.Io,
        name: []const u8,
        reported_kind: std.Io.File.Kind,
    ) !std.Io.File.Kind {
        if (reported_kind != .unknown) return reported_kind;
        const observed = try source.statFile(io, name, .{ .follow_symlinks = false });
        return switch (observed.kind) {
            .file, .directory => observed.kind,
            .block_device,
            .character_device,
            .named_pipe,
            .sym_link,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => error.UnsupportedOracleTreeEntry,
        };
    }

    fn copyTreeNoFollow(source: std.Io.Dir, destination: std.Io.Dir, io: std.Io) !void {
        var iterator = source.iterateAssumeFirstIteration();
        while (try iterator.next(io)) |entry| {
            if (entry.name.len == 0 or
                std.mem.eql(u8, entry.name, ".") or
                std.mem.eql(u8, entry.name, "..") or
                std.mem.findAny(u8, entry.name, "/\\") != null)
            {
                return error.UnsupportedOracleTreeEntry;
            }
            switch (try sourceEntryKindNoFollow(source, io, entry.name, entry.kind)) {
                .file => try copyFileNoFollow(source, destination, io, entry.name),
                .directory => {
                    try destination.createDir(io, entry.name, public_dir_permissions);
                    var source_child = try source.openDir(io, entry.name, .{
                        .iterate = true,
                        .follow_symlinks = false,
                    });
                    defer source_child.close(io);
                    var destination_child = try destination.openDir(io, entry.name, .{
                        .iterate = true,
                        .follow_symlinks = false,
                    });
                    defer destination_child.close(io);
                    if (std.Io.Dir.Permissions.has_executable_bit) {
                        try destination_child.setPermissions(io, public_dir_permissions);
                    }
                    try copyTreeNoFollow(source_child, destination_child, io);
                },
                .block_device,
                .character_device,
                .named_pipe,
                .sym_link,
                .unix_domain_socket,
                .whiteout,
                .door,
                .event_port,
                .unknown,
                => return error.UnsupportedOracleTreeEntry,
            }
        }
    }

    const ProtectedDescendantContext = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        protected_identities: *std.ArrayList(FileIdentity),
    };

    fn collectProtectedDescendantEntryNoFollow(
        dir: std.Io.Dir,
        context: ProtectedDescendantContext,
        name: []const u8,
        reported_kind: std.Io.File.Kind,
    ) anyerror!void {
        switch (try sourceEntryKindNoFollow(dir, context.io, name, reported_kind)) {
            .file => return,
            .directory => {},
            .block_device,
            .character_device,
            .named_pipe,
            .sym_link,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedOracleTreeEntry,
        }

        var child = try dir.openDir(context.io, name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer child.close(context.io);
        const child_identity = try directoryIdentity(child);
        if (identityMatchesAny(child_identity, context.protected_identities.items)) return;
        try context.protected_identities.append(context.allocator, child_identity);
        try collectProtectedDescendantIdentities(
            child,
            context.io,
            context.allocator,
            context.protected_identities,
        );
    }

    fn collectProtectedDescendantIdentities(
        dir: std.Io.Dir,
        io: std.Io,
        allocator: std.mem.Allocator,
        protected_identities: *std.ArrayList(FileIdentity),
    ) !void {
        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            if (entry.name.len == 0 or
                std.mem.eql(u8, entry.name, ".") or
                std.mem.eql(u8, entry.name, "..") or
                std.mem.findAny(u8, entry.name, "/\\") != null)
            {
                return error.UnsupportedOracleTreeEntry;
            }
            try collectProtectedDescendantEntryNoFollow(dir, .{
                .allocator = allocator,
                .io = io,
                .protected_identities = protected_identities,
            }, entry.name, entry.kind);
        }
    }

    fn openExistingDestinationLeafNoFollow(
        parent: std.Io.Dir,
        io: std.Io,
        name: []const u8,
    ) !?std.Io.Dir {
        const stat = parent.statFile(io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        return switch (stat.kind) {
            .sym_link => error.LinkedOracleDestination,
            .directory => try parent.openDir(io, name, .{
                .iterate = false,
                .follow_symlinks = false,
            }),
            .block_device,
            .character_device,
            .named_pipe,
            .file,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => error.OracleDestinationOccupied,
        };
    }

    fn observedDestinationIdentity(
        parent: std.Io.Dir,
        io: std.Io,
        name: []const u8,
    ) !?FileIdentity {
        const destination = try openExistingDestinationLeafNoFollow(parent, io, name);
        if (destination) |dir| {
            defer dir.close(io);
            return try directoryIdentity(dir);
        }
        return null;
    }

    fn destinationObservationMatches(
        expected: ?FileIdentity,
        observed: ?FileIdentity,
    ) bool {
        if (expected == null or observed == null) return expected == null and observed == null;
        return std.meta.eql(expected.?, observed.?);
    }

    fn restoreQuarantinedEntry(
        quarantine: std.Io.Dir,
        current: std.Io.Dir,
        io: std.Io,
        quarantine_name: []const u8,
        destination_name: []const u8,
    ) !void {
        try renameEntryNoReplace(quarantine, quarantine_name, current, destination_name, io);
    }

    const QuarantinePostcheckOutcome = union(enum) {
        identity_mismatch,
        observation_failed: anyerror,
        verified,
    };

    fn resolveQuarantinePostcheck(
        expected: FileIdentity,
        observation: anyerror!?FileIdentity,
    ) QuarantinePostcheckOutcome {
        const observed = observation catch |err| return .{ .observation_failed = err };
        if (observed != null and std.meta.eql(expected, observed.?)) return .verified;
        return .identity_mismatch;
    }

    fn deleteNonDirectoryNoFollow(parent: std.Io.Dir, io: std.Io, name: []const u8) !void {
        parent.deleteFile(io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            error.IsDir => return error.OracleCleanupRace,
            else => return err,
        };
    }

    fn clearDirectoryEntryNoFollow(
        dir: std.Io.Dir,
        io: std.Io,
        traversal: CleanupTraversal,
        name: []const u8,
        reported_kind: std.Io.File.Kind,
    ) anyerror!void {
        const kind = sourceEntryKindNoFollow(dir, io, name, reported_kind) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        switch (kind) {
            .file => {
                try deleteNonDirectoryNoFollow(dir, io, name);
                return;
            },
            .directory => {},
            .block_device,
            .character_device,
            .named_pipe,
            .sym_link,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedOracleTreeEntry,
        }

        const child_depth = traversal.current_depth + 1;
        const child_open_directories = child_depth + 1;
        if (child_depth > maximum_cleanup_depth or
            child_open_directories > max_cleanup_open_directories)
        {
            return error.OracleCleanupDepthLimitExceeded;
        }

        var child = dir.openDir(io, name, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => return,
            error.NotDir, error.SymLinkLoop => {
                try deleteNonDirectoryNoFollow(dir, io, name);
                return;
            },
            else => return err,
        };
        const child_identity = directoryIdentity(child) catch |err| {
            child.close(io);
            return err;
        };
        if (identityMatchesAny(child_identity, traversal.protected_identities)) {
            child.close(io);
            return error.ProtectedOracleCleanupAlias;
        }
        clearDirectoryNoFollow(
            child,
            io,
            .{
                .protected_identities = traversal.protected_identities,
                .current_depth = child_depth,
                .budget = traversal.budget,
            },
        ) catch |err| {
            child.close(io);
            return err;
        };
        child.close(io);
        dir.deleteDir(io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            error.NotDir, error.DirNotEmpty, error.FileBusy => return error.OracleCleanupRace,
            else => return err,
        };
    }

    fn clearDirectoryNoFollow(
        dir: std.Io.Dir,
        io: std.Io,
        traversal: CleanupTraversal,
    ) !void {
        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            try traversal.budget.consumeEntry();
            if (entry.name.len == 0 or
                std.mem.eql(u8, entry.name, ".") or
                std.mem.eql(u8, entry.name, "..") or
                std.mem.findAny(u8, entry.name, "/\\") != null)
            {
                return error.UnsupportedOracleTreeEntry;
            }
            try clearDirectoryEntryNoFollow(
                dir,
                io,
                traversal,
                entry.name,
                entry.kind,
            );
        }
    }

    fn cleanupQuarantinedLeaf(
        parent: std.Io.Dir,
        io: std.Io,
        name: []const u8,
        expected_directory_identity: ?FileIdentity,
        protected_identities: []const FileIdentity,
    ) !void {
        var dir = parent.openDir(io, name, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => return,
            error.NotDir, error.SymLinkLoop => return deleteNonDirectoryNoFollow(parent, io, name),
            else => return err,
        };
        const identity = directoryIdentity(dir) catch |err| {
            dir.close(io);
            return err;
        };
        if (identityMatchesAny(identity, protected_identities)) {
            dir.close(io);
            return error.ProtectedOracleCleanupAlias;
        }
        if (expected_directory_identity == null or
            !std.meta.eql(identity, expected_directory_identity.?))
        {
            dir.close(io);
            return error.OracleQuarantineIdentityChanged;
        }
        var cleanup_budget: CleanupBudget = .{};
        clearDirectoryNoFollow(dir, io, .{
            .protected_identities = protected_identities,
            .current_depth = 0,
            .budget = &cleanup_budget,
        }) catch |err| {
            dir.close(io);
            return err;
        };
        dir.close(io);
        parent.deleteDir(io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            error.NotDir, error.DirNotEmpty, error.FileBusy => return error.OracleCleanupRace,
            else => return err,
        };
    }

    fn cleanupEmptyContainerName(
        parent: std.Io.Dir,
        io: std.Io,
        name: []const u8,
        expected_identity: FileIdentity,
    ) !void {
        var dir = parent.openDir(io, name, .{
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => return,
            error.NotDir, error.SymLinkLoop => return error.OracleContainerIdentityChanged,
            else => return err,
        };
        const identity = directoryIdentity(dir) catch |err| {
            dir.close(io);
            return err;
        };
        dir.close(io);
        if (!std.meta.eql(identity, expected_identity)) {
            return error.OracleContainerIdentityChanged;
        }
        parent.deleteDir(io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            error.NotDir, error.DirNotEmpty, error.FileBusy => return error.OracleCleanupRace,
            else => return err,
        };
    }

    fn testDestinationCollisionPreservesReceiverDirectory() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "prepared-success", private_dir_permissions);
        const prepared_success = try tmp.dir.openDir(io, "prepared-success", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        const prepared_success_identity = try directoryIdentity(prepared_success);
        if (std.Io.Dir.Permissions.has_executable_bit) {
            try prepared_success.setPermissions(io, public_dir_permissions);
        }
        const installed = try installPreparedDestinationDir(
            tmp.dir,
            io,
            "installed",
            .{
                .name = "prepared-success",
                .identity = prepared_success_identity,
                .dir = prepared_success,
            },
        );
        defer installed.dir.close(io);
        try std.testing.expect(std.meta.eql(prepared_success_identity, try directoryIdentity(installed.dir)));
        var installed_by_name = try tmp.dir.openDir(io, "installed", .{ .follow_symlinks = false });
        defer installed_by_name.close(io);
        try std.testing.expect(std.meta.eql(prepared_success_identity, try directoryIdentity(installed_by_name)));
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "prepared-success", .{ .follow_symlinks = false }),
        );
        if (std.Io.Dir.Permissions.has_executable_bit) {
            const installed_stat = try installed.dir.stat(io);
            try std.testing.expectEqual(@as(std.posix.mode_t, 0o755), installed_stat.permissions.toMode() & 0o777);
        }

        try tmp.dir.createDir(io, "receiver", private_dir_permissions);
        var receiver = try tmp.dir.openDir(io, "receiver", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        if (std.Io.Dir.Permissions.has_executable_bit) {
            try receiver.setPermissions(io, .fromMode(0o710));
        }
        const receiver_identity = try directoryIdentity(receiver);
        receiver.close(io);

        try tmp.dir.createDir(io, "prepared", private_dir_permissions);
        const prepared = try tmp.dir.openDir(io, "prepared", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        const prepared_identity = try directoryIdentity(prepared);
        if (std.Io.Dir.Permissions.has_executable_bit) {
            try prepared.setPermissions(io, public_dir_permissions);
        }

        const resolved = try installPreparedDestinationDir(
            tmp.dir,
            io,
            "receiver",
            .{
                .name = "prepared",
                .identity = prepared_identity,
                .dir = prepared,
            },
        );
        defer resolved.dir.close(io);
        try std.testing.expect(std.meta.eql(receiver_identity, try directoryIdentity(resolved.dir)));
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "prepared", .{ .follow_symlinks = false }),
        );
        if (std.Io.Dir.Permissions.has_executable_bit) {
            const receiver_stat = try resolved.dir.stat(io);
            try std.testing.expectEqual(@as(std.posix.mode_t, 0o710), receiver_stat.permissions.toMode() & 0o777);
        }
    }

    fn testDestinationCollisionClassification() !void {
        try std.testing.expect(isDestinationCollisionError(error.PathAlreadyExists));
        try std.testing.expect(isDestinationCollisionError(error.DirNotEmpty));
        try std.testing.expect(!isDestinationCollisionError(error.AccessDenied));
    }

    fn testDestinationSetupPrimaryErrorPrecedence() !void {
        try std.testing.expectEqual(
            error.NotDir,
            preserveDestinationSetupPrimaryError(
                "prepared",
                error.NotDir,
                error.OracleCleanupRace,
            ),
        );
    }

    fn testDestinationCollisionPreservesPrimaryErrorWhenCleanupFails() !void {
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.writeFile(io, .{
            .sub_path = "receiver-file",
            .data = "receiver-owned\n",
        });
        try tmp.dir.createDir(io, "prepared", private_dir_permissions);
        const prepared = try tmp.dir.openDir(io, "prepared", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        const prepared_identity = try directoryIdentity(prepared);
        try prepared.writeFile(io, .{
            .sub_path = "cleanup-blocker.txt",
            .data = "prepared-residue\n",
        });

        try std.testing.expectError(
            error.NotDir,
            installPreparedDestinationDir(
                tmp.dir,
                io,
                "receiver-file",
                .{
                    .name = "prepared",
                    .identity = prepared_identity,
                    .dir = prepared,
                },
            ),
        );

        const receiver_marker = try tmp.dir.readFileAlloc(
            io,
            "receiver-file",
            std.testing.allocator,
            .limited(64),
        );
        defer std.testing.allocator.free(receiver_marker);
        try std.testing.expectEqualStrings("receiver-owned\n", receiver_marker);

        var retained_prepared = try tmp.dir.openDir(io, "prepared", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer retained_prepared.close(io);
        const residue_marker = try retained_prepared.readFileAlloc(
            io,
            "cleanup-blocker.txt",
            std.testing.allocator,
            .limited(64),
        );
        defer std.testing.allocator.free(residue_marker);
        try std.testing.expectEqualStrings("prepared-residue\n", residue_marker);
    }

    fn testNoReplacePromotionPreservesReceiverDirectory() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "staged", public_dir_permissions);
        var staged = try tmp.dir.openDir(io, "staged", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer staged.close(io);
        const staged_identity = try directoryIdentity(staged);

        try tmp.dir.createDir(io, "receiver", private_dir_permissions);
        var receiver = try tmp.dir.openDir(io, "receiver", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        if (std.Io.Dir.Permissions.has_executable_bit) {
            try receiver.setPermissions(io, .fromMode(0o710));
        }
        const receiver_identity = try directoryIdentity(receiver);
        receiver.close(io);

        try std.testing.expectError(
            error.OraclePublicationConflict,
            renameEntryNoReplace(tmp.dir, "staged", tmp.dir, "receiver", io),
        );
        var retained_staged = try tmp.dir.openDir(io, "staged", .{ .follow_symlinks = false });
        defer retained_staged.close(io);
        try std.testing.expect(std.meta.eql(staged_identity, try directoryIdentity(retained_staged)));
        var retained_receiver = try tmp.dir.openDir(io, "receiver", .{ .follow_symlinks = false });
        defer retained_receiver.close(io);
        try std.testing.expect(std.meta.eql(receiver_identity, try directoryIdentity(retained_receiver)));
        if (std.Io.Dir.Permissions.has_executable_bit) {
            const receiver_stat = try retained_receiver.stat(io);
            try std.testing.expectEqual(@as(std.posix.mode_t, 0o710), receiver_stat.permissions.toMode() & 0o777);
        }

        try tmp.dir.writeFile(io, .{
            .sub_path = "file-receiver",
            .data = "receiver-owned\n",
        });
        try std.testing.expectError(
            error.OraclePublicationConflict,
            renameEntryNoReplace(tmp.dir, "staged", tmp.dir, "file-receiver", io),
        );
        const marker = try tmp.dir.readFileAlloc(io, "file-receiver", std.testing.allocator, .limited(64));
        defer std.testing.allocator.free(marker);
        try std.testing.expectEqualStrings("receiver-owned\n", marker);
    }

    fn testAmbiguousQuarantineObservationPreservesUnprovedMovedEntry() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "receiver", private_dir_permissions);
        var receiver = try tmp.dir.openDir(io, "receiver", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        try receiver.writeFile(io, .{
            .sub_path = "receiver-marker.txt",
            .data = "receiver-owned-before-quarantine\n",
        });
        if (std.Io.Dir.Permissions.has_executable_bit) {
            try receiver.setPermissions(io, .fromMode(0o710));
        }
        const receiver_identity = try directoryIdentity(receiver);
        receiver.close(io);

        try tmp.dir.createDir(io, "quarantine", private_dir_permissions);
        var quarantine = try tmp.dir.openDir(io, "quarantine", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer quarantine.close(io);
        try tmp.dir.rename("receiver", quarantine, "tree", io);

        const failed_observation: anyerror!?FileIdentity =
            error.InjectedQuarantineObservationFailure;
        const outcome = resolveQuarantinePostcheck(receiver_identity, failed_observation);
        switch (outcome) {
            .observation_failed => |err| try std.testing.expectEqual(
                error.InjectedQuarantineObservationFailure,
                err,
            ),
            .identity_mismatch,
            .verified,
            => return error.UnexpectedQuarantinePostcheckOutcome,
        }

        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "receiver", .{ .follow_symlinks = false }),
        );
        {
            var retained_receiver = try quarantine.openDir(io, "tree", .{
                .iterate = true,
                .follow_symlinks = false,
            });
            defer retained_receiver.close(io);
            try std.testing.expect(std.meta.eql(
                receiver_identity,
                try directoryIdentity(retained_receiver),
            ));
            const marker = try retained_receiver.readFileAlloc(
                io,
                "receiver-marker.txt",
                std.testing.allocator,
                .limited(128),
            );
            defer std.testing.allocator.free(marker);
            try std.testing.expectEqualStrings("receiver-owned-before-quarantine\n", marker);
            if (std.Io.Dir.Permissions.has_executable_bit) {
                const retained_stat = try retained_receiver.stat(io);
                try std.testing.expectEqual(
                    @as(std.posix.mode_t, 0o710),
                    retained_stat.permissions.toMode() & 0o777,
                );
            }
        }

        try quarantine.rename("tree", quarantine, "expected-tree", io);
        try quarantine.createDir(io, "tree", private_dir_permissions);
        var unproved = try quarantine.openDir(io, "tree", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        try unproved.writeFile(io, .{
            .sub_path = "unproved-marker.txt",
            .data = "unproved-replacement\n",
        });
        if (std.Io.Dir.Permissions.has_executable_bit) {
            try unproved.setPermissions(io, .fromMode(0o750));
        }
        const unproved_identity = try directoryIdentity(unproved);
        unproved.close(io);

        const mismatch_outcome = resolveQuarantinePostcheck(
            receiver_identity,
            observedDestinationIdentity(quarantine, io, "tree"),
        );
        switch (mismatch_outcome) {
            .identity_mismatch => {},
            .verified,
            .observation_failed,
            => return error.UnexpectedQuarantinePostcheckOutcome,
        }
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "receiver", .{ .follow_symlinks = false }),
        );
        var retained_unproved = try quarantine.openDir(io, "tree", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer retained_unproved.close(io);
        try std.testing.expect(std.meta.eql(
            unproved_identity,
            try directoryIdentity(retained_unproved),
        ));
        const unproved_marker = try retained_unproved.readFileAlloc(
            io,
            "unproved-marker.txt",
            std.testing.allocator,
            .limited(128),
        );
        defer std.testing.allocator.free(unproved_marker);
        try std.testing.expectEqualStrings("unproved-replacement\n", unproved_marker);
        if (std.Io.Dir.Permissions.has_executable_bit) {
            const retained_unproved_stat = try retained_unproved.stat(io);
            try std.testing.expectEqual(
                @as(std.posix.mode_t, 0o750),
                retained_unproved_stat.permissions.toMode() & 0o777,
            );
        }

        var retained_expected = try quarantine.openDir(io, "expected-tree", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer retained_expected.close(io);
        try std.testing.expect(std.meta.eql(
            receiver_identity,
            try directoryIdentity(retained_expected),
        ));
        const expected_marker = try retained_expected.readFileAlloc(
            io,
            "receiver-marker.txt",
            std.testing.allocator,
            .limited(128),
        );
        defer std.testing.allocator.free(expected_marker);
        try std.testing.expectEqualStrings("receiver-owned-before-quarantine\n", expected_marker);
        if (std.Io.Dir.Permissions.has_executable_bit) {
            const retained_expected_stat = try retained_expected.stat(io);
            try std.testing.expectEqual(
                @as(std.posix.mode_t, 0o710),
                retained_expected_stat.permissions.toMode() & 0o777,
            );
        }
    }

    fn testProtectedDescendantIdentityCollection() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "child", private_dir_permissions);
        var child = try tmp.dir.openDir(io, "child", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer child.close(io);
        try child.createDir(io, "grandchild", private_dir_permissions);
        var grandchild = try child.openDir(io, "grandchild", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer grandchild.close(io);

        var identities: std.ArrayList(FileIdentity) = .empty;
        defer identities.deinit(std.testing.allocator);
        try identities.append(std.testing.allocator, try directoryIdentity(tmp.dir));
        try collectProtectedDescendantIdentities(
            tmp.dir,
            io,
            std.testing.allocator,
            &identities,
        );
        try std.testing.expect(identityMatchesAny(try directoryIdentity(child), identities.items));
        try std.testing.expect(identityMatchesAny(try directoryIdentity(grandchild), identities.items));
        var cleanup_budget: CleanupBudget = .{};
        try std.testing.expectError(
            error.ProtectedOracleCleanupAlias,
            clearDirectoryNoFollow(tmp.dir, io, .{
                .protected_identities = identities.items,
                .current_depth = 0,
                .budget = &cleanup_budget,
            }),
        );
        const child_stat = try tmp.dir.statFile(io, "child", .{ .follow_symlinks = false });
        try std.testing.expectEqual(std.Io.File.Kind.directory, child_stat.kind);
        const grandchild_stat = try child.statFile(io, "grandchild", .{ .follow_symlinks = false });
        try std.testing.expectEqual(std.Io.File.Kind.directory, grandchild_stat.kind);
    }

    fn testProtectedDescendantUnknownKindReclassification() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        var identities: std.ArrayList(FileIdentity) = .empty;
        defer identities.deinit(std.testing.allocator);
        try identities.append(std.testing.allocator, try directoryIdentity(tmp.dir));
        const context: ProtectedDescendantContext = .{
            .allocator = std.testing.allocator,
            .io = io,
            .protected_identities = &identities,
        };

        try tmp.dir.writeFile(io, .{
            .sub_path = "unknown-file",
            .data = "protected-file\n",
        });
        const identity_count_before_file = identities.items.len;
        try collectProtectedDescendantEntryNoFollow(
            tmp.dir,
            context,
            "unknown-file",
            .unknown,
        );
        try std.testing.expectEqual(identity_count_before_file, identities.items.len);
        const file_marker = try tmp.dir.readFileAlloc(
            io,
            "unknown-file",
            std.testing.allocator,
            .limited(64),
        );
        defer std.testing.allocator.free(file_marker);
        try std.testing.expectEqualStrings("protected-file\n", file_marker);

        try tmp.dir.createDir(io, "unknown-directory", private_dir_permissions);
        var child = try tmp.dir.openDir(io, "unknown-directory", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        try child.createDir(io, "nested-directory", private_dir_permissions);
        var nested = try child.openDir(io, "nested-directory", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        const child_identity = try directoryIdentity(child);
        const nested_identity = try directoryIdentity(nested);
        nested.close(io);
        child.close(io);
        try collectProtectedDescendantEntryNoFollow(
            tmp.dir,
            context,
            "unknown-directory",
            .unknown,
        );
        try std.testing.expect(identityMatchesAny(child_identity, identities.items));
        try std.testing.expect(identityMatchesAny(nested_identity, identities.items));

        try tmp.dir.writeFile(io, .{
            .sub_path = "reported-special",
            .data = "reported-special\n",
        });
        try std.testing.expectError(
            error.UnsupportedOracleTreeEntry,
            collectProtectedDescendantEntryNoFollow(
                tmp.dir,
                context,
                "reported-special",
                .named_pipe,
            ),
        );
        const special_marker = try tmp.dir.readFileAlloc(
            io,
            "reported-special",
            std.testing.allocator,
            .limited(64),
        );
        defer std.testing.allocator.free(special_marker);
        try std.testing.expectEqualStrings("reported-special\n", special_marker);

        if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
            try tmp.dir.writeFile(io, .{
                .sub_path = "linked-target",
                .data = "linked-target\n",
            });
            try tmp.dir.symLink(io, "linked-target", "unknown-link", .{
                .is_directory = false,
            });
            try std.testing.expectError(
                error.UnsupportedOracleTreeEntry,
                collectProtectedDescendantEntryNoFollow(
                    tmp.dir,
                    context,
                    "unknown-link",
                    .unknown,
                ),
            );
            const linked_stat = try tmp.dir.statFile(io, "unknown-link", .{
                .follow_symlinks = false,
            });
            try std.testing.expectEqual(std.Io.File.Kind.sym_link, linked_stat.kind);
            const linked_target = try tmp.dir.readFileAlloc(
                io,
                "linked-target",
                std.testing.allocator,
                .limited(64),
            );
            defer std.testing.allocator.free(linked_target);
            try std.testing.expectEqualStrings("linked-target\n", linked_target);
        }
    }

    fn testLinkedDestinationLeafRejected() !void {
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "target", private_dir_permissions);
        try tmp.dir.symLink(io, "target", "boundary", .{ .is_directory = true });
        try std.testing.expectError(
            error.LinkedOracleDestination,
            openExistingDestinationLeafNoFollow(tmp.dir, io, "boundary"),
        );
        const stat = try tmp.dir.statFile(io, "boundary", .{ .follow_symlinks = false });
        try std.testing.expectEqual(std.Io.File.Kind.sym_link, stat.kind);
    }

    fn testUnknownEntryKindReclassification() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.writeFile(io, .{ .sub_path = "ordinary-file", .data = "oracle\n" });
        try tmp.dir.createDir(io, "ordinary-directory", private_dir_permissions);
        try std.testing.expectEqual(
            std.Io.File.Kind.file,
            try sourceEntryKindNoFollow(tmp.dir, io, "ordinary-file", .unknown),
        );
        try std.testing.expectEqual(
            std.Io.File.Kind.directory,
            try sourceEntryKindNoFollow(tmp.dir, io, "ordinary-directory", .unknown),
        );

        if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
            try tmp.dir.symLink(io, "ordinary-file", "linked-file", .{ .is_directory = false });
            try std.testing.expectError(
                error.UnsupportedOracleTreeEntry,
                sourceEntryKindNoFollow(tmp.dir, io, "linked-file", .unknown),
            );
        }
    }

    fn testUnknownDirectoryCleanup() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "unknown-directory", private_dir_permissions);
        var child = try tmp.dir.openDir(io, "unknown-directory", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        try child.writeFile(io, .{ .sub_path = "nested-file", .data = "oracle\n" });
        child.close(io);

        var cleanup_budget: CleanupBudget = .{};
        try clearDirectoryEntryNoFollow(
            tmp.dir,
            io,
            .{
                .protected_identities = &.{},
                .current_depth = 0,
                .budget = &cleanup_budget,
            },
            "unknown-directory",
            .unknown,
        );
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "unknown-directory", .{ .follow_symlinks = false }),
        );

        if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
            try tmp.dir.writeFile(io, .{ .sub_path = "linked-target", .data = "oracle\n" });
            try tmp.dir.symLink(io, "linked-target", "unknown-link", .{ .is_directory = false });
            try std.testing.expectError(
                error.UnsupportedOracleTreeEntry,
                clearDirectoryEntryNoFollow(
                    tmp.dir,
                    io,
                    .{
                        .protected_identities = &.{},
                        .current_depth = 0,
                        .budget = &cleanup_budget,
                    },
                    "unknown-link",
                    .unknown,
                ),
            );
            const linked_stat = try tmp.dir.statFile(io, "unknown-link", .{ .follow_symlinks = false });
            try std.testing.expectEqual(std.Io.File.Kind.sym_link, linked_stat.kind);
        }
    }

    fn testCleanupEntryKindDispatch() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        var cleanup_budget: CleanupBudget = .{};
        const special_cases = [_]struct {
            kind: std.Io.File.Kind,
            name: []const u8,
        }{
            .{ .kind = .block_device, .name = "reported-block-device" },
            .{ .kind = .character_device, .name = "reported-character-device" },
            .{ .kind = .named_pipe, .name = "reported-named-pipe" },
            .{ .kind = .sym_link, .name = "reported-symbolic-link" },
            .{ .kind = .unix_domain_socket, .name = "reported-unix-domain-socket" },
            .{ .kind = .whiteout, .name = "reported-whiteout" },
            .{ .kind = .door, .name = "reported-door" },
            .{ .kind = .event_port, .name = "reported-event-port" },
        };
        for (special_cases) |case| {
            try tmp.dir.writeFile(io, .{
                .sub_path = case.name,
                .data = "cleanup-special-retained\n",
            });
            try std.testing.expectError(
                error.UnsupportedOracleTreeEntry,
                clearDirectoryEntryNoFollow(
                    tmp.dir,
                    io,
                    .{
                        .protected_identities = &.{},
                        .current_depth = 0,
                        .budget = &cleanup_budget,
                    },
                    case.name,
                    case.kind,
                ),
            );
            const retained = try tmp.dir.readFileAlloc(
                io,
                case.name,
                std.testing.allocator,
                .limited(64),
            );
            defer std.testing.allocator.free(retained);
            try std.testing.expectEqualStrings("cleanup-special-retained\n", retained);
        }

        try tmp.dir.writeFile(io, .{
            .sub_path = "ordinary-file",
            .data = "cleanup-file\n",
        });
        try clearDirectoryEntryNoFollow(
            tmp.dir,
            io,
            .{
                .protected_identities = &.{},
                .current_depth = 0,
                .budget = &cleanup_budget,
            },
            "ordinary-file",
            .file,
        );
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "ordinary-file", .{ .follow_symlinks = false }),
        );

        try tmp.dir.createDir(io, "ordinary-directory", private_dir_permissions);
        var ordinary_directory = try tmp.dir.openDir(io, "ordinary-directory", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        try ordinary_directory.writeFile(io, .{
            .sub_path = "nested-file",
            .data = "cleanup-directory\n",
        });
        ordinary_directory.close(io);
        try clearDirectoryEntryNoFollow(
            tmp.dir,
            io,
            .{
                .protected_identities = &.{},
                .current_depth = 0,
                .budget = &cleanup_budget,
            },
            "ordinary-directory",
            .directory,
        );
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "ordinary-directory", .{ .follow_symlinks = false }),
        );

        if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
            try tmp.dir.writeFile(io, .{
                .sub_path = "actual-link-target",
                .data = "actual-link-target\n",
            });
            try tmp.dir.symLink(io, "actual-link-target", "actual-link", .{
                .is_directory = false,
            });
            try std.testing.expectError(
                error.UnsupportedOracleTreeEntry,
                clearDirectoryEntryNoFollow(
                    tmp.dir,
                    io,
                    .{
                        .protected_identities = &.{},
                        .current_depth = 0,
                        .budget = &cleanup_budget,
                    },
                    "actual-link",
                    .sym_link,
                ),
            );
            const link_stat = try tmp.dir.statFile(io, "actual-link", .{
                .follow_symlinks = false,
            });
            try std.testing.expectEqual(std.Io.File.Kind.sym_link, link_stat.kind);
            const target = try tmp.dir.readFileAlloc(
                io,
                "actual-link-target",
                std.testing.allocator,
                .limited(64),
            );
            defer std.testing.allocator.free(target);
            try std.testing.expectEqualStrings("actual-link-target\n", target);
        }
    }

    fn createCleanupDirectoryChain(
        parent: std.Io.Dir,
        io: std.Io,
        depth: usize,
    ) !void {
        var cursor = try parent.openDir(io, ".", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer cursor.close(io);

        for (0..depth) |index| {
            var name_buffer: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buffer, "level-{d}", .{index});
            try cursor.createDir(io, name, private_dir_permissions);
            const child = try cursor.openDir(io, name, .{
                .iterate = true,
                .follow_symlinks = false,
            });
            cursor.close(io);
            cursor = child;
        }
        try cursor.writeFile(io, .{
            .sub_path = "retained-marker.txt",
            .data = "retained-cleanup-root\n",
        });
    }

    fn expectCleanupDirectoryChainMarker(
        parent: std.Io.Dir,
        io: std.Io,
        root_name: []const u8,
        depth: usize,
    ) !void {
        var cursor = try parent.openDir(io, root_name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer cursor.close(io);

        for (0..depth) |index| {
            var name_buffer: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buffer, "level-{d}", .{index});
            const child = try cursor.openDir(io, name, .{
                .iterate = true,
                .follow_symlinks = false,
            });
            cursor.close(io);
            cursor = child;
        }
        const marker = try cursor.readFileAlloc(
            io,
            "retained-marker.txt",
            std.testing.allocator,
            .limited(64),
        );
        defer std.testing.allocator.free(marker);
        try std.testing.expectEqualStrings("retained-cleanup-root\n", marker);
    }

    fn testCleanupDepthBound() !void {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();

        try tmp.dir.createDir(io, "exact-depth", private_dir_permissions);
        var exact = try tmp.dir.openDir(io, "exact-depth", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        const exact_identity = try directoryIdentity(exact);
        try createCleanupDirectoryChain(exact, io, maximum_cleanup_depth);
        exact.close(io);
        try cleanupQuarantinedLeaf(
            tmp.dir,
            io,
            "exact-depth",
            exact_identity,
            &.{},
        );
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.statFile(io, "exact-depth", .{ .follow_symlinks = false }),
        );

        try tmp.dir.createDir(io, "over-depth", private_dir_permissions);
        var over = try tmp.dir.openDir(io, "over-depth", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        const over_identity = try directoryIdentity(over);
        try createCleanupDirectoryChain(over, io, maximum_cleanup_depth + 1);
        over.close(io);
        try std.testing.expectError(
            error.OracleCleanupDepthLimitExceeded,
            cleanupQuarantinedLeaf(
                tmp.dir,
                io,
                "over-depth",
                over_identity,
                &.{},
            ),
        );
        const retained = try tmp.dir.statFile(io, "over-depth", .{ .follow_symlinks = false });
        try std.testing.expectEqual(std.Io.File.Kind.directory, retained.kind);
        try expectCleanupDirectoryChainMarker(
            tmp.dir,
            io,
            "over-depth",
            maximum_cleanup_depth + 1,
        );
    }

    fn testCleanupWorkBound() !void {
        var production_budget: CleanupBudget = .{};
        for (0..maximum_cleanup_entries) |_| {
            try production_budget.consumeEntry();
        }
        try std.testing.expectEqual(@as(usize, 0), production_budget.remaining_entries);
        try std.testing.expectError(
            error.OracleCleanupWorkLimitExceeded,
            production_budget.consumeEntry(),
        );

        const io = std.testing.io;
        var exact = std.testing.tmpDir(.{ .iterate = true });
        defer exact.cleanup();
        try exact.dir.writeFile(io, .{ .sub_path = "first", .data = "first\n" });
        try exact.dir.writeFile(io, .{ .sub_path = "second", .data = "second\n" });
        var exact_budget: CleanupBudget = .{ .remaining_entries = 2 };
        try clearDirectoryNoFollow(exact.dir, io, .{
            .protected_identities = &.{},
            .current_depth = 0,
            .budget = &exact_budget,
        });
        try std.testing.expectEqual(@as(usize, 0), exact_budget.remaining_entries);
        try std.testing.expectError(
            error.FileNotFound,
            exact.dir.statFile(io, "first", .{ .follow_symlinks = false }),
        );
        try std.testing.expectError(
            error.FileNotFound,
            exact.dir.statFile(io, "second", .{ .follow_symlinks = false }),
        );

        var recursive = std.testing.tmpDir(.{ .iterate = true });
        defer recursive.cleanup();
        try recursive.dir.createDir(io, "child", private_dir_permissions);
        var child = try recursive.dir.openDir(io, "child", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        try child.writeFile(io, .{ .sub_path = "nested", .data = "nested\n" });
        child.close(io);

        var recursive_budget: CleanupBudget = .{ .remaining_entries = 1 };
        try std.testing.expectError(
            error.OracleCleanupWorkLimitExceeded,
            clearDirectoryNoFollow(recursive.dir, io, .{
                .protected_identities = &.{},
                .current_depth = 0,
                .budget = &recursive_budget,
            }),
        );
        try std.testing.expectEqual(@as(usize, 0), recursive_budget.remaining_entries);
        var retained_child = try recursive.dir.openDir(io, "child", .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer retained_child.close(io);
        const nested = try retained_child.statFile(io, "nested", .{ .follow_symlinks = false });
        try std.testing.expectEqual(std.Io.File.Kind.file, nested.kind);

        if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
            var malformed = std.testing.tmpDir(.{ .iterate = true });
            defer malformed.cleanup();
            try malformed.dir.writeFile(io, .{
                .sub_path = "bad\\name",
                .data = "malformed-name\n",
            });

            var exhausted_budget: CleanupBudget = .{ .remaining_entries = 0 };
            try std.testing.expectError(
                error.OracleCleanupWorkLimitExceeded,
                clearDirectoryNoFollow(malformed.dir, io, .{
                    .protected_identities = &.{},
                    .current_depth = 0,
                    .budget = &exhausted_budget,
                }),
            );

            var one_entry_budget: CleanupBudget = .{ .remaining_entries = 1 };
            try std.testing.expectError(
                error.UnsupportedOracleTreeEntry,
                clearDirectoryNoFollow(malformed.dir, io, .{
                    .protected_identities = &.{},
                    .current_depth = 0,
                    .budget = &one_entry_budget,
                }),
            );
            try std.testing.expectEqual(@as(usize, 0), one_entry_budget.remaining_entries);
            const retained_malformed = try malformed.dir.statFile(
                io,
                "bad\\name",
                .{ .follow_symlinks = false },
            );
            try std.testing.expectEqual(std.Io.File.Kind.file, retained_malformed.kind);
        }
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        const exact_tree: *@This() = @fieldParentPtr("step", step);
        const io = step.owner.graph.io;
        if (pathContainsOrEquals(exact_tree.protected_path, exact_tree.destination_path) or
            pathContainsOrEquals(exact_tree.destination_path, exact_tree.protected_path))
        {
            return step.fail(
                "refusing to emit the Boundary oracle across protected corpus boundary '{s}' using destination '{s}'",
                .{ exact_tree.protected_path, exact_tree.destination_path },
            );
        }

        var protected_opened: std.ArrayList(std.Io.Dir) = .empty;
        defer {
            var index = protected_opened.items.len;
            while (index > 0) {
                index -= 1;
                protected_opened.items[index].close(io);
            }
            protected_opened.deinit(options.gpa);
        }
        var protected_identities: std.ArrayList(FileIdentity) = .empty;
        defer protected_identities.deinit(options.gpa);

        var protected_components = std.Io.Dir.path.componentIterator(exact_tree.protected_path);
        const protected_root_path = protected_components.root() orelse
            return step.fail("protected Boundary oracle corpus path is not absolute: '{s}'", .{exact_tree.protected_path});
        const protected_root = std.Io.Dir.openDirAbsolute(io, protected_root_path, .{
            .iterate = protected_components.peekNext() == null,
            .follow_symlinks = false,
        }) catch |err| return step.fail(
            "unable to open protected Boundary oracle filesystem root '{s}' without following links: {s}",
            .{ protected_root_path, @errorName(err) },
        );
        protected_opened.append(options.gpa, protected_root) catch |err| {
            protected_root.close(io);
            return err;
        };
        protected_identities.append(
            options.gpa,
            directoryIdentity(protected_root) catch |err| return step.fail(
                "unable to identify protected Boundary oracle filesystem root '{s}': {s}",
                .{ protected_root_path, @errorName(err) },
            ),
        ) catch |err| return err;
        var protected_current = protected_root;
        while (protected_components.next()) |component| {
            if (std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
                return step.fail("unsafe protected Boundary oracle component '{s}'", .{component.name});
            }
            const child = protected_current.openDir(io, component.name, .{
                .iterate = protected_components.peekNext() == null,
                .follow_symlinks = false,
            }) catch |err| return step.fail(
                "unable to open protected Boundary oracle component '{s}' without following links: {s}",
                .{ component.name, @errorName(err) },
            );
            protected_opened.append(options.gpa, child) catch |err| {
                child.close(io);
                return err;
            };
            protected_identities.append(
                options.gpa,
                directoryIdentity(child) catch |err| return step.fail(
                    "unable to identify protected Boundary oracle component '{s}': {s}",
                    .{ component.name, @errorName(err) },
                ),
            ) catch |err| return err;
            protected_current = child;
        }
        const protected_subtree_start = protected_identities.items.len - 1;
        const protected_identity = protected_identities.items[protected_subtree_start];
        collectProtectedDescendantIdentities(
            protected_current,
            io,
            options.gpa,
            &protected_identities,
        ) catch |err| return step.fail(
            "unable to identify every protected Boundary oracle descendant: {s}",
            .{@errorName(err)},
        );
        const protected_subtree_identities = protected_identities.items[protected_subtree_start..];

        const source_path = try exact_tree.source_dir.getPath4(step.owner, step);
        var source_opened: std.ArrayList(std.Io.Dir) = .empty;
        defer {
            var index = source_opened.items.len;
            while (index > 0) {
                index -= 1;
                source_opened.items[index].close(io);
            }
            source_opened.deinit(options.gpa);
        }
        var source_dir = source_path.root_dir.handle;
        var source_components = std.Io.Dir.path.componentIterator(source_path.sub_path);
        if (source_components.root()) |root_path| {
            const source_root = std.Io.Dir.openDirAbsolute(io, root_path, .{
                .iterate = source_components.peekNext() == null,
                .follow_symlinks = false,
            }) catch |err| return step.fail(
                "unable to open exact oracle source filesystem root '{s}' without following links: {s}",
                .{ root_path, @errorName(err) },
            );
            source_opened.append(options.gpa, source_root) catch |err| {
                source_root.close(io);
                return err;
            };
            source_dir = source_root;
        } else if (source_path.sub_path.len == 0) {
            const source_root = source_dir.openDir(io, ".", .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |err| return step.fail(
                "unable to open exact oracle source root '{f}' without following links: {s}",
                .{ source_path, @errorName(err) },
            );
            source_opened.append(options.gpa, source_root) catch |err| {
                source_root.close(io);
                return err;
            };
            source_dir = source_root;
        }
        while (source_components.next()) |component| {
            if (std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
                return step.fail("unsafe exact oracle source component '{s}'", .{component.name});
            }
            const child = source_dir.openDir(io, component.name, .{
                .iterate = source_components.peekNext() == null,
                .follow_symlinks = false,
            }) catch |err| return step.fail(
                "unable to open exact oracle source component '{s}' without following links: {s}",
                .{ component.name, @errorName(err) },
            );
            source_opened.append(options.gpa, child) catch |err| {
                child.close(io);
                return err;
            };
            source_dir = child;
        }

        var opened: std.ArrayList(std.Io.Dir) = .empty;
        defer {
            var index = opened.items.len;
            while (index > 0) {
                index -= 1;
                opened.items[index].close(io);
            }
            opened.deinit(options.gpa);
        }

        const destination_parent_path = std.Io.Dir.path.dirname(exact_tree.destination_path) orelse
            return step.fail("oracle emit destination has no parent: '{s}'", .{exact_tree.destination_path});
        const destination_leaf = std.Io.Dir.path.basename(exact_tree.destination_path);
        if (destination_leaf.len == 0) {
            return step.fail("oracle emit destination has no leaf: '{s}'", .{exact_tree.destination_path});
        }

        var current = std.Io.Dir.cwd();
        var destination_components = std.Io.Dir.path.componentIterator(destination_parent_path);
        const root_path = destination_components.root() orelse
            return step.fail("oracle emit destination is not absolute: '{s}'", .{exact_tree.destination_path});
        const root = std.Io.Dir.openDirAbsolute(io, root_path, .{
            .follow_symlinks = false,
        }) catch |err| return step.fail(
            "unable to open oracle destination filesystem root '{s}' without following links: {s}",
            .{ root_path, @errorName(err) },
        );
        opened.append(options.gpa, root) catch |err| {
            root.close(io);
            return err;
        };
        current = root;
        const root_identity = directoryIdentity(root) catch |err| return step.fail(
            "unable to identify oracle destination filesystem root '{s}': {s}",
            .{ root_path, @errorName(err) },
        );
        if (identityMatchesAny(root_identity, protected_subtree_identities)) {
            return step.fail("refusing protected Boundary oracle destination ancestor '{s}'", .{root_path});
        }

        var destination_used_link = false;
        while (destination_components.next()) |component| {
            if (std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
                return step.fail("unsafe oracle destination component '{s}'", .{component.name});
            }
            const resolved_child = openOrCreateDestinationDir(current, io, component.name) catch |err| return step.fail(
                "unable to resolve or create oracle destination component '{s}': {s}",
                .{ component.name, @errorName(err) },
            );
            const child = resolved_child.dir;
            opened.append(options.gpa, child) catch |err| {
                child.close(io);
                return err;
            };
            current = child;
            destination_used_link = destination_used_link or resolved_child.followed_link;
            const child_identity = directoryIdentity(child) catch |err| return step.fail(
                "unable to identify oracle destination component '{s}': {s}",
                .{ component.name, @errorName(err) },
            );
            if (identityMatchesAny(child_identity, protected_subtree_identities)) {
                return step.fail(
                    "refusing filesystem alias of protected Boundary oracle corpus or descendant at destination component '{s}'",
                    .{component.name},
                );
            }
            const resolved_inside_protected = if (destination_used_link)
                directoryIsWithinIdentity(child, io, protected_identity) catch |err| {
                    return step.fail(
                        "unable to prove resolved oracle destination component '{s}' stays outside protected corpus: {s}",
                        .{ component.name, @errorName(err) },
                    );
                }
            else
                false;
            if (resolved_inside_protected) {
                return step.fail(
                    "refusing resolved oracle destination component '{s}' inside protected Boundary oracle corpus",
                    .{component.name},
                );
            }
        }

        var validated_destination_identity: ?FileIdentity = null;
        const retained_destination = openExistingDestinationLeafNoFollow(
            current,
            io,
            destination_leaf,
        ) catch |err| switch (err) {
            error.LinkedOracleDestination => return step.fail(
                "refusing symbolic-link oracle destination leaf '{s}'",
                .{destination_leaf},
            ),
            else => return step.fail(
                "unable to inspect oracle destination leaf '{s}' without following links: {s}",
                .{ destination_leaf, @errorName(err) },
            ),
        };
        var retained_destination_open = retained_destination != null;
        defer if (retained_destination_open) retained_destination.?.close(io);
        if (retained_destination) |existing| {
            const destination_identity = directoryIdentity(existing) catch |err| return step.fail(
                "unable to identify oracle destination leaf '{s}': {s}",
                .{ destination_leaf, @errorName(err) },
            );
            if (identityMatchesAny(destination_identity, protected_identities.items)) {
                return step.fail(
                    "refusing filesystem alias '{s}' of protected Boundary oracle corpus or ancestor '{s}'",
                    .{ exact_tree.destination_path, exact_tree.protected_path },
                );
            }
            validated_destination_identity = destination_identity;
        }

        const container_tree_name = "tree";

        var staging_name_buffer: [80]u8 = undefined;
        var staging_name: []const u8 = "";
        var staging_container = std.Io.Dir.cwd();
        var staging_container_identity: FileIdentity = .{ .device = 0, .inode = 0 };
        var attempt: usize = 0;
        while (attempt < 16) : (attempt += 1) {
            var random_integer: u64 = 0;
            io.random(@ptrCast(&random_integer));
            staging_name = std.fmt.bufPrint(
                &staging_name_buffer,
                ".boundary-oracle-stage-{x}",
                .{random_integer},
            ) catch |err| return step.fail("unable to encode private staged oracle container name: {s}", .{@errorName(err)});
            current.createDir(io, staging_name, private_dir_permissions) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return step.fail(
                    "unable to create private staged oracle container '{s}': {s}",
                    .{ staging_name, @errorName(err) },
                ),
            };
            staging_container = current.openDir(io, staging_name, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |err| {
                current.deleteDir(io, staging_name) catch |cleanup_err| return step.fail(
                    "unable to open private staged oracle container '{s}' without following links: {s}; non-recursive cleanup also failed: {s}",
                    .{ staging_name, @errorName(err), @errorName(cleanup_err) },
                );
                return step.fail(
                    "unable to open private staged oracle container '{s}' without following links: {s}",
                    .{ staging_name, @errorName(err) },
                );
            };
            staging_container_identity = directoryIdentity(staging_container) catch |err| {
                staging_container.close(io);
                current.deleteDir(io, staging_name) catch |cleanup_err| return step.fail(
                    "unable to identify private staged oracle container '{s}': {s}; non-recursive cleanup also failed: {s}",
                    .{ staging_name, @errorName(err), @errorName(cleanup_err) },
                );
                return step.fail(
                    "unable to identify private staged oracle container '{s}': {s}",
                    .{ staging_name, @errorName(err) },
                );
            };
            break;
        } else return step.fail("unable to allocate a unique private staged oracle container", .{});

        var staging_container_open = true;
        var staging_container_created = true;
        var staging_tree = std.Io.Dir.cwd();
        var staging_tree_identity: ?FileIdentity = null;
        var staging_tree_open = false;
        var staging_tree_present = false;
        defer {
            if (staging_tree_open) staging_tree.close(io);
            if (staging_tree_present) {
                cleanupQuarantinedLeaf(
                    staging_container,
                    io,
                    container_tree_name,
                    staging_tree_identity,
                    protected_identities.items,
                ) catch |cleanup_err| std.log.err(
                    "unable to clean unpublished staged oracle tree in private container '{s}': {s}",
                    .{ staging_name, @errorName(cleanup_err) },
                );
            }
            if (staging_container_open) staging_container.close(io);
            if (staging_container_created) {
                cleanupEmptyContainerName(
                    current,
                    io,
                    staging_name,
                    staging_container_identity,
                ) catch |cleanup_err| std.log.err(
                    "unable to clean private staged oracle container '{s}': {s}",
                    .{ staging_name, @errorName(cleanup_err) },
                );
            }
        }

        staging_container.createDir(io, container_tree_name, public_dir_permissions) catch |err| return step.fail(
            "unable to create staged oracle tree inside private container '{s}': {s}",
            .{ staging_name, @errorName(err) },
        );
        staging_tree_present = true;
        staging_tree = staging_container.openDir(io, container_tree_name, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| {
            staging_container.deleteDir(io, container_tree_name) catch |cleanup_err| return step.fail(
                "unable to open staged oracle tree in private container '{s}': {s}; non-recursive cleanup also failed: {s}",
                .{ staging_name, @errorName(err), @errorName(cleanup_err) },
            );
            staging_tree_present = false;
            return step.fail(
                "unable to open staged oracle tree in private container '{s}': {s}",
                .{ staging_name, @errorName(err) },
            );
        };
        staging_tree_open = true;
        if (std.Io.Dir.Permissions.has_executable_bit) {
            staging_tree.setPermissions(io, public_dir_permissions) catch |err| return step.fail(
                "unable to set public permissions on staged oracle tree in private container '{s}': {s}",
                .{ staging_name, @errorName(err) },
            );
        }
        staging_tree_identity = directoryIdentity(staging_tree) catch |err| return step.fail(
            "unable to identify staged oracle tree in private container '{s}': {s}",
            .{ staging_name, @errorName(err) },
        );

        copyTreeNoFollow(source_dir, staging_tree, io) catch |err| return step.fail(
            "unable to copy exact oracle candidate into private staged tree '{s}/{s}': {s}",
            .{ staging_name, container_tree_name, @errorName(err) },
        );

        var quarantine_name_buffer: [80]u8 = undefined;
        var quarantine_name: []const u8 = "";
        var quarantine_container = std.Io.Dir.cwd();
        var quarantine_container_identity: FileIdentity = .{ .device = 0, .inode = 0 };
        attempt = 0;
        while (attempt < 16) : (attempt += 1) {
            var random_integer: u64 = 0;
            io.random(@ptrCast(&random_integer));
            quarantine_name = std.fmt.bufPrint(
                &quarantine_name_buffer,
                ".boundary-oracle-old-{x}",
                .{random_integer},
            ) catch |err| return step.fail("unable to encode private quarantine container name: {s}", .{@errorName(err)});
            current.createDir(io, quarantine_name, private_dir_permissions) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return step.fail(
                    "unable to create private prior-oracle quarantine container '{s}': {s}",
                    .{ quarantine_name, @errorName(err) },
                ),
            };
            quarantine_container = current.openDir(io, quarantine_name, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |err| {
                current.deleteDir(io, quarantine_name) catch |cleanup_err| return step.fail(
                    "unable to open private prior-oracle quarantine container '{s}': {s}; non-recursive cleanup also failed: {s}",
                    .{ quarantine_name, @errorName(err), @errorName(cleanup_err) },
                );
                return step.fail(
                    "unable to open private prior-oracle quarantine container '{s}': {s}",
                    .{ quarantine_name, @errorName(err) },
                );
            };
            quarantine_container_identity = directoryIdentity(quarantine_container) catch |err| {
                quarantine_container.close(io);
                current.deleteDir(io, quarantine_name) catch |cleanup_err| return step.fail(
                    "unable to identify private prior-oracle quarantine container '{s}': {s}; non-recursive cleanup also failed: {s}",
                    .{ quarantine_name, @errorName(err), @errorName(cleanup_err) },
                );
                return step.fail(
                    "unable to identify private prior-oracle quarantine container '{s}': {s}",
                    .{ quarantine_name, @errorName(err) },
                );
            };
            break;
        } else return step.fail("unable to allocate a unique private prior-oracle quarantine container", .{});

        var quarantine_container_open = true;
        var quarantine_container_created = true;
        var quarantine_tree_present = false;
        defer {
            if (quarantine_container_open) quarantine_container.close(io);
            if (quarantine_container_created and !quarantine_tree_present) {
                cleanupEmptyContainerName(
                    current,
                    io,
                    quarantine_name,
                    quarantine_container_identity,
                ) catch |cleanup_err| std.log.err(
                    "unable to clean private prior-oracle quarantine container '{s}': {s}",
                    .{ quarantine_name, @errorName(cleanup_err) },
                );
            }
        }

        const current_destination_identity = observedDestinationIdentity(
            current,
            io,
            destination_leaf,
        ) catch |err| return step.fail(
            "unable to revalidate oracle destination leaf '{s}' before publication: {s}",
            .{ destination_leaf, @errorName(err) },
        );
        if (!destinationObservationMatches(validated_destination_identity, current_destination_identity)) {
            return step.fail(
                "oracle destination leaf '{s}' changed after admission; receiver was not quarantined or replaced",
                .{destination_leaf},
            );
        }

        if (validated_destination_identity != null) {
            current.rename(destination_leaf, quarantine_container, container_tree_name, io) catch |err| {
                return step.fail(
                    "unable to quarantine the admitted oracle destination '{s}' through private container '{s}': {s}",
                    .{ destination_leaf, quarantine_name, @errorName(err) },
                );
            };
            quarantine_tree_present = true;

            const postcheck = resolveQuarantinePostcheck(
                validated_destination_identity.?,
                observedDestinationIdentity(
                    quarantine_container,
                    io,
                    container_tree_name,
                ),
            );
            switch (postcheck) {
                .verified => {},
                .observation_failed => |observation_err| return step.fail(
                    "unable to identify quarantined prior oracle destination '{s}/{s}': {s}; the unproved moved entry remains quarantined and restoration and publication were not attempted",
                    .{ quarantine_name, container_tree_name, @errorName(observation_err) },
                ),
                .identity_mismatch => return step.fail(
                    "quarantined prior oracle destination '{s}/{s}' does not match the admitted receiver identity for '{s}'; the unproved moved entry remains quarantined and restoration and publication were not attempted",
                    .{ quarantine_name, container_tree_name, destination_leaf },
                ),
            }
            retained_destination.?.close(io);
            retained_destination_open = false;
        }

        renameEntryNoReplace(
            staging_container,
            container_tree_name,
            current,
            destination_leaf,
            io,
        ) catch |publish_err| {
            if (quarantine_tree_present) {
                restoreQuarantinedEntry(
                    quarantine_container,
                    current,
                    io,
                    container_tree_name,
                    destination_leaf,
                ) catch |rollback_err| {
                    return step.fail(
                        "unable to publish staged oracle tree from private container '{s}' as '{s}': {s}; prior tree remains in quarantine '{s}/{s}' because rollback failed: {s}",
                        .{
                            staging_name,
                            destination_leaf,
                            @errorName(publish_err),
                            quarantine_name,
                            container_tree_name,
                            @errorName(rollback_err),
                        },
                    );
                };
                quarantine_tree_present = false;
                return step.fail(
                    "unable to publish staged oracle tree from private container '{s}' as '{s}': {s}; prior destination was restored",
                    .{ staging_name, destination_leaf, @errorName(publish_err) },
                );
            }
            return step.fail(
                "unable to publish staged oracle tree from private container '{s}' as '{s}': {s}; no prior destination was moved",
                .{ staging_name, destination_leaf, @errorName(publish_err) },
            );
        };
        staging_tree_present = false;
        staging_tree.close(io);
        staging_tree_open = false;
        staging_container.close(io);
        staging_container_open = false;
        var stage_cleanup_error: ?anyerror = null;
        cleanupEmptyContainerName(
            current,
            io,
            staging_name,
            staging_container_identity,
        ) catch |cleanup_err| {
            stage_cleanup_error = cleanup_err;
        };
        if (stage_cleanup_error == null) staging_container_created = false;

        if (quarantine_tree_present) {
            cleanupQuarantinedLeaf(
                quarantine_container,
                io,
                container_tree_name,
                validated_destination_identity,
                protected_identities.items,
            ) catch |cleanup_err| return step.fail(
                "published exact oracle destination '{s}', but prior tree remains in private quarantine '{s}/{s}' after handle-relative cleanup failed: {s}",
                .{ destination_leaf, quarantine_name, container_tree_name, @errorName(cleanup_err) },
            );
            quarantine_tree_present = false;
        }
        quarantine_container.close(io);
        quarantine_container_open = false;
        cleanupEmptyContainerName(
            current,
            io,
            quarantine_name,
            quarantine_container_identity,
        ) catch |cleanup_err| return step.fail(
            "published exact oracle destination '{s}', but empty private quarantine container '{s}' remains: {s}",
            .{ destination_leaf, quarantine_name, @errorName(cleanup_err) },
        );
        quarantine_container_created = false;

        if (stage_cleanup_error) |cleanup_err| {
            return step.fail(
                "published exact oracle destination '{s}', but empty private staging container '{s}' remains: {s}",
                .{ destination_leaf, staging_name, @errorName(cleanup_err) },
            );
        }
        step.result_cached = false;
    }
};

test "exact oracle identities compare canonically" {
    try ExactInstallTreeStep.testFileIdentityComparison();
}

test "exact oracle destination collision preserves the receiver directory" {
    try ExactInstallTreeStep.testDestinationCollisionPreservesReceiverDirectory();
}

test "exact oracle destination collision classifier includes DirNotEmpty" {
    try ExactInstallTreeStep.testDestinationCollisionClassification();
}

test "exact oracle destination setup preserves its primary error" {
    try ExactInstallTreeStep.testDestinationSetupPrimaryErrorPrecedence();
}

test "exact oracle destination collision preserves its primary error when cleanup fails" {
    try ExactInstallTreeStep.testDestinationCollisionPreservesPrimaryErrorWhenCleanupFails();
}

test "exact oracle final promotion preserves an empty receiver directory" {
    try ExactInstallTreeStep.testNoReplacePromotionPreservesReceiverDirectory();
}

test "exact-install quarantine ambiguity preserves the unproved moved entry" {
    try ExactInstallTreeStep.testAmbiguousQuarantineObservationPreservesUnprovedMovedEntry();
}

test "exact oracle protection includes descendant directory identities" {
    try ExactInstallTreeStep.testProtectedDescendantIdentityCollection();
}

test "exact oracle protected descendants reclassify unknown hints no-follow" {
    try ExactInstallTreeStep.testProtectedDescendantUnknownKindReclassification();
}

test "exact oracle destination leaf rejects symbolic links" {
    try ExactInstallTreeStep.testLinkedDestinationLeafRejected();
}

test "exact oracle unknown iterator hints are reclassified no-follow" {
    try ExactInstallTreeStep.testUnknownEntryKindReclassification();
}

test "exact oracle cleanup entry kinds dispatch exhaustively no-follow" {
    try ExactInstallTreeStep.testCleanupEntryKindDispatch();
    try ExactInstallTreeStep.testUnknownDirectoryCleanup();
}

test "exact oracle cleanup depth is bounded before descent" {
    try ExactInstallTreeStep.testCleanupDepthBound();
}

test "exact oracle cleanup work is cumulatively bounded" {
    try ExactInstallTreeStep.testCleanupWorkBound();
}

test "exact oracle Linux identity observes the retained directory with statx" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    try ExactInstallTreeStep.testLinuxStatxIdentityObservation();
}

test "exact oracle Linux statx identity rejects an unattested inode" {
    var statx = std.mem.zeroes(std.os.linux.Statx);
    statx.ino = 17;
    try std.testing.expectError(
        error.OracleFileIdentityUnavailable,
        ExactInstallTreeStep.linuxStatxIdentity(statx),
    );
    statx.mask.INO = true;
    try std.testing.expectEqual(
        ExactInstallTreeStep.FileIdentity{ .device = 0, .inode = 17 },
        try ExactInstallTreeStep.linuxStatxIdentity(statx),
    );
}

fn parseTestArgs(b: *std.Build) TestArgs {
    const args = b.args orelse return .{
        .filters = &.{},
        .passthrough = &.{},
    };

    var filters: std.ArrayList([]const u8) = .empty;
    var passthrough: std.ArrayList([]const u8) = .empty;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected a non-empty pattern after '--test-filter'.", .{});
            }
            filters.append(b.allocator, args[index]) catch |err|
                std.process.fatal("unable to store test filter: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            const pattern = arg["--test-filter=".len..];
            if (pattern.len == 0) {
                std.process.fatal("Expected '--test-filter=' to include a non-empty pattern.", .{});
            }
            filters.append(b.allocator, pattern) catch |err|
                std.process.fatal("unable to store test filter: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.eql(u8, arg, "--seed")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected an unsigned 32-bit integer after '--seed'.", .{});
            }
            _ = std.fmt.parseUnsigned(u32, args[index], 0) catch
                std.process.fatal("Expected '--seed' to contain an unsigned 32-bit integer; got '{s}'.", .{args[index]});
            passthrough.append(b.allocator, b.fmt("--seed={s}", .{args[index]})) catch |err|
                std.process.fatal("unable to store test runner seed: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            const seed = arg["--seed=".len..];
            if (seed.len == 0) {
                std.process.fatal("Expected '--seed=' to include an unsigned 32-bit integer.", .{});
            }
            _ = std.fmt.parseUnsigned(u32, seed, 0) catch
                std.process.fatal("Expected '--seed' to contain an unsigned 32-bit integer; got '{s}'.", .{seed});
            passthrough.append(b.allocator, arg) catch |err|
                std.process.fatal("unable to store test runner seed: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.eql(u8, arg, "--cache-dir")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected a path after '--cache-dir'.", .{});
            }
            passthrough.append(b.allocator, b.fmt("--cache-dir={s}", .{args[index]})) catch |err|
                std.process.fatal("unable to store test runner cache directory: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--cache-dir=")) {
            if (arg["--cache-dir=".len..].len == 0) {
                std.process.fatal("Expected '--cache-dir=' to include a path.", .{});
            }
            passthrough.append(b.allocator, arg) catch |err|
                std.process.fatal("unable to store test runner cache directory: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-warnings")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected a non-empty limit after '--max-warnings'.", .{});
            }
            _ = std.fmt.parseUnsigned(usize, args[index], 10) catch
                std.process.fatal("Expected '--max-warnings' to contain an unsigned integer; got '{s}'.", .{args[index]});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--max-warnings=")) {
            const limit = arg["--max-warnings=".len..];
            if (limit.len == 0) {
                std.process.fatal("Expected '--max-warnings=' to include a non-empty limit.", .{});
            }
            _ = std.fmt.parseUnsigned(usize, limit, 10) catch
                std.process.fatal("Expected '--max-warnings' to contain an unsigned integer; got '{s}'.", .{limit});
            continue;
        }
        passthrough.append(b.allocator, arg) catch |err|
            std.process.fatal("unable to store test runner argument: {s}", .{@errorName(err)});
    }

    return .{
        .filters = filters.toOwnedSlice(b.allocator) catch |err|
            std.process.fatal("unable to finalize test filters: {s}", .{@errorName(err)}),
        .passthrough = passthrough.toOwnedSlice(b.allocator) catch |err|
            std.process.fatal("unable to finalize test runner arguments: {s}", .{@errorName(err)}),
    };
}

fn addRunArtifactWithArgs(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    args: []const []const u8,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(artifact);
    if (args.len != 0) run.addArgs(args);
    return run;
}

fn addTestArtifact(
    b: *std.Build,
    test_step: *std.Build.Step,
    root_module: *std.Build.Module,
    test_args: TestArgs,
) void {
    const tests = b.addTest(.{ .root_module = root_module, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, tests, test_args.passthrough).step);
}

fn addCompileFailArtifact(
    b: *std.Build,
    compile_fail_step: *std.Build.Step,
    root_module: *std.Build.Module,
    expected_error: []const u8,
) void {
    const tests = b.addTest(.{ .root_module = root_module });
    tests.expect_errors = .{ .contains = expected_error };
    compile_fail_step.dependOn(&tests.step);
}

fn addZigPathCoverageGuard(b: *std.Build) *std.Build.Step {
    const guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\tmp="${TMPDIR:-/tmp}/boundary-zig-paths-$$"
        \\trap 'rm -f "$tmp.actual" "$tmp.actual.unsorted" "$tmp.expected" "$tmp.expected.unsorted"' EXIT
        \\find src examples test bench -type f -name '*.zig' > "$tmp.actual.unsorted"
        \\sort "$tmp.actual.unsorted" > "$tmp.actual"
        \\grep -E '^(src|examples|test|bench)/.*\.zig$' repo_zig_paths.txt > "$tmp.expected.unsorted"
        \\sort "$tmp.expected.unsorted" > "$tmp.expected"
        \\diff -u "$tmp.expected" "$tmp.actual"
    });
    guard.setCwd(b.path("."));
    return &guard.step;
}

fn addGlobalCacheCwdOwnershipProbe(b: *std.Build) *std.Build.Step {
    const global_cache_path = b.graph.global_cache_root.path orelse
        std.process.fatal("selected global cache has no path carrier", .{});

    const leaf = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\case "$1" in
        \\  /*) ;;
        \\  *) exit 1 ;;
        \\esac
        \\test -d "$1"
        ,
        "boundary-global-cache-owner-leaf",
        global_cache_path,
    });
    leaf.setName("check canonical global-cache path from repository root");
    leaf.setCwd(b.path("."));
    const leaf_step = b.step(
        "check-boundary-global-cache-path-owner-leaf",
        "Check that the selected global-cache carrier is an absolute directory from the repository root.",
    );
    leaf_step.dependOn(&leaf.step);

    const probe = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\tmp=$(mktemp -d "${TMPDIR:-/tmp}/boundary-global-cache-owner.XXXXXX")
        \\trap 'rm -rf "$tmp"' EXIT HUP INT TERM
        \\ln -s "$1" "$tmp/build.zig"
        \\cd "$tmp"
        \\"$2" build --build-file "$3" --cache-dir local-cache --global-cache-dir build.zig check-boundary-global-cache-path-owner-leaf --summary all
        ,
        "boundary-global-cache-owner-probe",
        global_cache_path,
        b.graph.zig_exe,
        b.pathFromRoot("build.zig"),
    });
    probe.setName("check external-cwd relative global-cache ownership");
    const probe_step = b.step(
        "check-boundary-global-cache-cwd-ownership",
        "Check relative global-cache ownership across an external build cwd and repository-root child.",
    );
    probe_step.dependOn(&probe.step);
    return probe_step;
}

fn addCoreModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CoreModules {
    const metadata_options = b.addOptions();
    metadata_options.addOption([]const u8, "boundary_package_version", package.version);
    metadata_options.addOption([]const u8, "minimum_zig_version", package.minimum_zig_version);
    const boundary_build_metadata = metadata_options.createModule();

    const portable_core = b.createModule(.{
        .root_source_file = b.path("src/portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const effect_ir = b.createModule(.{
        .root_source_file = b.path("src/effect_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_scenarios = b.createModule(.{
        .root_source_file = b.path("src/parity_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    const helper_body_ir = b.createModule(.{
        .root_source_file = b.path("src/private_modules/helper_body_ir_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    const program_frontend = b.createModule(.{
        .root_source_file = b.path("src/program_frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_frontend.addImport("effect_ir", effect_ir);
    program_frontend.addImport("helper_body_ir", helper_body_ir);
    program_frontend.addImport("parity_scenarios", parity_scenarios);
    const internal_program_plan = b.createModule(.{
        .root_source_file = b.path("src/internal_program_plan.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_program_plan.addImport("effect_ir", effect_ir);
    internal_program_plan.addImport("program_frontend", program_frontend);
    helper_body_ir.addImport("internal_program_plan", internal_program_plan);
    helper_body_ir.addImport("effect_ir", effect_ir);

    const loaded_execution = b.createModule(.{
        .root_source_file = b.path("src/program/loaded_execution.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_execution.addImport("internal_program_plan", internal_program_plan);

    const internal_kernel = b.createModule(.{
        .root_source_file = b.path("src/private_modules/internal_kernel_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_kernel.addImport("internal_program_plan", internal_program_plan);
    internal_kernel.addImport("parity_scenarios", parity_scenarios);

    const lowered_machine = b.createModule(.{
        .root_source_file = b.path("src/private_modules/lowered_machine_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowered_machine.addImport("internal_kernel", internal_kernel);
    lowered_machine.addImport("portable_core", portable_core);
    lowered_machine.addImport("parity_scenarios", parity_scenarios);

    const prompt_contract = b.createModule(.{
        .root_source_file = b.path("src/prompt_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_contract.addImport("portable_core", portable_core);

    const frontend = b.createModule(.{
        .root_source_file = b.path("src/frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    frontend.addImport("lowered_machine", lowered_machine);
    frontend.addImport("portable_core", portable_core);
    frontend.addImport("prompt_contract_support", prompt_contract);

    const interpreter = b.createModule(.{
        .root_source_file = b.path("src/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    interpreter.addImport("internal_kernel", internal_kernel);

    const lowering_api = b.createModule(.{
        .root_source_file = b.path("src/lowering_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowering_api.addImport("lowered_machine", lowered_machine);
    lowering_api.addImport("internal_program_plan", internal_program_plan);

    return .{
        .boundary_build_metadata = boundary_build_metadata,
        .portable_core = portable_core,
        .lowered_machine = lowered_machine,
        .prompt_contract = prompt_contract,
        .frontend = frontend,
        .effect_ir = effect_ir,
        .helper_body_ir = helper_body_ir,
        .internal_kernel = internal_kernel,
        .internal_program_plan = internal_program_plan,
        .loaded_execution = loaded_execution,
        .interpreter = interpreter,
        .lowering_api = lowering_api,
        .parity_scenarios = parity_scenarios,
    };
}

fn wireBoundaryImports(mod: *std.Build.Module, core: CoreModules) void {
    mod.addImport("boundary_build_metadata", core.boundary_build_metadata);
    mod.addImport("portable_core", core.portable_core);
    mod.addImport("lowered_machine", core.lowered_machine);
    mod.addImport("prompt_contract_support", core.prompt_contract);
    mod.addImport("frontend_support", core.frontend);
    mod.addImport("effect_ir", core.effect_ir);
    mod.addImport("helper_body_ir", core.helper_body_ir);
    mod.addImport("internal_kernel", core.internal_kernel);
    mod.addImport("internal_program_plan", core.internal_program_plan);
    mod.addImport("loaded_execution", core.loaded_execution);
    mod.addImport("interpreter", core.interpreter);
    mod.addImport("lowering_api", core.lowering_api);
    mod.addImport("parity_scenarios", core.parity_scenarios);
}

pub fn build(b: *std.Build) void {
    canonicalizeBuildOwnedCacheRoots(b);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const test_args = parseTestArgs(b);
    const proof_test_args = TestArgs{ .filters = &.{}, .passthrough = &.{} };
    const core = addCoreModules(b, target, optimize);
    const host_core = addCoreModules(b, b.graph.host, optimize);

    const boundary_shared = b.createModule(.{
        .root_source_file = b.path("src/boundary_shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(boundary_shared, core);

    const host_boundary_shared = b.createModule(.{
        .root_source_file = b.path("src/boundary_shared.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wireBoundaryImports(host_boundary_shared, host_core);

    const protocol_mod = b.createModule(.{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(protocol_mod, core);

    const host_protocol_mod = b.createModule(.{
        .root_source_file = b.path("src/protocol.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wireBoundaryImports(host_protocol_mod, host_core);

    const protocol_artifacts_mod = b.createModule(.{
        .root_source_file = b.path("src/protocol_artifacts.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wireBoundaryImports(protocol_artifacts_mod, host_core);
    protocol_artifacts_mod.addImport("protocol", host_protocol_mod);

    const boundary = b.addModule("boundary", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary.addImport("boundary_shared", boundary_shared);

    const host_boundary = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    host_boundary.addImport("boundary_shared", host_boundary_shared);

    const lib_check = b.addLibrary(.{
        .linkage = .static,
        .name = "boundary",
        .root_module = boundary,
    });
    b.installArtifact(lib_check);

    const test_step = b.step("test", "Run the boundary test suite.");
    const check_step = b.step("check", "Run the full Boundary validation suite.");
    check_step.dependOn(test_step);
    const build_script_tests_mod = b.createModule(.{
        .root_source_file = b.path("build.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    build_script_tests_mod.addImport("zlinter", b.dependency("zlinter", .{}).module("zlinter"));
    addTestArtifact(b, test_step, build_script_tests_mod, test_args);
    addTestArtifact(b, test_step, boundary, test_args);
    addTestArtifact(b, test_step, boundary_shared, test_args);
    addTestArtifact(b, test_step, core.effect_ir, test_args);
    addTestArtifact(b, test_step, core.frontend, test_args);
    addTestArtifact(b, test_step, core.internal_kernel, test_args);
    addTestArtifact(b, test_step, core.internal_program_plan, test_args);
    addTestArtifact(b, test_step, core.loaded_execution, test_args);
    addTestArtifact(b, test_step, core.lowered_machine, test_args);
    addTestArtifact(b, test_step, core.portable_core, test_args);
    addTestArtifact(b, test_step, protocol_mod, test_args);
    addTestArtifact(b, test_step, protocol_artifacts_mod, test_args);

    const protocol_manifest_step = b.step("check-boundary-protocol-manifest", "Check Boundary v0 protocol manifest encoding and fingerprint.");
    addTestArtifact(b, protocol_manifest_step, host_protocol_mod, proof_test_args);

    const protocol_artifacts_exe = b.addExecutable(.{
        .name = "boundary-protocol-artifacts",
        .root_module = protocol_artifacts_mod,
    });

    const update_public_surface_step = b.step("update-boundary-public-surface", "Update Boundary v0 public-surface snapshot.");
    update_public_surface_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"update-public-surface"}).step);

    const public_surface_step = b.step("check-boundary-public-surface", "Check Boundary v0 public-surface snapshot for drift.");
    public_surface_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-public-surface"}).step);

    const update_corpus_step = b.step("update-boundary-conformance-corpus", "Update Boundary v0 conformance corpus artifacts.");
    update_corpus_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"update-corpus"}).step);

    const corpus_step = b.step("check-boundary-conformance-corpus", "Check Boundary v0 conformance corpus artifacts.");
    corpus_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-corpus"}).step);

    const agent_profile_step = b.step("check-boundary-agent-profile", "Check Boundary Agent Profile v0 schema and fingerprint surface.");
    const agent_profile_mod = b.createModule(.{
        .root_source_file = b.path("src/agent.zig"),
        .target = target,
        .optimize = optimize,
    });
    addTestArtifact(b, agent_profile_step, agent_profile_mod, test_args);
    const receipt_agent_profile_step = b.step("check-boundary-agent-profile-receipt-host", "Check Boundary Agent Profile v0 proof receipts on the host target.");
    const receipt_agent_profile_mod = b.createModule(.{
        .root_source_file = b.path("src/agent.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    addTestArtifact(b, receipt_agent_profile_step, receipt_agent_profile_mod, proof_test_args);

    const agent_artifacts_mod = b.createModule(.{
        .root_source_file = b.path("src/agent_artifacts.zig"),
        .target = target,
        .optimize = optimize,
    });
    addTestArtifact(b, test_step, agent_artifacts_mod, test_args);
    const host_agent_artifacts_mod = b.createModule(.{
        .root_source_file = b.path("src/agent_artifacts.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const agent_artifacts_exe = b.addExecutable(.{
        .name = "boundary-agent-artifacts",
        .root_module = host_agent_artifacts_mod,
    });
    const update_agent_corpus_step = b.step("update-boundary-agent-conformance-corpus", "Update Boundary Agent Profile v0 conformance corpus artifacts.");
    update_agent_corpus_step.dependOn(&addRunArtifactWithArgs(b, agent_artifacts_exe, &.{"update-corpus"}).step);

    const agent_modules_step = b.step("check-boundary-agent-modules", "Check agent-shaped Certified Boundary Module transfer surface.");
    const agent_modules_mod = b.createModule(.{
        .root_source_file = b.path("examples/boundary_module_agent_transfer.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_modules_mod.addImport("boundary", boundary);
    addTestArtifact(b, agent_modules_step, agent_modules_mod, test_args);
    const agent_module_manifest_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_module_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_module_manifest_mod.addImport("boundary", boundary);
    addTestArtifact(b, agent_modules_step, agent_module_manifest_mod, test_args);
    const receipt_agent_modules_step = b.step("check-boundary-agent-modules-receipt-host", "Check agent-shaped Certified Boundary Module proof receipts on the host target.");
    const receipt_agent_modules_mod = b.createModule(.{
        .root_source_file = b.path("examples/boundary_module_agent_transfer.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_agent_modules_mod.addImport("boundary", host_boundary);
    addTestArtifact(b, receipt_agent_modules_step, receipt_agent_modules_mod, proof_test_args);
    const receipt_agent_manifest_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_module_manifest.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_agent_manifest_mod.addImport("boundary", host_boundary);
    addTestArtifact(b, receipt_agent_modules_step, receipt_agent_manifest_mod, proof_test_args);

    const agent_conformance_corpus_step = b.step("check-boundary-agent-conformance-corpus", "Check Boundary Agent Closure v0 conformance foundations.");
    agent_conformance_corpus_step.dependOn(agent_profile_step);
    agent_conformance_corpus_step.dependOn(agent_modules_step);
    agent_conformance_corpus_step.dependOn(&addRunArtifactWithArgs(b, agent_artifacts_exe, &.{"check-corpus"}).step);
    const agent_conformance_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_profile_conformance.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_conformance_mod.addImport("boundary", boundary);
    addTestArtifact(b, agent_conformance_corpus_step, agent_conformance_mod, test_args);
    const receipt_agent_corpus_step = b.step("check-boundary-agent-conformance-corpus-receipt-host", "Check Boundary Agent Closure v0 conformance proof receipts on the host target.");
    receipt_agent_corpus_step.dependOn(receipt_agent_profile_step);
    receipt_agent_corpus_step.dependOn(receipt_agent_modules_step);
    receipt_agent_corpus_step.dependOn(&addRunArtifactWithArgs(b, agent_artifacts_exe, &.{"check-corpus"}).step);
    const receipt_agent_conformance_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_profile_conformance.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_agent_conformance_mod.addImport("boundary", host_boundary);
    addTestArtifact(b, receipt_agent_corpus_step, receipt_agent_conformance_mod, proof_test_args);

    const format_drift_step = b.step("check-boundary-format-drift", "Check Boundary v0 format and public-surface drift.");
    format_drift_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-format-drift"}).step);

    const adversarial_codecs_step = b.step("check-boundary-adversarial-codecs", "Check Boundary v0 adversarial codec guardrails.");
    adversarial_codecs_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-adversarial-codecs"}).step);

    const budgets_step = b.step("check-boundary-v0-budgets", "Check Boundary v0 structural budgets.");
    budgets_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-budgets"}).step);

    const proof_receipts_step = b.step("emit-boundary-proof-receipts", "Emit Boundary v0 proof receipts.");
    proof_receipts_step.dependOn(protocol_manifest_step);
    proof_receipts_step.dependOn(public_surface_step);
    proof_receipts_step.dependOn(format_drift_step);
    proof_receipts_step.dependOn(corpus_step);
    proof_receipts_step.dependOn(receipt_agent_profile_step);
    proof_receipts_step.dependOn(receipt_agent_modules_step);
    proof_receipts_step.dependOn(receipt_agent_corpus_step);
    proof_receipts_step.dependOn(adversarial_codecs_step);
    proof_receipts_step.dependOn(budgets_step);
    const proof_receipts_run = addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{
        "emit-proof-receipts",
        "--out-dir",
        b.getInstallPath(.prefix, "protocol/boundary/proof-receipts"),
    });
    proof_receipts_run.step.dependOn(protocol_manifest_step);
    proof_receipts_run.step.dependOn(public_surface_step);
    proof_receipts_run.step.dependOn(format_drift_step);
    proof_receipts_run.step.dependOn(corpus_step);
    proof_receipts_run.step.dependOn(receipt_agent_profile_step);
    proof_receipts_run.step.dependOn(receipt_agent_modules_step);
    proof_receipts_run.step.dependOn(receipt_agent_corpus_step);
    proof_receipts_run.step.dependOn(adversarial_codecs_step);
    proof_receipts_run.step.dependOn(budgets_step);
    proof_receipts_step.dependOn(&proof_receipts_run.step);

    const dist_boundary_protocol_step = b.step("dist-boundary-protocol", "Build the Boundary v0 protocol distribution.");
    const dist_boundary_protocol_run = addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{
        "dist",
        "--out-dir",
        b.getInstallPath(.prefix, "dist/boundary-v" ++ package.version ++ "-protocol"),
    });
    dist_boundary_protocol_run.step.dependOn(proof_receipts_step);
    dist_boundary_protocol_step.dependOn(&dist_boundary_protocol_run.step);

    const executable_module_step = b.step("check-boundary-executable-module", "Check executable Certified Boundary Module v2 image foundations.");
    const executable_module_args = TestArgs{
        .filters = &.{"executable plan image"},
        .passthrough = &.{},
    };
    addTestArtifact(b, executable_module_step, boundary, executable_module_args);
    addTestArtifact(b, executable_module_step, boundary_shared, executable_module_args);

    const executable_plan_step = b.step("check-boundary-executable-plan-validation", "Check executable-plan image payload and full-module validation.");
    addTestArtifact(b, executable_plan_step, boundary, executable_module_args);
    addTestArtifact(b, executable_plan_step, boundary_shared, executable_module_args);
    const executable_plan_args = TestArgs{
        .filters = &.{"certified boundary module reference full image and loaded module projections validate"},
        .passthrough = &.{},
    };
    const executable_plan_validation_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    executable_plan_validation_mod.addImport("boundary", boundary);
    const executable_plan_tests = b.addTest(.{ .root_module = executable_plan_validation_mod, .filters = executable_plan_args.filters });
    executable_plan_step.dependOn(&addRunArtifactWithArgs(b, executable_plan_tests, executable_plan_args.passthrough).step);

    const loaded_value_step = b.step("check-boundary-loaded-value", "Check portable loaded value image encoding and validation.");
    const loaded_value_args = TestArgs{
        .filters = &.{"loaded value image"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_value_step, core.loaded_execution, loaded_value_args);
    addTestArtifact(b, loaded_value_step, boundary_shared, loaded_value_args);

    const loaded_session_step = b.step("check-boundary-loaded-session", "Check loaded module session surface and profile compatibility.");
    const loaded_session_args = TestArgs{
        .filters = &.{"loaded"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_session_step, core.loaded_execution, loaded_session_args);
    addTestArtifact(b, loaded_session_step, boundary_shared, loaded_session_args);
    const loaded_evidence_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_evidence_mod.addImport("boundary", boundary);
    const loaded_evidence_tests = b.addTest(.{ .root_module = loaded_evidence_mod, .filters = loaded_session_args.filters });
    loaded_session_step.dependOn(&addRunArtifactWithArgs(b, loaded_evidence_tests, loaded_session_args.passthrough).step);

    const loaded_v2_step = b.step("check-boundary-loaded-v2", "Check Boundary portable_v2 loaded execution profile gates.");
    const loaded_v2_args = TestArgs{
        .filters = &.{"portable v2"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_v2_step, core.loaded_execution, loaded_v2_args);
    const loaded_v2_core_evidence_mod = b.createModule(.{
        .root_source_file = b.path("src/program/evidence.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(loaded_v2_core_evidence_mod, core);
    const loaded_v2_core_evidence_tests = b.addTest(.{ .root_module = loaded_v2_core_evidence_mod, .filters = loaded_v2_args.filters });
    loaded_v2_step.dependOn(&addRunArtifactWithArgs(b, loaded_v2_core_evidence_tests, loaded_v2_args.passthrough).step);
    const loaded_v2_evidence_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_v2_evidence_mod.addImport("boundary", boundary);
    const loaded_v2_evidence_tests = b.addTest(.{ .root_module = loaded_v2_evidence_mod, .filters = loaded_v2_args.filters });
    loaded_v2_step.dependOn(&addRunArtifactWithArgs(b, loaded_v2_evidence_tests, loaded_v2_args.passthrough).step);

    const loaded_profile_codecs_step = b.step("check-boundary-loaded-profile-codecs", "Check loaded profile instruction and value codec gates.");
    const profile_codec_core_args = TestArgs{
        .filters = &.{
            "loaded execution profile",
            "loaded value image",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_profile_codecs_step, core.loaded_execution, profile_codec_core_args);
    const loaded_profile_codecs_args = TestArgs{
        .filters = &.{
            "certified boundary module reference full image and loaded module projections validate",
            "loaded executable portable v2 gates reachable arithmetic before session construction",
            "loaded executable portable v2 uses portable word semantics",
        },
        .passthrough = &.{},
    };
    const loaded_profile_codecs_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_profile_codecs_mod.addImport("boundary", boundary);
    const loaded_profile_codecs_tests = b.addTest(.{ .root_module = loaded_profile_codecs_mod, .filters = loaded_profile_codecs_args.filters });
    loaded_profile_codecs_step.dependOn(&addRunArtifactWithArgs(b, loaded_profile_codecs_tests, loaded_profile_codecs_args.passthrough).step);

    const loaded_reachability_step = b.step("check-boundary-loaded-reachability", "Check reachability-scoped loaded execution compatibility gates.");
    const loaded_reachability_core_args = TestArgs{
        .filters = &.{
            "loaded reachability ignores unsupported dead helper semantics and codecs",
            "loaded portable v2 rejects unsupported helper parking shape before mutable session construction",
        },
        .passthrough = &.{},
    };
    const loaded_reachability_core_mod = b.createModule(.{
        .root_source_file = b.path("src/program/evidence.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(loaded_reachability_core_mod, core);
    const loaded_reachability_core_tests = b.addTest(.{ .root_module = loaded_reachability_core_mod, .filters = loaded_reachability_core_args.filters });
    loaded_reachability_step.dependOn(&addRunArtifactWithArgs(b, loaded_reachability_core_tests, loaded_reachability_core_args.passthrough).step);
    const loaded_reachability_args = TestArgs{
        .filters = &.{
            "certified boundary module reference full image and loaded module projections validate",
            "loaded executable portable v2 gates reachable arithmetic before session construction",
            "loaded executable ignores dead helper call sites for residual imports",
            "loaded executable rejects choice operation mode",
        },
        .passthrough = &.{},
    };
    const loaded_reachability_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_reachability_mod.addImport("boundary", boundary);
    const loaded_reachability_tests = b.addTest(.{ .root_module = loaded_reachability_mod, .filters = loaded_reachability_args.filters });
    loaded_reachability_step.dependOn(&addRunArtifactWithArgs(b, loaded_reachability_tests, loaded_reachability_args.passthrough).step);

    const loaded_continuation_step = b.step("check-boundary-loaded-continuation", "Check portable loaded session continuation images.");
    const loaded_continuation_args = TestArgs{
        .filters = &.{"loaded session image"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_continuation_step, core.loaded_execution, loaded_continuation_args);
    addTestArtifact(b, loaded_continuation_step, boundary_shared, loaded_continuation_args);

    const loaded_session_image_step = b.step("check-boundary-loaded-session-image", "Check loaded session image validation regressions.");
    const loaded_session_image_args = TestArgs{
        .filters = &.{
            "loaded session image roundtrips failure state and rejects trailing bytes",
            "loaded session image binds declared failure ref to diagnostic summary",
            "loaded session image rejects status-inconsistent fuel ledger",
            "loaded session image v2 rejects present continuation with zero frames",
            "loaded session image binds fingerprinted identity fields",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_session_image_step, core.loaded_execution, loaded_session_image_args);

    const loaded_forged_session_step = b.step("check-boundary-loaded-forged-session-image", "Check forged loaded session image rejection regressions.");
    const loaded_forged_session_args = TestArgs{
        .filters = &.{
            "loaded session image rejects forged session fingerprint",
            "loaded session image rejects forged result fingerprint",
            "loaded session image v2 binds pending continuation fingerprint to continuation image",
            "loaded session image rejects malformed embedded value images",
            "loaded session image rejects embedded value ref mismatch",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_forged_session_step, core.loaded_execution, loaded_forged_session_args);
    const forged_session_evidence_args = TestArgs{
        .filters = &.{
            "loaded executable portable v2 restores helper frame parked on residual request",
            "loaded malformed rejects forged v2 continuation frame topology",
        },
        .passthrough = &.{},
    };
    const loaded_forged_session_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_forged_session_mod.addImport("boundary", boundary);
    const loaded_forged_session_tests = b.addTest(.{ .root_module = loaded_forged_session_mod, .filters = forged_session_evidence_args.filters });
    loaded_forged_session_step.dependOn(&addRunArtifactWithArgs(b, loaded_forged_session_tests, forged_session_evidence_args.passthrough).step);

    const loaded_resource_ledger_step = b.step("check-boundary-loaded-resource-ledger", "Check loaded session fuel and allocation ledger regressions.");
    const loaded_resource_ledger_args = TestArgs{
        .filters = &.{
            "loaded session image rejects status-inconsistent fuel ledger",
            "loaded session image rejects oversized owned value byte lengths before allocation",
            "loaded session allocation ledger uses checked arithmetic",
            "loaded session image rejects v2-only state hidden inside v1 image",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_resource_ledger_step, core.loaded_execution, loaded_resource_ledger_args);
    const ledger_evidence_args = TestArgs{
        .filters = &.{
            "loaded executable portable v2 gates reachable arithmetic before session construction",
            "loaded executable portable v2 accepts canonical entry arguments",
        },
        .passthrough = &.{},
    };
    const loaded_resource_ledger_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_resource_ledger_mod.addImport("boundary", boundary);
    const loaded_resource_ledger_tests = b.addTest(.{ .root_module = loaded_resource_ledger_mod, .filters = ledger_evidence_args.filters });
    loaded_resource_ledger_step.dependOn(&addRunArtifactWithArgs(b, loaded_resource_ledger_tests, ledger_evidence_args.passthrough).step);

    const loaded_frame_stack_step = b.step("check-boundary-loaded-frame-stack", "Check portable loaded helper frame stack parking and restoration.");
    const loaded_frame_stack_args = TestArgs{
        .filters = &.{
            "frame stack",
            "nested helper parking restores canonical result",
            "continuation frame topology",
        },
        .passthrough = &.{},
    };
    const loaded_frame_stack_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_frame_stack_mod.addImport("boundary", boundary);
    const loaded_frame_stack_tests = b.addTest(.{ .root_module = loaded_frame_stack_mod, .filters = loaded_frame_stack_args.filters });
    loaded_frame_stack_step.dependOn(&addRunArtifactWithArgs(b, loaded_frame_stack_tests, loaded_frame_stack_args.passthrough).step);

    const loaded_parity_step = b.step("check-boundary-generated-loaded-parity", "Check generated Program.Session and LoadedModule.Session canonical parity.");
    const loaded_parity_required_step = b.step("check-boundary-loaded-parity", "Check generated Program.Session and LoadedModule.Session canonical parity.");
    const agent_parity_step = b.step("check-boundary-agent-generated-loaded-parity", "Check Agent Profile v0 generated and loaded execution foundations.");
    const loaded_parity_args = TestArgs{
        .filters = &.{"generated-loaded parity"},
        .passthrough = &.{},
    };
    const loaded_parity_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_parity_mod.addImport("boundary", boundary);
    const loaded_parity_tests = b.addTest(.{ .root_module = loaded_parity_mod, .filters = loaded_parity_args.filters });
    const loaded_parity_run = addRunArtifactWithArgs(b, loaded_parity_tests, loaded_parity_args.passthrough);
    loaded_parity_step.dependOn(&loaded_parity_run.step);
    loaded_parity_required_step.dependOn(&loaded_parity_run.step);
    agent_parity_step.dependOn(agent_profile_step);
    agent_parity_step.dependOn(agent_modules_step);
    agent_parity_step.dependOn(loaded_parity_step);

    const receipt_loaded_v2_step = b.step("check-boundary-loaded-v2-receipt-host", "Check Boundary portable_v2 proof receipts on the host target.");
    addTestArtifact(b, receipt_loaded_v2_step, host_core.loaded_execution, loaded_v2_args);
    const receipt_v2_core_evidence_mod = b.createModule(.{
        .root_source_file = b.path("src/program/evidence.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wireBoundaryImports(receipt_v2_core_evidence_mod, host_core);
    const receipt_v2_core_evidence_tests = b.addTest(.{ .root_module = receipt_v2_core_evidence_mod, .filters = loaded_v2_args.filters });
    receipt_loaded_v2_step.dependOn(&addRunArtifactWithArgs(b, receipt_v2_core_evidence_tests, loaded_v2_args.passthrough).step);
    const receipt_loaded_v2_evidence_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_loaded_v2_evidence_mod.addImport("boundary", host_boundary);
    const receipt_v2_evidence_tests = b.addTest(.{ .root_module = receipt_loaded_v2_evidence_mod, .filters = loaded_v2_args.filters });
    receipt_loaded_v2_step.dependOn(&addRunArtifactWithArgs(b, receipt_v2_evidence_tests, loaded_v2_args.passthrough).step);

    const receipt_loaded_session_step = b.step("check-boundary-loaded-session-receipt-host", "Check loaded-session proof receipts on the host target.");
    addTestArtifact(b, receipt_loaded_session_step, host_core.loaded_execution, loaded_session_args);
    addTestArtifact(b, receipt_loaded_session_step, host_boundary_shared, loaded_session_args);
    const receipt_loaded_evidence_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_loaded_evidence_mod.addImport("boundary", host_boundary);
    const receipt_loaded_evidence_tests = b.addTest(.{ .root_module = receipt_loaded_evidence_mod, .filters = loaded_session_args.filters });
    receipt_loaded_session_step.dependOn(&addRunArtifactWithArgs(b, receipt_loaded_evidence_tests, loaded_session_args.passthrough).step);

    const receipt_loaded_parity_step = b.step("check-boundary-loaded-parity-receipt-host", "Check generated-loaded parity proof receipts on the host target.");
    const receipt_loaded_parity_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_loaded_parity_mod.addImport("boundary", host_boundary);
    const receipt_loaded_parity_tests = b.addTest(.{ .root_module = receipt_loaded_parity_mod, .filters = loaded_parity_args.filters });
    receipt_loaded_parity_step.dependOn(&addRunArtifactWithArgs(b, receipt_loaded_parity_tests, loaded_parity_args.passthrough).step);
    const receipt_agent_parity_step = b.step("check-boundary-agent-generated-loaded-parity-receipt-host", "Check Agent Profile v0 generated and loaded execution proof receipts on the host target.");
    receipt_agent_parity_step.dependOn(receipt_agent_profile_step);
    receipt_agent_parity_step.dependOn(receipt_agent_modules_step);
    receipt_agent_parity_step.dependOn(receipt_loaded_parity_step);

    proof_receipts_step.dependOn(receipt_loaded_v2_step);
    proof_receipts_step.dependOn(receipt_loaded_session_step);
    proof_receipts_step.dependOn(receipt_loaded_parity_step);
    proof_receipts_step.dependOn(receipt_agent_parity_step);
    proof_receipts_run.step.dependOn(receipt_loaded_v2_step);
    proof_receipts_run.step.dependOn(receipt_loaded_session_step);
    proof_receipts_run.step.dependOn(receipt_loaded_parity_step);
    proof_receipts_run.step.dependOn(receipt_agent_parity_step);

    const loaded_import_bindings_step = b.step("check-boundary-loaded-import-bindings", "Check exact loaded residual import/site binding regressions.");
    const loaded_import_bindings_args = TestArgs{
        .filters = &.{
            "loaded executable binds residual imports by site index",
            "loaded executable ignores dead helper call sites for residual imports",
            "loaded executable portable v2 executes two sequential residual requests",
            "generated-loaded parity canonical request bytes and i32 result",
        },
        .passthrough = &.{},
    };
    const loaded_import_bindings_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_import_bindings_mod.addImport("boundary", boundary);
    const loaded_import_bindings_tests = b.addTest(.{ .root_module = loaded_import_bindings_mod, .filters = loaded_import_bindings_args.filters });
    loaded_import_bindings_step.dependOn(&addRunArtifactWithArgs(b, loaded_import_bindings_tests, loaded_import_bindings_args.passthrough).step);

    const loaded_response_safety_step = b.step("check-boundary-loaded-response-safety", "Check loaded response rejection preserves parked session state.");
    const loaded_response_safety_args = TestArgs{
        .filters = &.{
            "loaded executable portable v2 executes two sequential residual requests",
            "loaded executable portable v2 restores helper frame parked on residual request",
            "generated-loaded parity structured sum response extracts product result",
        },
        .passthrough = &.{},
    };
    const loaded_response_safety_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_response_safety_mod.addImport("boundary", boundary);
    const loaded_response_safety_tests = b.addTest(.{ .root_module = loaded_response_safety_mod, .filters = loaded_response_safety_args.filters });
    loaded_response_safety_step.dependOn(&addRunArtifactWithArgs(b, loaded_response_safety_tests, loaded_response_safety_args.passthrough).step);

    const loaded_malformed_step = b.step("check-boundary-loaded-malformed", "Check malformed loaded module/value/session/response rejection.");
    const loaded_malformed_args = TestArgs{
        .filters = &.{
            "loaded value image rejects",
            "loaded session image rejects",
            "loaded session image v2 rejects",
            "loaded session image roundtrips failure state and rejects trailing bytes",
            "loaded malformed",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_malformed_step, core.loaded_execution, loaded_malformed_args);
    const loaded_malformed_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_malformed_mod.addImport("boundary", boundary);
    const loaded_malformed_tests = b.addTest(.{ .root_module = loaded_malformed_mod, .filters = loaded_malformed_args.filters });
    loaded_malformed_step.dependOn(&addRunArtifactWithArgs(b, loaded_malformed_tests, loaded_malformed_args.passthrough).step);

    const loaded_payload_result_step = b.step("check-boundary-loaded-payload-result-images", "Check loaded payload and result image binding regressions.");
    const loaded_payload_result_args = TestArgs{
        .filters = &.{
            "loaded session image rejects forged result fingerprint",
            "certified boundary module reference full image and loaded module projections validate",
            "loaded executable session parks unit payload residual request",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_payload_result_step, core.loaded_execution, loaded_payload_result_args);
    const loaded_payload_result_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_payload_result_mod.addImport("boundary", boundary);
    const loaded_payload_result_tests = b.addTest(.{ .root_module = loaded_payload_result_mod, .filters = loaded_payload_result_args.filters });
    loaded_payload_result_step.dependOn(&addRunArtifactWithArgs(b, loaded_payload_result_tests, loaded_payload_result_args.passthrough).step);

    const loaded_fuzz_step = b.step("check-boundary-loaded-fuzz", "Check deterministic malformed loaded execution fuzz seeds.");
    const loaded_fuzz_args = TestArgs{
        .filters = &.{"loaded fuzz"},
        .passthrough = &.{},
    };
    const loaded_fuzz_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_fuzz_mod.addImport("boundary", boundary);
    const loaded_fuzz_tests = b.addTest(.{ .root_module = loaded_fuzz_mod, .filters = loaded_fuzz_args.filters });
    loaded_fuzz_step.dependOn(&addRunArtifactWithArgs(b, loaded_fuzz_tests, loaded_fuzz_args.passthrough).step);

    const ir_api_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/ir_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    ir_api_tests_mod.addImport("effect_ir", core.effect_ir);
    ir_api_tests_mod.addImport("internal_kernel", core.internal_kernel);
    ir_api_tests_mod.addImport("internal_program_plan", core.internal_program_plan);
    addTestArtifact(b, test_step, ir_api_tests_mod, test_args);

    const synthetic_root_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/synthetic_boundary_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    synthetic_root_tests_mod.addImport("boundary_shared", boundary_shared);
    addTestArtifact(b, test_step, synthetic_root_tests_mod, test_args);

    const agent_loop_tests_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_loop_tests_mod.addImport("boundary", boundary);
    const agent_loop_tests = b.addTest(.{ .root_module = agent_loop_tests_mod, .filters = test_args.filters });
    const agent_loop_tests_run = addRunArtifactWithArgs(b, agent_loop_tests, test_args.passthrough);
    agent_loop_tests_run.setCwd(b.tmpPath());
    test_step.dependOn(&agent_loop_tests_run.step);
    const agent_loop_parity_args = TestArgs{
        .filters = &.{ "agent root", "agent toolbox" },
        .passthrough = &.{},
    };
    const agent_loop_parity_tests = b.addTest(.{ .root_module = agent_loop_tests_mod, .filters = agent_loop_parity_args.filters });
    const agent_loop_parity_run = addRunArtifactWithArgs(b, agent_loop_parity_tests, agent_loop_parity_args.passthrough);
    agent_loop_parity_run.setCwd(b.tmpPath());
    agent_parity_step.dependOn(&agent_loop_parity_run.step);
    const receipt_agent_loop_tests_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_loop.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    receipt_agent_loop_tests_mod.addImport("boundary", host_boundary);
    const receipt_loop_tests = b.addTest(.{ .root_module = receipt_agent_loop_tests_mod, .filters = agent_loop_parity_args.filters });
    const receipt_loop_tests_run = addRunArtifactWithArgs(b, receipt_loop_tests, agent_loop_parity_args.passthrough);
    receipt_loop_tests_run.setCwd(b.tmpPath());
    receipt_agent_parity_step.dependOn(&receipt_loop_tests_run.step);

    const program_api_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/program_api_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const plan_native_resource_mod = b.createModule(.{
        .root_source_file = b.path("examples/plan_native_resource.zig"),
        .target = target,
        .optimize = optimize,
    });
    const custom_approval_mod = b.createModule(.{
        .root_source_file = b.path("examples/custom_approval_workflow.zig"),
        .target = target,
        .optimize = optimize,
    });
    custom_approval_mod.addImport("boundary", boundary);
    plan_native_resource_mod.addImport("boundary", boundary);
    program_api_tests_mod.addImport("boundary", boundary);
    program_api_tests_mod.addImport("custom_approval_workflow", custom_approval_mod);
    program_api_tests_mod.addImport("plan_native_resource", plan_native_resource_mod);
    const program_api_tests = b.addTest(.{ .root_module = program_api_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, program_api_tests, test_args.passthrough).step);

    const evidence_kernel_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    evidence_kernel_tests_mod.addImport("boundary", boundary);
    const evidence_kernel_tests = b.addTest(.{ .root_module = evidence_kernel_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, evidence_kernel_tests, test_args.passthrough).step);

    const contract_matrix_mod = b.createModule(.{
        .root_source_file = b.path("test/plan_native_contract_matrix_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    contract_matrix_mod.addImport("boundary", boundary);
    const contract_matrix_tests = b.addTest(.{ .root_module = contract_matrix_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, contract_matrix_tests, test_args.passthrough).step);

    const public_optional_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/public_optional_bound_program_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    public_optional_tests_mod.addImport("boundary", boundary);
    const public_optional_tests = b.addTest(.{ .root_module = public_optional_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, public_optional_tests, test_args.passthrough).step);

    const compile_fail_step = b.step("compile-fail", "Check expected public ProgramPlan compile diagnostics.");
    test_step.dependOn(compile_fail_step);
    const compile_fail_specs = [_]struct {
        path: []const u8,
        expected_error: []const u8,
    }{
        .{
            .path = "test/compile_fail/missing_reachable_return_error_decl.zig",
            .expected_error = "Body.compiled_plan reachable return_error is not declared in Body.Error: Rejected",
        },
        .{
            .path = "test/compile_fail/invalid_result_cleanup_with_outputs.zig",
            .expected_error = "Body.deinitResult with Body.Outputs must have type fn (std.mem.Allocator, value) void; release outputs separately with Body.deinitOutputs",
        },
        .{
            .path = "test/compile_fail/value_schema_variant_mismatch.zig",
            .expected_error = "Body.value_schema_types does not match Body.compiled_plan.value_variants[1]",
        },
        .{
            .path = "test/compile_fail/invalid_sum_extract_destination.zig",
            .expected_error = "Body.compiled_plan failed ProgramPlan.validate: InvalidSumPayloadDestination",
        },
        .{
            .path = "test/compile_fail/encode_args_tuple_field_mismatch.zig",
            .expected_error = "expected i32, found bool",
        },
        .{
            .path = "test/compile_fail/missing_output_collector.zig",
            .expected_error = "Body.Outputs requires Body.collectOutputs",
        },
        .{
            .path = "test/compile_fail/invalid_output_cleanup_hook.zig",
            .expected_error = "Body.deinitOutputs must have type fn (std.mem.Allocator, outputs) void",
        },
        .{
            .path = "test/compile_fail/missing_nested_with_target.zig",
            .expected_error = "UnsupportedNestedWith",
        },
        .{
            .path = "test/compile_fail/nested_with_wrong_function_index.zig",
            .expected_error = "UnsupportedNestedWith",
        },
        .{
            .path = "test/compile_fail/nested_with_result_codec_mismatch.zig",
            .expected_error = "UnsupportedResultCodec",
        },
        .{
            .path = "test/compile_fail/schema_lower_binding_product_ref.zig",
            .expected_error = "schema.LowerBinding requires a schema ref for product/sum resume type 'schema_lower_binding_product_ref.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_refs_scalar_entry.zig",
            .expected_error = "is scalar and must not carry a schema index",
        },
        .{
            .path = "test/compile_fail/schema_refs_duplicate_type.zig",
            .expected_error = "schema.SchemaRefs has duplicate entry for type 'schema_refs_duplicate_type.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_refs_unsupported_type.zig",
            .expected_error = "schema.SchemaRefs unsupported type '*const i32': UnsupportedCodecType",
        },
        .{
            .path = "test/compile_fail/schema_registry_duplicate_structured_type.zig",
            .expected_error = "schema.Registry has duplicate structured type 'schema_registry_duplicate_structured_type.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_registry_missing_nested_ref.zig",
            .expected_error = "schema.Registry missing nested structured type 'schema_registry_missing_nested_ref.InnerPayload' referenced by 'schema_registry_missing_nested_ref.OuterPayload'",
        },
        .{
            .path = "test/compile_fail/schema_registry_unsupported_type.zig",
            .expected_error = "schema.Registry unsupported type '*const i32': UnsupportedCodecType",
        },
        .{
            .path = "test/compile_fail/schema_protocol_empty_label.zig",
            .expected_error = "schema.Protocol requires a non-empty label",
        },
        .{
            .path = "test/compile_fail/schema_protocol_duplicate_op_name.zig",
            .expected_error = "schema.Protocol has duplicate op name 'exists'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_empty_op_name.zig",
            .expected_error = "schema.Protocol op name must be non-empty",
        },
        .{
            .path = "test/compile_fail/schema_protocol_missing_product_ref.zig",
            .expected_error = "schema.LowerBinding requires a schema ref for product/sum payload type 'schema_protocol_missing_product_ref.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_missing_sum_ref.zig",
            .expected_error = "schema.LowerBinding requires a schema ref for product/sum resume type 'schema_protocol_missing_sum_ref.Decision'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_operation_missing_product_ref.zig",
            .expected_error = "schema.Protocol operation requires a schema ref for product/sum payload type 'schema_protocol_operation_missing_product_ref.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_operation_missing_sum_result_ref.zig",
            .expected_error = "schema.Protocol operation requires a schema ref for product/sum result type 'schema_protocol_operation_missing_sum_result_ref.Decision'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_transform_result.zig",
            .expected_error = "schema.Protocol transform operation does not accept Result",
        },
        .{
            .path = "test/compile_fail/semantic_protocol_payload_mismatch.zig",
            .expected_error = "semantic builder protocol call payload type mismatch",
        },
        .{
            .path = "test/compile_fail/semantic_protocol_resume_mismatch.zig",
            .expected_error = "semantic builder protocol call destination/resume type mismatch",
        },
        .{
            .path = "test/compile_fail/semantic_invalid_branch_target.zig",
            .expected_error = "semantic builder block not found: missing",
        },
        .{
            .path = "test/compile_fail/semantic_local_type_mismatch.zig",
            .expected_error = "semantic builder constString destination must be string",
        },
        .{
            .path = "test/compile_fail/semantic_empty_site_label.zig",
            .expected_error = "semantic builder protocol call label must be non-empty",
        },
        .{
            .path = "test/compile_fail/semantic_schema_registry_duplicate_tables.zig",
            .expected_error = "semantic builder derives value_schemas from schemas; omit the explicit table",
        },
        .{
            .path = "test/compile_fail/custom_protocol_coverage_omitted_operation.zig",
            .expected_error = "Program.protocol coverage omitted reachable operation site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_omitted_operation.zig",
            .expected_error = "Program.protocol coverage omitted reachable operation site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_omitted_after.zig",
            .expected_error = "Program.protocol coverage omitted reachable after site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_duplicate_site.zig",
            .expected_error = "Program.protocol coverage listed duplicate operation site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_foreign_site.zig",
            .expected_error = "Program.protocol coverage descriptor belongs to another program",
        },
        .{
            .path = "test/compile_fail/provider_harness_duplicate_handler.zig",
            .expected_error = "Program.Exchange.ProviderHarness listed duplicate operation handler",
        },
        .{
            .path = "test/compile_fail/provider_harness_forged_semantic_body.zig",
            .expected_error = "Program.Exchange.ProviderHarness function-backed entries must declare host_intrinsic semantic body",
        },
        .{
            .path = "test/compile_fail/provider_harness_forged_program_mapping.zig",
            .expected_error = "Program.Exchange.ProviderHarness program-backed entries must be declared with ProviderHandler.program",
        },
        .{
            .path = "test/compile_fail/provider_program_payload_arg_mismatch.zig",
            .expected_error = "provider Program payload_to_args argument schema does not match request payload/current-value schema",
        },
        .{
            .path = "test/compile_fail/provider_program_mapper_fingerprint_reserved.zig",
            .expected_error = "provider Program mapper_fingerprint is reserved until provider-program custom mapper execution is implemented",
        },
        .{
            .path = "test/compile_fail/provider_program_structured_schema_mismatch.zig",
            .expected_error = "provider Program payload_to_args argument schema does not match request payload/current-value schema",
        },
        .{
            .path = "test/compile_fail/provider_program_transform_return_now.zig",
            .expected_error = "provider Program result_to_return_now requires a return-now operation offer",
        },
        .{
            .path = "test/compile_fail/provider_program_metadata_mapping_reserved.zig",
            .expected_error = "provider Program payload_and_metadata_to_args is reserved until provider-program metadata argument execution is implemented",
        },
        .{
            .path = "test/compile_fail/provider_program_outcome_union_reserved.zig",
            .expected_error = "provider Program result_to_outcome_union is reserved until provider-program outcome-union execution is implemented",
        },
        .{
            .path = "test/compile_fail/protocol_request_foreign_site.zig",
            .expected_error = "Program.protocol descriptor belongs to another program",
        },
        .{
            .path = "test/compile_fail/protocol_target_response_abort_resume.zig",
            .expected_error = "Program.Handler.TargetResponse abort rejects resume",
        },
        .{
            .path = "test/compile_fail/protocol_target_response_transform_return_now.zig",
            .expected_error = "Program.Handler.TargetResponse transform rejects return_now",
        },
        .{
            .path = "test/compile_fail/interpreter_invalid_transform_return_now.zig",
            .expected_error = "Program.Handler.returnNow is invalid for this operation site",
        },
        .{
            .path = "test/compile_fail/interpreter_duplicate_handler.zig",
            .expected_error = "Program.Interpreter listed duplicate handler for site",
        },
        .{
            .path = "test/compile_fail/interpreter_duplicate_protocol_operation_handler.zig",
            .expected_error = "Program.Interpreter listed duplicate protocol operation handler",
        },
        .{
            .path = "test/compile_fail/interpreter_elimination_missing_protocol_operation.zig",
            .expected_error = "Program.Interpreter elimination omitted emitted protocol operation",
        },
        .{
            .path = "test/compile_fail/interpreter_effect_row_foreign_program.zig",
            .expected_error = "Program.Interpreter effectRow expected owning Program type",
        },
        .{
            .path = "test/compile_fail/interpreter_plain_operation_reinterpret.zig",
            .expected_error = "plain operation handlers cannot return reinterpret outcomes",
        },
        .{
            .path = "test/compile_fail/interpreter_protocol_handler_nested_mutable_payload.zig",
            .expected_error = "Program.Handler protocol request payload contains mutable string-list storage",
        },
        .{
            .path = "test/compile_fail/interpreter_protocol_handler_mutable_payload.zig",
            .expected_error = "cannot assign to constant",
        },
        .{
            .path = "test/compile_fail/interpreter_reinterpreted_mutable_payload.zig",
            .expected_error = "cannot assign to constant",
        },
        .{
            .path = "test/compile_fail/interpreter_foreign_site.zig",
            .expected_error = "Program.Handler site descriptor belongs to another program",
        },
        .{
            .path = "test/compile_fail/interpreter_forged_semantic_body.zig",
            .expected_error = "Program.Interpreter function-backed entries must declare host_intrinsic semantic body",
        },
        .{
            .path = "test/compile_fail/interpreter_coverage_omitted_operation.zig",
            .expected_error = "Program.Interpreter coverage omitted reachable operation site",
        },
        .{
            .path = "test/compile_fail/interpreter_coverage_omitted_after.zig",
            .expected_error = "Program.Interpreter coverage omitted reachable after site",
        },
        .{
            .path = "test/compile_fail/interpreter_coverage_fake_interpreter.zig",
            .expected_error = "Program.protocol expected a Program.Interpreter type",
        },
        .{
            .path = "test/compile_fail/reinterpret_mapper_invalid_source_outcome.zig",
            .expected_error = "Program.Handler.reinterpret mapper resume must return Program.Handler.SourceOutcome(SourceSite)",
        },
        .{
            .path = "test/compile_fail/reinterpret_mapper_invalid_resume_param.zig",
            .expected_error = "Program.Handler.reinterpret mapper resume parameter must match target protocol operation type",
        },
        .{
            .path = "test/compile_fail/reinterpret_mapper_invalid_return_param.zig",
            .expected_error = "Program.Handler.reinterpret mapper returnNow parameter must match target protocol operation type",
        },
        .{
            .path = "test/compile_fail/boundary_target_schema_mismatch.zig",
            .expected_error = "Boundary Target world-port schema mismatch",
        },
        .{
            .path = "test/compile_fail/boundary_target_direct_world_port_schema_witness.zig",
            .expected_error = "Boundary Target world-port source-map entry is missing schema witness",
        },
        .{
            .path = "test/compile_fail/boundary_target_operation_identity_mismatch.zig",
            .expected_error = "Boundary Target world-port schema mismatch",
        },
        .{
            .path = "test/compile_fail/boundary_target_world_port_absent_coordinate.zig",
            .expected_error = "BoundaryClosure.Elaboration world port shape coordinates do not match a residual Program site",
        },
        .{
            .path = "test/compile_fail/boundary_target_world_port_coordinate_mismatch.zig",
            .expected_error = "BoundaryClosure.Elaboration world port shape coordinates do not match a residual Program site",
        },
        .{
            .path = "test/compile_fail/boundary_target_missing_residual_program.zig",
            .expected_error = "Boundary Target requires .residual_program or .root; no residual target generation path is implemented",
        },
        .{
            .path = "test/compile_fail/boundary_target_residual_program_mismatch.zig",
            .expected_error = "Boundary Target residual Program does not match elaborated body certificate",
        },
        .{
            .path = "test/compile_fail/boundary_target_body_policy_mismatch.zig",
            .expected_error = "Boundary Target body policy does not match target policy",
        },
        .{
            .path = "test/compile_fail/boundary_target_program_backed_requirement.zig",
            .expected_error = "BoundaryClosure.Elaboration input rejected residual Program: BoundaryElaborationBlocked",
        },
    };
    inline for (compile_fail_specs) |spec| {
        const compile_fail_mod = b.createModule(.{
            .root_source_file = b.path(spec.path),
            .target = target,
            .optimize = optimize,
        });
        compile_fail_mod.addImport("boundary", boundary);
        addCompileFailArtifact(b, compile_fail_step, compile_fail_mod, spec.expected_error);
    }

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "boundary-state-basic", .path = "examples/state_basic.zig", .step = "run-state-basic", .desc = "Run the state effect example." },
        .{ .name = "boundary-typed-program-plan", .path = "examples/typed_program_plan.zig", .step = "run-typed-program-plan", .desc = "Run the typed ProgramPlan example." },
        .{ .name = "boundary-plan-native-optional", .path = "examples/plan_native_optional.zig", .step = "run-plan-native-optional", .desc = "Run the plan-native optional example." },
        .{ .name = "boundary-plan-native-state-reader", .path = "examples/plan_native_state_reader.zig", .step = "run-plan-native-state-reader", .desc = "Run the plan-native state/reader example." },
        .{ .name = "boundary-plan-native-writer", .path = "examples/plan_native_writer.zig", .step = "run-plan-native-writer", .desc = "Run the plan-native writer example." },
        .{ .name = "boundary-plan-native-exception", .path = "examples/plan_native_exception.zig", .step = "run-plan-native-exception", .desc = "Run the plan-native exception example." },
        .{ .name = "boundary-plan-native-resource", .path = "examples/plan_native_resource.zig", .step = "run-plan-native-resource", .desc = "Run the plan-native resource example." },
        .{ .name = "boundary-custom-approval-workflow", .path = "examples/custom_approval_workflow.zig", .step = "run-custom-approval-workflow", .desc = "Run the custom approval workflow example." },
        .{ .name = "boundary-agent-loop", .path = "examples/agent_loop.zig", .step = "run-agent-loop", .desc = "Run the host-driven Program.Session agent loop example." },
        .{ .name = "boundary-agent-module-manifest", .path = "examples/agent_module_manifest.zig", .step = "run-agent-module-manifest", .desc = "Run the Agent Profile module byte provenance example." },
        .{ .name = "boundary-agent-profile-conformance", .path = "examples/agent_profile_conformance.zig", .step = "run-agent-profile-conformance", .desc = "Run the Agent Profile v0 conformance scenario summary." },
        .{ .name = "boundary-continuation-branching", .path = "examples/continuation_branching.zig", .step = "run-continuation-branching", .desc = "Run the Program.Session continuation capsule branching example." },
        .{ .name = "boundary-interpreter-branching", .path = "examples/interpreter_branching.zig", .step = "run-interpreter-branching", .desc = "Run the continuation-aware Program.Interpreter branching example." },
        .{ .name = "boundary-protocol-reinterpretation", .path = "examples/protocol_reinterpretation.zig", .step = "run-protocol-reinterpretation", .desc = "Run the protocol morphism reinterpretation example." },
        .{ .name = "boundary-residualized-approval-policy", .path = "examples/residualized_approval_policy.zig", .step = "run-residualized-approval-policy", .desc = "Run the residualized approval policy example." },
        .{ .name = "boundary-effect-pipeline", .path = "examples/effect_pipeline.zig", .step = "run-effect-pipeline", .desc = "Run the proof-carrying effect pipeline example." },
        .{ .name = "boundary-effect-capability-routing", .path = "examples/effect_capability_routing.zig", .step = "run-effect-capability-routing", .desc = "Run the capability-routed Effect Exchange example." },
        .{ .name = "boundary-effect-capability-attenuation", .path = "examples/effect_capability_attenuation.zig", .step = "run-effect-capability-attenuation", .desc = "Run the Effect Exchange capability attenuation example." },
        .{ .name = "boundary-effect-treaty-direct", .path = "examples/effect_treaty_direct.zig", .step = "run-effect-treaty-direct", .desc = "Run the direct Effect Treaty negotiation example." },
        .{ .name = "boundary-effect-treaty-morphism", .path = "examples/effect_treaty_morphism.zig", .step = "run-effect-treaty-morphism", .desc = "Run the morphism-adapted Effect Treaty negotiation example." },
        .{ .name = "boundary-effect-treaty-replayable", .path = "examples/effect_treaty_replayable.zig", .step = "run-effect-treaty-replayable", .desc = "Run the replay-policy Effect Treaty example." },
        .{ .name = "boundary-provider-harness-direct", .path = "examples/provider_harness_direct.zig", .step = "run-provider-harness-direct", .desc = "Run the direct ProviderHarness treaty execution example." },
        .{ .name = "boundary-provider-harness-morphism", .path = "examples/provider_harness_morphism.zig", .step = "run-provider-harness-morphism", .desc = "Run the morphism ProviderHarness treaty execution example." },
        .{ .name = "boundary-provider-harness-replayable", .path = "examples/provider_harness_replayable.zig", .step = "run-provider-harness-replayable", .desc = "Run the replayable ProviderHarness treaty execution example." },
        .{ .name = "boundary-defunctionalization-boundary", .path = "examples/defunctionalization_boundary.zig", .step = "run-defunctionalization-boundary", .desc = "Run the defunctionalization boundary audit example." },
        .{ .name = "boundary-host-intrinsic-allowlist", .path = "examples/host_intrinsic_allowlist.zig", .step = "run-host-intrinsic-allowlist", .desc = "Run the host intrinsic allowlist example." },
        .{ .name = "boundary-closure-strict", .path = "examples/boundary_closure_strict.zig", .step = "run-boundary-closure-strict", .desc = "Run the strict Boundary Closure Certificate example." },
        .{ .name = "boundary-closure-nested", .path = "examples/boundary_closure_nested.zig", .step = "run-boundary-closure-nested", .desc = "Run the nested Boundary Closure Certificate example." },
        .{ .name = "boundary-closure-world-port", .path = "examples/boundary_closure_world_port.zig", .step = "run-boundary-closure-world-port", .desc = "Run the world-port Boundary Closure Certificate example." },
        .{ .name = "boundary-elaboration-strict", .path = "examples/boundary_elaboration_strict.zig", .step = "run-boundary-elaboration-strict", .desc = "Run the strict Boundary Closure Elaboration example." },
        .{ .name = "boundary-elaboration-nested", .path = "examples/boundary_elaboration_nested.zig", .step = "run-boundary-elaboration-nested", .desc = "Run the nested Boundary Closure Elaboration example." },
        .{ .name = "boundary-elaboration-world-port", .path = "examples/boundary_elaboration_world_port.zig", .step = "run-boundary-elaboration-world-port", .desc = "Run the world-port Boundary Closure Elaboration example." },
        .{ .name = "boundary-world-surface-strict", .path = "examples/world_surface_strict.zig", .step = "run-world-surface-strict", .desc = "Run the strict Certified Boundary Target WorldSurface example." },
        .{ .name = "boundary-world-surface-nested", .path = "examples/world_surface_nested.zig", .step = "run-world-surface-nested", .desc = "Run the scoped root-copy Certified Boundary Target WorldSurface example." },
        .{ .name = "boundary-world-surface-ports", .path = "examples/world_surface_ports.zig", .step = "run-world-surface-ports", .desc = "Run the world-port Certified Boundary Target WorldSurface example." },
        .{ .name = "boundary-module-reference", .path = "examples/boundary_module_reference.zig", .step = "run-boundary-module-reference", .desc = "Run the Certified Boundary Module reference transfer example." },
        .{ .name = "boundary-module-roundtrip", .path = "examples/boundary_module_roundtrip.zig", .step = "run-boundary-module-roundtrip", .desc = "Run the Certified Boundary Module full-image roundtrip example." },
        .{ .name = "boundary-module-loaded-run", .path = "examples/boundary_module_loaded_run.zig", .step = "run-boundary-module-loaded-run", .desc = "Run the LoadedModule fail-closed execution surface example." },
        .{ .name = "boundary-module-agent-transfer", .path = "examples/boundary_module_agent_transfer.zig", .step = "run-boundary-module-agent-transfer", .desc = "Run the agent-shaped Certified Boundary Module transfer example." },
        .{ .name = "boundary-module-inspect", .path = "examples/boundary_module_inspect.zig", .step = "run-boundary-module-inspect", .desc = "Run the LoadedModule inspection helper example." },
        .{ .name = "boundary-module-imports", .path = "examples/boundary_module_imports.zig", .step = "run-boundary-module-imports", .desc = "Run the ImportSurface projection and binding report example." },
        .{ .name = "boundary-module-diagnostics", .path = "examples/boundary_module_diagnostics.zig", .step = "run-boundary-module-diagnostics", .desc = "Run the structured module validation diagnostic example." },
        .{ .name = "boundary-module-compatibility", .path = "examples/boundary_module_compatibility.zig", .step = "run-boundary-module-compatibility", .desc = "Run the module compatibility report example." },
        .{ .name = "boundary-normalization-provider", .path = "examples/boundary_normalization_provider.zig", .step = "run-boundary-normalization-provider", .desc = "Run the provider Boundary Normalization Calculus example." },
        .{ .name = "boundary-normalization-nested", .path = "examples/boundary_normalization_nested.zig", .step = "run-boundary-normalization-nested", .desc = "Run the nested Boundary Normalization Calculus example." },
        .{ .name = "boundary-normalization-ports", .path = "examples/boundary_normalization_ports.zig", .step = "run-boundary-normalization-ports", .desc = "Run the WorldPort Boundary Normalization Calculus example." },
        .{ .name = "boundary-program-provider-direct", .path = "examples/program_provider_direct.zig", .step = "run-program-provider-direct", .desc = "Run the direct program-backed ProviderHarness example." },
        .{ .name = "boundary-program-provider-nested", .path = "examples/program_provider_nested.zig", .step = "run-program-provider-nested", .desc = "Run the nested program-backed ProviderHarness example." },
        .{ .name = "boundary-program-provider-resume", .path = "examples/program_provider_resume.zig", .step = "run-program-provider-resume", .desc = "Run the parked and resumed program-backed ProviderHarness example." },
        .{ .name = "boundary-effect-exchange-mailbox", .path = "examples/effect_exchange_mailbox.zig", .step = "run-effect-exchange-mailbox", .desc = "Run the transport-neutral Effect Exchange mailbox example." },
        .{ .name = "boundary-effect-exchange-restart", .path = "examples/effect_exchange_restart.zig", .step = "run-effect-exchange-restart", .desc = "Run the Effect Exchange capsule restart example." },
        .{ .name = "boundary-linear-effect-sessions", .path = "examples/linear_effect_sessions.zig", .step = "run-linear-effect-sessions", .desc = "Run the Linear Effect Sessions obligation example." },
        .{ .name = "boundary-linear-branch-safety", .path = "examples/linear_branch_safety.zig", .step = "run-linear-branch-safety", .desc = "Run the Linear Effect Sessions branch safety example." },
        .{ .name = "boundary-durable-capsule-replay", .path = "examples/durable_capsule_replay.zig", .step = "run-durable-capsule-replay", .desc = "Run the durable Program.Session capsule image replay example." },
        .{ .name = "boundary-journal-replay", .path = "examples/journal_replay.zig", .step = "run-journal-replay", .desc = "Run the Program.Session interaction journal replay example." },
    };
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("boundary", boundary);
        const exe = b.addExecutable(.{ .name = example.name, .root_module = exe_mod });
        const run_step = b.step(example.step, example.desc);
        if (target.query.isNative()) {
            run_step.dependOn(&addRunArtifactWithArgs(b, exe, if (b.args) |args| args else &.{}).step);
        } else {
            run_step.dependOn(&exe.step);
        }
    }

    const runtime_dist_dir = b.getInstallPath(.prefix, "dist/boundary-v" ++ package.version ++ "-agent-runtime");
    const boundary_agent_runtime_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_loop.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    boundary_agent_runtime_mod.addImport("boundary", host_boundary);
    const boundary_agent_runtime_exe = b.addExecutable(.{
        .name = "boundary-agent-runtime-artifacts",
        .root_module = boundary_agent_runtime_mod,
    });
    const emit_boundary_agent_runtime = b.addRunArtifact(boundary_agent_runtime_exe);
    emit_boundary_agent_runtime.addArgs(&.{ "export-agent-runtime", runtime_dist_dir });
    emit_boundary_agent_runtime.step.dependOn(receipt_agent_modules_step);
    emit_boundary_agent_runtime.step.dependOn(receipt_agent_parity_step);
    const emit_runtime_step = b.step("emit-boundary-agent-runtime-artifacts", "Emit Boundary Agent Runtime pack-ready module artifacts.");
    emit_runtime_step.dependOn(&emit_boundary_agent_runtime.step);

    const check_runtime_root = b.tmpPath();
    const check_boundary_agent_runtime = b.addRunArtifact(boundary_agent_runtime_exe);
    check_boundary_agent_runtime.setName("check Boundary Agent Runtime pack-ready artifacts");
    check_boundary_agent_runtime.setCwd(check_runtime_root);
    check_boundary_agent_runtime.addArgs(&.{ "export-agent-runtime", "bundle" });
    check_boundary_agent_runtime.step.dependOn(receipt_agent_modules_step);
    check_boundary_agent_runtime.step.dependOn(receipt_agent_parity_step);
    const check_runtime_step = b.step("check-boundary-agent-runtime-artifacts", "Check Boundary Agent Runtime pack-ready artifacts.");
    check_runtime_step.dependOn(&check_boundary_agent_runtime.step);
    check_step.dependOn(check_runtime_step);

    const world_image_v1_corpus_dir = "conformance/world-image-v1/v0/boundary";
    const world_image_v1_receiver_pin = "conformance/world-image-v1/v0/boundary.receiver-pin.sha256";
    const world_image_v1_oracle_mod = b.createModule(.{
        .root_source_file = b.path("test/world_image_v1_oracle.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .link_libc = true,
    });
    world_image_v1_oracle_mod.addImport("boundary", host_boundary);
    world_image_v1_oracle_mod.addImport("agent_loop", boundary_agent_runtime_mod);
    const world_image_v1_oracle_exe = b.addExecutable(.{
        .name = "boundary-world-image-v1-oracle",
        .root_module = world_image_v1_oracle_mod,
    });

    const oracle_update_candidate_a_root = b.tmpPath();
    const oracle_update_candidate_b_root = b.tmpPath();
    const oracle_update_candidate_a_dir = oracle_update_candidate_a_root.path(b, "bundle");
    const oracle_update_candidate_b_dir = oracle_update_candidate_b_root.path(b, "bundle");
    const oracle_update_generate_a = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_update_generate_a.setName("generate Boundary World Image v1 tracked-update candidate A");
    oracle_update_generate_a.setCwd(oracle_update_candidate_a_root);
    oracle_update_generate_a.addArg("generate");
    const oracle_update_generate_b = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_update_generate_b.setName("generate Boundary World Image v1 tracked-update candidate B");
    oracle_update_generate_b.setCwd(oracle_update_candidate_b_root);
    oracle_update_generate_b.addArg("generate");
    const oracle_update_compare = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_update_compare.setName("compare Boundary World Image v1 tracked-update candidates");
    oracle_update_compare.setCwd(b.path("."));
    oracle_update_compare.addArgs(&.{ "verify", "--expected-dir" });
    oracle_update_compare.addDirectoryArg(oracle_update_candidate_a_dir);
    oracle_update_compare.addArg("--actual-dir");
    oracle_update_compare.addDirectoryArg(oracle_update_candidate_b_dir);
    oracle_update_compare.step.dependOn(&oracle_update_generate_a.step);
    oracle_update_compare.step.dependOn(&oracle_update_generate_b.step);
    const oracle_update_run = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_update_run.setName("publish Boundary World Image v1 tracked oracle");
    oracle_update_run.setCwd(b.path("."));
    oracle_update_run.addArgs(&.{ "publish-tracked", "--candidate-dir" });
    oracle_update_run.addDirectoryArg(oracle_update_candidate_a_dir);
    oracle_update_run.addArg("--receiver-pin");
    oracle_update_run.addFileArg(b.path(world_image_v1_receiver_pin));
    oracle_update_run.addArg("--exclusive-publication-namespace");
    oracle_update_run.step.dependOn(&oracle_update_compare.step);
    const oracle_update_step = b.step(
        "update-boundary-world-image-v1-oracle",
        "Update the checked-in Boundary World Image v1 rewrite oracle; invoking this step asserts exclusive control of its tracked publication namespace for the command's duration.",
    );
    oracle_update_step.dependOn(&oracle_update_run.step);

    const oracle_generation_a_root = b.tmpPath();
    const oracle_generation_b_root = b.tmpPath();
    const oracle_generation_a_dir = oracle_generation_a_root.path(b, "bundle");
    const oracle_generation_b_dir = oracle_generation_b_root.path(b, "bundle");
    const oracle_generation_a = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_generation_a.setName("generate Boundary World Image v1 oracle A");
    oracle_generation_a.setCwd(oracle_generation_a_root);
    oracle_generation_a.addArg("generate");
    const oracle_generation_b = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_generation_b.setName("generate Boundary World Image v1 oracle B");
    oracle_generation_b.setCwd(oracle_generation_b_root);
    oracle_generation_b.addArg("generate");

    const oracle_publication_test_root = b.tmpPath();
    const oracle_publication_test = b.addRunArtifact(world_image_v1_oracle_exe);
    oracle_publication_test.setName("check Boundary World Image v1 oracle publication safety");
    oracle_publication_test.setCwd(oracle_publication_test_root);
    oracle_publication_test.addArg("test-publication");
    oracle_publication_test.addArg("--receiver-pin");
    oracle_publication_test.addFileArg(b.path(world_image_v1_receiver_pin));
    const oracle_publication_check_step = b.step(
        "check-boundary-world-image-v1-oracle-publication",
        "Check fixed output admission and recoverable tracked-oracle publication.",
    );
    oracle_publication_check_step.dependOn(&oracle_publication_test.step);
    const independent_oracle_gates = [_]*std.Build.Step{
        loaded_parity_required_step,
        loaded_response_safety_step,
        loaded_malformed_step,
        receipt_agent_parity_step,
        check_runtime_step,
        oracle_publication_check_step,
    };
    for (&independent_oracle_gates) |independent_oracle_gate| {
        oracle_update_run.step.dependOn(independent_oracle_gate);
    }

    const compare_world_image_v1_oracle = b.addRunArtifact(world_image_v1_oracle_exe);
    compare_world_image_v1_oracle.setName("compare Boundary World Image v1 oracle trees");
    compare_world_image_v1_oracle.setCwd(b.path("."));
    compare_world_image_v1_oracle.addArgs(&.{
        "compare",
        "--expected-dir",
    });
    compare_world_image_v1_oracle.addDirectoryArg(b.path(world_image_v1_corpus_dir));
    compare_world_image_v1_oracle.addArg("--first-dir");
    compare_world_image_v1_oracle.addDirectoryArg(oracle_generation_a_dir);
    compare_world_image_v1_oracle.addArg("--second-dir");
    compare_world_image_v1_oracle.addDirectoryArg(oracle_generation_b_dir);
    compare_world_image_v1_oracle.step.dependOn(&oracle_generation_a.step);
    compare_world_image_v1_oracle.step.dependOn(&oracle_generation_b.step);

    const oracle_check_step = b.step(
        "check-boundary-world-image-v1-oracle",
        "Check deterministic exact Boundary World Image v1 rewrite oracle bytes.",
    );
    oracle_check_step.dependOn(&compare_world_image_v1_oracle.step);
    for (&independent_oracle_gates) |independent_oracle_gate| {
        oracle_check_step.dependOn(independent_oracle_gate);
    }
    oracle_check_step.dependOn(addGlobalCacheCwdOwnershipProbe(b));
    check_step.dependOn(oracle_check_step);

    const oracle_emit_dir = b.pathResolve(&.{
        b.graph.cache.cwd,
        b.getInstallPath(.prefix, "conformance/world-image-v1/v0/boundary"),
    });
    const oracle_emit_candidate_root = b.tmpPath();
    const oracle_emit_candidate_dir = oracle_emit_candidate_root.path(b, "bundle");
    const emit_world_image_v1_oracle_run = b.addRunArtifact(world_image_v1_oracle_exe);
    emit_world_image_v1_oracle_run.setCwd(oracle_emit_candidate_root);
    emit_world_image_v1_oracle_run.addArg("generate");
    emit_world_image_v1_oracle_run.step.dependOn(oracle_check_step);
    const replace_emitted_oracle = ExactInstallTreeStep.create(
        b,
        oracle_emit_candidate_dir,
        oracle_emit_dir,
        b.pathFromRoot(world_image_v1_corpus_dir),
    );
    replace_emitted_oracle.step.dependOn(&emit_world_image_v1_oracle_run.step);
    const oracle_emit_parent_dir = std.Io.Dir.path.dirname(oracle_emit_dir) orelse
        std.process.fatal("emitted Boundary oracle path has no parent: '{s}'", .{oracle_emit_dir});
    const resolved_emit_parent = resolveExistingAbsolutePrefix(b, oracle_emit_parent_dir);
    const oracle_emit_leaf = std.Io.Dir.path.basename(oracle_emit_dir);
    const verify_emitted_oracle = b.addRunArtifact(world_image_v1_oracle_exe);
    verify_emitted_oracle.setName("verify emitted Boundary World Image v1 oracle bytes");
    verify_emitted_oracle.setCwd(.{ .cwd_relative = resolved_emit_parent });
    verify_emitted_oracle.addArgs(&.{
        "verify",
        "--expected-dir",
    });
    verify_emitted_oracle.addDirectoryArg(b.path(world_image_v1_corpus_dir));
    verify_emitted_oracle.addArg("--actual-dir");
    verify_emitted_oracle.addArg(oracle_emit_leaf);
    verify_emitted_oracle.addArg("--require-public-modes");
    verify_emitted_oracle.step.dependOn(&replace_emitted_oracle.step);
    const oracle_emit_step = b.step(
        "emit-boundary-world-image-v1-oracle",
        "Emit the verified Boundary World Image v1 rewrite oracle under zig-out.",
    );
    oracle_emit_step.dependOn(&verify_emitted_oracle.step);

    const bench_check_step = b.step("bench-check", "Compile retained benchmark programs.");
    test_step.dependOn(bench_check_step);

    const boundary_bench = b.createModule(.{
        .root_source_file = b.path("src/bench_support.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    wireBoundaryImports(boundary_bench, core);

    const bench_specs = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "boundary-abortive-effect-decompose-bench", .path = "bench/abortive_effect_decompose_bench.zig", .step = "bench-abortive-effect-decompose", .desc = "Run the abortive effect decomposition benchmark." },
        .{ .name = "boundary-algebraic-builder-decompose-bench", .path = "bench/algebraic_builder_decompose_bench.zig", .step = "bench-algebraic-builder-decompose", .desc = "Run the algebraic builder decomposition benchmark." },
        .{ .name = "boundary-direct-first-suspend-bench", .path = "bench/direct_first_suspend_bench.zig", .step = "bench-first-suspend", .desc = "Run the direct-style first-suspend benchmark." },
        .{ .name = "boundary-effect-family-matrix-bench", .path = "bench/effect_family_matrix_bench.zig", .step = "bench-family-matrix", .desc = "Compare every retained effect family against its comparator lane." },
        .{ .name = "boundary-direct-no-capture-bench", .path = "bench/no_capture_bench.zig", .step = "bench", .desc = "Run the direct-style no-capture benchmark." },
        .{ .name = "boundary-resource-effect-decompose-bench", .path = "bench/resource_effect_decompose_bench.zig", .step = "bench-resource-effect-decompose", .desc = "Run the resource effect decomposition benchmark." },
        .{ .name = "boundary-state-effect-bench", .path = "bench/state_effect_bench.zig", .step = "bench-state-effect", .desc = "Compare the additive state effect against the raw prompt baseline." },
        .{ .name = "boundary-writer-effect-decompose-bench", .path = "bench/writer_effect_decompose_bench.zig", .step = "bench-writer-effect-decompose", .desc = "Run the writer effect decomposition benchmark." },
    };
    inline for (bench_specs) |bench| {
        const bench_mod = b.createModule(.{
            .root_source_file = b.path(bench.path),
            .target = target,
            .optimize = bench_optimize,
        });
        bench_mod.addImport("boundary", boundary_bench);
        bench_mod.addImport("lowered_machine", core.lowered_machine);
        const bench_exe = b.addExecutable(.{ .name = bench.name, .root_module = bench_mod });
        bench_check_step.dependOn(&bench_exe.step);
        const bench_run_step = b.step(bench.step, bench.desc);
        if (target.query.isNative()) {
            bench_run_step.dependOn(&b.addRunArtifact(bench_exe).step);
        } else {
            bench_run_step.dependOn(&bench_exe.step);
        }
    }

    const zprof_hotspots_step = b.step("zprof-hotspots", "Profile writer/resource allocator hotspots with zprof.");
    if (b.lazyDependency("zprof", .{
        .target = target,
        .optimize = bench_optimize,
    })) |zprof_dep| {
        const zprof_hotspots_mod = b.createModule(.{
            .root_source_file = b.path("bench/zprof_hotspots.zig"),
            .target = target,
            .optimize = bench_optimize,
        });
        zprof_hotspots_mod.addImport("boundary", boundary_bench);
        zprof_hotspots_mod.addImport("zprof", zprof_dep.module("zprof"));
        const zprof_hotspots_exe = b.addExecutable(.{ .name = "boundary-zprof-hotspots", .root_module = zprof_hotspots_mod });
        zprof_hotspots_step.dependOn(&b.addRunArtifact(zprof_hotspots_exe).step);
    }

    const lint_step = b.step("lint", "Lint source code.");
    const zig_path_coverage_guard = addZigPathCoverageGuard(b);
    lint_step.dependOn(zig_path_coverage_guard);
    var builder = zlinter.builder(b, .{});
    builder.addPaths(.{
        .include = &.{
            b.path("build.zig"),
            b.path("src"),
            b.path("examples"),
            b.path("test"),
            b.path("bench"),
        },
        .exclude = &.{},
    });
    inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
        const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
        builder.addRule(.{ .builtin = rule }, .{});
    }
    const interactive_lint = builder.build();
    lint_step.dependOn(interactive_lint);
    const strict_oracle_lint = strict: {
        const saved_args = b.args;
        defer b.args = saved_args;
        b.args = &.{ "--max-warnings", "0" };
        break :strict builder.build();
    };
    oracle_check_step.dependOn(strict_oracle_lint);
    oracle_check_step.dependOn(zig_path_coverage_guard);

    for (&[_]*std.Build.Step{
        protocol_manifest_step,
        public_surface_step,
        corpus_step,
        agent_profile_step,
        agent_modules_step,
        agent_conformance_corpus_step,
        agent_parity_step,
        format_drift_step,
        adversarial_codecs_step,
        budgets_step,
        proof_receipts_step,
        executable_module_step,
        executable_plan_step,
        loaded_value_step,
        loaded_session_step,
        loaded_v2_step,
        loaded_profile_codecs_step,
        loaded_reachability_step,
        loaded_continuation_step,
        loaded_session_image_step,
        loaded_forged_session_step,
        loaded_resource_ledger_step,
        loaded_frame_stack_step,
        loaded_parity_required_step,
        receipt_loaded_v2_step,
        receipt_loaded_session_step,
        receipt_loaded_parity_step,
        loaded_import_bindings_step,
        loaded_response_safety_step,
        loaded_malformed_step,
        loaded_payload_result_step,
        loaded_fuzz_step,
    }) |validation_step| {
        check_step.dependOn(validation_step);
    }
}
