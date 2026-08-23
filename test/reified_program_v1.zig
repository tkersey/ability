const cir = @import("control_ir");
const compiler = @import("compiler");
const image_emit_v1 = @import("image_emit_v1");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const machine_v2_profile_v1 = @import("machine_v2_profile_v1");
const program_v2 = @import("program_v2");
const reducer_clause_v1 = @import("reducer_clause_v1");
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

fn MeteredBody(comptime block_cost: u64) type {
    return struct {
        pub const InitialArgs = Body.InitialArgs;
        pub const Result = Body.Result;
        pub const Failure = Body.Failure;
        pub const effect_sites = Body.effect_sites;
        pub const schema_types = Body.schema_types;
        pub const control_ir = Body.control_ir;
        pub const block_costs = [_]u64{block_cost};
    };
}

const Reified = compiler.ReifiedFor("reified-program-proof", Body);
const MachineV2Lowering = compiler.MachineV2LoweringFor(Reified);
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
const KernelMachine = Program.kernelMachineV2(options);
const Image = Program.image();
const Profile = Program.machineV2Profile(options);
const ProgramSchemas = image_emit_v1.ProgramSchemaSet(Reified);
const ProgramRoots = image_emit_v1.ProgramRoots(Reified, ProgramSchemas);
const ProgramFailures = image_emit_v1.ProgramFailures(Reified);
const ProgramEffects = image_emit_v1.ProgramEffects(Reified, ProgramSchemas);
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

pub const ReificationReceiptWitness = struct {
    image_profile_invariance_passed: bool,
    metering_annotation_invariance_passed: bool,
    malformed_image_case_count: u32,
    malformed_state_case_count: u32,
    machine_abi: u16,
    state_format_version: u16,
};

const InvarianceWitness = struct {
    image_profile: bool,
    metering_annotation: bool,
};

fn invarianceWitness() InvarianceWitness {
    const LowProfile = Program.machineV2Profile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 8,
    });
    const HighProfile = Program.machineV2Profile(.{
        .maximum_frames = 32,
        .maximum_state_bytes = 1 << 20,
        .maximum_machine_fuel = 1_000_000,
    });
    const CheapProgram = program_v2.program("metering-invariant", MeteredBody(1));
    const CostlyProgram = program_v2.program("metering-invariant", MeteredBody(9));
    const CheapImage = CheapProgram.image();
    const CostlyImage = CostlyProgram.image();
    const CheapProfile = CheapProgram.machineV2Profile(options);
    const CostlyProfile = CostlyProgram.machineV2Profile(options);
    return .{
        .image_profile = std.mem.eql(u8, &Image.bytes, &Program.image().bytes) and
            std.mem.eql(
                u8,
                &Image.program_transition_digest,
                &Program.program_transition_digest,
            ) and
            !std.mem.eql(u8, &LowProfile.bytes, &HighProfile.bytes) and
            !std.mem.eql(
                u8,
                &LowProfile.machine_v2_contract_digest,
                &HighProfile.machine_v2_contract_digest,
            ),
        .metering_annotation = std.mem.eql(
            u8,
            &CheapImage.bytes,
            &CostlyImage.bytes,
        ) and std.mem.eql(
            u8,
            &CheapProgram.program_transition_digest,
            &CostlyProgram.program_transition_digest,
        ) and !std.mem.eql(
            u8,
            &CheapProfile.bytes,
            &CostlyProfile.bytes,
        ) and !std.mem.eql(
            u8,
            &CheapProgram.machine_v2_semantic_digest,
            &CostlyProgram.machine_v2_semantic_digest,
        ),
    };
}

fn malformedImageCaseCount() !u32 {
    var malformed: [Image.bytes.len]u8 = undefined;
    var rejected: u32 = 0;
    for (0..1000) |index| {
        @memcpy(&malformed, &Image.bytes);
        const offset = (index * 104729) % malformed.len;
        malformed[offset] ^= @as(u8, 1) << @intCast(index % 8);
        var workspace: image_v1.ValidationWorkspace = .{};
        if (image_v1.validateImage(&malformed, &workspace)) |_| {
            return error.MalformedImageAccepted;
        } else |_| {
            rejected += 1;
        }
    }
    return rejected;
}

fn malformedStateCaseCount(allocator: std.mem.Allocator) !u32 {
    const state = try ProgramMachine.initialState(allocator, 29);
    defer ProgramMachine.deinitState(state);
    const encoded = try ProgramMachine.encodeState(allocator, state);
    defer allocator.free(encoded);
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&Image.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(
        program_image,
        &Profile.bytes,
        &workspace,
    );
    var invariant_scratch: [4096]u8 = undefined;
    var malformed: [4096]u8 = undefined;
    var rejected: u32 = 0;
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
        if (ProgramMachine.decodeState(allocator, bytes)) |decoded| {
            ProgramMachine.deinitState(decoded);
            return error.MalformedDirectStateAccepted;
        } else |_| {}
        workspace = .{};
        if (kernel_v1.validateState(
            image,
            bytes,
            &invariant_scratch,
            &workspace,
        )) {
            return error.MalformedKernelStateAccepted;
        } else |_| {
            rejected += 1;
        }
    }
    return rejected;
}

fn zeroFuelMalformedStateRejected(allocator: std.mem.Allocator) !bool {
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&Image.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(
        program_image,
        &Profile.bytes,
        &workspace,
    );
    const state = try ProgramMachine.initialState(allocator, 29);
    defer ProgramMachine.deinitState(state);
    const encoded = try ProgramMachine.encodeState(allocator, state);
    defer allocator.free(encoded);
    const malformed = try allocator.dupe(u8, encoded);
    defer allocator.free(malformed);
    malformed[0] ^= 0xff;
    var fuel: u64 = 0;
    var output_state: [4096]u8 = undefined;
    var output_value: [4096]u8 = undefined;
    var scratch: [8192]u8 = undefined;
    workspace = .{};
    if (kernel_v1.step(
        image,
        malformed,
        &fuel,
        &output_state,
        &output_value,
        &scratch,
        &workspace,
    )) |_| {
        return false;
    } else |err| {
        if (err != error.InvalidState or fuel != 0) return false;
    }
    return true;
}

pub fn reificationReceiptWitness(
    allocator: std.mem.Allocator,
) !ReificationReceiptWitness {
    const invariance = invarianceWitness();
    const malformed_state_count = try malformedStateCaseCount(allocator);
    return .{
        .image_profile_invariance_passed = invariance.image_profile,
        .metering_annotation_invariance_passed = invariance.metering_annotation,
        .malformed_image_case_count = try malformedImageCaseCount(),
        .malformed_state_case_count = malformed_state_count +
            @intFromBool(try zeroFuelMalformedStateRejected(allocator)),
        .machine_abi = machine_v2_profile_v1.machine_abi_version,
        .state_format_version = machine_v2_profile_v1.state_format_version,
    };
}

test "direct specialization consumes the exact Reified Program" {
    try std.testing.expect(Direct.reified_program == Reified);
    try std.testing.expect(CompatibilityDefinition.reified_program == Reified);
    try std.testing.expect(DirectMachine == ProgramMachine);
    try std.testing.expectEqualSlices(
        u8,
        &Reified.program_transition_digest,
        &Program.program_transition_digest,
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
    try std.testing.expectEqual(
        @as(u64, 1),
        MachineV2Lowering.effective_block_costs[0],
    );
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
    try std.testing.expectEqual(@as(usize, 34), ProgramSegments.bytes.len);
    try std.testing.expectEqual(
        @as(u32, 30),
        std.mem.readInt(u32, ProgramSegments.bytes[4..8], .little),
    );
    try std.testing.expectEqual(@as(u8, 3), ProgramSegments.bytes[26]);
    try std.testing.expectEqual(@as(usize, 4), ProgramTransitions.bytes.len);
    try std.testing.expectEqual(@as(usize, 36), ProgramConstructors.bytes.len);
    try std.testing.expectEqual(@as(u8, 0), ProgramConstructors.bytes[12]);
    try std.testing.expectEqualSlices(
        u8,
        &Program.program_transition_digest,
        &Image.program_transition_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &ProgramMachine.Manifest.machine_contract_digest,
        &Profile.machine_v2_contract_digest,
    );
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&Image.bytes, &workspace);
    const catalogs = parsed.catalogs;
    try std.testing.expectEqual(
        Image.byte_length,
        catalogs.envelope.header.total_length,
    );
    try std.testing.expectEqual(@as(u32, 1), catalogs.value_count);
    try std.testing.expectEqual(@as(u32, 1), parsed.segment_count);
    try std.testing.expectEqual(@as(u32, 1), parsed.constructor_count);
    var reencoded: [Image.bytes.len]u8 = undefined;
    const reencoded_length = try image_v1.reencodeValidated(
        parsed,
        &reencoded,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Image.bytes,
        reencoded[0..reencoded_length],
    );
}

test "BPI1 is invariant across Machine v2 profiles and metering annotations" {
    const witness = invarianceWitness();
    try std.testing.expect(witness.image_profile);
    try std.testing.expect(witness.metering_annotation);
}

test "Program.image has no Machine options parameter" {
    const info = @typeInfo(@TypeOf(Program.image)).@"fn";
    try std.testing.expectEqual(@as(usize, 0), info.params.len);
}

test "direct unmetered clause and BPI1 evaluator have one transition meaning" {
    const direct = Direct.reduceClause(Direct.initial(77));
    const direct_result = switch (direct) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&Image.bytes, &workspace);
    var args: [4]u8 = undefined;
    std.mem.writeInt(u32, &args, 77, .little);
    var slots = [_]reducer_clause_v1.Slot{.{}} ** 1024;
    slots[0] = .{ .bytes = &args, .initialized = true };
    var output: [4]u8 = undefined;
    var scratch: [8192]u8 = undefined;
    const evaluated = try reducer_clause_v1.evaluateClause(
        image,
        image.catalogs.entry_segment_id,
        &slots,
        &output,
        &scratch,
        &workspace,
    );
    const bytes = switch (evaluated) {
        .completed => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(
        direct_result,
        std.mem.readInt(u32, bytes[0..4], .little),
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

    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&Image.bytes, &workspace);
    const validated = try kernel_v1.bindMachineV2(parsed, &Profile.bytes, &workspace);
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 29, .little);
    var kernel_state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const kernel_length = try kernel_v1.initial(
        validated,
        &initial_args,
        &kernel_state,
        &invariant_scratch,
        &workspace,
    );
    try std.testing.expectEqualSlices(
        u8,
        compiled_bytes,
        kernel_state[0..kernel_length],
    );
    try kernel_v1.validateState(
        validated,
        compiled_bytes,
        &invariant_scratch,
        &workspace,
    );

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

test "BPI1 catalog validation fails closed on forged roots" {
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

test "BPI1 executable validation rejects a forged terminator" {
    var malformed = Image.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segment_offset: usize = envelope.sections[7].offset;
    malformed[segment_offset + 26] = 0xff;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidTerminator,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "MachineV2Profile validation recomputes the v2 contract digest" {
    var malformed = Profile.bytes;
    malformed[96] ^= 0xff;
    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&Image.bytes, &workspace);
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.bindMachineV2(image, &malformed, &workspace),
    );
}

test "bound kernel certificate rejects backing mutation and reacquires workspace" {
    var image_bytes = Image.bytes;
    var profile_bytes = Profile.bytes;
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&image_bytes, &workspace);
    const binding = try kernel_v1.bindMachineV2(
        parsed,
        &profile_bytes,
        &workspace,
    );
    var args: [4]u8 = undefined;
    std.mem.writeInt(u32, &args, 29, .little);
    var state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        binding,
        &args,
        &state,
        &invariant_scratch,
        &workspace,
    );
    var predecessor: [4096]u8 = undefined;
    @memcpy(predecessor[0..state_length], state[0..state_length]);

    image_bytes[0] ^= 1;
    workspace = .{};
    try std.testing.expectError(
        error.InvalidImage,
        kernel_v1.validateState(
            binding,
            state[0..state_length],
            &invariant_scratch,
            &workspace,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        predecessor[0..state_length],
        state[0..state_length],
    );
    image_bytes[0] ^= 1;

    profile_bytes[0] ^= 1;
    workspace = .{};
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.validateState(
            binding,
            state[0..state_length],
            &invariant_scratch,
            &workspace,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        predecessor[0..state_length],
        state[0..state_length],
    );
    profile_bytes[0] ^= 1;

    workspace = .{};
    var reacquired: [4096]u8 = undefined;
    const reacquired_length = try kernel_v1.initial(
        binding,
        &args,
        &reacquired,
        &invariant_scratch,
        &workspace,
    );
    try std.testing.expectEqualSlices(
        u8,
        state[0..state_length],
        reacquired[0..reacquired_length],
    );
}

test "kernel rejects mutable outputs aliased with authenticated backing" {
    var image_bytes = Image.bytes;
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&image_bytes, &workspace);
    const binding = try kernel_v1.bindMachineV2(
        parsed,
        &Profile.bytes,
        &workspace,
    );
    var args: [4]u8 = undefined;
    std.mem.writeInt(u32, &args, 29, .little);
    var invariant_scratch: [4096]u8 = undefined;
    const before = image_bytes;
    workspace = .{};
    try std.testing.expectError(
        error.InvalidBindings,
        kernel_v1.initial(
            binding,
            &args,
            &image_bytes,
            &invariant_scratch,
            &workspace,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &image_bytes);
}

test "kernel rejects caller fuel aliased with mutable output" {
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&Image.bytes, &workspace);
    const binding = try kernel_v1.bindMachineV2(
        parsed,
        &Profile.bytes,
        &workspace,
    );
    var args: [4]u8 = undefined;
    std.mem.writeInt(u32, &args, 29, .little);
    var state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        binding,
        &args,
        &state,
        &invariant_scratch,
        &workspace,
    );
    var output_state: [4096]u8 = undefined;
    var output_value: [16]u8 align(8) = [_]u8{0xa5} ** 16;
    const caller_fuel: *u64 = @ptrCast(&output_value);
    caller_fuel.* = 8;
    const before = output_value;
    var scratch: [8192]u8 = undefined;
    workspace = .{};
    try std.testing.expectError(
        error.InvalidBindings,
        kernel_v1.step(
            binding,
            state[0..state_length],
            caller_fuel,
            &output_state,
            &output_value,
            &scratch,
            &workspace,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &output_value);
}

test "kernel rejects invariant scratch aliased with State" {
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&Image.bytes, &workspace);
    const binding = try kernel_v1.bindMachineV2(
        parsed,
        &Profile.bytes,
        &workspace,
    );
    var args: [4]u8 = undefined;
    std.mem.writeInt(u32, &args, 29, .little);
    var state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        binding,
        &args,
        &state,
        &invariant_scratch,
        &workspace,
    );
    var before: [4096]u8 = undefined;
    @memcpy(before[0..state_length], state[0..state_length]);
    workspace = .{};
    try std.testing.expectError(
        error.InvalidBindings,
        kernel_v1.validateState(
            binding,
            state[0..state_length],
            state[0..4],
            &workspace,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        before[0..state_length],
        state[0..state_length],
    );
}

test "BPI validator rejects workspace aliased with image bytes" {
    comptime std.debug.assert(
        @sizeOf(image_v1.ValidationWorkspace) >= Image.bytes.len,
    );
    var storage: [@sizeOf(image_v1.ValidationWorkspace)]u8 align(@alignOf(image_v1.ValidationWorkspace)) = undefined;
    @memcpy(storage[0..Image.bytes.len], &Image.bytes);
    const workspace: *image_v1.ValidationWorkspace = @ptrCast(&storage);
    try std.testing.expectError(
        error.InvalidImage,
        image_v1.validateImage(storage[0..Image.bytes.len], workspace),
    );
}

test "MachineV2Profile binds segment costs to v2 semantic identity" {
    var malformed = Profile.bytes;
    const cost_offset = machine_v2_profile_v1.header_length;
    std.mem.writeInt(
        u64,
        malformed[cost_offset..][0..8],
        std.mem.readInt(u64, malformed[cost_offset..][0..8], .little) + 1,
        .little,
    );
    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&Image.bytes, &workspace);
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.bindMachineV2(image, &malformed, &workspace),
    );
}

test "self-consistent forged Machine contract cannot authenticate profile semantics" {
    var malformed = Profile.bytes;
    const cost_offset = machine_v2_profile_v1.header_length;
    std.mem.writeInt(
        u64,
        malformed[cost_offset..][0..8],
        std.mem.readInt(u64, malformed[cost_offset..][0..8], .little) + 1,
        .little,
    );
    malformed[64] ^= 1;
    const contract = machine_v2_profile_v1.machineV2ContractDigest(
        malformed[64..96].*,
        std.mem.readInt(u32, malformed[128..132], .little),
        std.mem.readInt(u32, malformed[132..136], .little),
        std.mem.readInt(u64, malformed[136..144], .little),
    );
    @memcpy(malformed[96..128], &contract);
    _ = try machine_v2_profile_v1.validate(
        &malformed,
        Image.program_transition_digest,
    );

    const state = try ProgramMachine.initialState(std.testing.allocator, 29);
    defer ProgramMachine.deinitState(state);
    const authoritative = try ProgramMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(authoritative);
    const before = try std.testing.allocator.dupe(u8, authoritative);
    defer std.testing.allocator.free(before);

    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&Image.bytes, &workspace);
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.bindMachineV2(image, &malformed, &workspace),
    );
    try std.testing.expectEqualSlices(u8, before, authoritative);
}

test "MachineV2Profile rejects a State ceiling below one RNF frame" {
    var malformed = Profile.bytes;
    std.mem.writeInt(u32, malformed[132..136], 75, .little);
    const contract = machine_v2_profile_v1.machineV2ContractDigest(
        malformed[64..96].*,
        std.mem.readInt(u32, malformed[128..132], .little),
        75,
        std.mem.readInt(u64, malformed[136..144], .little),
    );
    @memcpy(malformed[96..128], &contract);
    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(&Image.bytes, &workspace);
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.bindMachineV2(image, &malformed, &workspace),
    );
}

test "MachineV2Profile authenticates every scalar and constructor component" {
    const segment_count = std.mem.readInt(u32, Profile.bytes[168..172], .little);
    const terminator_override = machine_v2_profile_v1.header_length +
        @as(usize, segment_count) * 8;
    const constructor_origin = machine_v2_profile_v1.header_length +
        @as(usize, segment_count) * 9;
    const constructor_mapping = constructor_origin + std.mem.readInt(
        u32,
        Profile.bytes[172..176],
        .little,
    );
    inline for (.{
        @as(usize, 32), // Program transition binding
        @as(usize, 64), // Machine-v2 semantic digest
        @as(usize, 96), // Machine-v2 contract digest
        @as(usize, 128), // Maximum frames
        @as(usize, 132), // Maximum State bytes
        @as(usize, 136), // Maximum Machine fuel
        @as(usize, 180), // Initial Machine-v2 constructor
        terminator_override,
        constructor_origin,
        constructor_mapping,
    }) |offset| {
        var malformed = Profile.bytes;
        malformed[offset] ^= 1;
        var workspace: image_v1.ValidationWorkspace = .{};
        const image = try image_v1.validateImage(&Image.bytes, &workspace);
        try std.testing.expectError(
            error.InvalidProfile,
            kernel_v1.bindMachineV2(image, &malformed, &workspace),
        );
    }
}

test "BPI1 validation recomputes the Program transition digest" {
    var malformed = Image.bytes;
    malformed[32] ^= 0x01;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.ProgramTransitionDigestMismatch,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BPI1 validation recomputes evaluator scratch requirements" {
    var malformed = Image.bytes;
    malformed[64] ^= 0x01;
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.ScratchRequirementMismatch,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BPI1 rejects 1000 deterministic mutations without trap" {
    try std.testing.expectEqual(@as(u32, 1000), try malformedImageCaseCount());
}

test "direct and kernel reject shared malformed State classes" {
    try std.testing.expectEqual(
        @as(u32, 12),
        try malformedStateCaseCount(std.testing.allocator),
    );
}

test "zero caller fuel cannot launder a malformed State" {
    try std.testing.expect(
        try zeroFuelMalformedStateRejected(std.testing.allocator),
    );
}

test "maximum resume sizing rejects malformed State framing" {
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&Image.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(program_image, &Profile.bytes, &workspace);
    const state = try ProgramMachine.initialState(std.testing.allocator, 29);
    defer ProgramMachine.deinitState(state);
    const encoded = try ProgramMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const malformed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed);
    std.mem.writeInt(u32, malformed[60..64], 2, .little);
    try std.testing.expectError(
        error.InvalidState,
        kernel_v1.maximumResumeStateSize(image, malformed, &workspace),
    );
}

test "KernelMachine terminal owner OOM preserves State ownership" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{},
    );
    const state = try KernelMachine.initialState(failing.allocator(), 29);
    defer KernelMachine.deinitState(state);
    const before = try KernelMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var fuel: u64 = 8;
    const fuel_before = fuel;
    failing.fail_index = failing.allocations + 2;
    try std.testing.expectError(
        error.OutOfMemory,
        KernelMachine.step(state, &fuel),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(fuel_before, fuel);
    failing.fail_index = std.math.maxInt(usize);
    const after = try KernelMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    const done = switch (try KernelMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 29), done.value().*);
}

test "KernelMachine debug metadata matches its inherited Manifest" {
    const DebugKernel = Program.kernelMachineV2(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
        .debug_metadata = true,
    });
    try std.testing.expect(DebugKernel.Manifest.includes_debug_metadata);
    try std.testing.expect(@hasDecl(DebugKernel, "DebugMetadata"));
    try std.testing.expect(@hasDecl(DebugKernel, "debug_metadata"));
    try std.testing.expect(DebugKernel.DebugMetadata != void);
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
    const Schemas = image_emit_v1.ProgramSchemaSet(ConstantReified);
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
    const ConstantImage = ConstantProgram.image();
    const ConstantProfile = ConstantProgram.machineV2Profile(options);
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(
        &ConstantImage.bytes,
        &workspace,
    );
    const validated = try kernel_v1.bindMachineV2(
        parsed,
        &ConstantProfile.bytes,
        &workspace,
    );
    var state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        validated,
        &.{},
        &state,
        &invariant_scratch,
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
    const ScalarImage = ScalarProgram.image();
    const ScalarProfile = ScalarProgram.machineV2Profile(options);
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&ScalarImage.bytes, &workspace);
    var missing_failure_role = ScalarImage.bytes;
    const failures_offset: usize = @intCast(
        parsed.catalogs.envelope.sections[2].offset,
    );
    missing_failure_role[failures_offset + 12] = 'x';
    workspace = .{};
    try std.testing.expectError(
        error.InvalidFailureMap,
        image_v1.validateImage(&missing_failure_role, &workspace),
    );
    workspace = .{};
    const reparsed = try image_v1.validateImage(&ScalarImage.bytes, &workspace);
    const validated = try kernel_v1.bindMachineV2(
        reparsed,
        &ScalarProfile.bytes,
        &workspace,
    );

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
        var invariant_scratch: [4096]u8 = undefined;
        const state_length = try kernel_v1.initial(
            validated,
            &args,
            &state,
            &invariant_scratch,
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
    var malformed = ScalarImage.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segments_offset: usize = @intCast(envelope.sections[7].offset);
    const record = segments_offset + 4;
    var instruction = record + image_v1.segment_prefix_length +
        @as(usize, std.mem.readInt(u16, malformed[record + 10 ..][0..2], .little)) * 2;
    instruction += std.mem.readInt(
        u32,
        malformed[instruction..][0..4],
        .little,
    );
    std.mem.writeInt(u16, malformed[instruction + 16 ..][0..2], 2, .little);
    workspace = .{};
    try std.testing.expectError(
        error.InvalidInstruction,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BPI1 rejects out-of-domain authored failure tags" {
    const fail_blocks = [_]cir.Block{.{
        .id = 0,
        .terminator = .{ .fail = 0 },
    }};
    const FailBody = struct {
        pub const InitialArgs = void;
        pub const Result = void;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "failure-tag-image-proof",
            .value_types = &.{},
            .blocks = &fail_blocks,
            .entry = 0,
            .result_type = .{ .scalar = .unit },
        };
    };
    const FailImage = program_v2.program(
        "failure-tag-image-proof",
        FailBody,
    ).image();
    const envelope = try image_v1.validateEnvelope(&FailImage.bytes);
    const segments_offset: usize = @intCast(envelope.sections[7].offset);
    const terminator_payload = segments_offset + 4 + image_v1.segment_prefix_length + 8;
    inline for (.{ @as(u32, 1), std.math.maxInt(u32) }) |tag| {
        var malformed = FailImage.bytes;
        std.mem.writeInt(
            u32,
            malformed[terminator_payload..][0..4],
            tag,
            .little,
        );
        var workspace: image_v1.ValidationWorkspace = .{};
        try std.testing.expectError(
            error.InvalidTerminator,
            image_v1.validateImage(&malformed, &workspace),
        );
    }
    var truncated: [FailImage.bytes.len - 4]u8 = undefined;
    @memcpy(
        truncated[0..terminator_payload],
        FailImage.bytes[0..terminator_payload],
    );
    @memcpy(
        truncated[terminator_payload..],
        FailImage.bytes[terminator_payload + 4 ..],
    );
    std.mem.writeInt(u64, truncated[24..32], truncated.len, .little);
    const segment_descriptor = image_v1.fixed_prefix_length + 7 *
        image_v1.section_descriptor_length;
    std.mem.writeInt(
        u64,
        truncated[segment_descriptor + 16 ..][0..8],
        std.mem.readInt(
            u64,
            FailImage.bytes[segment_descriptor + 16 ..][0..8],
            .little,
        ) - 4,
        .little,
    );
    inline for (.{ @as(usize, 8), @as(usize, 9) }) |section| {
        const descriptor = image_v1.fixed_prefix_length + section *
            image_v1.section_descriptor_length;
        std.mem.writeInt(
            u64,
            truncated[descriptor + 8 ..][0..8],
            std.mem.readInt(
                u64,
                FailImage.bytes[descriptor + 8 ..][0..8],
                .little,
            ) - 4,
            .little,
        );
    }
    const segment_record = segments_offset + 4;
    std.mem.writeInt(
        u32,
        truncated[segment_record..][0..4],
        std.mem.readInt(
            u32,
            FailImage.bytes[segment_record..][0..4],
            .little,
        ) - 4,
        .little,
    );
    std.mem.writeInt(
        u32,
        truncated[terminator_payload - 8 ..][0..4],
        8,
        .little,
    );
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidTerminator,
        image_v1.validateImage(&truncated, &workspace),
    );
}

test "BPI1 type-checks branch and terminal values" {
    const u8_type: cir.ValueType = .{ .scalar = .u8 };
    const bool_type: cir.ValueType = .{ .scalar = .boolean };
    const compare_operands = [_]cir.ValueId{0};
    const typed_blocks = [_]cir.Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .instructions = &.{.{
                .kind = .compare_eq_zero,
                .result = 1,
                .operands = &compare_operands,
                .operation = .compare_eq_zero,
            }},
            .terminator = .{ .branch = .{
                .condition = 1,
                .then_edge = .{ .target = 1 },
                .else_edge = .{ .target = 2 },
            } },
        },
        .{
            .id = 1,
            .instructions = &.{.{
                .kind = .constant,
                .result = 2,
                .operation = .{ .constant = 0 },
            }},
            .terminator = .{ .return_value = 2 },
        },
        .{
            .id = 2,
            .instructions = &.{.{
                .kind = .constant,
                .result = 3,
                .operation = .{ .constant = 1 },
            }},
            .terminator = .{ .return_value = 3 },
        },
    };
    const TypedBody = struct {
        pub const InitialArgs = u8;
        pub const Result = u8;
        pub const Failure = enum { rejected };
        pub const constants = .{ @as(u8, 7), @as(u8, 8) };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "typed-terminator-image-proof",
            .value_types = &.{ u8_type, bool_type, u8_type, u8_type },
            .blocks = &typed_blocks,
            .entry = 0,
            .result_type = u8_type,
        };
    };
    const TypedImage = program_v2.program(
        "typed-terminator-image-proof",
        TypedBody,
    ).image();
    var malformed = TypedImage.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segments_offset: usize = @intCast(envelope.sections[7].offset);
    const record = segments_offset + 4;
    var terminator = record + image_v1.segment_prefix_length + 2;
    terminator += std.mem.readInt(
        u32,
        malformed[terminator..][0..4],
        .little,
    );
    std.mem.writeInt(u16, malformed[terminator + 8 ..][0..2], 0, .little);
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidTerminator,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BPI1 enforces one resume marker for effect continuations" {
    const Site = struct {
        pub const id: u32 = 0;
        pub const semantic_identity = "test.resume-shape.v1";
        pub const Payload = u32;
        pub const Resume = u32;
    };
    const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
    const effect_blocks = [_]cir.Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .@"suspend" = .{
                .kind = .effect,
                .site_id = 0,
                .request_values = &.{0},
                .continuation = .{
                    .target = 1,
                    .arguments = &resume_arguments,
                },
                .resume_type = u32_type,
            } },
        },
        .{ .id = 1, .parameters = &.{1}, .terminator = .{ .return_value = 1 } },
    };
    const EffectBody = struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{Site};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "resume-shape-image-proof",
            .value_types = &.{ u32_type, u32_type },
            .blocks = &effect_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    const EffectImage = program_v2.program(
        "resume-shape-image-proof",
        EffectBody,
    ).image();
    var malformed = EffectImage.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segments_offset: usize = @intCast(envelope.sections[7].offset);
    const record = segments_offset + 4;
    const terminator = record + image_v1.segment_prefix_length + 2;
    const payload = terminator + 8;
    const request_count = std.mem.readInt(
        u16,
        malformed[payload + 10 ..][0..2],
        .little,
    );
    const continuation = payload + 12 + @as(usize, request_count) * 2 + 4;
    malformed[continuation + 4] = 0;
    std.mem.writeInt(u16, malformed[continuation + 6 ..][0..2], 0, .little);
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidTerminator,
        image_v1.validateImage(&malformed, &workspace),
    );
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
    const BranchImage = BranchProgram.image();
    const BranchProfile = BranchProgram.machineV2Profile(options);
    var workspace: image_v1.ValidationWorkspace = .{};
    const parsed = try image_v1.validateImage(&BranchImage.bytes, &workspace);

    var duplicate_definition = BranchImage.bytes;
    const segments_offset: usize = @intCast(
        parsed.catalogs.envelope.sections[7].offset,
    );
    var third_segment = segments_offset + 4;
    third_segment += std.mem.readInt(
        u32,
        duplicate_definition[third_segment..][0..4],
        .little,
    );
    third_segment += std.mem.readInt(
        u32,
        duplicate_definition[third_segment..][0..4],
        .little,
    );
    const duplicate_instruction = third_segment + image_v1.segment_prefix_length;
    std.mem.writeInt(
        u16,
        duplicate_definition[duplicate_instruction + 8 ..][0..2],
        1,
        .little,
    );
    workspace = .{};
    try std.testing.expectError(
        error.InvalidValue,
        image_v1.validateImage(&duplicate_definition, &workspace),
    );

    var unreachable_catalog = BranchImage.bytes;
    const roots_offset: usize = @intCast(
        parsed.catalogs.envelope.sections[0].offset,
    );
    std.mem.writeInt(
        u16,
        unreachable_catalog[roots_offset + 12 ..][0..2],
        1,
        .little,
    );
    workspace = .{};
    try std.testing.expectError(
        error.InvalidRoot,
        image_v1.validateImage(&unreachable_catalog, &workspace),
    );

    workspace = .{};
    const rebound = try image_v1.validateImage(&BranchImage.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(
        rebound,
        &BranchProfile.bytes,
        &workspace,
    );

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
        var invariant_scratch: [4096]u8 = undefined;
        const state_length = try kernel_v1.initial(
            image,
            &args,
            &state,
            &invariant_scratch,
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
    var invariant_scratch: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        image,
        &.{1},
        &state,
        &invariant_scratch,
        &workspace,
    );
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

test "BPI1 rejects a path constructor with no executable role" {
    const RoleInput = struct {
        condition: bool,
        value: u32,
    };
    const role_entry_instructions = [_]cir.Instruction{
        .{
            .kind = .pure,
            .result = 1,
            .operands = &.{0},
            .operation = .{ .product_extract = 0 },
        },
        .{
            .kind = .pure,
            .result = 2,
            .operands = &.{0},
            .operation = .{ .product_extract = 1 },
        },
    };
    const role_edge_arguments = [_]cir.EdgeArgument{
        .{ .value = 1 },
        .{ .value = 2 },
    };
    const role_join_instructions = [_]cir.Instruction{.{
        .kind = .pure,
        .result = 5,
        .operands = &.{ 3, 4, 4 },
        .operation = .select,
    }};
    const role_blocks = [_]cir.Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .instructions = &role_entry_instructions,
            .terminator = .{ .branch = .{
                .condition = 1,
                .then_edge = .{ .target = 1, .arguments = &role_edge_arguments },
                .else_edge = .{ .target = 1, .arguments = &role_edge_arguments },
            } },
        },
        .{
            .id = 1,
            .parameters = &.{ 3, 4 },
            .instructions = &role_join_instructions,
            .terminator = .{ .return_value = 5 },
        },
    };
    const RoleBody = struct {
        pub const InitialArgs = RoleInput;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{};
        pub const schema_types = .{RoleInput};
        pub const control_ir: cir.Program = .{
            .label = "constructor-role-proof",
            .value_types = &.{
                cir.ValueType{ .schema = 0 },
                cir.ValueType{ .scalar = .boolean },
                u32_type,
                cir.ValueType{ .scalar = .boolean },
                u32_type,
                u32_type,
            },
            .blocks = &role_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    const RoleImage = program_v2.program(
        "constructor-role-proof",
        RoleBody,
    ).image();
    var workspace: image_v1.ValidationWorkspace = .{};
    const validated = try image_v1.validateImage(&RoleImage.bytes, &workspace);
    const transitions_offset: usize = @intCast(
        validated.catalogs.envelope.sections[9].offset,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        std.mem.readInt(u32, RoleImage.bytes[transitions_offset..][0..4], .little),
    );
    const first_constructor = std.mem.readInt(
        u32,
        RoleImage.bytes[transitions_offset + 12 ..][0..4],
        .little,
    );
    const second_constructor = std.mem.readInt(
        u32,
        RoleImage.bytes[transitions_offset + 24 ..][0..4],
        .little,
    );
    try std.testing.expect(first_constructor != second_constructor);
    var malformed = RoleImage.bytes;
    std.mem.writeInt(
        u32,
        malformed[transitions_offset + 24 ..][0..4],
        first_constructor,
        .little,
    );
    workspace = .{};
    try std.testing.expectError(
        error.InvalidConstructor,
        image_v1.validateImage(&malformed, &workspace),
    );
}
