const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const large_value_count = 1100;
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

const large_block_count = 129;
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
        .maximum_constructors = 512,
        .maximum_environment_fields = 4,
        .maximum_invariant_terms = 4,
        .maximum_generated_operations = 8192,
    };
};
const LargeBlockProgram = program_v2.program(
    "compiler-capacity-blocks-v1",
    LargeBlockBody,
);

test "compiler admits more than 1024 typed values" {
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

test "compiler admits more than 128 reachable blocks" {
    const Machine = LargeBlockProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 4096,
    });
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
