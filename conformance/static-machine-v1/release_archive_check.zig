// zlinter-disable require_errdefer_dealloc
const std = @import("std");

const expected_archive_sha256 = "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a";
const expected_package_hash = "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_";
const maximum_archive_bytes = 32 * 1024 * 1024;

const VerificationError = error{
    ArchiveSha256Mismatch,
    PackageHashMismatch,
    ZigFetchFailed,
};

fn archiveSha256(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = @splat(0);
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn verifyArchiveSha256(bytes: []const u8, expected: []const u8) VerificationError!void {
    const actual = archiveSha256(bytes);
    if (!std.mem.eql(u8, &actual, expected)) return error.ArchiveSha256Mismatch;
}

fn verifyPackageHash(output: []const u8, expected: []const u8) VerificationError!void {
    const actual = std.mem.trim(u8, output, " \r\n\t");
    if (!std.mem.eql(u8, actual, expected)) return error.PackageHashMismatch;
}

fn verifyArchive(
    init: std.process.Init,
    zig_exe: []const u8,
    archive_path: []const u8,
) !void {
    const archive_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        archive_path,
        init.gpa,
        .limited(maximum_archive_bytes),
    );
    defer init.gpa.free(archive_bytes);
    try verifyArchiveSha256(archive_bytes, expected_archive_sha256);

    const result = try std.process.run(init.gpa, init.io, .{
        .argv = &.{ zig_exe, "fetch", archive_path },
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(16 * 1024),
    });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            std.log.err("zig fetch failed for '{s}': {s}", .{ archive_path, result.stderr });
            return error.ZigFetchFailed;
        },
        else => {
            std.log.err("zig fetch terminated abnormally for '{s}'", .{archive_path});
            return error.ZigFetchFailed;
        },
    }
    try verifyPackageHash(result.stdout, expected_package_hash);
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
        std.log.err("usage: boundary-release-archive-check <zig-exe> <archive-path>", .{});
        return error.InvalidArguments;
    };
    if (args.next() != null) return error.InvalidArguments;
    try verifyArchive(init, zig_exe, archive_path);
}

test "release archive falsifiers reject wrong byte and package identities" {
    try std.testing.expectError(
        error.ArchiveSha256Mismatch,
        verifyArchiveSha256("not the reviewed archive", expected_archive_sha256),
    );
    try std.testing.expectError(
        error.PackageHashMismatch,
        verifyPackageHash("boundary-floating-branch\n", expected_package_hash),
    );
}
