// zlinter-disable require_errdefer_dealloc
const release_metadata = @import("boundary_static_machine_release_metadata");
const std = @import("std");

const maximum_archive_bytes = 32 * 1024 * 1024;
const completion_receipt_name = "archive-check-complete";
const completion_receipt_bytes = "boundary-release-archive-check/v1\n";

const VerificationError = error{
    ArchiveSha256Mismatch,
    PackageHashMismatch,
    MetadataIdentityMismatch,
    ZigVersionMismatch,
    ZigFetchFailed,
};

const ArchiveSha256Comparison = struct {
    actual: [64]u8,
    matches: bool,
};

const ArchiveSnapshot = struct {
    directory_path: []u8,
    archive_path: []u8,

    fn create(
        init: std.process.Init,
        temporary_root: []const u8,
        archive_bytes: []const u8,
    ) !ArchiveSnapshot {
        var random_bytes: [16]u8 = @splat(0);
        init.io.random(&random_bytes);
        const suffix = std.fmt.bytesToHex(random_bytes, .lower);
        const directory_path = try std.fmt.allocPrint(
            init.gpa,
            "{s}/boundary-release-archive-{s}",
            .{ temporary_root, suffix },
        );
        errdefer init.gpa.free(directory_path);
        try std.Io.Dir.createDirAbsolute(
            init.io,
            directory_path,
            @enumFromInt(0o700),
        );
        errdefer std.Io.Dir.cwd().deleteTree(init.io, directory_path) catch |err| {
            std.log.warn(
                "could not remove failed private archive snapshot {s}: {s}",
                .{ directory_path, @errorName(err) },
            );
        };

        const archive_path = try std.Io.Dir.path.join(
            init.gpa,
            &.{ directory_path, "boundary-v0.7.0.tar.gz" },
        );
        errdefer init.gpa.free(archive_path);
        var file = try std.Io.Dir.createFileAbsolute(init.io, archive_path, .{
            .exclusive = true,
            .permissions = @enumFromInt(0o600),
        });
        defer file.close(init.io);
        try file.writeStreamingAll(init.io, archive_bytes);

        const build_path = try std.Io.Dir.path.join(
            init.gpa,
            &.{ directory_path, "build.zig" },
        );
        defer init.gpa.free(build_path);
        var build_file = try std.Io.Dir.createFileAbsolute(init.io, build_path, .{
            .exclusive = true,
            .permissions = @enumFromInt(0o600),
        });
        defer build_file.close(init.io);
        try build_file.writeStreamingAll(
            init.io,
            "pub fn build(_: *@import(\"std\").Build) void {}\n",
        );

        return .{
            .directory_path = directory_path,
            .archive_path = archive_path,
        };
    }

    fn deinit(snapshot: *ArchiveSnapshot, init: std.process.Init) void {
        std.Io.Dir.cwd().deleteTree(init.io, snapshot.directory_path) catch |err| {
            std.log.warn(
                "could not remove private archive snapshot {s}: {s}",
                .{ snapshot.directory_path, @errorName(err) },
            );
        };
        init.gpa.free(snapshot.archive_path);
        init.gpa.free(snapshot.directory_path);
        snapshot.* = undefined;
    }
};

fn archiveSha256(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = @splat(0);
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn compareArchiveSha256(bytes: []const u8, expected: []const u8) ArchiveSha256Comparison {
    const actual = archiveSha256(bytes);
    return .{
        .actual = actual,
        .matches = std.mem.eql(u8, &actual, expected),
    };
}

fn verifyArchiveSha256(bytes: []const u8, expected: []const u8) VerificationError!void {
    if (!compareArchiveSha256(bytes, expected).matches) {
        return error.ArchiveSha256Mismatch;
    }
}

fn verifyCommandOutput(
    output: []const u8,
    expected: []const u8,
    comptime mismatch: VerificationError,
) VerificationError!void {
    if (!std.mem.eql(u8, std.mem.trim(u8, output, " \r\n\t"), expected)) {
        return mismatch;
    }
}

fn runZig(
    init: std.process.Init,
    argv: []const []const u8,
    failure_label: []const u8,
    cwd: std.process.Child.Cwd,
) !std.process.RunResult {
    const result = try std.process.run(init.gpa, init.io, .{
        .argv = argv,
        .cwd = cwd,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(16 * 1024),
    });
    switch (result.term) {
        .exited => |code| if (code == 0) return result,
        else => {},
    }
    std.log.err("{s} failed: {s}", .{ failure_label, result.stderr });
    init.gpa.free(result.stdout);
    init.gpa.free(result.stderr);
    return error.ZigFetchFailed;
}

fn verifyArchive(
    init: std.process.Init,
    zig_exe: []const u8,
    archive_path: []const u8,
    global_cache_path: []const u8,
    proof_root: []const u8,
) !void {
    var parsed = try release_metadata.parse(init.gpa);
    defer parsed.deinit();
    const expected = parsed.value.code_archive;
    release_metadata.validateCodeArchive(expected) catch |err| {
        std.log.err(
            "release metadata does not match the fixed Boundary v0.7.0 oracle: {s}",
            .{@errorName(err)},
        );
        return error.MetadataIdentityMismatch;
    };

    const version = try runZig(
        init,
        &.{ zig_exe, "version" },
        "zig version",
        .inherit,
    );
    defer init.gpa.free(version.stdout);
    defer init.gpa.free(version.stderr);
    verifyCommandOutput(
        version.stdout,
        expected.zig_version,
        error.ZigVersionMismatch,
    ) catch |err| {
        std.log.err(
            "Zig version mismatch: expected {s}, got {s}",
            .{ expected.zig_version, std.mem.trim(u8, version.stdout, " \r\n\t") },
        );
        return err;
    };

    const archive_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        archive_path,
        init.gpa,
        .limited(maximum_archive_bytes),
    );
    defer init.gpa.free(archive_bytes);
    const initial_comparison = compareArchiveSha256(archive_bytes, expected.sha256);
    if (!initial_comparison.matches) {
        std.log.err(
            "archive SHA-256 mismatch: expected {s}, got {s}",
            .{ expected.sha256, initial_comparison.actual },
        );
        return error.ArchiveSha256Mismatch;
    }

    var snapshot = try ArchiveSnapshot.create(init, proof_root, archive_bytes);
    defer snapshot.deinit(init);
    const result = try runZig(
        init,
        &.{
            zig_exe,
            "fetch",
            "--global-cache-dir",
            global_cache_path,
            snapshot.archive_path,
        },
        "zig fetch",
        .{ .path = snapshot.directory_path },
    );
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    verifyCommandOutput(
        result.stdout,
        expected.zig_package_hash,
        error.PackageHashMismatch,
    ) catch |err| {
        std.log.err(
            "Zig package hash mismatch: expected {s}, got {s}",
            .{
                expected.zig_package_hash,
                std.mem.trim(u8, result.stdout, " \r\n\t"),
            },
        );
        return err;
    };
}

fn writeCompletionReceipt(
    init: std.process.Init,
    proof_root: []const u8,
    receipt_path: []const u8,
) !void {
    if (receipt_path.len == 0) return;
    const expected_path = try std.Io.Dir.path.join(
        init.gpa,
        &.{ proof_root, completion_receipt_name },
    );
    defer init.gpa.free(expected_path);
    if (!std.Io.Dir.path.isAbsolute(receipt_path) or
        !std.mem.eql(u8, receipt_path, expected_path))
    {
        return error.InvalidCompletionReceiptPath;
    }
    var receipt = try std.Io.Dir.createFileAbsolute(init.io, receipt_path, .{
        .exclusive = true,
        .permissions = @enumFromInt(0o600),
    });
    defer receipt.close(init.io);
    try receipt.writeStreamingAll(init.io, completion_receipt_bytes);
}

/// Verifies one local Boundary v0.7.0 archive against both reviewed identities.
pub fn main(init: std.process.Init) anyerror!void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const zig_exe = args.next() orelse {
        std.log.err(
            "usage: boundary-release-archive-check <zig-exe> <archive-path> <global-cache-path> <proof-root> <completion-receipt-path-or-empty>",
            .{},
        );
        return error.InvalidArguments;
    };
    const archive_path = args.next() orelse {
        std.log.err(
            "missing archive; pass -Dboundary-release-archive=/path/to/boundary-v0.7.0.tar.gz",
            .{},
        );
        return error.InvalidArguments;
    };
    if (archive_path.len == 0) {
        std.log.err(
            "missing archive; pass -Dboundary-release-archive=/path/to/boundary-v0.7.0.tar.gz",
            .{},
        );
        return error.InvalidArguments;
    }
    const global_cache_path = args.next() orelse {
        std.log.err(
            "missing global cache path; the caller must bind every nested Zig process to one cache",
            .{},
        );
        return error.InvalidArguments;
    };
    if (global_cache_path.len == 0) return error.InvalidArguments;
    const proof_root = args.next() orelse {
        std.log.err(
            "missing proof root; the caller must provide an absolute writable workspace",
            .{},
        );
        return error.InvalidArguments;
    };
    if (proof_root.len == 0 or !std.Io.Dir.path.isAbsolute(proof_root)) {
        std.log.err("proof root must be an absolute writable directory", .{});
        return error.InvalidArguments;
    }
    const completion_receipt_path = args.next() orelse {
        std.log.err("missing completion receipt path; pass an empty value only for build-integrated verification", .{});
        return error.InvalidArguments;
    };
    if (args.next() != null) return error.InvalidArguments;
    try verifyArchive(
        init,
        zig_exe,
        archive_path,
        global_cache_path,
        proof_root,
    );
    try writeCompletionReceipt(init, proof_root, completion_receipt_path);
}

test "release archive falsifiers retain wrong byte and command identities" {
    var parsed = try release_metadata.parse(std.testing.allocator);
    defer parsed.deinit();
    const expected = parsed.value.code_archive;
    try release_metadata.validateCodeArchive(expected);

    const accepted_bytes = "focused archive predicate baseline";
    const accepted_sha256 = archiveSha256(accepted_bytes);
    try verifyArchiveSha256(accepted_bytes, &accepted_sha256);
    try verifyCommandOutput(
        expected.zig_package_hash,
        expected.zig_package_hash,
        error.PackageHashMismatch,
    );
    try verifyCommandOutput(
        expected.zig_version,
        expected.zig_version,
        error.ZigVersionMismatch,
    );

    var drifted = expected;
    drifted.commit = "0000000000000000000000000000000000000000";
    try std.testing.expectError(
        error.CodeArchiveIdentityMismatch,
        release_metadata.validateCodeArchive(drifted),
    );

    const rejected_bytes = "not the reviewed archive";
    const archive_comparison = compareArchiveSha256(rejected_bytes, expected.sha256);
    const rejected_sha256 = archiveSha256(rejected_bytes);
    try std.testing.expect(!archive_comparison.matches);
    try std.testing.expectEqualStrings(&rejected_sha256, &archive_comparison.actual);
    try std.testing.expectError(
        error.ArchiveSha256Mismatch,
        verifyArchiveSha256(rejected_bytes, expected.sha256),
    );
    try std.testing.expectError(
        error.PackageHashMismatch,
        verifyCommandOutput(
            "boundary-floating-branch\n",
            expected.zig_package_hash,
            error.PackageHashMismatch,
        ),
    );
    try std.testing.expectError(
        error.ZigVersionMismatch,
        verifyCommandOutput(
            "0.17.0-dev\n",
            expected.zig_version,
            error.ZigVersionMismatch,
        ),
    );
}

test "release archive completion receipt is canonical" {
    try std.testing.expectEqualStrings(
        "archive-check-complete",
        completion_receipt_name,
    );
    try std.testing.expectEqualStrings(
        "boundary-release-archive-check/v1\n",
        completion_receipt_bytes,
    );
}
