// zlinter-disable require_errdefer_dealloc
const release_metadata = @import("boundary_static_machine_release_metadata");
const std = @import("std");

const maximum_archive_bytes = 32 * 1024 * 1024;

const VerificationError = error{
    ArchiveSnapshotChanged,
    ArchiveSha256Mismatch,
    PackageHashMismatch,
    ZigVersionMismatch,
    ZigFetchFailed,
};

const ArchiveSha256Comparison = struct {
    actual: [64]u8,
    matches: bool,
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
) !std.process.RunResult {
    const result = try std.process.run(init.gpa, init.io, .{
        .argv = argv,
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
) !void {
    var parsed = try release_metadata.parse(init.gpa);
    defer parsed.deinit();
    const expected = parsed.value.code_archive;

    const version = try runZig(init, &.{ zig_exe, "version" }, "zig version");
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

    const result = try runZig(
        init,
        &.{ zig_exe, "fetch", archive_path },
        "zig fetch",
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

    const retained_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        archive_path,
        init.gpa,
        .limited(maximum_archive_bytes),
    );
    defer init.gpa.free(retained_bytes);
    if (!std.mem.eql(u8, archive_bytes, retained_bytes)) {
        const retained_sha256 = archiveSha256(retained_bytes);
        std.log.err(
            "archive changed during verification: initial {s}, retained {s}",
            .{ initial_comparison.actual, retained_sha256 },
        );
        return error.ArchiveSnapshotChanged;
    }
}

/// Verifies one local Boundary v0.7.0 archive against both reviewed identities.
pub fn main(init: std.process.Init) anyerror!void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const zig_exe = args.next() orelse {
        std.log.err("usage: boundary-release-archive-check <zig-exe> <archive-path>", .{});
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
    if (args.next() != null) return error.InvalidArguments;
    try verifyArchive(init, zig_exe, archive_path);
}

test "release archive falsifiers retain wrong byte and command identities" {
    var parsed = try release_metadata.parse(std.testing.allocator);
    defer parsed.deinit();
    const expected = parsed.value.code_archive;

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
