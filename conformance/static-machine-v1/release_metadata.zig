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
