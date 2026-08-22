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
const KernelMachine = Program.kernelMachine(options);
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
    try std.testing.expectEqualSlices(
        u8,
        &ProgramMachine.Manifest.machine_contract_digest,
        &KernelMachine.Manifest.machine_contract_digest,
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
    var reencoded: [Image.bytes.len]u8 = undefined;
    const reencoded_length = try image_v1.reencodeValidated(
        validated,
        &reencoded,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Image.bytes,
        reencoded[0..reencoded_length],
    );
}

test "Reified Program preserves direct canonical State bytes" {
    const direct = try DirectMachine.initialState(std.testing.allocator, 29);
    defer DirectMachine.deinitState(direct);
    const compiled = try ProgramMachine.initialState(std.testing.allocator, 29);
    defer ProgramMachine.deinitState(compiled);
    const kernel_typed = try KernelMachine.initialState(
        std.testing.allocator,
        29,
    );
    defer KernelMachine.deinitState(kernel_typed);

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
    const kernel_typed_bytes = try KernelMachine.encodeState(
        std.testing.allocator,
        kernel_typed,
    );
    defer std.testing.allocator.free(kernel_typed_bytes);
    try std.testing.expectEqualSlices(
        u8,
        compiled_bytes,
        kernel_typed_bytes,
    );
    const direct_from_kernel = try ProgramMachine.decodeState(
        std.testing.allocator,
        kernel_typed_bytes,
    );
    defer ProgramMachine.deinitState(direct_from_kernel);
    try ProgramMachine.validateState(direct_from_kernel);
    const kernel_from_direct = try KernelMachine.decodeState(
        std.testing.allocator,
        compiled_bytes,
    );
    defer KernelMachine.deinitState(kernel_from_direct);
    try KernelMachine.validateState(kernel_from_direct);
    var typed_kernel_fuel: u64 = 8;
    const typed_kernel_done = switch (try KernelMachine.step(
        kernel_typed,
        &typed_kernel_fuel,
    )) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer typed_kernel_done.deinit();
    try std.testing.expectEqual(@as(u32, 29), typed_kernel_done.value().*);
    try std.testing.expectEqual(@as(u64, 7), typed_kernel_fuel);

    const image_v1 = @import("image_v1");
    const kernel_v1 = @import("kernel_v1");
    var workspace: image_v1.ValidationWorkspace = .{};
    const validated = try image_v1.validateImage(&Image.bytes, &workspace);
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 29, .little);
    var kernel_state: [4096]u8 = undefined;
    const kernel_length = try kernel_v1.initial(
        validated,
        &initial_args,
        &kernel_state,
        &workspace,
    );
    try std.testing.expectEqualSlices(
        u8,
        compiled_bytes,
        kernel_state[0..kernel_length],
    );
    try kernel_v1.validateState(validated, compiled_bytes, &workspace);

    const terminal_state = try ProgramMachine.initialState(
        std.testing.allocator,
        29,
    );
    defer ProgramMachine.deinitState(terminal_state);
    var direct_fuel: u64 = 8;
    const direct_done = switch (try ProgramMachine.step(
        terminal_state,
        &direct_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer direct_done.deinit();
    var kernel_fuel: u64 = 8;
    var kernel_result: [4]u8 = undefined;
    var kernel_scratch: [8192]u8 = undefined;
    var kernel_next_state: [4096]u8 = undefined;
    const kernel_done = try kernel_v1.step(
        validated,
        kernel_state[0..kernel_length],
        &kernel_fuel,
        &kernel_next_state,
        &kernel_result,
        &kernel_scratch,
        &workspace,
    );
    const kernel_value = switch (kernel_done) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
    try std.testing.expectEqual(
        direct_done.value().*,
        std.mem.readInt(u32, kernel_value[0..4], .little),
    );
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

test "BEI1 validation recomputes kernel scratch requirements" {
    const image_v1 = @import("image_v1");
    var malformed = Image.bytes;
    malformed[120] ^= 0x01;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.ScratchRequirementMismatch,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BEI1 rejects 1000 deterministic mutations without trap" {
    const image_v1 = @import("image_v1");
    var malformed: [Image.bytes.len]u8 = undefined;
    for (0..1000) |index| {
        @memcpy(&malformed, &Image.bytes);
        const offset = (index * 104729) % malformed.len;
        malformed[offset] ^= @as(u8, 1) << @intCast(index % 8);
        var workspace: image_v1.ValidationWorkspace = .{};
        if (image_v1.validateImage(&malformed, &workspace)) |_| {
            return error.MalformedImageAccepted;
        } else |_| {}
    }
}

test "direct and kernel reject shared malformed State classes" {
    const state = try ProgramMachine.initialState(std.testing.allocator, 29);
    defer ProgramMachine.deinitState(state);
    const encoded = try ProgramMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const image_v1 = @import("image_v1");
    const kernel_v1 = @import("kernel_v1");
    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&Image.bytes, &workspace);
    var malformed: [4096]u8 = undefined;
    for (0..12) |case| {
        @memcpy(malformed[0..encoded.len], encoded);
        var length = encoded.len;
        switch (case) {
            0 => malformed[0] ^= 0xff,
            1 => std.mem.writeInt(u16, malformed[8..10], 2, .little),
            2 => std.mem.writeInt(u16, malformed[10..12], 3, .little),
            3 => malformed[12] ^= 0xff,
            4 => std.mem.writeInt(u64, malformed[44..52], 1, .little),
            5 => std.mem.writeInt(
                u64,
                malformed[52..60],
                options.maximum_machine_fuel + 1,
                .little,
            ),
            6 => std.mem.writeInt(u32, malformed[60..64], 0, .little),
            7 => std.mem.writeInt(u32, malformed[64..68], 1, .little),
            8 => std.mem.writeInt(u32, malformed[68..72], 0xffff, .little),
            9 => std.mem.writeInt(u32, malformed[72..76], 0, .little),
            10 => length -= 1,
            11 => {
                malformed[length] = 0;
                length += 1;
            },
            else => unreachable,
        }
        const bytes = malformed[0..length];
        if (ProgramMachine.decodeState(std.testing.allocator, bytes)) |decoded| {
            ProgramMachine.deinitState(decoded);
            return error.MalformedDirectStateAccepted;
        } else |_| {}
        if (kernel_v1.validateState(image, bytes, &workspace)) {
            return error.MalformedKernelStateAccepted;
        } else |_| {}
    }
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
    const ConstantProgram = program_v2.program(
        "constant-image-proof",
        ConstantBody,
    );
    const ConstantImage = ConstantProgram.image(options);
    const image_v1 = @import("image_v1");
    const kernel_v1 = @import("kernel_v1");
    var workspace: image_v1.ValidationWorkspace = .{};
    const validated = try image_v1.validateImage(
        &ConstantImage.bytes,
        &workspace,
    );
    var state: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        validated,
        &.{},
        &state,
        &workspace,
    );
    var fuel: u64 = 8;
    var output: [4]u8 = undefined;
    var scratch: [8192]u8 = undefined;
    var next_state: [4096]u8 = undefined;
    const outcome = try kernel_v1.step(
        validated,
        state[0..state_length],
        &fuel,
        &next_state,
        &output,
        &scratch,
        &workspace,
    );
    const value = switch (outcome) {
        .done => |bytes| bytes,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(
        @as(u32, 42),
        std.mem.readInt(u32, value[0..4], .little),
    );
}

test "fixed kernel scalar algebra matches direct success and failure" {
    const instructions = [_]cir.Instruction{
        .{
            .kind = .constant,
            .result = 1,
            .operation = .{ .constant = 0 },
        },
        .{
            .kind = .pure,
            .result = 2,
            .operands = &.{ 0, 1 },
            .operation = .integer_add,
        },
    };
    const scalar_blocks = [_]cir.Block{.{
        .id = 0,
        .parameters = &.{0},
        .instructions = &instructions,
        .terminator = .{ .return_value = 2 },
    }};
    const ScalarBody = struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { arithmetic_overflow };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const constants = .{@as(u32, 1)};
        pub const control_ir: cir.Program = .{
            .label = "kernel-scalar-proof",
            .value_types = &.{ u32_type, u32_type, u32_type },
            .blocks = &scalar_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    const ScalarProgram = program_v2.program("kernel-scalar-proof", ScalarBody);
    const ScalarMachine = ScalarProgram.compile(options);
    const ScalarImage = ScalarProgram.image(options);
    const image_v1 = @import("image_v1");
    const kernel_v1 = @import("kernel_v1");
    var workspace: image_v1.ValidationWorkspace = .{};
    const validated = try image_v1.validateImage(&ScalarImage.bytes, &workspace);

    inline for (.{ @as(u32, 41), std.math.maxInt(u32) }) |input| {
        const direct_state = try ScalarMachine.initialState(
            std.testing.allocator,
            input,
        );
        defer ScalarMachine.deinitState(direct_state);
        var direct_fuel: u64 = 8;
        const direct = try ScalarMachine.step(direct_state, &direct_fuel);

        var args: [4]u8 = undefined;
        std.mem.writeInt(u32, &args, input, .little);
        var state: [4096]u8 = undefined;
        const state_length = try kernel_v1.initial(
            validated,
            &args,
            &state,
            &workspace,
        );
        var kernel_fuel: u64 = 8;
        var output: [4]u8 = undefined;
        var scratch: [8192]u8 = undefined;
        var next_state: [4096]u8 = undefined;
        const kernel = try kernel_v1.step(
            validated,
            state[0..state_length],
            &kernel_fuel,
            &next_state,
            &output,
            &scratch,
            &workspace,
        );
        try std.testing.expectEqual(direct_fuel, kernel_fuel);
        if (input == 41) {
            const direct_done = switch (direct) {
                .done => |value| value,
                else => return error.TestUnexpectedResult,
            };
            defer direct_done.deinit();
            const kernel_done = switch (kernel) {
                .done => |value| value,
                else => return error.TestUnexpectedResult,
            };
            try std.testing.expectEqual(
                direct_done.value().*,
                std.mem.readInt(u32, kernel_done[0..4], .little),
            );
        } else {
            const direct_failed = switch (direct) {
                .failed => |failure| failure,
                else => return error.TestUnexpectedResult,
            };
            const kernel_failed = switch (kernel) {
                .failed => |failure| failure,
                else => return error.TestUnexpectedResult,
            };
            try std.testing.expectEqual(
                @intFromEnum(direct_failed.authored),
                std.mem.readInt(u32, kernel_failed[0..4], .little),
            );
        }
    }
}

test "fixed kernel branches and yields at the next segment boundary" {
    const branch_blocks = [_]cir.Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .branch = .{
                .condition = 0,
                .then_edge = .{ .target = 1 },
                .else_edge = .{ .target = 2 },
            } },
        },
        .{
            .id = 1,
            .instructions = &.{.{
                .kind = .constant,
                .result = 1,
                .operation = .{ .constant = 0 },
            }},
            .terminator = .{ .return_value = 1 },
        },
        .{
            .id = 2,
            .instructions = &.{.{
                .kind = .constant,
                .result = 2,
                .operation = .{ .constant = 1 },
            }},
            .terminator = .{ .return_value = 2 },
        },
    };
    const BranchBody = struct {
        pub const InitialArgs = bool;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const constants = .{ @as(u32, 11), @as(u32, 22) };
        pub const control_ir: cir.Program = .{
            .label = "kernel-branch-proof",
            .value_types = &.{
                .{ .scalar = .boolean },
                u32_type,
                u32_type,
            },
            .blocks = &branch_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    const BranchProgram = program_v2.program("kernel-branch-proof", BranchBody);
    const BranchMachine = BranchProgram.compile(options);
    const BranchImage = BranchProgram.image(options);
    const image_v1 = @import("image_v1");
    const kernel_v1 = @import("kernel_v1");
    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&BranchImage.bytes, &workspace);

    inline for (.{ true, false }) |condition| {
        const direct_state = try BranchMachine.initialState(
            std.testing.allocator,
            condition,
        );
        defer BranchMachine.deinitState(direct_state);
        var direct_fuel: u64 = 8;
        const direct_done = switch (try BranchMachine.step(
            direct_state,
            &direct_fuel,
        )) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        defer direct_done.deinit();

        const args = [_]u8{@intFromBool(condition)};
        var state: [4096]u8 = undefined;
        const state_length = try kernel_v1.initial(
            image,
            &args,
            &state,
            &workspace,
        );
        var kernel_fuel: u64 = 8;
        var next_state: [4096]u8 = undefined;
        var output: [4]u8 = undefined;
        var scratch: [12 * 1024]u8 = undefined;
        const kernel_done = switch (try kernel_v1.step(
            image,
            state[0..state_length],
            &kernel_fuel,
            &next_state,
            &output,
            &scratch,
            &workspace,
        )) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(direct_fuel, kernel_fuel);
        try std.testing.expectEqual(
            direct_done.value().*,
            std.mem.readInt(u32, kernel_done[0..4], .little),
        );
    }

    const direct_state = try BranchMachine.initialState(
        std.testing.allocator,
        true,
    );
    defer BranchMachine.deinitState(direct_state);
    var direct_fuel: u64 = 1;
    try std.testing.expectEqual(
        BranchMachine.Outcome.yielded,
        try BranchMachine.step(direct_state, &direct_fuel),
    );
    const direct_bytes = try BranchMachine.encodeState(
        std.testing.allocator,
        direct_state,
    );
    defer std.testing.allocator.free(direct_bytes);
    var state: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(image, &.{1}, &state, &workspace);
    var kernel_fuel: u64 = 1;
    var next_state: [4096]u8 = undefined;
    var output: [4]u8 = undefined;
    var scratch: [12 * 1024]u8 = undefined;
    const yielded = switch (try kernel_v1.step(
        image,
        state[0..state_length],
        &kernel_fuel,
        &next_state,
        &output,
        &scratch,
        &workspace,
    )) {
        .yielded => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
    try std.testing.expectEqualSlices(u8, direct_bytes, yielded);
}
