// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const first = boundary.ir.builder.local(root, 0);
    const second = boundary.ir.builder.local(root, 1);
    const first_condition = boundary.ir.builder.local(root, 2);
    const second_condition = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = first_condition.index, .operand = first.index },
        .{ .kind = .compare_eq_zero, .dst = second_condition.index, .operand = second.index },
        .{ .kind = .add_const_i32, .dst = first.index, .operand = first.index, .aux = 0 },
        .{ .kind = .compare_eq_zero, .dst = first_condition.index, .operand = first.index },
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 2,
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
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 4, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = "static-machine-multiple-condition-predicates",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .bool }, .{ .codec = .bool } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-multiple-condition-predicates", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

test "StaticMachine rejects interleaved unchanged condition predicates" {
    _ = Machine;
}
