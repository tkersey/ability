// zlinter-disable declaration_naming no_inferred_error_unions no_swallow_error require_doc_comment
const boundary = @import("boundary");
const std = @import("std");

fn purePlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
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
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 0,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn branchCachePlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const result = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        .{ .kind = .const_i32, .dst = result.index, .operand = 1 },
        boundary.ir.builder.returnValue(root, result) catch unreachable,
        .{ .kind = .const_i32, .dst = result.index, .operand = 2 },
        boundary.ir.builder.returnValue(root, result) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 19,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn oneEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const resumed = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = payload.index, .string_literal = "payload" },
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), payload) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "test", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "decide",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const root_value = boundary.ir.builder.local(root, 0);
    const helper_value = boundary.ir.builder.local(helper, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        .{ .kind = .add_const_i32, .dst = root_value.index, .operand = root_value.index, .aux = 1 },
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
        boundary.ir.builder.callOp(helper, helper_value, boundary.ir.builder.op(helper, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 3,
            .instruction_count = 2,
        },
    };
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "helper", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "yield",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn stringEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const resumed = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "test", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "text",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 3,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn afterEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const resumed = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "test", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "after",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 4,
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

fn pairStringArgsPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const first = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.returnValue(root, first) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string,
        .parameter_count = 2,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 5,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .string } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn zeroInstructionPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 6,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

fn returnErrorPlan(comptime label: []const u8, comptime error_name: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const instructions = [_]boundary.ir.plan.Instruction{.{ .kind = .return_error, .string_literal = error_name }};
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 1,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 7,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const nested_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn alternateNestedTargetPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const first_target = boundary.ir.builder.function(1);
    const second_target = boundary.ir.builder.function(2);
    const root_value = boundary.ir.builder.local(root, 0);
    const first_value = boundary.ir.builder.local(first_target, 0);
    const second_value = boundary.ir.builder.local(second_target, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .call_nested_with, .dst = root_value.index, .aux = @intFromEnum(boundary.ir.ValueCodec.i32), .string_literal = nested_metadata },
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = first_value.index, .operand = 1 },
        boundary.ir.builder.returnValue(first_target, first_value) catch unreachable,
        .{ .kind = .const_i32, .dst = second_value.index, .operand = 2 },
        boundary.ir.builder.returnValue(second_target, second_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{ .symbol_name = "run", .value_codec = .i32, .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 1, .first_block = 0, .entry_block = 0, .block_count = 1, .first_instruction = 0, .instruction_count = 2 },
        .{ .symbol_name = "first", .value_codec = .i32, .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 1, .local_count = 1, .first_block = 1, .entry_block = 0, .block_count = 1, .first_instruction = 2, .instruction_count = 2 },
        .{ .symbol_name = "second", .value_codec = .i32, .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 2, .local_count = 1, .first_block = 2, .entry_block = 0, .block_count = 1, .first_instruction = 4, .instruction_count = 2 },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{ .{ .kind = .return_value }, .{ .kind = .return_value }, .{ .kind = .return_value } };
    const targets = .{boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 1 }};
    return boundary.ir.builder.finishWithNestedTargets(.{
        .label = label,
        .ir_hash = 8,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }, targets) catch unreachable;
}

fn provenanceVariantPlan(comptime hash: u64) boundary.ir.ProgramPlan {
    var plan = oneEffectPlan("static-machine-provenance-identity");
    plan.ir_hash = hash;
    return plan;
}

fn afterProvenanceVariantPlan(comptime hash: u64) boundary.ir.ProgramPlan {
    var plan = afterEffectPlan("static-machine-after-provenance-identity");
    plan.ir_hash = hash;
    return plan;
}

fn stackedAfterPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const outer_resume = boundary.ir.builder.local(root, 0);
    const inner_resume = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, outer_resume, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.callOp(root, inner_resume, boundary.ir.builder.op(root, 1), null) catch unreachable,
        boundary.ir.builder.returnValue(root, inner_resume) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "outer", .first_op = 0, .op_count = 1 },
        .{ .label = "inner", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]boundary.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "outer",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 1,
            .op_name = "inner",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 9,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn abortDelimitedAfterPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const outer_resume = boundary.ir.builder.local(root, 2);
    const inner_resume = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.callOp(root, outer_resume, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 1), null) catch unreachable,
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
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 4,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "outer", .first_op = 0, .op_count = 1 },
        .{ .label = "abort", .first_op = 1, .op_count = 1 },
        .{ .label = "inner", .first_op = 2, .op_count = 1 },
    };
    const ops = [_]boundary.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "outer",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 1,
            .op_name = "abort",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
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
        .label = label,
        .ir_hash = 21,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .bool }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn loopPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .jump, .primary = 0 }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 10,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

fn nonCompletingHelperPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const root_value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = @intCast(instructions.len),
        },
        .{
            .symbol_name = "never",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = @intCast(instructions.len),
            .instruction_count = 0,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 },
        .{ .first_instruction = @intCast(instructions.len), .instruction_count = 0, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .jump, .primary = 1 },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 15,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn nonCompletingNestedPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const provider = boundary.ir.builder.function(1);
    const root_value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(boundary.ir.ValueCodec.i32),
            .string_literal = nested_metadata,
        },
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = @intCast(instructions.len),
        },
        .{
            .symbol_name = "provider",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = @intCast(instructions.len),
            .instruction_count = 0,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 },
        .{ .first_instruction = @intCast(instructions.len), .instruction_count = 0, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .jump, .primary = 1 },
    };
    const targets = .{boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = provider.index }};
    return boundary.ir.builder.finishWithNestedTargets(.{
        .label = label,
        .ir_hash = 16,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }, targets) catch unreachable;
}

fn overflowPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .add_const_i32, .dst = value.index, .operand = value.index, .aux = 1 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
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
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 11,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn stringListEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const resumed = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string_list,
        .result_codec = .string_list,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "test", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "items",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string_list,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 12,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .string_list }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const OneEffectBody = struct {
    pub const compiled_plan = oneEffectPlan("static-machine-one-effect");
};
const OneEffectProgram = boundary.program("static-machine-one-effect", struct {}, OneEffectBody);
const OneEffectMachine = boundary.staticMachine(OneEffectProgram, .{});

const PureBody = struct {
    pub const compiled_plan = purePlan("static-machine-pure");
};
const PureProgram = boundary.program("static-machine-pure", struct {}, PureBody);
const PureMachine = boundary.staticMachine(PureProgram, .{});

const BranchCacheBody = struct {
    pub const compiled_plan = branchCachePlan("static-machine-branch-cache");
};
const BranchCacheProgram = boundary.program("static-machine-branch-cache", struct {}, BranchCacheBody);
const BranchCacheMachine = boundary.staticMachine(BranchCacheProgram, .{});

const HelperBody = struct {
    pub const compiled_plan = helperEffectPlan("static-machine-helper");
};
const HelperProgram = boundary.program("static-machine-helper", struct {}, HelperBody);
const HelperMachine = boundary.staticMachine(HelperProgram, .{});

const StringBody = struct {
    pub const compiled_plan = stringEffectPlan("static-machine-owned-string-response");
};
const StringProgram = boundary.program("static-machine-owned-string-response", struct {}, StringBody);
const StringMachine = boundary.staticMachine(StringProgram, .{});

const AfterBody = struct {
    pub const compiled_plan = afterEffectPlan("static-machine-after-checkpoint");
};
const AfterProgram = boundary.program("static-machine-after-checkpoint", struct {}, AfterBody);
const AfterMachine = boundary.staticMachine(AfterProgram, .{});

const PairArgsBody = struct {
    pub const compiled_plan = pairStringArgsPlan("static-machine-pair-args");
};
const PairArgsProgram = boundary.program("static-machine-pair-args", struct {}, PairArgsBody);
const PairArgsMachine = boundary.staticMachine(PairArgsProgram, .{});

const ZeroBody = struct {
    pub const compiled_plan = zeroInstructionPlan("static-machine-zero-instruction");
};
const ZeroProgram = boundary.program("static-machine-zero-instruction", struct {}, ZeroBody);
const ZeroMachine = boundary.staticMachine(ZeroProgram, .{});

const AuthoredBudgetBody = struct {
    pub const Error = error{ExecutionBudgetExceeded};
    pub const compiled_plan = returnErrorPlan("static-machine-authored-budget", "ExecutionBudgetExceeded");
};
const AuthoredBudgetProgram = boundary.program("static-machine-authored-budget", struct {}, AuthoredBudgetBody);
const AuthoredBudgetMachine = boundary.staticMachine(AuthoredBudgetProgram, .{});

const NestedFirstBody = struct {
    pub const compiled_plan = alternateNestedTargetPlan("static-machine-nested-identity");
    pub const nested_with_targets = .{boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 1 }};
};
const NestedSecondBody = struct {
    pub const compiled_plan = NestedFirstBody.compiled_plan;
    pub const nested_with_targets = .{boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 2 }};
};
const NestedFirstProgram = boundary.program("static-machine-nested-identity", struct {}, NestedFirstBody);
const NestedSecondProgram = boundary.program("static-machine-nested-identity", struct {}, NestedSecondBody);
const NestedFirstMachine = boundary.staticMachine(NestedFirstProgram, .{});
const NestedSecondMachine = boundary.staticMachine(NestedSecondProgram, .{});

const ProvenanceBodyA = struct {
    pub const compiled_plan = provenanceVariantPlan(13);
};
const ProvenanceBodyB = struct {
    pub const compiled_plan = provenanceVariantPlan(14);
};
const ProvenanceProgramA = boundary.program("static-machine-provenance-identity", struct {}, ProvenanceBodyA);
const ProvenanceProgramB = boundary.program("static-machine-provenance-identity", struct {}, ProvenanceBodyB);
const ProvenanceMachineA = boundary.staticMachine(ProvenanceProgramA, .{});
const ProvenanceMachineB = boundary.staticMachine(ProvenanceProgramB, .{});

const RelabeledProgramA = boundary.program("static-machine-label-a", struct {}, ProvenanceBodyA);
const RelabeledProgramB = boundary.program("static-machine-label-b", struct {}, ProvenanceBodyA);
const RelabeledMachineA = boundary.staticMachine(RelabeledProgramA, .{});
const RelabeledMachineB = boundary.staticMachine(RelabeledProgramB, .{});

const AfterProvenanceBodyA = struct {
    pub const compiled_plan = afterProvenanceVariantPlan(17);
};
const AfterProvenanceBodyB = struct {
    pub const compiled_plan = afterProvenanceVariantPlan(18);
};
const AfterProvenanceProgramA = boundary.program("static-machine-after-provenance-identity", struct {}, AfterProvenanceBodyA);
const AfterProvenanceProgramB = boundary.program("static-machine-after-provenance-identity", struct {}, AfterProvenanceBodyB);
const AfterProvenanceMachineA = boundary.staticMachine(AfterProvenanceProgramA, .{});
const AfterProvenanceMachineB = boundary.staticMachine(AfterProvenanceProgramB, .{});

const AfterHandlersA = struct {
    outer: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 1;
        }
        pub fn afterDispatch(_: *const @This(), value: bool) ![]const u8 {
            return if (value) "true" else "false";
        }
    },
    inner: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 7;
        }
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value != 0;
        }
    },
};
const AfterHandlersB = struct {
    outer: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 1;
        }
        pub fn afterDispatch(_: *const @This(), value: []const u8) ![]const u8 {
            return value;
        }
    },
    inner: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 7;
        }
        pub fn afterDispatch(_: *const @This(), value: i32) ![]const u8 {
            return if (value != 0) "true" else "false";
        }
    },
};
const AfterContractBody = struct {
    pub const compiled_plan = stackedAfterPlan("static-machine-after-contract");
};
const AfterContractProgramA = boundary.program("static-machine-after-contract", AfterHandlersA, AfterContractBody);
const AfterContractProgramB = boundary.program("static-machine-after-contract", AfterHandlersB, AfterContractBody);
const AfterContractMachineA = boundary.staticMachine(AfterContractProgramA, .{});
const AfterContractMachineB = boundary.staticMachine(AfterContractProgramB, .{});

const AfterHandlersHandlerlessOuter = struct {
    outer: struct {},
    inner: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value != 0;
        }
    },
};
const HandlerlessOuterProgram = boundary.program(
    "static-machine-handlerless-outer-after",
    AfterHandlersHandlerlessOuter,
    AfterContractBody,
);
const HandlerlessOuterMachine = boundary.staticMachine(HandlerlessOuterProgram, .{});

const AbortDelimitedAfterHandlers = struct {
    outer: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 1;
        }
        pub fn afterDispatch(_: *const @This(), value: bool) ![]const u8 {
            return if (value) "true" else "false";
        }
    },
    abort: struct {
        pub fn dispatch(_: *const @This()) ![]const u8 {
            return "aborted";
        }
    },
    inner: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 7;
        }
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value != 0;
        }
    },
};
const AbortDelimitedAfterBody = struct {
    pub const compiled_plan = abortDelimitedAfterPlan("static-machine-abort-delimited-after");
};
const AbortDelimitedAfterProgram = boundary.program(
    "static-machine-abort-delimited-after",
    AbortDelimitedAfterHandlers,
    AbortDelimitedAfterBody,
);
const AbortDelimitedAfterMachine = boundary.staticMachine(AbortDelimitedAfterProgram, .{});

const LoopBody = struct {
    pub const compiled_plan = loopPlan("static-machine-cumulative-budget");
};
const LoopProgram = boundary.program("static-machine-cumulative-budget", struct {}, LoopBody);
const LoopMachine = boundary.staticMachine(LoopProgram, .{});

const NonCompletingHelperBody = struct {
    pub const compiled_plan = nonCompletingHelperPlan("static-machine-noncompleting-helper");
};
const NonCompletingHelperProgram = boundary.program(
    "static-machine-noncompleting-helper",
    struct {},
    NonCompletingHelperBody,
);
const NonCompletingHelperMachine = boundary.staticMachine(NonCompletingHelperProgram, .{});

const NonCompletingNestedBody = struct {
    pub const compiled_plan = nonCompletingNestedPlan("static-machine-noncompleting-nested");
    pub const nested_with_targets = .{boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 1 }};
};
const NonCompletingNestedProgram = boundary.program(
    "static-machine-noncompleting-nested",
    struct {},
    NonCompletingNestedBody,
);
const NonCompletingNestedMachine = boundary.staticMachine(NonCompletingNestedProgram, .{});

const OverflowBody = struct {
    pub const compiled_plan = overflowPlan("static-machine-post-dispatch-overflow");
};
const OverflowProgram = boundary.program("static-machine-post-dispatch-overflow", struct {}, OverflowBody);
const OverflowMachine = boundary.staticMachine(OverflowProgram, .{});

const StringListBody = struct {
    pub const compiled_plan = stringListEffectPlan("static-machine-string-list-oom");
};
const StringListProgram = boundary.program("static-machine-string-list-oom", struct {}, StringListBody);
const StringListMachine = boundary.staticMachine(StringListProgram, .{});

const TinyStateMachine = boundary.staticMachine(OneEffectProgram, .{ .maximum_state_bytes = 32 });

test "StaticMachine executes a pure scalar program" {
    comptime {
        if (@typeInfo(PureMachine.OwnedResult) != .@"opaque" or @hasDecl(PureMachine.OwnedResult, "takeStorage")) {
            @compileError("StaticMachine OwnedResult must be opaque and expose no storage transfer operation");
        }
    }
    const state = try PureMachine.initialState(std.testing.allocator, .{});
    defer PureMachine.deinitState(state);
    var fuel: u64 = 100;
    var result = switch (try PureMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value());
}

test "StaticMachine state survives a canonical parked-state round trip" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);

    var fuel: u64 = 100;
    const request = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqualStrings("payload", try request.payload([]const u8));

    const encoded = try OneEffectMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try OneEffectMachine.decodeState(std.testing.allocator, encoded);
    defer OneEffectMachine.deinitState(restored);

    const restored_request = switch (try OneEffectMachine.current(restored)) {
        .request => |current| current,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(request.trace().operation_site_fingerprint, restored_request.trace().operation_site_fingerprint);
    try std.testing.expectEqualStrings("payload", try restored_request.payload([]const u8));

    try OneEffectMachine.@"resume"(restored, restored_request, @as(i32, 41));
    var result = switch (try OneEffectMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value());
}

test "StaticMachine preserves helper suspension across state bytes" {
    const state = try HelperMachine.initialState(std.testing.allocator, .{});
    defer HelperMachine.deinitState(state);

    var fuel: u64 = 100;
    _ = switch (try HelperMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const encoded = try HelperMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try HelperMachine.decodeState(std.testing.allocator, encoded);
    defer HelperMachine.deinitState(restored);

    const request = switch (try HelperMachine.current(restored)) {
        .request => |current| current,
        else => return error.UnexpectedTransition,
    };
    try HelperMachine.@"resume"(restored, request, @as(i32, 40));
    var result = switch (try HelperMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value());
}

test "StaticMachine matches Program.Session observations" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try OneEffectProgram.Session.start(&runtime, .{});
    defer session.deinit();
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);

    const session_request = switch (try session.next()) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    var fuel: u64 = 100;
    const static_request = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try session_request.expectSite(OneEffectProgram.protocol.operationSite("test", "decide", 0));
    try static_request.expectSite(OneEffectMachine.EffectRow.operationSite("test", "decide", 0));
    try std.testing.expectEqual(session_request.operation_site_index, static_request.operation_site_index);
    try std.testing.expectEqual(session_request.function_index, static_request.function_index);
    try std.testing.expectEqual(session_request.block_index, static_request.block_index);
    try std.testing.expectEqual(session_request.instruction_index, static_request.instruction_index);
    try std.testing.expect(session_request.payload_ref.eql(static_request.payload_ref));
    try std.testing.expect(session_request.resume_ref.eql(static_request.resume_ref));
    try std.testing.expect(session_request.result_ref.eql(static_request.result_ref));
    try std.testing.expectEqualStrings(try session_request.payload([]const u8), try static_request.payload([]const u8));

    try session.@"resume"(session_request, @as(i32, 41));
    try OneEffectMachine.@"resume"(state, static_request, @as(i32, 41));
    var session_result = switch (try session.next()) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer session_result.deinit();
    var static_result = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer static_result.deinit();
    try std.testing.expectEqual(session_result.value, static_result.value());
}

test "StaticMachine fuel yield is explicit and non-mutating" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);
    const before = try OneEffectMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);

    var fuel: u64 = 0;
    switch (try OneEffectMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const after = try OneEffectMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "StaticMachine resumes from partial deterministic fuel" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);

    var yield_count: usize = 0;
    var request: ?OneEffectMachine.Request = null;
    for (0..8) |_| {
        var fuel: u64 = 1;
        switch (try OneEffectMachine.reduce(state, &fuel)) {
            .yielded_fuel => {
                yield_count += 1;
                const encoded = try OneEffectMachine.encodeState(std.testing.allocator, state);
                std.testing.allocator.free(encoded);
            },
            .request => |parked| {
                request = parked;
                break;
            },
            else => return error.UnexpectedTransition,
        }
    }
    try std.testing.expect(yield_count != 0);
    try std.testing.expect(request != null);
    try std.testing.expectEqualStrings("payload", try request.?.payload([]const u8));
}

test "StaticMachine rejects malformed, stale, and duplicate responses" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);
    var fuel: u64 = 100;
    const original = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(state, original, @as(bool, true)),
    );

    const encoded = try OneEffectMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try OneEffectMachine.decodeState(std.testing.allocator, encoded);
    defer OneEffectMachine.deinitState(restored);
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, original, @as(i32, 41)),
    );
    const current = switch (try OneEffectMachine.current(restored)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try OneEffectMachine.@"resume"(restored, current, @as(i32, 41));
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, current, @as(i32, 41)),
    );
}

test "StaticMachine state codec rejects changed and trailing bytes" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);
    var fuel: u64 = 100;
    _ = try OneEffectMachine.reduce(state, &fuel);
    const encoded = try OneEffectMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const changed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(changed);
    changed[0] ^= 1;
    try std.testing.expectError(error.ProgramContractViolation, OneEffectMachine.decodeState(std.testing.allocator, changed));

    const trailing = try std.testing.allocator.alloc(u8, encoded.len + 1);
    defer std.testing.allocator.free(trailing);
    @memcpy(trailing[0..encoded.len], encoded);
    trailing[encoded.len] = 0;
    try std.testing.expectError(error.ProgramContractViolation, OneEffectMachine.decodeState(std.testing.allocator, trailing));
}

test "StaticMachine owns accepted response bytes" {
    const state = try StringMachine.initialState(std.testing.allocator, .{});
    defer StringMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try StringMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };

    const response = try std.testing.allocator.dupe(u8, "owned response");
    try StringMachine.@"resume"(state, request, @as([]const u8, response));
    @memset(response, 'x');
    std.testing.allocator.free(response);

    var result = switch (try StringMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("owned response", result.value());
}

test "StaticMachine authored budget failure is terminal and never a fuel yield" {
    const state = try AuthoredBudgetMachine.initialState(std.testing.allocator, .{});
    defer AuthoredBudgetMachine.deinitState(state);
    var fuel: u64 = 100;
    try std.testing.expectError(error.ExecutionBudgetExceeded, AuthoredBudgetMachine.reduce(state, &fuel));
    try std.testing.expectError(error.ExecutionBudgetExceeded, AuthoredBudgetMachine.reduce(state, &fuel));
    try std.testing.expectError(
        error.ProgramContractViolation,
        AuthoredBudgetMachine.encodeState(std.testing.allocator, state),
    );
}

test "StaticMachine state surface does not expose the session core" {
    const storage_field = @typeInfo(OneEffectMachine.State).@"struct".fields[0];
    const StateStorage = @typeInfo(storage_field.type).pointer.child;
    try std.testing.expect(@typeInfo(StateStorage) == .@"opaque");
    try std.testing.expect(!@hasDecl(StateStorage, "next"));
    try std.testing.expect(!@hasDecl(StateStorage, "nextWithFuel"));
    try std.testing.expect(!@hasDecl(StateStorage, "encodeState"));
    try std.testing.expect(!@hasDecl(StateStorage, "decodeState"));
}

test "StaticMachine enforces the state byte limit during encoding" {
    const state = try TinyStateMachine.initialState(std.testing.allocator, .{});
    defer TinyStateMachine.deinitState(state);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TinyStateMachine.encodeState(std.testing.allocator, state),
    );
}

test "StaticMachine canonical state ignores equal-value alias topology" {
    comptime {
        if (PairArgsMachine.InitialArgs != struct { []const u8, []const u8 }) {
            @compileError("StaticMachine InitialArgs must derive from Program entry parameters");
        }
    }

    const shared = "same";
    const shared_state = try PairArgsMachine.initialState(std.testing.allocator, .{ shared, shared });
    defer PairArgsMachine.deinitState(shared_state);

    const first = try std.testing.allocator.dupe(u8, "same");
    defer std.testing.allocator.free(first);
    const second = try std.testing.allocator.dupe(u8, "same");
    defer std.testing.allocator.free(second);
    const separate_state = try PairArgsMachine.initialState(std.testing.allocator, .{ first, second });
    defer PairArgsMachine.deinitState(separate_state);

    const shared_bytes = try PairArgsMachine.encodeState(std.testing.allocator, shared_state);
    defer std.testing.allocator.free(shared_bytes);
    const separate_bytes = try PairArgsMachine.encodeState(std.testing.allocator, separate_state);
    defer std.testing.allocator.free(separate_bytes);
    try std.testing.expectEqualSlices(u8, shared_bytes, separate_bytes);
}

test "StaticMachine validates and restores a resumed after checkpoint" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.@"resume"(state, request, @as(i32, 10));
    const after = switch (try AfterMachine.reduce(state, &fuel)) {
        .after => |value| value,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.resumeAfter(state, after, @as(i32, 15));

    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try AfterMachine.decodeState(std.testing.allocator, encoded);
    defer AfterMachine.deinitState(restored);
    var result = switch (try AfterMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 15), result.value());
}

test "StaticMachine accepts and round trips a zero-instruction program" {
    const state = try ZeroMachine.initialState(std.testing.allocator, .{});
    defer ZeroMachine.deinitState(state);
    const encoded = try ZeroMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try ZeroMachine.decodeState(std.testing.allocator, encoded);
    defer ZeroMachine.deinitState(restored);
    var fuel: u64 = 10;
    var result = switch (try ZeroMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual({}, result.value());
}

test "StaticMachine state binds the complete nested target contract" {
    try std.testing.expect(NestedFirstMachine.Manifest.machine_contract_fingerprint != NestedSecondMachine.Manifest.machine_contract_fingerprint);
    const state = try NestedFirstMachine.initialState(std.testing.allocator, .{});
    defer NestedFirstMachine.deinitState(state);
    const encoded = try NestedFirstMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        NestedSecondMachine.decodeState(std.testing.allocator, encoded),
    );
}

test "StaticMachine exposes a closed authored failure surface" {
    comptime {
        if (AuthoredBudgetMachine.Failure != error{ExecutionBudgetExceeded}) {
            @compileError("StaticMachine Failure must contain only Body.Error");
        }
        if (AuthoredBudgetMachine.Error != error{
            ExecutionBudgetExceeded,
            OutOfMemory,
            ProgramContractViolation,
        }) {
            @compileError("StaticMachine Error must be a closed machine operation error set");
        }
    }
}

test "StaticMachine canonical identity ignores provenance-only ProgramPlan fields" {
    const SiteA = ProvenanceMachineA.EffectRow.operationSite("test", "decide", 0);
    const SiteB = ProvenanceMachineB.EffectRow.operationSite("test", "decide", 0);
    const LegacySiteA = ProvenanceProgramA.protocol.operationSite("test", "decide", 0);
    const LegacySiteB = ProvenanceProgramB.protocol.operationSite("test", "decide", 0);
    try std.testing.expectEqual(
        ProvenanceMachineA.Manifest.canonical_plan_fingerprint,
        ProvenanceMachineB.Manifest.canonical_plan_fingerprint,
    );
    try std.testing.expectEqual(
        ProvenanceMachineA.Manifest.machine_contract_fingerprint,
        ProvenanceMachineB.Manifest.machine_contract_fingerprint,
    );
    try std.testing.expectEqual(ProvenanceMachineA.Manifest.canonical_plan_fingerprint, ProvenanceMachineA.Manifest.plan_hash);
    try std.testing.expectEqual(ProvenanceMachineA.Manifest.plan_hash, ProvenanceMachineA.EffectRow.hash);
    try std.testing.expect(ProvenanceMachineA.Manifest.legacy_plan_hash != ProvenanceMachineB.Manifest.legacy_plan_hash);
    try std.testing.expectEqual(ProvenanceMachineA.Manifest.legacy_plan_hash, ProvenanceProgramA.protocol.hash);
    try std.testing.expectEqual(LegacySiteA.fingerprint, SiteA.legacy_fingerprint);
    try std.testing.expectEqual(LegacySiteB.fingerprint, SiteB.legacy_fingerprint);
    try std.testing.expect(SiteA.legacy_fingerprint != SiteB.legacy_fingerprint);
    try std.testing.expectEqual(SiteA.fingerprint, SiteA.canonical_fingerprint);
    try std.testing.expectEqual(SiteA.fingerprint, SiteB.fingerprint);

    const state_a = try ProvenanceMachineA.initialState(std.testing.allocator, .{});
    defer ProvenanceMachineA.deinitState(state_a);
    const state_b = try ProvenanceMachineB.initialState(std.testing.allocator, .{});
    defer ProvenanceMachineB.deinitState(state_b);
    var fuel_a: u64 = 100;
    var fuel_b: u64 = 100;
    const request_a = switch (try ProvenanceMachineA.reduce(state_a, &fuel_a)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const request_b = switch (try ProvenanceMachineB.reduce(state_b, &fuel_b)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(SiteA.fingerprint, request_a.operation_site_fingerprint);
    try std.testing.expectEqual(SiteB.fingerprint, request_b.operation_site_fingerprint);
    try std.testing.expectEqual(request_a.operation_site_fingerprint, request_b.operation_site_fingerprint);
    try std.testing.expectEqual(
        request_a.canonical_operation_site_fingerprint,
        request_b.canonical_operation_site_fingerprint,
    );
    try std.testing.expectEqual(request_a.fingerprint(), request_b.fingerprint());

    const encoded_a = try ProvenanceMachineA.encodeState(std.testing.allocator, state_a);
    defer std.testing.allocator.free(encoded_a);
    const encoded_b = try ProvenanceMachineB.encodeState(std.testing.allocator, state_b);
    defer std.testing.allocator.free(encoded_b);
    try std.testing.expectEqualSlices(u8, encoded_a, encoded_b);

    const restored = try ProvenanceMachineB.decodeState(std.testing.allocator, encoded_a);
    defer ProvenanceMachineB.deinitState(restored);
    const restored_request = switch (try ProvenanceMachineB.current(restored)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try restored_request.expectSite(ProvenanceMachineB.EffectRow.operationSite("test", "decide", 0));
}

test "StaticMachine complete contract identity binds the program label" {
    try std.testing.expectEqual(
        RelabeledMachineA.Manifest.canonical_plan_fingerprint,
        RelabeledMachineB.Manifest.canonical_plan_fingerprint,
    );
    try std.testing.expect(
        RelabeledMachineA.Manifest.machine_contract_fingerprint !=
            RelabeledMachineB.Manifest.machine_contract_fingerprint,
    );

    const state = try RelabeledMachineA.initialState(std.testing.allocator, .{});
    defer RelabeledMachineA.deinitState(state);
    const encoded = try RelabeledMachineA.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        RelabeledMachineB.decodeState(std.testing.allocator, encoded),
    );
}

test "StaticMachine after descriptors and requests share canonical primary identity" {
    const OperationSiteA = AfterProvenanceMachineA.EffectRow.operationSite("test", "after", 0);
    const OperationSiteB = AfterProvenanceMachineB.EffectRow.operationSite("test", "after", 0);
    const AfterSiteA = AfterProvenanceMachineA.EffectRow.afterSite("test", "after", 0);
    const AfterSiteB = AfterProvenanceMachineB.EffectRow.afterSite("test", "after", 0);
    const LegacyAfterSiteA = AfterProvenanceProgramA.protocol.afterSite("test", "after", 0);
    const LegacyAfterSiteB = AfterProvenanceProgramB.protocol.afterSite("test", "after", 0);

    try std.testing.expectEqual(OperationSiteA.fingerprint, OperationSiteB.fingerprint);
    try std.testing.expectEqual(AfterSiteA.fingerprint, AfterSiteB.fingerprint);
    try std.testing.expectEqual(OperationSiteA.fingerprint, AfterSiteA.source_operation_site_fingerprint);
    try std.testing.expectEqual(OperationSiteB.fingerprint, AfterSiteB.source_operation_site_fingerprint);
    try std.testing.expectEqual(AfterSiteA.fingerprint, AfterSiteA.canonical_fingerprint);
    try std.testing.expectEqual(AfterSiteA.source_operation_site_fingerprint, AfterSiteA.source_operation_site_canonical_fingerprint);
    try std.testing.expectEqual(LegacyAfterSiteA.fingerprint, AfterSiteA.legacy_fingerprint);
    try std.testing.expectEqual(LegacyAfterSiteB.fingerprint, AfterSiteB.legacy_fingerprint);
    try std.testing.expectEqual(
        LegacyAfterSiteA.source_operation_site_fingerprint,
        AfterSiteA.source_operation_site_legacy_fingerprint,
    );
    try std.testing.expect(AfterSiteA.legacy_fingerprint != AfterSiteB.legacy_fingerprint);

    const state_a = try AfterProvenanceMachineA.initialState(std.testing.allocator, .{});
    defer AfterProvenanceMachineA.deinitState(state_a);
    const state_b = try AfterProvenanceMachineB.initialState(std.testing.allocator, .{});
    defer AfterProvenanceMachineB.deinitState(state_b);
    var fuel_a: u64 = 100;
    var fuel_b: u64 = 100;
    const request_a = switch (try AfterProvenanceMachineA.reduce(state_a, &fuel_a)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const request_b = switch (try AfterProvenanceMachineB.reduce(state_b, &fuel_b)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(OperationSiteA.fingerprint, request_a.operation_site_fingerprint);
    try std.testing.expectEqual(OperationSiteB.fingerprint, request_b.operation_site_fingerprint);
    try AfterProvenanceMachineA.@"resume"(state_a, request_a, @as(i32, 10));
    try AfterProvenanceMachineB.@"resume"(state_b, request_b, @as(i32, 10));
    const after_a = switch (try AfterProvenanceMachineA.reduce(state_a, &fuel_a)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    const after_b = switch (try AfterProvenanceMachineB.reduce(state_b, &fuel_b)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(AfterSiteA.fingerprint, after_a.after_site_fingerprint);
    try std.testing.expectEqual(AfterSiteB.fingerprint, after_b.after_site_fingerprint);
    try std.testing.expectEqual(AfterSiteA.source_operation_site_fingerprint, after_a.source_operation_site_fingerprint);
    try std.testing.expectEqual(AfterSiteB.source_operation_site_fingerprint, after_b.source_operation_site_fingerprint);
}

test "StaticMachine contract binds handler-derived after protocol refs" {
    try std.testing.expect(
        AfterContractMachineA.Manifest.machine_contract_fingerprint !=
            AfterContractMachineB.Manifest.machine_contract_fingerprint,
    );
    try std.testing.expect(
        AfterContractMachineA.EffectRow.afterSite("inner", "inner", 0).Output !=
            AfterContractMachineB.EffectRow.afterSite("inner", "inner", 0).Output,
    );

    const state_b = try AfterContractMachineB.initialState(std.testing.allocator, .{});
    defer AfterContractMachineB.deinitState(state_b);
    var fuel_b: u64 = 100;
    const outer_b = switch (try AfterContractMachineB.reduce(state_b, &fuel_b)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };

    const state = try AfterContractMachineA.initialState(std.testing.allocator, .{});
    defer AfterContractMachineA.deinitState(state);
    var fuel: u64 = 100;
    const outer = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(
        outer.canonical_operation_site_fingerprint,
        outer_b.canonical_operation_site_fingerprint,
    );
    try std.testing.expect(outer.fingerprint() != outer_b.fingerprint());
    try std.testing.expectEqual(AfterContractMachineA.Manifest.machine_contract_fingerprint, outer.trace().plan_hash);
    try std.testing.expectEqual(AfterContractMachineB.Manifest.machine_contract_fingerprint, outer_b.trace().plan_hash);
    try std.testing.expectEqual(AfterContractMachineA.Manifest.request_trace_plan_hash, outer.trace().plan_hash);
    try std.testing.expectEqual(AfterContractMachineB.Manifest.request_trace_plan_hash, outer_b.trace().plan_hash);
    try AfterContractMachineA.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AfterContractMachineA.@"resume"(state, inner, @as(i32, 7));
    const inner_after = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(@as(u64, 6920645909099374944), inner_after.fingerprint());

    const encoded = try AfterContractMachineA.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterContractMachineB.decodeState(std.testing.allocator, encoded),
    );

    const restored = try AfterContractMachineA.decodeState(std.testing.allocator, encoded);
    defer AfterContractMachineA.deinitState(restored);
    const restored_inner_after = switch (try AfterContractMachineA.current(restored)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(inner_after.fingerprint(), restored_inner_after.fingerprint());
    try AfterContractMachineA.resumeAfter(restored, restored_inner_after, true);
    const outer_after = switch (try AfterContractMachineA.reduce(restored, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(true, try outer_after.value(bool));
    try AfterContractMachineA.resumeAfter(restored, outer_after, @as([]const u8, "true"));
    var result = switch (try AfterContractMachineA.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("true", result.value());
}

test "StaticMachine preserves a handlerless dynamic outer after contract" {
    const state = try HandlerlessOuterMachine.initialState(std.testing.allocator, .{});
    defer HandlerlessOuterMachine.deinitState(state);
    var fuel: u64 = 100;

    const outer = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try HandlerlessOuterMachine.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try HandlerlessOuterMachine.@"resume"(state, inner, @as(i32, 7));
    const inner_after = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try HandlerlessOuterMachine.resumeAfter(state, inner_after, true);

    const outer_after = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    const OuterSite = HandlerlessOuterMachine.EffectRow.afterSite("outer", "outer", 0);
    try std.testing.expect(!OuterSite.has_static_input_ref);
    try std.testing.expect(outer_after.output_ref.eql(OuterSite.output_ref));
    try std.testing.expectEqual(true, try outer_after.value(bool));
    try HandlerlessOuterMachine.resumeAfter(state, outer_after, @as([]const u8, "outer:true"));

    var result = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("outer:true", result.value());
}

test "StaticMachine after closure does not traverse a terminal abort edge" {
    const state = try AbortDelimitedAfterMachine.initialState(std.testing.allocator, .{@as(i32, 0)});
    defer AbortDelimitedAfterMachine.deinitState(state);
    var fuel: u64 = 100;

    const outer = switch (try AbortDelimitedAfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AbortDelimitedAfterMachine.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try AbortDelimitedAfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AbortDelimitedAfterMachine.@"resume"(state, inner, @as(i32, 7));
    const inner_after = switch (try AbortDelimitedAfterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try AbortDelimitedAfterMachine.resumeAfter(state, inner_after, true);
    const outer_after = switch (try AbortDelimitedAfterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try AbortDelimitedAfterMachine.resumeAfter(state, outer_after, @as([]const u8, "true"));
    var result = switch (try AbortDelimitedAfterMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("true", result.value());
}

fn hashLengthPrefixedBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    var length_bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u64, &length_bytes, bytes.len, .little);
    hasher.update(&length_bytes);
    hasher.update(bytes);
}

fn stateImageChecksum(payload: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashLengthPrefixedBytes(&hasher, "boundary.static-machine.state.image");
    var version = [_]u8{0} ** 4;
    std.mem.writeInt(u32, &version, 1, .little);
    hasher.update(&version);
    hashLengthPrefixedBytes(&hasher, payload);
    return hasher.final();
}

fn stateCoreOffset(bytes: []const u8) !usize {
    var index: usize = 8 + 4 + 4;
    const program_length = std.mem.readInt(u64, bytes[index..][0..8], .little);
    index += 8 + (std.math.cast(usize, program_length) orelse return error.BadLength);
    const plan_length = std.mem.readInt(u64, bytes[index..][0..8], .little);
    index += 8 + (std.math.cast(usize, plan_length) orelse return error.BadLength);
    index += 8;
    return index;
}

fn refreshStateChecksum(bytes: []u8) void {
    std.mem.writeInt(
        u64,
        bytes[bytes.len - 8 ..][0..8],
        stateImageChecksum(bytes[0 .. bytes.len - 8]),
        .little,
    );
}

fn singleFrameOffset(payload: []const u8, expected_after_count: usize) !usize {
    const core_offset = try stateCoreOffset(payload);
    const after_count_offset = core_offset + 8 + 8 + 1;
    if (after_count_offset + 8 > payload.len) return error.BadLength;
    try std.testing.expectEqual(
        @as(u64, @intCast(expected_after_count)),
        std.mem.readInt(u64, payload[after_count_offset..][0..8], .little),
    );
    const frame_count_offset = after_count_offset + 8 + expected_after_count * 6;
    if (frame_count_offset + 8 > payload.len) return error.BadLength;
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, payload[frame_count_offset..][0..8], .little));
    return frame_count_offset + 8;
}

fn insertSingleAfterEntry(encoded: []const u8, entry: [6]u8) ![]u8 {
    const old_payload = encoded[0 .. encoded.len - 8];
    const core_offset = try stateCoreOffset(old_payload);
    const after_count_offset = core_offset + 8 + 8 + 1;
    const insertion_offset = after_count_offset + 8;
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, old_payload[after_count_offset..][0..8], .little));

    const forged = try std.testing.allocator.alloc(u8, encoded.len + entry.len);
    @memcpy(forged[0..insertion_offset], old_payload[0..insertion_offset]);
    std.mem.writeInt(u64, forged[after_count_offset..][0..8], 1, .little);
    @memcpy(forged[insertion_offset..][0..entry.len], &entry);
    @memcpy(forged[insertion_offset + entry.len .. forged.len - 8], old_payload[insertion_offset..]);
    refreshStateChecksum(forged);
    return forged;
}

fn afterContractPendingOffset(payload: []const u8, expected_after_count: usize) !usize {
    const core_offset = try stateCoreOffset(payload);
    const after_count_offset = core_offset + 8 + 8 + 1;
    if (after_count_offset + 8 > payload.len) return error.BadLength;
    try std.testing.expectEqual(
        @as(u64, @intCast(expected_after_count)),
        std.mem.readInt(u64, payload[after_count_offset..][0..8], .little),
    );
    const frame_count_offset = after_count_offset + 8 + expected_after_count * 6;
    if (frame_count_offset + 8 > payload.len) return error.BadLength;
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, payload[frame_count_offset..][0..8], .little));
    const frame_offset = frame_count_offset + 8;
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    if (locals_count_offset + 8 > payload.len) return error.BadLength;
    try std.testing.expectEqual(@as(u8, 0), payload[frame_offset + 49]);
    try std.testing.expectEqual(@as(u64, 2), std.mem.readInt(u64, payload[locals_count_offset..][0..8], .little));
    const locals_offset = locals_count_offset + 8;
    const encoded_i32_local_size = 2 + 1 + 4;
    const frame_last_return_size = 1 + 4;
    const pending_offset = locals_offset + 2 * encoded_i32_local_size + frame_last_return_size;
    if (pending_offset + 2 > payload.len) return error.BadLength;
    try std.testing.expectEqual(@as(u8, 1), payload[pending_offset]);
    try std.testing.expectEqual(@as(u8, 1), payload[pending_offset + 1]);
    return pending_offset;
}

test "StaticMachine rejects a globally valid but control-unreachable after stack" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const old_payload = encoded[0 .. encoded.len - 8];
    const core_offset = try stateCoreOffset(old_payload);
    const after_length_offset = core_offset + 8 + 8 + 1;
    const insertion_offset = after_length_offset + 8;
    const forged = try std.testing.allocator.alloc(u8, encoded.len + 6);
    defer std.testing.allocator.free(forged);
    @memcpy(forged[0..insertion_offset], old_payload[0..insertion_offset]);
    std.mem.writeInt(u64, forged[after_length_offset..][0..8], 1, .little);
    @memset(forged[insertion_offset..][0..6], 0);
    @memcpy(forged[insertion_offset + 6 .. forged.len - 8], old_payload[insertion_offset..]);
    std.mem.writeInt(
        u64,
        forged[forged.len - 8 ..][0..8],
        stateImageChecksum(forged[0 .. forged.len - 8]),
        .little,
    );

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects an unowned root after-stack prefix" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try insertSingleAfterEntry(encoded, .{ 0, 0, 0, 0, 0, 0 });
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 1);
    std.mem.writeInt(u64, forged[frame_offset + 5 * 8 ..][0..8], 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a pending operation whose after entry is already recorded" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    _ = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try insertSingleAfterEntry(encoded, .{ 0, 0, 0, 0, 0, 0 });
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a cursor after a non-completing helper call" {
    const state = try NonCompletingHelperMachine.initialState(std.testing.allocator, .{});
    defer NonCompletingHelperMachine.deinitState(state);
    const encoded = try NonCompletingHelperMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const core_offset = try stateCoreOffset(forged[0 .. forged.len - 8]);
    const after_count_offset = core_offset + 8 + 8 + 1;
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, forged[after_count_offset..][0..8], .little));
    const frame_offset = after_count_offset + 8 + 8;
    const instruction_index_offset = frame_offset + 2 * 8;
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, forged[instruction_index_offset..][0..8], .little));
    std.mem.writeInt(u64, forged[instruction_index_offset..][0..8], 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        NonCompletingHelperMachine.decodeState(std.testing.allocator, forged),
    );
}

fn expectActiveNonCompletingChildRoundTrip(comptime Machine: type) !void {
    const state = try Machine.initialState(std.testing.allocator, .{});
    defer Machine.deinitState(state);
    var fuel: u64 = 1;
    switch (try Machine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    try Machine.validateState(state);

    const encoded = try Machine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try Machine.decodeState(std.testing.allocator, encoded);
    defer Machine.deinitState(restored);
    try Machine.validateState(restored);
}

test "StaticMachine round trips an active non-completing helper child" {
    try expectActiveNonCompletingChildRoundTrip(NonCompletingHelperMachine);
}

test "StaticMachine round trips an active non-completing nested child" {
    try expectActiveNonCompletingChildRoundTrip(NonCompletingNestedMachine);
}

test "StaticMachine rejects a fabricated zero-depth unwind before return" {
    const state = try PureMachine.initialState(std.testing.allocator, .{});
    defer PureMachine.deinitState(state);
    const encoded = try PureMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const old_payload = encoded[0 .. encoded.len - 8];
    try std.testing.expectEqual(@as(u8, 0), old_payload[old_payload.len - 1]);
    const forged = try std.testing.allocator.alloc(u8, encoded.len + 24);
    defer std.testing.allocator.free(forged);
    @memcpy(forged[0..old_payload.len], old_payload);
    forged[old_payload.len - 1] = 1;

    var cursor = old_payload.len;
    std.mem.writeInt(u64, forged[cursor..][0..8], 0, .little);
    cursor += 8;
    forged[cursor] = @intFromEnum(boundary.ir.ValueCodec.i32);
    forged[cursor + 1] = 0;
    cursor += 2;
    std.mem.writeInt(i32, forged[cursor..][0..4], 99, .little);
    cursor += 4;
    forged[cursor] = @intFromEnum(boundary.ir.ValueCodec.i32);
    forged[cursor + 1] = 0;
    cursor += 2;
    std.mem.writeInt(u64, forged[cursor..][0..8], 0, .little);
    cursor += 8;
    try std.testing.expectEqual(forged.len - 8, cursor);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        PureMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a positive-depth unwind before return" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.@"resume"(state, request, @as(i32, 7));
    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const old_payload = encoded[0 .. encoded.len - 8];
    try std.testing.expectEqual(@as(u8, 0), old_payload[old_payload.len - 1]);
    const forged = try std.testing.allocator.alloc(u8, encoded.len + 24);
    defer std.testing.allocator.free(forged);
    @memcpy(forged[0..old_payload.len], old_payload);
    forged[old_payload.len - 1] = 1;

    var cursor = old_payload.len;
    std.mem.writeInt(u64, forged[cursor..][0..8], 0, .little);
    cursor += 8;
    forged[cursor] = @intFromEnum(boundary.ir.ValueCodec.i32);
    forged[cursor + 1] = 0;
    cursor += 2;
    std.mem.writeInt(i32, forged[cursor..][0..4], 7, .little);
    cursor += 4;
    forged[cursor] = @intFromEnum(boundary.ir.ValueCodec.i32);
    forged[cursor + 1] = 0;
    cursor += 2;
    std.mem.writeInt(u64, forged[cursor..][0..8], 1, .little);
    cursor += 8;
    try std.testing.expectEqual(forged.len - 8, cursor);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a last-return cache that differs from its source local" {
    const state = try PureMachine.initialState(std.testing.allocator, .{});
    defer PureMachine.deinitState(state);
    var fuel: u64 = 2;
    switch (try PureMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try PureMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, forged[locals_count_offset..][0..8], .little));
    const last_return_offset = locals_count_offset + 8 + 2 + 1 + 4;
    try std.testing.expectEqual(@as(u8, 1), forged[last_return_offset]);
    try std.testing.expectEqual(@as(i32, 7), std.mem.readInt(i32, forged[last_return_offset + 1 ..][0..4], .little));
    std.mem.writeInt(i32, forged[last_return_offset + 1 ..][0..4], 8, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        PureMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a last-condition cache that differs from its source local" {
    const state = try BranchCacheMachine.initialState(std.testing.allocator, .{@as(i32, 0)});
    defer BranchCacheMachine.deinitState(state);
    var fuel: u64 = 1;
    switch (try BranchCacheMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try BranchCacheMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const last_condition_offset = frame_offset + 6 * 8;
    try std.testing.expectEqual(@as(u8, 1), forged[last_condition_offset]);
    forged[last_condition_offset] = 0;
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        BranchCacheMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects divergent pending and unwind after values" {
    const state = try AfterContractMachineA.initialState(std.testing.allocator, .{});
    defer AfterContractMachineA.deinitState(state);
    var fuel: u64 = 100;
    const outer = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AfterContractMachineA.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AfterContractMachineA.@"resume"(state, inner, @as(i32, 7));
    _ = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };

    const encoded = try AfterContractMachineA.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    const pending_offset = try afterContractPendingOffset(forged[0 .. forged.len - 8], 2);
    const pending_value_offset = pending_offset + 55;
    const unwind_value_offset = pending_offset + 91;
    try std.testing.expectEqual(@as(i32, 7), std.mem.readInt(i32, forged[pending_value_offset..][0..4], .little));
    try std.testing.expectEqual(@as(i32, 7), std.mem.readInt(i32, forged[unwind_value_offset..][0..4], .little));
    std.mem.writeInt(i32, forged[unwind_value_offset..][0..4], 8, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterContractMachineA.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects an unwind ref not produced by the consumed after suffix" {
    const state = try HandlerlessOuterMachine.initialState(std.testing.allocator, .{});
    defer HandlerlessOuterMachine.deinitState(state);
    var fuel: u64 = 100;
    const outer = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try HandlerlessOuterMachine.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try HandlerlessOuterMachine.@"resume"(state, inner, @as(i32, 7));
    const inner_after = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    const forged_i32_fingerprint = inner_after.trace().current_value_fingerprint;
    try HandlerlessOuterMachine.resumeAfter(state, inner_after, true);
    _ = switch (try HandlerlessOuterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };

    const encoded = try HandlerlessOuterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const old_payload = encoded[0 .. encoded.len - 8];
    const pending_offset = try afterContractPendingOffset(old_payload, 2);
    const forged = try std.testing.allocator.alloc(u8, encoded.len + 6);
    defer std.testing.allocator.free(forged);

    var old_cursor = pending_offset + 52;
    var new_cursor = old_cursor;
    @memcpy(forged[0..old_cursor], old_payload[0..old_cursor]);
    forged[new_cursor] = @intFromEnum(boundary.ir.ValueCodec.i32);
    forged[new_cursor + 1] = 0;
    new_cursor += 2;
    old_cursor += 2;
    try std.testing.expectEqual(@as(u8, 0), old_payload[old_cursor]);
    forged[new_cursor] = 0;
    new_cursor += 1;
    old_cursor += 1;
    try std.testing.expectEqual(@as(u8, 1), old_payload[old_cursor]);
    std.mem.writeInt(i32, forged[new_cursor..][0..4], 7, .little);
    new_cursor += 4;
    old_cursor += 1;
    std.mem.writeInt(u64, forged[new_cursor..][0..8], forged_i32_fingerprint, .little);
    new_cursor += 8;
    old_cursor += 8;

    const unwind_current_ref_offset = pending_offset + 85;
    @memcpy(
        forged[new_cursor..][0 .. unwind_current_ref_offset - old_cursor],
        old_payload[old_cursor..unwind_current_ref_offset],
    );
    new_cursor += unwind_current_ref_offset - old_cursor;
    old_cursor = unwind_current_ref_offset;
    forged[new_cursor] = @intFromEnum(boundary.ir.ValueCodec.i32);
    forged[new_cursor + 1] = 0;
    new_cursor += 2;
    old_cursor += 2;
    try std.testing.expectEqual(@as(u8, 0), old_payload[old_cursor]);
    forged[new_cursor] = 0;
    new_cursor += 1;
    old_cursor += 1;
    try std.testing.expectEqual(@as(u8, 1), old_payload[old_cursor]);
    std.mem.writeInt(i32, forged[new_cursor..][0..4], 7, .little);
    new_cursor += 4;
    old_cursor += 1;
    @memcpy(forged[new_cursor .. forged.len - 8], old_payload[old_cursor..]);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        HandlerlessOuterMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine validates the final after handler input contract" {
    const state = try AfterContractMachineA.initialState(std.testing.allocator, .{});
    defer AfterContractMachineA.deinitState(state);
    var fuel: u64 = 100;
    const outer = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AfterContractMachineA.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try AfterContractMachineA.@"resume"(state, inner, @as(i32, 7));
    const inner_after = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try AfterContractMachineA.resumeAfter(state, inner_after, true);
    _ = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };

    const encoded = try AfterContractMachineA.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const old_payload = encoded[0 .. encoded.len - 8];
    const core_offset = try stateCoreOffset(old_payload);
    const after_count_offset = core_offset + 8 + 8 + 1;
    const entries_offset = after_count_offset + 8;
    try std.testing.expectEqual(@as(u64, 2), std.mem.readInt(u64, old_payload[after_count_offset..][0..8], .little));

    const forged = try std.testing.allocator.alloc(u8, encoded.len - 6);
    defer std.testing.allocator.free(forged);
    @memcpy(forged[0..entries_offset], old_payload[0..entries_offset]);
    std.mem.writeInt(u64, forged[after_count_offset..][0..8], 1, .little);
    @memcpy(forged[entries_offset..][0..6], old_payload[entries_offset + 6 ..][0..6]);
    @memcpy(
        forged[entries_offset + 6 .. forged.len - 8],
        old_payload[entries_offset + 12 ..],
    );

    const pending_offset = try afterContractPendingOffset(forged[0 .. forged.len - 8], 1);
    std.mem.writeInt(u64, forged[pending_offset + 18 ..][0..8], 1, .little);
    std.mem.writeInt(u16, forged[pending_offset + 26 ..][0..2], 1, .little);
    std.mem.writeInt(u64, forged[pending_offset + 28 ..][0..8], 1, .little);
    std.mem.writeInt(u64, forged[pending_offset + 36 ..][0..8], 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterContractMachineA.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine cumulative budget exhaustion is terminal" {
    const state = try LoopMachine.initialState(std.testing.allocator, .{});
    defer LoopMachine.deinitState(state);
    var fuel: u64 = std.math.maxInt(u64);
    try std.testing.expectError(error.ExecutionBudgetExceeded, LoopMachine.reduce(state, &fuel));
    try std.testing.expectError(error.ExecutionBudgetExceeded, LoopMachine.reduce(state, &fuel));
    try std.testing.expectError(error.ProgramContractViolation, LoopMachine.validateState(state));
    try std.testing.expectError(
        error.ProgramContractViolation,
        LoopMachine.encodeState(std.testing.allocator, state),
    );
}

test "StaticMachine post-dispatch reduction failures are terminal" {
    const state = try OverflowMachine.initialState(std.testing.allocator, .{@as(i32, std.math.maxInt(i32))});
    defer OverflowMachine.deinitState(state);
    var fuel: u64 = 100;
    try std.testing.expectError(error.ProgramContractViolation, OverflowMachine.reduce(state, &fuel));
    try std.testing.expectError(error.ProgramContractViolation, OverflowMachine.reduce(state, &fuel));
    try std.testing.expectError(error.ProgramContractViolation, OverflowMachine.validateState(state));
    try std.testing.expectError(
        error.ProgramContractViolation,
        OverflowMachine.encodeState(std.testing.allocator, state),
    );
}

const OwnedAllocationDelta = struct {
    bytes: usize,
    allocations: usize,
};

fn stringListResumeOwnedDelta() !OwnedAllocationDelta {
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const state = try StringListMachine.initialState(counting.allocator(), .{});
    defer StringListMachine.deinitState(state);
    var fuel: u64 = 100;
    const parked = switch (try StringListMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    const outstanding_bytes_before = counting.allocated_bytes - counting.freed_bytes;
    const outstanding_allocations_before = counting.allocations - counting.deallocations;
    try StringListMachine.@"resume"(state, parked, @as([]const []const u8, &.{ "alpha", "beta" }));
    return .{
        .bytes = counting.allocated_bytes - counting.freed_bytes - outstanding_bytes_before,
        .allocations = counting.allocations - counting.deallocations - outstanding_allocations_before,
    };
}

fn stringListResumeOutcome(fail_index: usize, expected_delta: OwnedAllocationDelta) !?bool {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
    const state = StringListMachine.initialState(failing.allocator(), .{}) catch |err| switch (err) {
        error.OutOfMemory => return null,
        else => return err,
    };
    defer StringListMachine.deinitState(state);
    var fuel: u64 = 100;
    const transition = StringListMachine.reduce(state, &fuel) catch |err| switch (err) {
        error.OutOfMemory => return null,
        else => return err,
    };
    const parked = switch (transition) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    const before = try StringListMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    const outstanding_bytes_before = failing.allocated_bytes - failing.freed_bytes;
    const outstanding_allocations_before = failing.allocations - failing.deallocations;
    StringListMachine.@"resume"(state, parked, @as([]const []const u8, &.{ "alpha", "beta" })) catch |err| switch (err) {
        error.OutOfMemory => {
            try std.testing.expect(failing.has_induced_failure);
            try StringListMachine.validateState(state);
            const current = switch (try StringListMachine.current(state)) {
                .request => |value| value,
                else => return error.UnexpectedTransition,
            };
            try std.testing.expectEqual(parked.fingerprint(), current.fingerprint());
            const after = try StringListMachine.encodeState(std.testing.allocator, state);
            defer std.testing.allocator.free(after);
            try std.testing.expectEqualSlices(u8, before, after);
            failing.fail_index = std.math.maxInt(usize);
            try StringListMachine.@"resume"(state, parked, @as([]const []const u8, &.{ "alpha", "beta" }));
            try std.testing.expectEqual(
                expected_delta.bytes,
                failing.allocated_bytes - failing.freed_bytes - outstanding_bytes_before,
            );
            try std.testing.expectEqual(
                expected_delta.allocations,
                failing.allocations - failing.deallocations - outstanding_allocations_before,
            );
            return true;
        },
        else => return err,
    };
    try std.testing.expectEqual(
        expected_delta.bytes,
        failing.allocated_bytes - failing.freed_bytes - outstanding_bytes_before,
    );
    try std.testing.expectEqual(
        expected_delta.allocations,
        failing.allocations - failing.deallocations - outstanding_allocations_before,
    );
    return false;
}

test "StaticMachine string-list resume keeps ownership valid across allocation failure" {
    const expected_delta = try stringListResumeOwnedDelta();
    var observed_resume_failure = false;
    var observed_success = false;
    for (0..256) |fail_index| {
        if (try stringListResumeOutcome(fail_index, expected_delta)) |resume_failed| {
            if (resume_failed) {
                observed_resume_failure = true;
            } else {
                observed_success = true;
                break;
            }
        }
    }
    try std.testing.expect(observed_resume_failure);
    try std.testing.expect(observed_success);
}

fn stringResultDetachOutcome(fail_index: usize) !?bool {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
    const state = StringMachine.initialState(failing.allocator(), .{}) catch |err| switch (err) {
        error.OutOfMemory => return null,
        else => return err,
    };
    defer StringMachine.deinitState(state);
    var fuel: u64 = 100;
    const transition = StringMachine.reduce(state, &fuel) catch |err| switch (err) {
        error.OutOfMemory => return null,
        else => return err,
    };
    const request = switch (transition) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    StringMachine.@"resume"(state, request, @as([]const u8, "detached")) catch |err| switch (err) {
        error.OutOfMemory => return null,
        else => return err,
    };

    const completed = StringMachine.reduce(state, &fuel) catch |err| switch (err) {
        error.OutOfMemory => {
            try std.testing.expect(failing.has_induced_failure);
            failing.fail_index = std.math.maxInt(usize);
            var retried = switch (try StringMachine.reduce(state, &fuel)) {
                .done => |done| done,
                else => return error.UnexpectedTransition,
            };
            defer retried.deinit();
            try std.testing.expectEqualStrings("detached", retried.value());
            return true;
        },
        else => return err,
    };
    var done = switch (completed) {
        .done => |value| value,
        else => return error.UnexpectedTransition,
    };
    defer done.deinit();
    try std.testing.expectEqualStrings("detached", done.value());
    return false;
}

test "StaticMachine retries terminal result detachment after allocation failure" {
    var observed_detach_failure = false;
    for (0..256) |fail_index| {
        if (try stringResultDetachOutcome(fail_index)) |detach_failed| {
            if (detach_failed) {
                observed_detach_failure = true;
                break;
            }
        }
    }
    try std.testing.expect(observed_detach_failure);
}
