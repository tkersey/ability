const cir = @import("control_ir");
const compiler = @import("compiler");
const image_emit_v1 = @import("image_emit_v1");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .return_value = 0 },
}};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "reified-program-proof",
        .value_types = &.{u32_type},
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Reified = compiler.ReifiedFor("reified-program-proof", Body);
const Direct = compiler.DirectDefinitionFor(Reified);
const CompatibilityDefinition = compiler.DefinitionFor(
    "reified-program-proof",
    Body,
);
const Program = program_v2.program("reified-program-proof", Body);
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const DirectMachine = machine.Machine(Direct, options);
const ProgramMachine = Program.compile(options);
const Image = Program.image(options);
const ProgramSchemas = image_emit_v1.ProgramSchemaSet(Reified, Direct);
const ProgramRoots = image_emit_v1.ProgramRoots(Reified, ProgramSchemas);
const ProgramFailures = image_emit_v1.ProgramFailures(Reified);
const ProgramEffects = image_emit_v1.ProgramEffects(Direct, ProgramSchemas);
const ProgramConstants = image_emit_v1.ProgramConstants(Reified, ProgramSchemas);
const ProgramValues = image_emit_v1.ProgramValues(Reified, ProgramSchemas);
const ProgramFunctions = image_emit_v1.ProgramFunctions(Reified, ProgramSchemas);
const ProgramSegments = image_emit_v1.ProgramSegments(
    Reified,
    ProgramSchemas,
    ProgramConstants,
);
const ProgramTransitions = image_emit_v1.ProgramEntryTransitions(Reified);
const ProgramConstructors = image_emit_v1.ProgramConstructors(
    Reified,
    ProgramSchemas,
);

test "direct specialization consumes the exact Reified Program" {
    try std.testing.expect(Direct.reified_program == Reified);
    try std.testing.expect(CompatibilityDefinition.reified_program == Reified);
    try std.testing.expect(DirectMachine == ProgramMachine);
    try std.testing.expectEqualSlices(
        u8,
        &Reified.semantic_digest,
        &Program.semantic_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &DirectMachine.Manifest.machine_contract_digest,
        &ProgramMachine.Manifest.machine_contract_digest,
    );
    try std.testing.expectEqual(
        Reified.rnf_value.constructor_count,
        Program.rnf.constructor_count,
    );
    try std.testing.expectEqual(@as(u32, 0), Reified.initial_constructor_id);
    try std.testing.expectEqual(@as(u64, 1), Reified.effective_block_costs[0]);
    try std.testing.expectEqual(@as(u32, 2), ProgramSchemas.node_count);
    try std.testing.expectEqual(
        ProgramSchemas.root_ids[0],
        ProgramSchemas.root_ids[1],
    );
    try std.testing.expectEqual(@as(usize, 28), ProgramRoots.bytes.len);
    try std.testing.expectEqual(
        Reified.initial_constructor_id,
        std.mem.readInt(u32, ProgramRoots.bytes[16..20], .little),
    );
    try std.testing.expectEqual(@as(usize, 20), ProgramFailures.bytes.len);
    try std.testing.expectEqual(@as(usize, 4), ProgramEffects.bytes.len);
    try std.testing.expectEqual(@as(usize, 4), ProgramConstants.bytes.len);
    try std.testing.expectEqual(@as(usize, 8), ProgramValues.bytes.len);
    try std.testing.expectEqual(@as(usize, 12), ProgramFunctions.bytes.len);
    try std.testing.expectEqual(@as(usize, 42), ProgramSegments.bytes.len);
    try std.testing.expectEqual(
        @as(u32, 38),
        std.mem.readInt(u32, ProgramSegments.bytes[4..8], .little),
    );
    try std.testing.expectEqual(@as(u8, 3), ProgramSegments.bytes[34]);
    try std.testing.expectEqual(@as(usize, 4), ProgramTransitions.bytes.len);
    try std.testing.expectEqual(@as(usize, 36), ProgramConstructors.bytes.len);
    try std.testing.expectEqual(@as(u8, 0), ProgramConstructors.bytes[12]);
    try std.testing.expectEqualSlices(
        u8,
        &Program.semantic_digest,
        &Image.program_semantic_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &ProgramMachine.Manifest.machine_contract_digest,
        &Image.machine_contract_digest,
    );
    const image_v1 = @import("image_v1");
    var workspace: image_v1.ValidationWorkspace = .{};
    const validated = try image_v1.validateImage(&Image.bytes, &workspace);
    const catalogs = validated.catalogs;
    try std.testing.expectEqual(
        Image.byte_length,
        catalogs.envelope.header.total_length,
    );
    try std.testing.expectEqual(@as(u32, 1), catalogs.value_count);
    try std.testing.expectEqual(@as(u32, 1), validated.segment_count);
    try std.testing.expectEqual(@as(u32, 1), validated.constructor_count);
}

test "Reified Program preserves direct canonical State bytes" {
    const direct = try DirectMachine.initialState(std.testing.allocator, 29);
    defer DirectMachine.deinitState(direct);
    const compiled = try ProgramMachine.initialState(std.testing.allocator, 29);
    defer ProgramMachine.deinitState(compiled);

    const direct_bytes = try DirectMachine.encodeState(
        std.testing.allocator,
        direct,
    );
    defer std.testing.allocator.free(direct_bytes);
    const compiled_bytes = try ProgramMachine.encodeState(
        std.testing.allocator,
        compiled,
    );
    defer std.testing.allocator.free(compiled_bytes);
    try std.testing.expectEqualSlices(u8, direct_bytes, compiled_bytes);
}

test "BEI1 catalog validation fails closed on forged roots" {
    const image_v1 = @import("image_v1");
    var malformed = Image.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const root_offset: usize = envelope.sections[0].offset;
    std.mem.writeInt(u32, malformed[root_offset..][0..4], 0xffff_ffff, .little);
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidRoot,
        image_v1.validateCatalogs(&malformed, &workspace),
    );
}

test "BEI1 executable validation rejects a forged terminator" {
    const image_v1 = @import("image_v1");
    var malformed = Image.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segment_offset: usize = envelope.sections[7].offset;
    malformed[segment_offset + 34] = 0xff;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidTerminator,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BEI1 validation recomputes the Machine contract digest" {
    const image_v1 = @import("image_v1");
    var malformed = Image.bytes;
    malformed[72] ^= 0xff;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.MachineContractDigestMismatch,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BEI1 validation recomputes the Program semantic digest" {
    const image_v1 = @import("image_v1");
    var malformed = Image.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segment_offset: usize = envelope.sections[7].offset;
    malformed[segment_offset + 21] ^= 0x01;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.ProgramSemanticDigestMismatch,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "Reified constants emit in canonical first-use order" {
    const constant_instructions = [_]cir.Instruction{.{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    }};
    const constant_blocks = [_]cir.Block{.{
        .id = 0,
        .instructions = &constant_instructions,
        .terminator = .{ .return_value = 0 },
    }};
    const ConstantBody = struct {
        pub const InitialArgs = void;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const constants = .{@as(u32, 42)};
        pub const control_ir: cir.Program = .{
            .label = "constant-image-proof",
            .value_types = &.{u32_type},
            .blocks = &constant_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    const ConstantReified = compiler.ReifiedFor(
        "constant-image-proof",
        ConstantBody,
    );
    const ConstantDirect = compiler.DirectDefinitionFor(ConstantReified);
    const Schemas = image_emit_v1.ProgramSchemaSet(
        ConstantReified,
        ConstantDirect,
    );
    const Constants = image_emit_v1.ProgramConstants(
        ConstantReified,
        Schemas,
    );
    try std.testing.expectEqual(@as(u32, 1), Constants.constant_count);
    try std.testing.expectEqual(@as(usize, 16), Constants.bytes.len);
    try std.testing.expectEqual(
        @as(u32, 42),
        std.mem.readInt(u32, Constants.bytes[12..16], .little),
    );
}
