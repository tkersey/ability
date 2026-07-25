const std = @import("std");

const metadata_bytes = @embedFile("release-metadata.json");

/// Identifies the reviewed Boundary source archive and its verifier toolchain.
pub const CodeArchive = struct {
    tag: []const u8,
    commit: []const u8,
    url: []const u8,
    sha256: []const u8,
    zig_package_hash: []const u8,
    zig_version: []const u8,
};

/// Fixed acceptance oracle for the reviewed Boundary v0.7.0 code archive.
pub const reviewed_code_archive = CodeArchive{
    .tag = "v0.7.0",
    .commit = "7f2472100454aa2cd5c62e07db0c1e23eaf46a77",
    .url = "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz",
    .sha256 = "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a",
    .zig_package_hash = "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_",
    .zig_version = "0.16.0",
};

/// Rejects release metadata that differs from the fixed v0.7.0 oracle.
pub fn validateCodeArchive(actual: CodeArchive) error{CodeArchiveIdentityMismatch}!void {
    const expected = reviewed_code_archive;
    if (!std.mem.eql(u8, actual.tag, expected.tag) or
        !std.mem.eql(u8, actual.commit, expected.commit) or
        !std.mem.eql(u8, actual.url, expected.url) or
        !std.mem.eql(u8, actual.sha256, expected.sha256) or
        !std.mem.eql(u8, actual.zig_package_hash, expected.zig_package_hash) or
        !std.mem.eql(u8, actual.zig_version, expected.zig_version))
    {
        return error.CodeArchiveIdentityMismatch;
    }
}

/// Binds one documentation-supplement path to its SHA-256 digest.
pub const SupplementFile = struct {
    path: []const u8,
    sha256: []const u8,
};

/// Distinguishes post-tag release documentation from the immutable code archive.
pub const DocumentationSupplement = struct {
    included_in_code_archive: bool,
    identity_kind: []const u8,
    publication_binding: []const u8,
    files: []const SupplementFile,
};

/// Records the owner-derived StaticMachine ABI v1 compatibility surface.
pub const StaticMachineAbi = struct {
    version: u32,
    constructor: []const u8,
    options: []const u8,
    state_encoding: []const u8,
    world_ports: []const u8,
    compatibility_document: []const u8,
    supported_contracts: []const []const u8,
    unsupported_contracts: []const []const u8,
};

/// Carries the complete Boundary StaticMachine release receipt.
pub const ReleaseMetadata = struct {
    schema: []const u8,
    code_archive: CodeArchive,
    documentation_supplement: DocumentationSupplement,
    static_machine_abi: StaticMachineAbi,
};

/// Parses the checked release receipt without tolerating unknown fields.
pub fn parse(allocator: std.mem.Allocator) !std.json.Parsed(ReleaseMetadata) {
    return std.json.parseFromSlice(
        ReleaseMetadata,
        allocator,
        metadata_bytes,
        .{ .ignore_unknown_fields = false },
    );
}
