// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const first = boundary.ir.builder.local(root, 0);
    const second = boundary.ir.builder.local(root, 1);
    const condition = boundary.ir.builder.local(root, 2);
    const resumed = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = first.index, .operand = first.index },
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .const_i32, .dst = resumed.index, .operand = 0 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = second.index },
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 2,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 4,
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
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 3 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = "static-machine-in-place-after-predicate-overlap",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .bool },
            .{ .codec = .i32 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Handlers = struct {
    step: struct {
        pub fn dispatch(_: *const @This()) error{}!i32 {
            return 1;
        }

        pub fn afterDispatch(_: *const @This(), value: i32) error{}!i32 {
            return value;
        }
    },
};

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-in-place-after-predicate-overlap", Handlers, Body);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest;
}
