// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const source = boundary.ir.builder.local(root, 0);
    const result = boundary.ir.builder.local(root, 1);
    const first = boundary.ir.builder.local(helper, 0);
    const second = boundary.ir.builder.local(helper, 1);
    const condition = boundary.ir.builder.local(helper, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, result, helper, 0) catch unreachable,
        boundary.ir.builder.returnValue(root, result) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = first.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = second.index },
        boundary.ir.builder.returnValue(helper, first) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 3,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 3,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 3, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = "static-machine-helper-predicate-parameter-alias",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .bool },
        },
        .call_args = &.{ source.index, source.index },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program(
    "static-machine-helper-predicate-parameter-alias",
    struct {},
    Body,
);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest;
}
