const boundary = @import("boundary");
const release_metadata = @import("boundary_static_machine_release_metadata");
const release_sources = @import("boundary_static_machine_release_sources");
const std = @import("std");

const readme_bytes = release_sources.readme_bytes;
const static_machine_bytes = release_sources.static_machine_bytes;
const compatibility_bytes = release_sources.compatibility_bytes;
const release_hardening_bytes = release_sources.release_hardening_bytes;

const ValidationError = error{
    InvalidSchema,
    CodeArchiveIdentityMismatch,
    DocumentationIdentityConflated,
    DocumentationIdentityInvalid,
    InvalidTextLineEnding,
    StaticMachineAbiMismatch,
    SupportMatrixMismatch,
    CompatibilityClaimMissing,
    PrimaryWorldExampleMismatch,
};

const MatrixClaim = struct {
    identifier: []const u8,
    marker: []const u8,
};

const supported_claims = [_]MatrixClaim{
    .{ .identifier = "authentic-boundary-program", .marker = "`authentic-boundary-program`: the input type is returned by `boundary.program`." },
    .{ .identifier = "canonical-v1-state", .marker = "`canonical-v1-state`: state bytes use `.canonical_v1`." },
    .{ .identifier = "explicit-world-ports", .marker = "`explicit-world-ports`: residual world ports use `.explicit`." },
    .{ .identifier = "acyclic-static-helper-provider-graphs", .marker = "`acyclic-static-helper-provider-graphs`: helper and nested-provider frame graphs are static and acyclic." },
    .{ .identifier = "admitted-scalar-product-sum-carriers", .marker = "`admitted-scalar-product-sum-carriers`: admitted scalar, product, and sum schemas retain their exact logical identities." },
    .{ .identifier = "closed-authored-failure-set", .marker = "`closed-authored-failure-set`: `Body.Error` is closed and excludes reserved operational errors." },
    .{ .identifier = "bounded-frames-state-and-validation-work", .marker = "`bounded-frames-state-and-validation-work`: frame admission, state bytes, and generated validation work are bounded." },
    .{ .identifier = "native-and-wasm32-freestanding", .marker = "`native-and-wasm32-freestanding`: native and `wasm32-freestanding` compile gates are required." },
};

const unsupported_claims = [_]MatrixClaim{
    .{ .identifier = "recursive-helper-provider-graphs", .marker = "`recursive-helper-provider-graphs`: rejected by StaticMachine v1." },
    .{ .identifier = "program-output-or-cleanup-hooks", .marker = "`program-output-or-cleanup-hooks`: rejected by StaticMachine v1." },
    .{ .identifier = "mutable-string-list-carriers", .marker = "`mutable-string-list-carriers`: rejected by StaticMachine v1." },
    .{ .identifier = "comptime-struct-fields", .marker = "`comptime-struct-fields`: rejected by StaticMachine v1." },
    .{ .identifier = "non-exhaustive-enums", .marker = "`non-exhaustive-enums`: rejected by StaticMachine v1." },
    .{ .identifier = "unrepresentable-compact-condition-histories", .marker = "`unrepresentable-compact-condition-histories`: rejected by StaticMachine v1." },
    .{ .identifier = "dynamic-provider-discovery", .marker = "`dynamic-provider-discovery`: outside StaticMachine v1." },
    .{ .identifier = "runtime-module-loading", .marker = "`runtime-module-loading`: outside StaticMachine v1." },
    .{ .identifier = "v0-continuation-migration", .marker = "`v0-continuation-migration`: no transparent migration is supported." },
};

const required_compatibility_claims = [_][]const u8{
    "World Application v1 accepts only machines whose `Machine.EffectRow.after_site_count == 0`; Boundary StaticMachine ABI v1 itself still admits statically known after sites.",
    "`debug_metadata` is diagnostic-only: changing it does not alter the portable contract fingerprint or canonical state bytes.",
    "`maximum_frames` is an admission bound: it must cover the reachable helper/provider depth, but increasing an already sufficient value does not alter the portable contract fingerprint or canonical state bytes.",
    "`maximum_state_bytes` is identity-bearing: changing it alters the machine contract because it bounds canonical state images.",
    "The focused release gate selects only registered `static_machine_*` compile-fail fixtures; it is representative rather than exhaustive, while the aggregate `compile-fail` gate retains the complete repository rejection corpus.",
};

const primary_world_example_claims = [_][]const u8{
    "return 42;",
    ".op_name = \"authored\", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = false",
    "The supported portable path reuses the same validated program type:",
    "`boundary.staticMachine` is the World Comptime v1 deployment surface.",
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

fn canonicalTextSha256(bytes: []const u8) ValidationError![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var segment_start: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        if (bytes[index] != '\r') {
            index += 1;
            continue;
        }
        if (index + 1 >= bytes.len or bytes[index + 1] != '\n') {
            return error.InvalidTextLineEnding;
        }
        hasher.update(bytes[segment_start..index]);
        hasher.update("\n");
        index += 2;
        segment_start = index;
    }
    hasher.update(bytes[segment_start..]);
    var digest: [32]u8 = @splat(0);
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn validateMatrixClaims(
    actual: []const []const u8,
    claims: []const MatrixClaim,
    document: []const u8,
) ValidationError!void {
    if (actual.len != claims.len) return error.SupportMatrixMismatch;
    for (actual, claims) |actual_id, claim| {
        if (!std.mem.eql(u8, actual_id, claim.identifier)) return error.SupportMatrixMismatch;
        if (std.mem.find(u8, document, claim.marker) == null) {
            return error.CompatibilityClaimMissing;
        }
    }
}

fn validateCompatibilityDocument(document: []const u8) ValidationError!void {
    for (&required_compatibility_claims) |claim| {
        if (std.mem.find(u8, document, claim) == null) {
            return error.CompatibilityClaimMissing;
        }
    }
}

fn validatePrimaryWorldExample(document: []const u8) ValidationError!void {
    for (&primary_world_example_claims) |claim| {
        if (std.mem.find(u8, document, claim) == null) {
            return error.PrimaryWorldExampleMismatch;
        }
    }
}

fn validateMetadata(metadata: release_metadata.ReleaseMetadata) ValidationError!void {
    if (!std.mem.eql(u8, metadata.schema, "boundary-static-machine-release/v1")) {
        return error.InvalidSchema;
    }

    release_metadata.validateCodeArchive(metadata.code_archive) catch
        return error.CodeArchiveIdentityMismatch;

    const supplement = metadata.documentation_supplement;
    if (supplement.included_in_code_archive or
        !std.mem.eql(
            u8,
            supplement.identity_kind,
            "ordered-canonical-text-sha256-file-set-v1",
        ) or
        !std.mem.eql(u8, supplement.publication_binding, "reviewed-release-closure-git-commit"))
    {
        return error.DocumentationIdentityConflated;
    }
    if (supplement.files.len != supplement_sources.len) {
        return error.DocumentationIdentityInvalid;
    }
    for (supplement.files, supplement_sources) |file, source| {
        const digest = try canonicalTextSha256(source.bytes);
        if (!std.mem.eql(u8, file.path, source.path) or
            !std.mem.eql(u8, file.sha256, &digest))
        {
            return error.DocumentationIdentityInvalid;
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
    try validateMatrixClaims(abi.supported_contracts, &supported_claims, compatibility_bytes);
    try validateMatrixClaims(abi.unsupported_contracts, &unsupported_claims, compatibility_bytes);
    try validateCompatibilityDocument(compatibility_bytes);
    try validatePrimaryWorldExample(readme_bytes);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.find(u8, haystack, needle) != null);
}

fn releaseUnitPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = "boundary-release-owner-binding",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch |err| @compileError(@errorName(err));
}

const ReleaseProgram = boundary.program("boundary-release-owner-binding", struct {}, struct {
    /// Authentic ProgramPlan compiled into the release ABI witness.
    pub const compiled_plan = releaseUnitPlan();
});
const ReleaseMachine = boundary.staticMachine(ReleaseProgram, .{});
const ReleaseDebugMachine = boundary.staticMachine(ReleaseProgram, .{ .debug_metadata = true });
const ReleaseExpandedFramesMachine = boundary.staticMachine(ReleaseProgram, .{ .maximum_frames = 65 });
const ReleaseExpandedStateMachine = boundary.staticMachine(ReleaseProgram, .{ .maximum_state_bytes = (1 << 20) + 1 });

test "Boundary v0.7.0 StaticMachine release identity and public surface" {
    try std.testing.expect(@hasDecl(boundary, "staticMachine"));
    try std.testing.expect(@hasDecl(boundary, "StaticMachineOptions"));

    var parsed = try release_metadata.parse(std.testing.allocator);
    defer parsed.deinit();
    try validateMetadata(parsed.value);

    try std.testing.expectEqual(parsed.value.static_machine_abi.version, ReleaseMachine.abi_version);
    try std.testing.expectEqual(ReleaseMachine.abi_version, ReleaseMachine.Manifest.abi);
    try std.testing.expect(ReleaseMachine.Manifest.state_is_canonical_v1);
    try std.testing.expect(ReleaseMachine.Manifest.ports_are_explicit);
    try std.testing.expect(!ReleaseMachine.Manifest.includes_debug_metadata);
    try std.testing.expect(ReleaseDebugMachine.Manifest.includes_debug_metadata);
    try std.testing.expectEqual(
        ReleaseMachine.Manifest.machine_contract_fingerprint,
        ReleaseDebugMachine.Manifest.machine_contract_fingerprint,
    );
    try std.testing.expectEqual(
        ReleaseMachine.Manifest.machine_contract_fingerprint,
        ReleaseExpandedFramesMachine.Manifest.machine_contract_fingerprint,
    );
    try std.testing.expect(
        ReleaseMachine.Manifest.machine_contract_fingerprint !=
            ReleaseExpandedStateMachine.Manifest.machine_contract_fingerprint,
    );

    try expectContains(readme_bytes, "boundary.program -> boundary.staticMachine -> world.application");
    try expectContains(readme_bytes, "Program.Session");
    try expectContains(readme_bytes, "Advanced compatibility: Certified Boundary Modules");
    try expectContains(static_machine_bytes, "Machine.abi_version == 1");
    try expectContains(compatibility_bytes, "Fail-closed restrictions");
    try expectContains(compatibility_bytes, "No transparent migration from a v0 continuation");
}

test "release metadata falsifiers reject wrong code identity and conflated documentation" {
    var parsed = try release_metadata.parse(std.testing.allocator);
    defer parsed.deinit();

    const valid = parsed.value;
    try validateMetadata(valid);

    var wrong_commit = valid;
    wrong_commit.code_archive.commit = "0000000000000000000000000000000000000000";
    try std.testing.expectError(error.CodeArchiveIdentityMismatch, validateMetadata(wrong_commit));

    var wrong_hash = valid;
    wrong_hash.code_archive.zig_package_hash = "boundary-floating-branch";
    try std.testing.expectError(error.CodeArchiveIdentityMismatch, validateMetadata(wrong_hash));

    const lf_digest = try canonicalTextSha256("first\nsecond\n");
    const crlf_digest = try canonicalTextSha256("first\r\nsecond\r\n");
    try std.testing.expectEqualStrings(&lf_digest, &crlf_digest);
    try std.testing.expectError(
        error.InvalidTextLineEnding,
        canonicalTextSha256("first\rsecond\n"),
    );

    var conflated = valid;
    conflated.documentation_supplement.included_in_code_archive = true;
    try std.testing.expectError(error.DocumentationIdentityConflated, validateMetadata(conflated));

    var unsupported_claim = valid;
    unsupported_claim.static_machine_abi.unsupported_contracts =
        unsupported_claim.static_machine_abi.unsupported_contracts[0..8];
    try std.testing.expectError(error.SupportMatrixMismatch, validateMetadata(unsupported_claim));

    try std.testing.expectError(
        error.CompatibilityClaimMissing,
        validateCompatibilityDocument(
            "World Application v1 accepts only machines whose after count is zero. " ++
                "Boundary StaticMachine ABI v1 rejects after sites. " ++
                "`debug_metadata` is not identity-bearing. " ++
                "`maximum_frames` is an admission bound. " ++
                "`maximum_state_bytes` is identity-bearing.",
        ),
    );

    try std.testing.expectError(
        error.PrimaryWorldExampleMismatch,
        validatePrimaryWorldExample(
            "return 41; " ++
                ".op_name = \"authored\", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true " ++
                "The supported portable path reuses the same validated program type: " ++
                "`boundary.staticMachine` is the World Comptime v1 deployment surface.",
        ),
    );
}
