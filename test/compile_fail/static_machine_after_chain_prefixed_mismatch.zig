// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const prefix_resume = boundary.ir.builder.local(root, 2);
    const middle_resume = boundary.ir.builder.local(root, 3);
    const inner_resume = boundary.ir.builder.local(root, 4);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.callOp(root, prefix_resume, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.callOp(root, middle_resume, boundary.ir.builder.op(root, 1), null) catch unreachable,
        boundary.ir.builder.callOp(root, inner_resume, boundary.ir.builder.op(root, 2), null) catch unreachable,
        boundary.ir.builder.returnValue(root, inner_resume) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 3,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 5,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 4,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "prefix", .first_op = 0, .op_count = 1 },
        .{ .label = "middle", .first_op = 1, .op_count = 1 },
        .{ .label = "inner", .first_op = 2, .op_count = 1 },
    };
    const ops = [_]boundary.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "prefix",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 1,
            .op_name = "middle",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 2,
            .op_name = "inner",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 1 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 2 },
        .{ .first_instruction = 1, .instruction_count = 4, .terminator_index = 3 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = "static-machine-after-chain-prefixed-mismatch",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Handlers = struct {
    prefix: struct {
        pub fn dispatch(_: *const @This()) error{}!i32 {
            return 1;
        }

        pub fn afterDispatch(_: *const @This(), value: []const u8) error{}![]const u8 {
            return value;
        }
    },
    middle: struct {
        pub fn dispatch(_: *const @This()) error{}!i32 {
            return 2;
        }

        pub fn afterDispatch(_: *const @This(), value: bool) error{}![]const u8 {
            return if (value) "true" else "false";
        }
    },
    inner: struct {
        pub fn dispatch(_: *const @This()) error{}!i32 {
            return 3;
        }

        pub fn afterDispatch(_: *const @This(), value: i32) error{}!i32 {
            return value;
        }
    },
};

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-after-chain-prefixed-mismatch", Handlers, Body);
const Machine = boundary.staticMachine(Program, .{});

test "StaticMachine validates every adjacent pair after a prefix after site" {
    _ = Machine;
}
