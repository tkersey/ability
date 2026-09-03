const cir = @import("control_ir");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const large_value_count = 1200;
const large_value_types = [_]cir.ValueType{.{ .scalar = .u32 }} ** large_value_count;
const copy_operands = blk: {
    @setEvalBranchQuota(10_000_000);
    var result: [large_value_count - 1][1]cir.ValueId = undefined;
    for (&result, 0..) |*operand, index| operand.* = .{@intCast(index)};
    break :blk result;
};
const copy_instructions = blk: {
    @setEvalBranchQuota(10_000_000);
    var result: [large_value_count - 1]cir.Instruction = undefined;
    for (&result, 0..) |*instruction, index| instruction.* = .{
        .kind = .copy,
        .result = @intCast(index + 1),
        .operands = &copy_operands[index],
        .operation = .copy,
    };
    break :blk result;
};
const large_value_blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &copy_instructions,
    .terminator = .{ .return_value = large_value_count - 1 },
}};
const LargeValueBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "compiler-capacity-values-v1",
        .value_types = &large_value_types,
        .blocks = &large_value_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
    pub const compiler_limits: cir.CompilerLimits = .{
        .maximum_values = large_value_count,
        .maximum_blocks = 1,
        .maximum_constructors = 4,
        .maximum_environment_fields = 4,
        .maximum_invariant_terms = 4,
        .maximum_generated_operations = 8192,
    };
};
const LargeValueProgram = program_v2.program(
    "compiler-capacity-values-v1",
    LargeValueBody,
);

const large_block_count = 180;
const block_value_types = [_]cir.ValueType{.{ .scalar = .u32 }} ** large_block_count;
const block_parameters = blk: {
    @setEvalBranchQuota(10_000_000);
    var result: [large_block_count][1]cir.ValueId = undefined;
    for (&result, 0..) |*parameter, index| parameter.* = .{@intCast(index)};
    break :blk result;
};
const block_arguments = blk: {
    @setEvalBranchQuota(10_000_000);
    var result: [large_block_count - 1][1]cir.EdgeArgument = undefined;
    for (&result, 0..) |*argument, index| {
        argument.* = .{.{ .value = @intCast(index) }};
    }
    break :blk result;
};
const many_blocks = blk: {
    @setEvalBranchQuota(10_000_000);
    var result: [large_block_count]cir.Block = undefined;
    for (&result, 0..) |*block, index| {
        block.* = if (index + 1 == large_block_count) .{
            .id = @intCast(index),
            .parameters = &block_parameters[index],
            .terminator = .{ .return_value = @intCast(index) },
        } else .{
            .id = @intCast(index),
            .parameters = &block_parameters[index],
            .terminator = .{ .jump = .{
                .target = @intCast(index + 1),
                .arguments = &block_arguments[index],
            } },
        };
    }
    break :blk result;
};
const LargeBlockBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "compiler-capacity-blocks-v1",
        .value_types = &block_value_types,
        .blocks = &many_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
    pub const compiler_limits: cir.CompilerLimits = .{
        .maximum_values = large_block_count,
        .maximum_blocks = large_block_count,
        .maximum_constructors = 256,
        .maximum_environment_fields = 4,
        .maximum_invariant_terms = 4,
        .maximum_generated_operations = 8192,
    };
};
const LargeBlockProgram = program_v2.program(
    "compiler-capacity-blocks-v1",
    LargeBlockBody,
);
const large_block_options: machine.Options = .{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 4096,
};

test "compiler admits 1200 typed values" {
    const Machine = LargeValueProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 4096,
    });
    const state = try Machine.initialState(std.testing.allocator, 73);
    defer Machine.deinitState(state);
    var fuel: u64 = 4096;
    const done = switch (try Machine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.UnexpectedOutcome,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 73), done.value().*);
    try std.testing.expect(LargeValueProgram.image().bytes.len > 0);
}

test "compiler admits 180 reachable blocks" {
    const Machine = LargeBlockProgram.compile(large_block_options);
    const state = try Machine.initialState(std.testing.allocator, 91);
    defer Machine.deinitState(state);
    var fuel: u64 = 4096;
    const done = switch (try Machine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.UnexpectedOutcome,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 91), done.value().*);
    try std.testing.expect(LargeBlockProgram.image().bytes.len > 0);
}

test "fixed Machine-v2 kernel admits 180 reachable blocks" {
    const Image = LargeBlockProgram.image();
    const Profile = LargeBlockProgram.machineV2Profile(large_block_options);
    var workspace: image_v1.ValidationWorkspace = .{};
    const envelope = try image_v1.validateImage(&Image.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(
        envelope,
        &Profile.bytes,
        &workspace,
    );
    var input: [4]u8 = undefined;
    std.mem.writeInt(u32, &input, 91, .little);
    var state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        image,
        &input,
        &state,
        &invariant_scratch,
        &workspace,
    );
    var fuel: u64 = 4096;
    var next_state: [4096]u8 = undefined;
    var output: [4096]u8 = undefined;
    var scratch: [256 * 1024]u8 = undefined;
    const done = switch (try kernel_v1.step(
        image,
        state[0..state_length],
        &fuel,
        &next_state,
        &output,
        &scratch,
        &workspace,
    )) {
        .done => |value| value,
        else => return error.UnexpectedOutcome,
    };
    try std.testing.expectEqual(@as(u32, 91), std.mem.readInt(u32, done[0..4], .little));
}
