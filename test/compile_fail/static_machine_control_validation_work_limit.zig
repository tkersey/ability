// zlinter-disable declaration_naming no_undefined require_doc_comment no_swallow_error
const boundary = @import("boundary");

const block_count = 25;

fn makeBlocks() [block_count]boundary.ir.plan.Block {
    var result: [block_count]boundary.ir.plan.Block = undefined;
    for (0..block_count) |index| {
        result[index] = .{
            .first_instruction = if (index == 0) 0 else 1,
            .instruction_count = if (index == 0) 1 else 0,
            .terminator_index = @intCast(index),
        };
    }
    return result;
}

fn makeTerminators() [block_count]boundary.ir.plan.Terminator {
    var result: [block_count]boundary.ir.plan.Terminator = undefined;
    for (0..block_count) |index| {
        result[index] = .{
            .kind = .jump,
            .primary = @intCast(if (index + 1 == block_count) 0 else index + 1),
        };
    }
    return result;
}

const blocks = makeBlocks();
const terminators = makeTerminators();

fn plan() boundary.ir.ProgramPlan {
    @setEvalBranchQuota(100_000);
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, value, boundary.ir.builder.op(root, 0), null) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = block_count,
        .first_instruction = 0,
        .instruction_count = 1,
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "protocol", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "step",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    return boundary.ir.builder.finish(.{
        .label = "static-machine-control-validation-work-limit",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-control-validation-work-limit", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest.control_validation_step_bound;
}
