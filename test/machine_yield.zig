const cir = @import("control_ir");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const machine_v2_profile_v1 = @import("machine_v2_profile_v1");
const program_v2 = @import("program_v2");
const std = @import("std");

const u32_type: cir.ValueType = .{ .scalar = .u32 };

fn YieldBody(comptime kind: cir.SuspensionKind) type {
    return struct {
        const value_types = [_]cir.ValueType{
            u32_type,
            u32_type,
        };
        const continuation_arguments = [_]cir.EdgeArgument{
            .{ .value = 0 },
        };
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = kind,
                    .continuation = .{
                        .target = 1,
                        .arguments = &continuation_arguments,
                    },
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = @tagName(kind),
            .value_types = &value_types,
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const ExplicitProgram = program_v2.program(
    "explicit-yield",
    YieldBody(.explicit_yield),
);
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const ExplicitMachine = ExplicitProgram.compile(options);
const ExplicitImage = ExplicitProgram.image();
const ExplicitProfile = ExplicitProgram.machineV2Profile(options);

const CheckpointProgram = program_v2.program(
    "caller-fuel-checkpoint",
    YieldBody(.caller_fuel),
);
const CheckpointMachine = CheckpointProgram.compile(options);
const CheckpointImage = CheckpointProgram.image();
const CheckpointProfile = CheckpointProgram.machineV2Profile(options);

const MixedInput = struct {
    condition: bool,
    value: u32,
};
const mixed_value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .scalar = .boolean },
    u32_type,
    u32_type,
    u32_type,
    u32_type,
};
const mixed_entry_instructions = [_]cir.Instruction{
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
const mixed_checkpoint_arguments = [_]cir.EdgeArgument{.{ .value = 3 }};
const mixed_ordinary_arguments = [_]cir.EdgeArgument{.{ .value = 4 }};
const mixed_branch_arguments = [_]cir.EdgeArgument{.{ .value = 2 }};
const mixed_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &mixed_entry_instructions,
        .terminator = .{ .branch = .{
            .condition = 1,
            .then_edge = .{ .target = 1, .arguments = &mixed_branch_arguments },
            .else_edge = .{ .target = 2, .arguments = &mixed_branch_arguments },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{3},
        .terminator = .{ .@"suspend" = .{
            .kind = .caller_fuel,
            .continuation = .{
                .target = 3,
                .arguments = &mixed_checkpoint_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .parameters = &.{4},
        .terminator = .{ .jump = .{
            .target = 3,
            .arguments = &mixed_ordinary_arguments,
        } },
    },
    .{ .id = 3, .parameters = &.{5}, .terminator = .{ .return_value = 5 } },
};
const MixedBody = struct {
    pub const InitialArgs = MixedInput;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{MixedInput};
    pub const control_ir: cir.Program = .{
        .label = "mixed-checkpoint-jump",
        .value_types = &mixed_value_types,
        .blocks = &mixed_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const MixedProgram = program_v2.program("mixed-checkpoint-jump", MixedBody);
const mixed_options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
};
const MixedDirect = MixedProgram.compileV2(mixed_options);
const MixedKernel = MixedProgram.kernelMachineV2(mixed_options);
const MixedImage = MixedProgram.image();
const MixedProfile = MixedProgram.machineV2Profile(mixed_options);

test "explicit yield persists the continuation before returning to the caller" {
    try std.testing.expectEqual(
        @as(usize, 2),
        ExplicitProgram.rnf.constructor_count,
    );
    const checkpoint = &ExplicitProgram.rnf.constructors[1];
    try std.testing.expectEqual(.caller_fuel_yield, checkpoint.kind);
    try std.testing.expectEqual(@as(cir.BlockId, 1), checkpoint.source_block);
    try std.testing.expectEqual(@as(usize, 1), checkpoint.environment_len);
    try std.testing.expectEqual(
        @as(cir.ValueId, 1),
        checkpoint.environment[0].value,
    );
    for (checkpoint.invariantTerms()) |term| switch (term) {
        .value_copy => return error.TestUnexpectedResult,
        else => {},
    };

    const state = try ExplicitMachine.initialState(std.testing.allocator, 11);
    defer ExplicitMachine.deinitState(state);
    var fuel: u64 = 4;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try ExplicitMachine.step(state, &fuel)),
    );
    try std.testing.expectEqual(@as(u64, 3), fuel);

    const encoded = try ExplicitMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try ExplicitMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer ExplicitMachine.deinitState(restored);

    var resume_fuel: u64 = 1;
    const done = switch (try ExplicitMachine.step(restored, &resume_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 11), done.value().*);
    try std.testing.expectEqual(@as(u64, 0), resume_fuel);
}

test "caller-fuel checkpoint yields only when the next segment is unfunded" {
    const state = try CheckpointMachine.initialState(
        std.testing.allocator,
        19,
    );
    defer CheckpointMachine.deinitState(state);
    var one_segment: u64 = 1;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try CheckpointMachine.step(
            state,
            &one_segment,
        )),
    );
    try std.testing.expectEqual(@as(u64, 0), one_segment);

    var resume_fuel: u64 = 1;
    const resumed = switch (try CheckpointMachine.step(state, &resume_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer resumed.deinit();
    try std.testing.expectEqual(@as(u32, 19), resumed.value().*);

    const uninterrupted = try CheckpointMachine.initialState(
        std.testing.allocator,
        23,
    );
    defer CheckpointMachine.deinitState(uninterrupted);
    var two_segments: u64 = 2;
    const done = switch (try CheckpointMachine.step(
        uninterrupted,
        &two_segments,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 23), done.value().*);
    try std.testing.expectEqual(@as(u64, 0), two_segments);
}

test "fixed kernel preserves explicit and caller-fuel checkpoints" {
    inline for (.{
        .{ ExplicitImage, ExplicitProfile, @as(u32, 11), @as(u64, 4), true },
        .{ CheckpointImage, CheckpointProfile, @as(u32, 19), @as(u64, 1), false },
    }) |fixture| {
        const Image = fixture[0];
        const Profile = fixture[1];
        const input = fixture[2];
        var workspace: image_v1.ValidationWorkspace = .{};
        const program_image = try image_v1.validateImage(&Image.bytes, &workspace);
        const image = try kernel_v1.bindMachineV2(program_image, &Profile.bytes, &workspace);
        var args: [4]u8 = undefined;
        std.mem.writeInt(u32, &args, input, .little);
        var state: [4096]u8 = undefined;
        const state_length = try kernel_v1.initial(
            image,
            &args,
            &state,
            &workspace,
        );
        var fuel = fixture[3];
        var next_state: [4096]u8 = undefined;
        var output: [4]u8 = undefined;
        var scratch: [12 * 1024]u8 = undefined;
        const yielded = switch (try kernel_v1.step(
            image,
            state[0..state_length],
            &fuel,
            &next_state,
            &output,
            &scratch,
            &workspace,
        )) {
            .yielded => |value| value,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(
            if (fixture[4]) @as(u64, 3) else 0,
            fuel,
        );
        var resume_fuel: u64 = 1;
        var terminal_state: [4096]u8 = undefined;
        const done = switch (try kernel_v1.step(
            image,
            yielded,
            &resume_fuel,
            &terminal_state,
            &output,
            &scratch,
            &workspace,
        )) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(
            input,
            std.mem.readInt(u32, done[0..4], .little),
        );
        try std.testing.expectEqual(@as(u64, 0), resume_fuel);
    }
}

test "BPI1 excludes synthetic caller-fuel suspension and retains explicit yield" {
    var workspace: image_v1.ValidationWorkspace = .{};
    const explicit = try image_v1.validateImage(&ExplicitImage.bytes, &workspace);
    const explicit_segments = explicit.catalogs.envelope.section(.segments);
    const explicit_terminator = 4 + image_v1.segment_prefix_length +
        @as(usize, std.mem.readInt(u16, explicit_segments[14..16], .little)) * 2;
    try std.testing.expectEqual(
        @as(u8, 2),
        explicit_segments[explicit_terminator + 4],
    );
    var malformed_explicit = ExplicitImage.bytes;
    const explicit_section_offset: usize = @intCast(
        explicit.catalogs.envelope.sections[7].offset,
    );
    const explicit_terminator_absolute = explicit_section_offset +
        explicit_terminator;
    const explicit_terminator_length = std.mem.readInt(
        u32,
        malformed_explicit[explicit_terminator_absolute..][0..4],
        .little,
    );
    std.mem.writeInt(
        u32,
        malformed_explicit[explicit_terminator_absolute + explicit_terminator_length - 4 ..][0..4],
        explicit.catalogs.initial_args_schema_id,
        .little,
    );
    workspace = .{};
    try std.testing.expectError(
        error.InvalidTerminator,
        image_v1.validateImage(&malformed_explicit, &workspace),
    );

    workspace = .{};
    const checkpoint = try image_v1.validateImage(
        &CheckpointImage.bytes,
        &workspace,
    );
    const checkpoint_segments = checkpoint.catalogs.envelope.section(.segments);
    const checkpoint_terminator = 4 + image_v1.segment_prefix_length +
        @as(usize, std.mem.readInt(u16, checkpoint_segments[14..16], .little)) * 2;
    try std.testing.expectEqual(
        @as(u8, 0),
        checkpoint_segments[checkpoint_terminator + 4],
    );
    const constructors = checkpoint.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..std.mem.readInt(u32, constructors[0..4], .little)) |_| {
        try std.testing.expect(constructors[cursor + 8] != 6);
        cursor += std.mem.readInt(u32, constructors[cursor..][0..4], .little);
    }
    try std.testing.expectEqual(constructors.len, cursor);
}

test "mixed checkpoint and ordinary jump share BPI1 but preserve Machine v2" {
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&MixedImage.bytes, &workspace);
    _ = try kernel_v1.bindMachineV2(
        program_image,
        &MixedProfile.bytes,
        &workspace,
    );
    const profile_segment_count = std.mem.readInt(
        u32,
        MixedProfile.bytes[168..172],
        .little,
    );
    const profile_constructor_count = std.mem.readInt(
        u32,
        MixedProfile.bytes[172..176],
        .little,
    );
    const profile_transition_count = std.mem.readInt(
        u32,
        MixedProfile.bytes[176..180],
        .little,
    );
    const override_start = machine_v2_profile_v1.header_length +
        @as(usize, profile_segment_count) * 8;
    const origin_start = override_start + profile_segment_count;
    const mapping_start = origin_start + profile_constructor_count;
    const transition_kind_start = mapping_start + profile_constructor_count * 4;
    const transition_constructor_start = transition_kind_start +
        profile_transition_count;
    inline for (.{ override_start + 1, transition_kind_start }) |offset| {
        var malformed_profile = MixedProfile.bytes;
        malformed_profile[offset] ^= 1;
        workspace = .{};
        const authentic_image = try image_v1.validateImage(
            &MixedImage.bytes,
            &workspace,
        );
        try std.testing.expectError(
            error.InvalidProfile,
            kernel_v1.bindMachineV2(
                authentic_image,
                &malformed_profile,
                &workspace,
            ),
        );
    }
    var malformed_mapping = MixedProfile.bytes;
    const last_mapping = mapping_start +
        (@as(usize, profile_constructor_count) - 1) * 4;
    std.mem.writeInt(u32, malformed_mapping[last_mapping..][0..4], 0, .little);
    workspace = .{};
    const mapping_image = try image_v1.validateImage(&MixedImage.bytes, &workspace);
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.bindMachineV2(
            mapping_image,
            &malformed_mapping,
            &workspace,
        ),
    );
    var malformed_transition = MixedProfile.bytes;
    const original_transition_constructor = std.mem.readInt(
        u32,
        malformed_transition[transition_constructor_start..][0..4],
        .little,
    );
    std.mem.writeInt(
        u32,
        malformed_transition[transition_constructor_start..][0..4],
        (original_transition_constructor + 1) % profile_constructor_count,
        .little,
    );
    workspace = .{};
    const transition_image = try image_v1.validateImage(
        &MixedImage.bytes,
        &workspace,
    );
    try std.testing.expectError(
        error.InvalidProfile,
        kernel_v1.bindMachineV2(
            transition_image,
            &malformed_transition,
            &workspace,
        ),
    );
    const segments = program_image.catalogs.envelope.section(.segments);
    var segment_cursor: usize = 4;
    for (0..program_image.segment_count) |_| {
        const segment_length = std.mem.readInt(
            u32,
            segments[segment_cursor..][0..4],
            .little,
        );
        var terminator = segment_cursor + image_v1.segment_prefix_length +
            @as(
                usize,
                std.mem.readInt(
                    u16,
                    segments[segment_cursor + 10 ..][0..2],
                    .little,
                ),
            ) * 2;
        for (0..std.mem.readInt(
            u32,
            segments[segment_cursor + 12 ..][0..4],
            .little,
        )) |_| {
            terminator += std.mem.readInt(
                u32,
                segments[terminator..][0..4],
                .little,
            );
        }
        if (segments[terminator + 4] == 2) {
            try std.testing.expect(segments[terminator + 8] != 3);
        }
        segment_cursor += segment_length;
    }
    const constructors = program_image.catalogs.envelope.section(.constructors);
    var constructor_cursor: usize = 4;
    for (0..program_image.constructor_count) |_| {
        try std.testing.expect(constructors[constructor_cursor + 8] != 6);
        constructor_cursor += std.mem.readInt(
            u32,
            constructors[constructor_cursor..][0..4],
            .little,
        );
    }

    inline for (.{ true, false }) |condition| {
        const input: MixedInput = .{ .condition = condition, .value = 37 };
        const direct = try MixedDirect.initialState(std.testing.allocator, input);
        defer MixedDirect.deinitState(direct);
        const kernel = try MixedKernel.initialState(std.testing.allocator, input);
        defer MixedKernel.deinitState(kernel);
        const direct_initial = try MixedDirect.encodeState(
            std.testing.allocator,
            direct,
        );
        defer std.testing.allocator.free(direct_initial);
        const kernel_initial = try MixedKernel.encodeState(
            std.testing.allocator,
            kernel,
        );
        defer std.testing.allocator.free(kernel_initial);
        try std.testing.expectEqualSlices(u8, direct_initial, kernel_initial);

        var direct_fuel: u64 = 4;
        var kernel_fuel: u64 = 4;
        try std.testing.expectEqual(
            .yielded,
            std.meta.activeTag(try MixedDirect.step(direct, &direct_fuel)),
        );
        try std.testing.expectEqual(
            .yielded,
            std.meta.activeTag(try MixedKernel.step(kernel, &kernel_fuel)),
        );
        try std.testing.expectEqual(direct_fuel, kernel_fuel);
        const direct_yielded = try MixedDirect.encodeState(
            std.testing.allocator,
            direct,
        );
        defer std.testing.allocator.free(direct_yielded);
        const kernel_yielded = try MixedKernel.encodeState(
            std.testing.allocator,
            kernel,
        );
        defer std.testing.allocator.free(kernel_yielded);
        try std.testing.expectEqualSlices(u8, direct_yielded, kernel_yielded);

        var direct_completion_fuel: u64 = 1;
        var kernel_completion_fuel: u64 = 1;
        const direct_done = switch (try MixedDirect.step(
            direct,
            &direct_completion_fuel,
        )) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        defer direct_done.deinit();
        const kernel_done = switch (try MixedKernel.step(
            kernel,
            &kernel_completion_fuel,
        )) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        defer kernel_done.deinit();
        try std.testing.expectEqual(@as(u32, 37), direct_done.value().*);
        try std.testing.expectEqual(direct_done.value().*, kernel_done.value().*);
        try std.testing.expectEqual(
            direct_completion_fuel,
            kernel_completion_fuel,
        );
    }
}

test "KernelMachine preserves terminal execution-budget failure and prior charges" {
    const budget_options: machine.Options = .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 1,
    };
    const Direct = CheckpointProgram.compile(budget_options);
    const Kernel = CheckpointProgram.kernelMachineV2(budget_options);
    const direct = try Direct.initialState(std.testing.allocator, 19);
    defer Direct.deinitState(direct);
    const kernel = try Kernel.initialState(std.testing.allocator, 19);
    defer Kernel.deinitState(kernel);
    var direct_fuel: u64 = 5;
    var kernel_fuel: u64 = 5;
    try std.testing.expectEqual(
        Direct.Outcome{ .failed = .execution_budget_exceeded },
        try Direct.step(direct, &direct_fuel),
    );
    try std.testing.expectEqual(
        Kernel.Outcome{ .failed = .execution_budget_exceeded },
        try Kernel.step(kernel, &kernel_fuel),
    );
    try std.testing.expectEqual(@as(u64, 4), direct_fuel);
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
    try std.testing.expectError(
        error.ProgramContractViolation,
        Kernel.validateState(kernel),
    );
}
