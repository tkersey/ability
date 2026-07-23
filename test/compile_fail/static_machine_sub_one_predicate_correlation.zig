// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const source = boundary.ir.builder.local(root, 0);
    const derived = boundary.ir.builder.local(root, 1);
    const condition = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .sub_one, .dst = derived.index, .operand = source.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = source.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = derived.index },
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = "static-machine-sub-one-predicate-correlation",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .bool } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-sub-one-predicate-correlation", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest;
}
