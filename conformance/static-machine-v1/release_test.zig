const std = @import("std");
const boundary = @import("boundary");
const release_sources = @import("boundary_static_machine_release_sources");

const metadata_bytes = @embedFile("release-metadata.json");
const readme_bytes = release_sources.readme_bytes;
const static_machine_bytes = release_sources.static_machine_bytes;
const compatibility_bytes = release_sources.compatibility_bytes;
const release_hardening_bytes = release_sources.release_hardening_bytes;

const expected_commit = "7f2472100454aa2cd5c62e07db0c1e23eaf46a77";
const expected_archive_url = "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz";
const expected_archive_sha256 = "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a";
const expected_package_hash = "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_";

const CodeArchive = struct {
    tag: []const u8,
    commit: []const u8,
    url: []const u8,
    sha256: []const u8,
    zig_package_hash: []const u8,
};

const SupplementFile = struct {
    path: []const u8,
    sha256: []const u8,
};

const DocumentationSupplement = struct {
    included_in_code_archive: bool,
    identity_kind: []const u8,
    publication_binding: []const u8,
    files: []const SupplementFile,
};

const StaticMachineAbi = struct {
    version: u32,
    constructor: []const u8,
    options: []const u8,
    state_encoding: []const u8,
    world_ports: []const u8,
    compatibility_document: []const u8,
    supported_contracts: []const []const u8,
    unsupported_contracts: []const []const u8,
};

const ReleaseMetadata = struct {
    schema: []const u8,
    code_archive: CodeArchive,
    documentation_supplement: DocumentationSupplement,
    static_machine_abi: StaticMachineAbi,
};

const ValidationError = error{
    InvalidSchema,
    CodeArchiveIdentityMismatch,
    DocumentationIdentityConflated,
    DocumentationIdentityIncomplete,
    StaticMachineAbiMismatch,
    SupportMatrixMismatch,
};

const expected_supported = [_][]const u8{
    "authentic-boundary-program",
    "canonical-v1-state",
    "explicit-world-ports",
    "acyclic-static-helper-provider-graphs",
    "admitted-scalar-product-sum-carriers",
    "closed-authored-failure-set",
    "bounded-frames-state-and-validation-work",
    "native-and-wasm32-freestanding",
};

const expected_unsupported = [_][]const u8{
    "recursive-helper-provider-graphs",
    "program-output-or-cleanup-hooks",
    "mutable-string-list-carriers",
    "comptime-struct-fields",
    "non-exhaustive-enums",
    "unrepresentable-compact-condition-histories",
    "dynamic-provider-discovery",
    "runtime-module-loading",
    "v0-continuation-migration",
};

const supplement_sources = [_]struct {
    path: []const u8,
    bytes: []const u8,
}{
    .{ .path = "README.md", .bytes = readme_bytes },
    .{ .path = "docs/release_hardening.md", .bytes = release_hardening_bytes },
    .{ .path = "docs/static_machine.md", .bytes = static_machine_bytes },
    .{ .path = "docs/static_machine_compatibility.md", .bytes = compatibility_bytes },
};

fn parseMetadata(allocator: std.mem.Allocator) !std.json.Parsed(ReleaseMetadata) {
    return std.json.parseFromSlice(
        ReleaseMetadata,
        allocator,
        metadata_bytes,
        .{ .ignore_unknown_fields = false },
    );
}

fn expectExactStrings(actual: []const []const u8, expected: []const []const u8) !void {
    if (actual.len != expected.len) return error.SupportMatrixMismatch;
    for (actual, expected) |actual_item, expected_item| {
        if (!std.mem.eql(u8, actual_item, expected_item)) {
            return error.SupportMatrixMismatch;
        }
    }
}

fn sha256(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn validateMetadata(metadata: ReleaseMetadata) ValidationError!void {
    if (!std.mem.eql(u8, metadata.schema, "boundary-static-machine-release/v1")) {
        return error.InvalidSchema;
    }

    const archive = metadata.code_archive;
    if (!std.mem.eql(u8, archive.tag, "v0.7.0") or
        !std.mem.eql(u8, archive.commit, expected_commit) or
        !std.mem.eql(u8, archive.url, expected_archive_url) or
        !std.mem.eql(u8, archive.sha256, expected_archive_sha256) or
        !std.mem.eql(u8, archive.zig_package_hash, expected_package_hash))
    {
        return error.CodeArchiveIdentityMismatch;
    }

    const supplement = metadata.documentation_supplement;
    if (supplement.included_in_code_archive or
        !std.mem.eql(u8, supplement.identity_kind, "ordered-sha256-file-set-v1") or
        !std.mem.eql(u8, supplement.publication_binding, "reviewed-release-closure-git-commit"))
    {
        return error.DocumentationIdentityConflated;
    }
    if (supplement.files.len != supplement_sources.len) {
        return error.DocumentationIdentityIncomplete;
    }
    for (supplement.files, supplement_sources) |file, source| {
        const digest = sha256(source.bytes);
        if (!std.mem.eql(u8, file.path, source.path) or
            !std.mem.eql(u8, file.sha256, &digest))
        {
            return error.DocumentationIdentityIncomplete;
        }
    }

    const abi = metadata.static_machine_abi;
    if (abi.version != 1 or
        !std.mem.eql(u8, abi.constructor, "boundary.staticMachine") or
        !std.mem.eql(u8, abi.options, "boundary.StaticMachineOptions") or
        !std.mem.eql(u8, abi.state_encoding, "canonical_v1") or
        !std.mem.eql(u8, abi.world_ports, "explicit") or
        !std.mem.eql(u8, abi.compatibility_document, "docs/static_machine_compatibility.md"))
    {
        return error.StaticMachineAbiMismatch;
    }
    try expectExactStrings(abi.supported_contracts, &expected_supported);
    try expectExactStrings(abi.unsupported_contracts, &expected_unsupported);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) != null);
}

test "Boundary v0.7.0 StaticMachine release identity and public surface" {
    try std.testing.expect(@hasDecl(boundary, "staticMachine"));
    try std.testing.expect(@hasDecl(boundary, "StaticMachineOptions"));

    var parsed = try parseMetadata(std.testing.allocator);
    defer parsed.deinit();
    try validateMetadata(parsed.value);

    try expectContains(readme_bytes, "boundary.program -> boundary.staticMachine -> world.application");
    try expectContains(readme_bytes, "Program.Session");
    try expectContains(readme_bytes, "Advanced compatibility: Certified Boundary Modules");
    try expectContains(static_machine_bytes, "Machine.abi_version == 1");
    try expectContains(compatibility_bytes, "Fail-closed restrictions");
    try expectContains(compatibility_bytes, "No transparent migration from a v0 continuation");
}

test "release metadata falsifiers reject wrong code identity and conflated documentation" {
    var parsed = try parseMetadata(std.testing.allocator);
    defer parsed.deinit();

    const valid = parsed.value;

    var wrong_commit = valid;
    wrong_commit.code_archive.commit = "0000000000000000000000000000000000000000";
    try std.testing.expectError(error.CodeArchiveIdentityMismatch, validateMetadata(wrong_commit));

    var wrong_hash = valid;
    wrong_hash.code_archive.zig_package_hash = "boundary-floating-branch";
    try std.testing.expectError(error.CodeArchiveIdentityMismatch, validateMetadata(wrong_hash));

    var conflated = valid;
    conflated.documentation_supplement.included_in_code_archive = true;
    try std.testing.expectError(error.DocumentationIdentityConflated, validateMetadata(conflated));

    var unsupported_claim = valid;
    unsupported_claim.static_machine_abi.unsupported_contracts =
        unsupported_claim.static_machine_abi.unsupported_contracts[0..8];
    try std.testing.expectError(error.SupportMatrixMismatch, validateMetadata(unsupported_claim));
}
