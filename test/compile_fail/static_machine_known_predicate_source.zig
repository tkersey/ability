// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const other = boundary.ir.builder.local(root, 0);
    const known = boundary.ir.builder.local(root, 1);
    const condition = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = other.index },
        .{ .kind = .const_i32, .dst = known.index, .operand = 0 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = known.index },
        .{ .kind = .const_i32, .dst = known.index, .operand = 1 },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 6,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "step",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "step",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 1 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 2 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 3 },
        .{ .first_instruction = 3, .instruction_count = 0, .terminator_index = 4 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 5 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .branch_if, .primary = 4, .secondary = 5 },
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return boundary.ir.builder.finish(.{
        .label = "static-machine-known-predicate-source",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
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
const Program = boundary.program("static-machine-known-predicate-source", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest;
}
