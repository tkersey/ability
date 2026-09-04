const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const count = 129;
const value_types = [_]cir.ValueType{.{ .scalar = .u32 }} ** count;
const parameters = blk: {
    var result: [count][1]cir.ValueId = undefined;
    for (&result, 0..) |*parameter, index| parameter.* = .{@intCast(index)};
    break :blk result;
};
const callee_arguments = blk: {
    var result: [count - 1][1]cir.EdgeArgument = undefined;
    for (&result, 0..) |*argument, index| {
        argument.* = .{.{ .value = @intCast(index) }};
    }
    break :blk result;
};
const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const functions = blk: {
    var result: [count]cir.Function = undefined;
    for (&result, 0..) |*function, index| function.* = .{
        .id = @intCast(index),
        .entry = @intCast(index),
        .result_type = .{ .scalar = .u32 },
    };
    break :blk result;
};
const blocks = blk: {
    var result: [count]cir.Block = undefined;
    for (&result, 0..) |*block, index| block.* = if (index + 1 == count) .{
        .id = @intCast(index),
        .function_id = @intCast(index),
        .parameters = &parameters[index],
        .terminator = .{ .return_to_caller = @intCast(index) },
    } else .{
        .id = @intCast(index),
        .function_id = @intCast(index),
        .parameters = &parameters[index],
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = @intCast(index + 1),
            .callee = .{
                .target = @intCast(index + 1),
                .arguments = &callee_arguments[index],
            },
            .continuation = .{
                .target = @intCast(index),
                .arguments = &resume_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    };
    break :blk result;
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const compiler_limits: cir.CompilerLimits = .{
        .maximum_values = count,
        .maximum_blocks = count,
        .maximum_constructors = 256,
        .maximum_environment_fields = 4,
        .maximum_invariant_terms = 4,
        .maximum_generated_operations = 8192,
    };
    pub const control_ir: cir.Program = .{
        .label = "image-function-catalog-limit",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &functions,
    };
};

comptime {
    _ = program_v2.program(
        "image-function-catalog-limit",
        Body,
    ).reachable_function_count;
}
