// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const source = boundary.ir.builder.local(root, 0);
    const first = boundary.ir.builder.local(root, 1);
    const second = boundary.ir.builder.local(root, 2);
    const condition = boundary.ir.builder.local(root, 3);
    const helper_value = boundary.ir.builder.local(helper, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, first, helper, 0) catch unreachable,
        boundary.ir.builder.callHelper(root, second, helper, 1) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = first.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = second.index },
        boundary.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 4,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 4,
        },
        .{
            .symbol_name = "identity",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 4,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 4,
            .instruction_count = 1,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 4, .terminator_index = 0 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = "static-machine-repeated-helper-predicate-derivation",
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
            .{ .codec = .bool },
            .{ .codec = .i32 },
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
const Program = boundary.program("static-machine-repeated-helper-predicate-derivation", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest;
}
