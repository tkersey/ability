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

fn usizeIdentityPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .usize,
        .result_codec = .usize,
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
        .ir_hash = 20,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const PortableWordProduct = struct {
    wide: u64,
    portable: usize,
};
const PortableWordSchemas = boundary.ir.schema.Registry(.{PortableWordProduct});

fn portableWordProductPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 0,
        .result_codec = .product,
        .result_schema_index = 0,
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
        .ir_hash = 21,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &PortableWordSchemas.value_schemas,
        .value_fields = &PortableWordSchemas.value_fields,
        .value_variants = &PortableWordSchemas.value_variants,
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn nominalCarrierEffectPlan(comptime Payload: type) boundary.ir.ProgramPlan {
    const Schemas = boundary.ir.schema.Registry(.{Payload});
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const resumed = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), payload) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
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
        .op_name = "inspect",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = "static-machine-nominal-carrier",
        .ir_hash = 23,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &Schemas.value_schemas,
        .value_fields = &Schemas.value_fields,
        .value_variants = &Schemas.value_variants,
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sumIdentityPlan(comptime Sum: type) boundary.ir.ProgramPlan {
    const Schemas = boundary.ir.schema.Registry(.{Sum});
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .sum,
        .value_schema_index = 0,
        .result_codec = .sum,
        .result_schema_index = 0,
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
        .label = "static-machine-enum-identity",
        .ir_hash = 24,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &Schemas.value_schemas,
        .value_fields = &Schemas.value_fields,
        .value_variants = &Schemas.value_variants,
        .locals = &.{.{ .codec = .sum, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn extractedPortableWordPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const wide = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .product_extract_field, .dst = wide.index, .operand = value.index, .aux = 0 },
        boundary.ir.builder.returnValue(root, wide) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .usize,
        .result_codec = .usize,
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
        .ir_hash = 22,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &PortableWordSchemas.value_schemas,
        .value_fields = &PortableWordSchemas.value_fields,
        .value_variants = &PortableWordSchemas.value_variants,
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .usize },
        },
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

fn inPlaceBranchCachePlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const condition = boundary.ir.builder.local(root, 0);
    const result = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = condition.index },
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
        .local_count = 2,
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
        .ir_hash = 42,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn rewrittenSourceBranchCachePlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const result = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        .{ .kind = .const_i32, .dst = input.index, .operand = 1 },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
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
        .requirement_count = 1,
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
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "test",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 4, .terminator_index = 1 },
        .{ .first_instruction = 5, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 43,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn correlatedBinarySumPlan(comptime Sum: type, comptime label: []const u8) boundary.ir.ProgramPlan {
    const Schemas = boundary.ir.schema.Registry(.{Sum});
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const result = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .sum_variant_is, .dst = condition.index, .operand = input.index, .aux = 0 },
        .{ .kind = .sum_variant_is, .dst = condition.index, .operand = input.index, .aux = 1 },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
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
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 4,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "test",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
        .{ .first_instruction = 5, .instruction_count = 2, .terminator_index = 3 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 3 },
        .{ .kind = .jump, .primary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 44,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &Schemas.value_schemas,
        .value_fields = &Schemas.value_fields,
        .value_variants = &Schemas.value_variants,
        .locals = &.{
            .{ .codec = .sum, .schema_index = 0 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn interleavedConditionPredicatesPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 45,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .bool },
            .{ .codec = .bool },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn conditionalLocalPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const value = boundary.ir.builder.local(root, 2);
    const copied_input = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .add_const_i32, .dst = copied_input.index, .operand = input.index, .aux = 0 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = copied_input.index },
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = copied_input.index },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .const_i32, .dst = input.index, .operand = 99 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
        .{ .kind = .const_i32, .dst = value.index, .operand = 9 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 8,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "park",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 0, .terminator_index = 2 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 4 },
        .{ .first_instruction = 5, .instruction_count = 1, .terminator_index = 5 },
        .{ .first_instruction = 6, .instruction_count = 2, .terminator_index = 6 },
        .{ .first_instruction = 8, .instruction_count = 2, .terminator_index = 7 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .branch_if, .primary = 4, .secondary = 5 },
        .{ .kind = .jump, .primary = 6 },
        .{ .kind = .jump, .primary = 7 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 40,
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
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn correlatedAbsentLocalPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const value = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
        .{ .kind = .const_i32, .dst = value.index, .operand = 9 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 7,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "park",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 0, .terminator_index = 2 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 4 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 5 },
        .{ .first_instruction = 5, .instruction_count = 2, .terminator_index = 6 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 4 },
        .{ .kind = .branch_if, .primary = 5, .secondary = 6 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 44,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn gatedPredicateAuthorityPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const first = boundary.ir.builder.local(root, 0);
    const second = boundary.ir.builder.local(root, 1);
    const condition = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = first.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = second.index },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 2,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 4,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "park",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 3, .instruction_count = 0, .terminator_index = 3 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 3 },
        .{ .kind = .branch_if, .primary = 3, .secondary = 2 },
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 45,
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

fn helperGatedPredicateAuthorityPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const first = boundary.ir.builder.local(root, 0);
    const second = boundary.ir.builder.local(root, 1);
    const condition = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = first.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = second.index },
        boundary.ir.builder.callHelper(root, null, helper, null) catch unreachable,
        boundary.ir.builder.callOp(helper, null, boundary.ir.builder.op(helper, 0), null) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 4,
            .first_instruction = 0,
            .instruction_count = 3,
        },
        .{
            .symbol_name = "helper",
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 3,
            .local_count = 0,
            .first_block = 4,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 3,
            .instruction_count = 1,
        },
    };
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "park",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 3, .instruction_count = 0, .terminator_index = 3 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 4 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 3 },
        .{ .kind = .branch_if, .primary = 3, .secondary = 2 },
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 46,
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

fn rewrittenPredicateAbsentLocalPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const value = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        .{ .kind = .const_i32, .dst = input.index, .operand = 0 },
        .{ .kind = .const_i32, .dst = input.index, .operand = 1 },
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
        .{ .kind = .const_i32, .dst = value.index, .operand = 9 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 7,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "park",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = 5, .instruction_count = 1, .terminator_index = 4 },
        .{ .first_instruction = 6, .instruction_count = 1, .terminator_index = 5 },
        .{ .first_instruction = 7, .instruction_count = 2, .terminator_index = 6 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 4 },
        .{ .kind = .branch_if, .primary = 5, .secondary = 6 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 45,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn controlValidationLocalWorkPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
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
        .local_count = 64,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 1 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 2 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 0 },
        .{ .kind = .jump, .primary = 0 },
    };
    const locals = [_]boundary.ir.plan.Local{
        .{ .codec = .i32 },
        .{ .codec = .bool },
    } ++ [_]boundary.ir.plan.Local{.{ .codec = .i32 }} ** 62;
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 45,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
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

fn helperValueCompletionPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const root_value = boundary.ir.builder.local(root, 0);
    const helper_value = boundary.ir.builder.local(helper, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = helper_value.index, .operand = 7 },
        boundary.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
            .instruction_count = 3,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .unit,
            .first_requirement = 1,
            .requirement_count = 0,
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
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "park",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "wait",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
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
        .ir_hash = 39,
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

fn unitLocalPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
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
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 22,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .unit }},
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
const alternate_nested_metadata = "j\x1fk\x1fl\x1fm\x1fn\x1fo\x1fp\x1fq\x1fr";

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

fn mutuallyExclusiveAfterPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    @setEvalBranchQuota(10_000);
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const outer_resume = boundary.ir.builder.local(root, 2);
    const first_resume = boundary.ir.builder.local(root, 3);
    const second_resume = boundary.ir.builder.local(root, 4);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = first_resume.index, .operand = 0 },
        .{ .kind = .const_i32, .dst = second_resume.index, .operand = 0 },
        boundary.ir.builder.callOp(root, outer_resume, boundary.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.callOp(root, first_resume, boundary.ir.builder.op(root, 1), null) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.returnValue(root, first_resume) catch unreachable,
        boundary.ir.builder.callOp(root, second_resume, boundary.ir.builder.op(root, 2), null) catch unreachable,
        boundary.ir.builder.returnValue(root, second_resume) catch unreachable,
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
        .block_count = 6,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "outer", .first_op = 0, .op_count = 1 },
        .{ .label = "first", .first_op = 1, .op_count = 1 },
        .{ .label = "second", .first_op = 2, .op_count = 1 },
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
            .op_name = "first",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 2,
            .op_name = "second",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 4, .terminator_index = 0 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 5, .instruction_count = 0, .terminator_index = 2 },
        .{ .first_instruction = 5, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = 6, .instruction_count = 1, .terminator_index = 4 },
        .{ .first_instruction = 7, .instruction_count = 2, .terminator_index = 5 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .branch_if, .primary = 4, .secondary = 5 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 41,
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

fn correlatedOutermostAfterPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const outer_resume = boundary.ir.builder.local(root, 2);
    const inner_resume = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.callOp(root, outer_resume, boundary.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        boundary.ir.builder.callOp(root, inner_resume, boundary.ir.builder.op(root, 1), null) catch unreachable,
        boundary.ir.builder.returnValue(root, inner_resume) catch unreachable,
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 2), null) catch unreachable,
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
        .block_count = 6,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "outer", .first_op = 0, .op_count = 1 },
        .{ .label = "inner", .first_op = 1, .op_count = 1 },
        .{ .label = "abort", .first_op = 2, .op_count = 1 },
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
        .{
            .requirement_index = 2,
            .op_name = "abort",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 0, .terminator_index = 2 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 4 },
        .{ .first_instruction = 5, .instruction_count = 1, .terminator_index = 5 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .branch_if, .primary = 4, .secondary = 5 },
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 45,
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

fn correlatedBinarySumAfterPlan(
    comptime Sum: type,
    comptime label: []const u8,
) boundary.ir.ProgramPlan {
    @setEvalBranchQuota(10_000);
    const Schemas = boundary.ir.schema.Registry(.{Sum});
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const outer_resume = boundary.ir.builder.local(root, 2);
    const inner_resume = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .sum_variant_is, .dst = condition.index, .operand = input.index, .aux = 0 },
        boundary.ir.builder.callOp(root, outer_resume, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.callOp(root, outer_resume, boundary.ir.builder.op(root, 1), null) catch unreachable,
        .{ .kind = .sum_variant_is, .dst = condition.index, .operand = input.index, .aux = 1 },
        boundary.ir.builder.callOp(root, inner_resume, boundary.ir.builder.op(root, 3), null) catch unreachable,
        boundary.ir.builder.returnValue(root, inner_resume) catch unreachable,
        boundary.ir.builder.callOp(root, inner_resume, boundary.ir.builder.op(root, 2), null) catch unreachable,
        boundary.ir.builder.returnValue(root, inner_resume) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 4,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 6,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "outer_a", .first_op = 0, .op_count = 1 },
        .{ .label = "outer_b", .first_op = 1, .op_count = 1 },
        .{ .label = "inner_a", .first_op = 2, .op_count = 1 },
        .{ .label = "inner_b", .first_op = 3, .op_count = 1 },
    };
    const ops = [_]boundary.ir.plan.Op{
        .{ .requirement_index = 0, .op_name = "outer_a", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true },
        .{ .requirement_index = 1, .op_name = "outer_b", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true },
        .{ .requirement_index = 2, .op_name = "inner_a", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true },
        .{ .requirement_index = 3, .op_name = "inner_b", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = 4, .instruction_count = 2, .terminator_index = 4 },
        .{ .first_instruction = 6, .instruction_count = 2, .terminator_index = 5 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .branch_if, .primary = 4, .secondary = 5 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 46,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &Schemas.value_schemas,
        .value_fields = &Schemas.value_fields,
        .value_variants = &Schemas.value_variants,
        .locals = &.{
            .{ .codec = .sum, .schema_index = 0 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
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

fn nonCompletingConditionalParentPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const never = boundary.ir.builder.function(1);
    const input = boundary.ir.builder.local(root, 0);
    const condition = boundary.ir.builder.local(root, 1);
    const value = boundary.ir.builder.local(root, 2);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = input.index },
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        boundary.ir.builder.callHelper(root, null, never, null) catch unreachable,
        boundary.ir.builder.returnValue(root, value) catch unreachable,
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
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 4,
            .first_instruction = 0,
            .instruction_count = @intCast(instructions.len),
        },
        .{
            .symbol_name = "never",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 3,
            .local_count = 0,
            .first_block = 4,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = @intCast(instructions.len),
            .instruction_count = 0,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 3 },
        .{ .first_instruction = @intCast(instructions.len), .instruction_count = 0, .terminator_index = 4 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .jump, .primary = 3 },
        .{ .kind = .return_value },
        .{ .kind = .jump, .primary = 4 },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 43,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn legacyCompletionNamespacePlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const completing = boundary.ir.builder.function(1);
    const looping = boundary.ir.builder.function(2);
    const provider = boundary.ir.builder.function(3);
    const root_value = boundary.ir.builder.local(root, 0);
    const completing_value = boundary.ir.builder.local(completing, 0);
    const provider_value = boundary.ir.builder.local(provider, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, root_value, provider, null) catch unreachable,
        boundary.ir.builder.callHelper(root, root_value, looping, null) catch unreachable,
        boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = completing_value.index, .operand = 7 },
        boundary.ir.builder.returnValue(completing, completing_value) catch unreachable,
        boundary.ir.builder.callOp(provider, provider_value, boundary.ir.builder.op(provider, 1), null) catch unreachable,
        boundary.ir.builder.returnValue(provider, provider_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
            .instruction_count = 4,
        },
        .{
            .symbol_name = "completing",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 4,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "looping",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 8,
            .instruction_count = 0,
        },
        .{
            .symbol_name = "provider",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 1,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 3,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 6,
            .instruction_count = 2,
        },
    };
    const requirements = [_]boundary.ir.plan.Requirement{
        .{ .label = "legacy-visible", .first_op = 0, .op_count = 1 },
        .{ .label = "reachable", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]boundary.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "after-loop",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .unit,
        },
        .{
            .requirement_index = 1,
            .op_name = "request",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
        },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 4, .terminator_index = 0 },
        .{ .first_instruction = 8, .instruction_count = 0, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 2, .terminator_index = 2 },
        .{ .first_instruction = 6, .instruction_count = 2, .terminator_index = 3 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 25,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
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

const UsizeIdentityBody = struct {
    pub const compiled_plan = usizeIdentityPlan("static-machine-usize-identity");
};
const UsizeIdentityProgram = boundary.program("static-machine-usize-identity", struct {}, UsizeIdentityBody);
const UsizeIdentityMachine = boundary.staticMachine(UsizeIdentityProgram, .{});

const PortableWordProductBody = struct {
    pub const value_schema_types = .{PortableWordProduct};
    pub const compiled_plan = portableWordProductPlan("static-machine-portable-word-product");
};
const PortableWordProductProgram = boundary.program(
    "static-machine-portable-word-product",
    struct {},
    PortableWordProductBody,
);
const PortableWordProductMachine = boundary.staticMachine(PortableWordProductProgram, .{});

fn NominalCarrierProgram(comptime Payload: type) type {
    return boundary.program("static-machine-nominal-carrier", struct {}, struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = nominalCarrierEffectPlan(Payload);
    });
}

const NominalCarrierA = struct { word: u64 };
const NominalCarrierB = struct { word: u64 };
const ImmutableStringListCarrier = struct { items: []const []const u8 };
const NominalCarrierMachineA = boundary.staticMachine(NominalCarrierProgram(NominalCarrierA), .{});
const NominalCarrierMachineB = boundary.staticMachine(NominalCarrierProgram(NominalCarrierB), .{});
const ImmutableStringListCarrierMachine = boundary.staticMachine(
    NominalCarrierProgram(ImmutableStringListCarrier),
    .{},
);

fn SumIdentityProgram(comptime Sum: type) type {
    return boundary.program("static-machine-enum-identity", struct {}, struct {
        pub const value_schema_types = .{Sum};
        pub const compiled_plan = sumIdentityPlan(Sum);
    });
}

const EnumMappingA = enum(u8) { ready = 1, waiting = 2 };
const EnumMappingB = enum(u8) { ready = 2, waiting = 1 };
const EnumMappingWide = enum(u16) { ready = 1, waiting = 2 };
const EnumMachineA = boundary.staticMachine(SumIdentityProgram(EnumMappingA), .{});
const EnumMachineB = boundary.staticMachine(SumIdentityProgram(EnumMappingB), .{});
const EnumMachineWide = boundary.staticMachine(SumIdentityProgram(EnumMappingWide), .{});

const ExtractedPortableWordBody = struct {
    pub const value_schema_types = .{PortableWordProduct};
    pub const compiled_plan = extractedPortableWordPlan("static-machine-extracted-portable-word");
};
const ExtractedPortableWordProgram = boundary.program(
    "static-machine-extracted-portable-word",
    struct {},
    ExtractedPortableWordBody,
);
const ExtractedPortableWordMachine = boundary.staticMachine(ExtractedPortableWordProgram, .{});

const BranchCacheBody = struct {
    pub const compiled_plan = branchCachePlan("static-machine-branch-cache");
};
const BranchCacheProgram = boundary.program("static-machine-branch-cache", struct {}, BranchCacheBody);
const BranchCacheMachine = boundary.staticMachine(BranchCacheProgram, .{});

const InPlaceBranchCacheBody = struct {
    pub const compiled_plan = inPlaceBranchCachePlan("static-machine-in-place-branch-cache");
};
const InPlaceBranchCacheProgram = boundary.program(
    "static-machine-in-place-branch-cache",
    struct {},
    InPlaceBranchCacheBody,
);
const InPlaceBranchCacheMachine = boundary.staticMachine(InPlaceBranchCacheProgram, .{});

const RewrittenSourceBranchCacheBody = struct {
    pub const compiled_plan = rewrittenSourceBranchCachePlan(
        "static-machine-rewritten-source-branch-cache",
    );
};
const RewrittenSourceBranchCacheProgram = boundary.program(
    "static-machine-rewritten-source-branch-cache",
    struct {},
    RewrittenSourceBranchCacheBody,
);
const RewrittenSourceBranchCacheMachine = boundary.staticMachine(
    RewrittenSourceBranchCacheProgram,
    .{},
);

const BinaryConditionChoice = enum(u8) { first, second };
const CorrelatedBinarySumBody = struct {
    pub const value_schema_types = .{BinaryConditionChoice};
    pub const compiled_plan = correlatedBinarySumPlan(
        BinaryConditionChoice,
        "static-machine-correlated-binary-sum",
    );
};
const CorrelatedBinarySumProgram = boundary.program(
    "static-machine-correlated-binary-sum",
    struct {},
    CorrelatedBinarySumBody,
);
const CorrelatedBinarySumMachine = boundary.staticMachine(CorrelatedBinarySumProgram, .{});

const CorrelatedBinarySumAfterHandlers = struct {
    outer_a: struct {
        pub fn afterDispatch(_: *const @This(), value: bool) ![]const u8 {
            return if (value) "a" else "unexpected";
        }
    },
    outer_b: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) ![]const u8 {
            return if (value != 0) "b" else "unexpected";
        }
    },
    inner_a: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value != 0;
        }
    },
    inner_b: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
            return value;
        }
    },
};
const CorrelatedBinarySumAfterBody = struct {
    pub const value_schema_types = .{BinaryConditionChoice};
    pub const compiled_plan = correlatedBinarySumAfterPlan(
        BinaryConditionChoice,
        "static-machine-correlated-binary-sum-after",
    );
};
const CorrelatedBinarySumAfterProgram = boundary.program(
    "static-machine-correlated-binary-sum-after",
    CorrelatedBinarySumAfterHandlers,
    CorrelatedBinarySumAfterBody,
);
const CorrelatedBinarySumAfterMachine = boundary.staticMachine(
    CorrelatedBinarySumAfterProgram,
    .{},
);

const InterleavedConditionPredicatesBody = struct {
    pub const compiled_plan = interleavedConditionPredicatesPlan(
        "static-machine-interleaved-condition-predicates",
    );
};
const InterleavedConditionPredicatesProgram = boundary.program(
    "static-machine-interleaved-condition-predicates",
    struct {},
    InterleavedConditionPredicatesBody,
);

const ConditionalLocalBody = struct {
    pub const compiled_plan = conditionalLocalPlan("static-machine-conditional-local");
};
const ConditionalLocalProgram = boundary.program(
    "static-machine-conditional-local",
    struct {},
    ConditionalLocalBody,
);
const ConditionalLocalMachine = boundary.staticMachine(ConditionalLocalProgram, .{});

const CorrelatedAbsentLocalBody = struct {
    pub const compiled_plan = correlatedAbsentLocalPlan("static-machine-correlated-absent-local");
};
const CorrelatedAbsentLocalProgram = boundary.program(
    "static-machine-correlated-absent-local",
    struct {},
    CorrelatedAbsentLocalBody,
);
const CorrelatedAbsentLocalMachine = boundary.staticMachine(CorrelatedAbsentLocalProgram, .{});

const GatedPredicateAuthorityBody = struct {
    pub const compiled_plan = gatedPredicateAuthorityPlan(
        "static-machine-gated-predicate-authority",
    );
};
const GatedPredicateAuthorityProgram = boundary.program(
    "static-machine-gated-predicate-authority",
    struct {},
    GatedPredicateAuthorityBody,
);
const GatedPredicateAuthorityMachine = boundary.staticMachine(
    GatedPredicateAuthorityProgram,
    .{},
);

const HelperGatedPredicateAuthorityBody = struct {
    pub const compiled_plan = helperGatedPredicateAuthorityPlan(
        "static-machine-helper-gated-predicate-authority",
    );
};
const HelperGatedPredicateAuthorityProgram = boundary.program(
    "static-machine-helper-gated-predicate-authority",
    struct {},
    HelperGatedPredicateAuthorityBody,
);
const HelperGatedPredicateAuthorityMachine = boundary.staticMachine(
    HelperGatedPredicateAuthorityProgram,
    .{},
);

const RewrittenPredicateAbsentLocalBody = struct {
    pub const compiled_plan = rewrittenPredicateAbsentLocalPlan(
        "static-machine-rewritten-predicate-absent-local",
    );
};
const RewrittenPredicateAbsentLocalProgram = boundary.program(
    "static-machine-rewritten-predicate-absent-local",
    struct {},
    RewrittenPredicateAbsentLocalBody,
);
const RewrittenPredicateAbsentLocalMachine = boundary.staticMachine(
    RewrittenPredicateAbsentLocalProgram,
    .{},
);

const ControlValidationLocalWorkBody = struct {
    pub const compiled_plan = controlValidationLocalWorkPlan(
        "static-machine-control-validation-local-work",
    );
};
const ControlValidationLocalWorkProgram = boundary.program(
    "static-machine-control-validation-local-work",
    struct {},
    ControlValidationLocalWorkBody,
);
const ControlValidationLocalWorkMachine = boundary.staticMachine(
    ControlValidationLocalWorkProgram,
    .{},
);

const HelperBody = struct {
    pub const compiled_plan = helperEffectPlan("static-machine-helper");
};
const HelperProgram = boundary.program("static-machine-helper", struct {}, HelperBody);
const HelperMachine = boundary.staticMachine(HelperProgram, .{});

const HelperValueCompletionBody = struct {
    pub const compiled_plan = helperValueCompletionPlan("static-machine-helper-value-completion");
};
const HelperValueCompletionProgram = boundary.program(
    "static-machine-helper-value-completion",
    struct {},
    HelperValueCompletionBody,
);
const HelperValueCompletionMachine = boundary.staticMachine(HelperValueCompletionProgram, .{});

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

const UnitLocalBody = struct {
    pub const compiled_plan = unitLocalPlan("static-machine-unit-local");
};
const UnitLocalProgram = boundary.program("static-machine-unit-local", struct {}, UnitLocalBody);
const UnitLocalMachine = boundary.staticMachine(UnitLocalProgram, .{});

const AuthoredRejectedBody = struct {
    pub const Error = error{Rejected};
    pub const compiled_plan = returnErrorPlan("static-machine-authored-rejected", "Rejected");
};
const AuthoredRejectedProgram = boundary.program("static-machine-authored-rejected", struct {}, AuthoredRejectedBody);
const AuthoredRejectedMachine = boundary.staticMachine(AuthoredRejectedProgram, .{});

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

const NestedOrderedBodyA = struct {
    pub const compiled_plan = NestedFirstBody.compiled_plan;
    pub const nested_with_targets = .{
        boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 1 },
        boundary.ir.NestedWithTarget{ .metadata = alternate_nested_metadata, .function_index = 2 },
    };
};
const NestedOrderedBodyB = struct {
    pub const compiled_plan = NestedFirstBody.compiled_plan;
    pub const nested_with_targets = .{
        boundary.ir.NestedWithTarget{ .metadata = alternate_nested_metadata, .function_index = 2 },
        boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 1 },
    };
};
const NestedOrderedProgramA = boundary.program("static-machine-nested-order", struct {}, NestedOrderedBodyA);
const NestedOrderedProgramB = boundary.program("static-machine-nested-order", struct {}, NestedOrderedBodyB);
const NestedOrderedMachineA = boundary.staticMachine(NestedOrderedProgramA, .{});
const NestedOrderedMachineB = boundary.staticMachine(NestedOrderedProgramB, .{});

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

const MutuallyExclusiveAfterHandlers = struct {
    outer: struct {
        pub fn afterDispatch(_: *const @This(), value: bool) ![]const u8 {
            return if (value) "matched" else "unexpected";
        }
    },
    first: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value == 7;
        }
    },
    second: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value == 9;
        }
    },
};
const MutuallyExclusiveAfterBody = struct {
    pub const compiled_plan = mutuallyExclusiveAfterPlan("static-machine-mutually-exclusive-after");
};
const MutuallyExclusiveAfterProgram = boundary.program(
    "static-machine-mutually-exclusive-after",
    MutuallyExclusiveAfterHandlers,
    MutuallyExclusiveAfterBody,
);
const MutuallyExclusiveAfterMachine = boundary.staticMachine(MutuallyExclusiveAfterProgram, .{});

const CorrelatedOutermostAfterHandlers = struct {
    outer: struct {
        pub fn afterDispatch(_: *const @This(), value: bool) ![]const u8 {
            return if (value) "matched" else "unexpected";
        }
    },
    inner: struct {
        pub fn afterDispatch(_: *const @This(), value: i32) !bool {
            return value != 0;
        }
    },
};
const CorrelatedOutermostAfterBody = struct {
    pub const compiled_plan = correlatedOutermostAfterPlan("static-machine-correlated-outermost-after");
};
const CorrelatedOutermostAfterProgram = boundary.program(
    "static-machine-correlated-outermost-after",
    CorrelatedOutermostAfterHandlers,
    CorrelatedOutermostAfterBody,
);
const CorrelatedOutermostAfterMachine = boundary.staticMachine(CorrelatedOutermostAfterProgram, .{});

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

const NonCompletingConditionalParentBody = struct {
    pub const compiled_plan = nonCompletingConditionalParentPlan(
        "static-machine-noncompleting-conditional-parent",
    );
};
const NonCompletingConditionalParentProgram = boundary.program(
    "static-machine-noncompleting-conditional-parent",
    struct {},
    NonCompletingConditionalParentBody,
);
const NonCompletingConditionalParentMachine = boundary.staticMachine(
    NonCompletingConditionalParentProgram,
    .{},
);

const LegacyCompletionNamespaceBody = struct {
    pub const compiled_plan = legacyCompletionNamespacePlan("static-machine-versioned-completion");
};
const LegacyCompletionNamespaceProgram = boundary.program(
    "static-machine-versioned-completion",
    struct {},
    LegacyCompletionNamespaceBody,
);
const LegacyCompletionNamespaceMachine = boundary.staticMachine(LegacyCompletionNamespaceProgram, .{});

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
const TightParkMachine = boundary.staticMachine(OneEffectProgram, .{ .maximum_state_bytes = 250 });
const BoundedStringMachine = boundary.staticMachine(StringProgram, .{ .maximum_state_bytes = 2048 });
const WideBoundedStringMachine = boundary.staticMachine(StringProgram, .{ .maximum_state_bytes = 4096 });
const BoundedAfterMachine = boundary.staticMachine(AfterContractProgramA, .{ .maximum_state_bytes = 2048 });
const DebugOneEffectMachine = boundary.staticMachine(OneEffectProgram, .{ .debug_metadata = true });

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

test "StaticMachine after storage is allocated lazily" {
    var storage: [16 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    const state = try AfterMachine.initialState(fixed.allocator(), .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    _ = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
}

test "StaticMachine canonical usize domain is portable across native and wasm32" {
    comptime {
        if (UsizeIdentityMachine.Manifest.canonical_usize_bits != 32) {
            @compileError("StaticMachine canonical usize width must be explicit in its manifest");
        }
    }

    const maximum = @as(usize, std.math.maxInt(u32));
    const state = try UsizeIdentityMachine.initialState(std.testing.allocator, .{maximum});
    defer UsizeIdentityMachine.deinitState(state);
    const encoded = try UsizeIdentityMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try UsizeIdentityMachine.decodeState(std.testing.allocator, encoded);
    defer UsizeIdentityMachine.deinitState(restored);
    var fuel: u64 = 100;
    var result = switch (try UsizeIdentityMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(maximum, result.value());
}

test "StaticMachine publishes a fixed control-path validation scratch bound" {
    try std.testing.expect(
        OneEffectMachine.Manifest.control_path_state_count <=
            OneEffectMachine.Manifest.maximum_control_path_states,
    );
    try std.testing.expect(
        OneEffectMachine.Manifest.control_validation_scratch_bytes <=
            OneEffectMachine.Manifest.maximum_control_validation_scratch_bytes,
    );
    try std.testing.expectEqual(
        @as(usize, 102_400),
        OneEffectMachine.Manifest.maximum_control_validation_scratch_bytes,
    );
    try std.testing.expectEqual(@as(usize, 2), HelperMachine.Manifest.maximum_frame_depth);
    const HelperPathStateIndex = std.math.IntFittingRange(
        0,
        HelperMachine.Manifest.control_path_state_count - 1,
    );
    const helper_visited_word_count = try std.math.divCeil(
        usize,
        HelperMachine.Manifest.control_path_state_count,
        @bitSizeOf(u64),
    );
    const helper_path_scratch_bytes =
        HelperMachine.Manifest.control_path_state_count * @sizeOf(HelperPathStateIndex) +
        helper_visited_word_count * @sizeOf(u64);
    const helper_frame_authority_scratch_bytes =
        HelperMachine.Manifest.maximum_frame_depth * @sizeOf(u64);
    try std.testing.expectEqual(
        helper_path_scratch_bytes + helper_frame_authority_scratch_bytes,
        HelperMachine.Manifest.control_validation_scratch_bytes,
    );
    try std.testing.expectEqual(
        @as(usize, 1_048_576),
        OneEffectMachine.Manifest.maximum_control_validation_steps,
    );
    try std.testing.expect(
        OneEffectMachine.Manifest.control_validation_step_bound <=
            OneEffectMachine.Manifest.maximum_control_validation_steps,
    );
    try std.testing.expect(
        OneEffectMachine.Manifest.control_instruction_metadata_bytes <=
            OneEffectMachine.Manifest.control_path_state_count * 2,
    );
}

test "StaticMachine rejects native usize values outside its canonical domain without changing Session" {
    if (@bitSizeOf(usize) <= 32) return;
    const oversized = @as(usize, std.math.maxInt(u32)) + 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        UsizeIdentityMachine.initialState(std.testing.allocator, .{oversized}),
    );

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try UsizeIdentityProgram.Session.startWithArgs(&runtime, .{}, .{oversized});
    defer session.deinit();
    var result = switch (try session.next()) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(oversized, result.value);
}

test "StaticMachine preserves full u64 schema fields while bounding nested usize fields" {
    const value: PortableWordProduct = .{
        .wide = std.math.maxInt(u64),
        .portable = std.math.maxInt(u32),
    };
    const state = try PortableWordProductMachine.initialState(std.testing.allocator, .{value});
    defer PortableWordProductMachine.deinitState(state);
    const encoded = try PortableWordProductMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try PortableWordProductMachine.decodeState(std.testing.allocator, encoded);
    defer PortableWordProductMachine.deinitState(restored);
    var fuel: u64 = 100;
    var result = switch (try PortableWordProductMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(value, result.value());

    if (@bitSizeOf(usize) > 32) {
        try std.testing.expectError(
            error.ProgramContractViolation,
            PortableWordProductMachine.initialState(std.testing.allocator, .{PortableWordProduct{
                .wide = std.math.maxInt(u64),
                .portable = @as(usize, std.math.maxInt(u32)) + 1,
            }}),
        );
    }
}

test "StaticMachine applies its canonical usize domain after extracting a u64 schema field" {
    if (@bitSizeOf(usize) <= 32) return;
    const value: PortableWordProduct = .{
        .wide = std.math.maxInt(u64),
        .portable = 0,
    };
    const state = try ExtractedPortableWordMachine.initialState(std.testing.allocator, .{value});
    defer ExtractedPortableWordMachine.deinitState(state);
    var fuel: u64 = 100;
    try std.testing.expectError(
        error.ProgramContractViolation,
        ExtractedPortableWordMachine.reduce(state, &fuel),
    );

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try ExtractedPortableWordProgram.Session.startWithArgs(&runtime, .{}, .{value});
    defer session.deinit();
    var result = switch (try session.next()) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, std.math.maxInt(u64)), result.value);
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
    try std.testing.expect(restored_request.token != 0);
    try std.testing.expect(request._session_id != restored_request._session_id);
    try std.testing.expectEqual(request.trace().operation_site_fingerprint, restored_request.trace().operation_site_fingerprint);
    try std.testing.expectEqualStrings("payload", try restored_request.payload([]const u8));
    const reencoded = try OneEffectMachine.encodeState(std.testing.allocator, restored);
    defer std.testing.allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, encoded, reencoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, request, @as(i32, 41)),
    );
    var zero_token = restored_request;
    zero_token.token = 0;
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, zero_token, @as(i32, 41)),
    );

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
    var tampered_turn = current;
    tampered_turn._turn_index +%= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, tampered_turn, @as(i32, 41)),
    );
    var tampered_payload = current;
    tampered_payload._payload_value_fingerprint ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, tampered_payload, @as(i32, 41)),
    );
    var tampered_request = current;
    tampered_request._fingerprint ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, tampered_request, @as(i32, 41)),
    );
    var tampered_plan = current;
    tampered_plan._plan_fingerprint ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, tampered_plan, @as(i32, 41)),
    );
    try OneEffectMachine.@"resume"(restored, current, @as(i32, 41));
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(restored, current, @as(i32, 41)),
    );
}

test "StaticMachine rejected reduce preserves a parked request borrow" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);
    var fuel: u64 = 100;
    const parked = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const payload_before = try parked.payload([]const u8);
    const fuel_before = fuel;

    try std.testing.expectError(error.ProgramContractViolation, OneEffectMachine.reduce(state, &fuel));
    try std.testing.expectEqual(fuel_before, fuel);

    const current = switch (try OneEffectMachine.current(state)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const payload_after = try current.payload([]const u8);
    try std.testing.expectEqual(@intFromPtr(payload_before.ptr), @intFromPtr(payload_after.ptr));
    try std.testing.expectEqualStrings("payload", try parked.payload([]const u8));

    try OneEffectMachine.@"resume"(state, parked, @as(i32, 41));
    const done = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .done => |result| result,
        else => return error.UnexpectedTransition,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(i32, 41), done.value());
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

test "StaticMachine rejects an oversized response without consuming its request" {
    const state = try BoundedStringMachine.initialState(std.testing.allocator, .{});
    defer BoundedStringMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try BoundedStringMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    const before = try BoundedStringMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    const oversized = try std.testing.allocator.alloc(u8, 4096);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');

    try std.testing.expectError(
        error.ProgramContractViolation,
        BoundedStringMachine.@"resume"(state, request, @as([]const u8, oversized)),
    );
    try BoundedStringMachine.validateState(state);
    const current = switch (try BoundedStringMachine.current(state)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(request.fingerprint(), current.fingerprint());
    const after = try BoundedStringMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);

    try BoundedStringMachine.@"resume"(state, request, @as([]const u8, "small"));
    var result = switch (try BoundedStringMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("small", result.value());
}

test "StaticMachine contract identity binds the deterministic state byte limit" {
    try std.testing.expect(
        BoundedStringMachine.Manifest.machine_contract_fingerprint !=
            WideBoundedStringMachine.Manifest.machine_contract_fingerprint,
    );

    const narrow_state = try BoundedStringMachine.initialState(std.testing.allocator, .{});
    defer BoundedStringMachine.deinitState(narrow_state);
    const wide_state = try WideBoundedStringMachine.initialState(std.testing.allocator, .{});
    defer WideBoundedStringMachine.deinitState(wide_state);
    var narrow_fuel: u64 = 100;
    var wide_fuel: u64 = 100;
    const narrow_request = switch (try BoundedStringMachine.reduce(narrow_state, &narrow_fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    const wide_request = switch (try WideBoundedStringMachine.reduce(wide_state, &wide_fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expect(narrow_request.fingerprint() != wide_request.fingerprint());

    const narrow_image = try BoundedStringMachine.encodeState(std.testing.allocator, narrow_state);
    defer std.testing.allocator.free(narrow_image);
    try std.testing.expectError(
        error.ProgramContractViolation,
        WideBoundedStringMachine.decodeState(std.testing.allocator, narrow_image),
    );

    const response = try std.testing.allocator.alloc(u8, 2500);
    defer std.testing.allocator.free(response);
    @memset(response, 'x');
    try std.testing.expectError(
        error.ProgramContractViolation,
        BoundedStringMachine.@"resume"(narrow_state, narrow_request, @as([]const u8, response)),
    );
    try WideBoundedStringMachine.@"resume"(wide_state, wide_request, @as([]const u8, response));
    var result = switch (try WideBoundedStringMachine.reduce(wide_state, &wide_fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualSlices(u8, response, result.value());
}

test "StaticMachine rejects an oversized after response without consuming its request" {
    const state = try BoundedAfterMachine.initialState(std.testing.allocator, .{});
    defer BoundedAfterMachine.deinitState(state);
    var fuel: u64 = 100;
    const outer = switch (try BoundedAfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try BoundedAfterMachine.@"resume"(state, outer, @as(i32, 1));
    const inner = switch (try BoundedAfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try BoundedAfterMachine.@"resume"(state, inner, @as(i32, 7));
    const inner_after = switch (try BoundedAfterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try BoundedAfterMachine.resumeAfter(state, inner_after, true);
    const outer_after = switch (try BoundedAfterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    const before = try BoundedAfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    const oversized = try std.testing.allocator.alloc(u8, 4096);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');

    try std.testing.expectError(
        error.ProgramContractViolation,
        BoundedAfterMachine.resumeAfter(state, outer_after, @as([]const u8, oversized)),
    );
    try BoundedAfterMachine.validateState(state);
    const current = switch (try BoundedAfterMachine.current(state)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(outer_after.fingerprint(), current.fingerprint());
    const after = try BoundedAfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);

    try BoundedAfterMachine.resumeAfter(state, outer_after, @as([]const u8, "true"));
    var result = switch (try BoundedAfterMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("true", result.value());
}

test "StaticMachine authored failure is terminal and never a fuel yield" {
    const state = try AuthoredRejectedMachine.initialState(std.testing.allocator, .{});
    defer AuthoredRejectedMachine.deinitState(state);
    var fuel: u64 = 100;
    try std.testing.expectError(error.Rejected, AuthoredRejectedMachine.reduce(state, &fuel));
    try std.testing.expectError(error.Rejected, AuthoredRejectedMachine.reduce(state, &fuel));
    try std.testing.expectError(
        error.ProgramContractViolation,
        AuthoredRejectedMachine.encodeState(std.testing.allocator, state),
    );
}

test "StaticMachine state surface does not expose the session core" {
    try std.testing.expect(@typeInfo(OneEffectMachine.State) == .pointer);
    const StateStorage = @typeInfo(OneEffectMachine.State).pointer.child;
    try std.testing.expect(@typeInfo(StateStorage) == .@"opaque");
    try std.testing.expect(!@hasDecl(StateStorage, "next"));
    try std.testing.expect(!@hasDecl(StateStorage, "nextWithFuel"));
    try std.testing.expect(!@hasDecl(StateStorage, "encodeState"));
    try std.testing.expect(!@hasDecl(StateStorage, "decodeState"));
}

test "StaticMachine cloneState creates independent live ownership" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    const cloned = try OneEffectMachine.cloneState(std.testing.allocator, state);
    defer OneEffectMachine.deinitState(cloned);

    const original_bytes = try OneEffectMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(original_bytes);
    const cloned_bytes = try OneEffectMachine.encodeState(std.testing.allocator, cloned);
    defer std.testing.allocator.free(cloned_bytes);
    try std.testing.expectEqualSlices(u8, original_bytes, cloned_bytes);

    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(cloned, request, @as(i32, 41)),
    );
    try OneEffectMachine.@"resume"(state, request, @as(i32, 41));
    const cloned_request = switch (try OneEffectMachine.current(cloned)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(request.fingerprint(), cloned_request.fingerprint());
    try OneEffectMachine.@"resume"(cloned, cloned_request, @as(i32, 42));
}

test "StaticMachine cloneState reidentifies runnable ownership" {
    const state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(state);
    const cloned = try OneEffectMachine.cloneState(std.testing.allocator, state);
    defer OneEffectMachine.deinitState(cloned);

    var original_fuel: u64 = 100;
    const original_request = switch (try OneEffectMachine.reduce(state, &original_fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    var cloned_fuel: u64 = 100;
    const cloned_request = switch (try OneEffectMachine.reduce(cloned, &cloned_fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(original_request.fingerprint(), cloned_request.fingerprint());
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(cloned, original_request, @as(i32, 41)),
    );
    try OneEffectMachine.@"resume"(cloned, cloned_request, @as(i32, 42));
}

test "StaticMachine debug metadata manifest claim is inspectable" {
    try std.testing.expect(!OneEffectMachine.Manifest.includes_debug_metadata);
    try std.testing.expect(OneEffectMachine.Manifest.debug_metadata == null);
    try std.testing.expect(DebugOneEffectMachine.Manifest.includes_debug_metadata);
    const metadata = DebugOneEffectMachine.Manifest.debug_metadata orelse return error.MissingDebugMetadata;
    try std.testing.expectEqual(DebugOneEffectMachine.Manifest.operation_site_count, metadata.operation_sites.len);
    try std.testing.expectEqual(DebugOneEffectMachine.Manifest.after_site_count, metadata.after_sites.len);
}

test "StaticMachine rejects an initial state above its byte limit" {
    try std.testing.expectError(
        error.ProgramContractViolation,
        TinyStateMachine.initialState(std.testing.allocator, .{}),
    );
}

test "StaticMachine rejects an oversized parked transition atomically" {
    const state = try TightParkMachine.initialState(std.testing.allocator, .{});
    defer TightParkMachine.deinitState(state);
    const before = try TightParkMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var fuel: u64 = 100;
    const original_fuel = fuel;

    try std.testing.expectError(error.ProgramContractViolation, TightParkMachine.reduce(state, &fuel));
    try std.testing.expectEqual(original_fuel, fuel);
    try TightParkMachine.validateState(state);
    const after = try TightParkMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
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
    var tampered_turn = after;
    tampered_turn._turn_index +%= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.resumeAfter(state, tampered_turn, @as(i32, 15)),
    );
    var tampered_value = after;
    tampered_value._value_fingerprint ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.resumeAfter(state, tampered_value, @as(i32, 15)),
    );
    var tampered_request = after;
    tampered_request._fingerprint ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.resumeAfter(state, tampered_request, @as(i32, 15)),
    );
    var tampered_plan = after;
    tampered_plan._plan_fingerprint ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.resumeAfter(state, tampered_plan, @as(i32, 15)),
    );
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

test "StaticMachine nested target identity normalizes unique resolver row order" {
    try std.testing.expectEqual(
        NestedOrderedMachineA.Manifest.machine_contract_fingerprint,
        NestedOrderedMachineB.Manifest.machine_contract_fingerprint,
    );
    const state = try NestedOrderedMachineA.initialState(std.testing.allocator, .{});
    defer NestedOrderedMachineA.deinitState(state);
    const encoded = try NestedOrderedMachineA.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try NestedOrderedMachineB.decodeState(std.testing.allocator, encoded);
    defer NestedOrderedMachineB.deinitState(restored);
}

test "ProgramPlan rejects duplicate nested target metadata" {
    const duplicate_targets = .{
        boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 1 },
        boundary.ir.NestedWithTarget{ .metadata = nested_metadata, .function_index = 2 },
    };
    try std.testing.expectError(
        error.DuplicateNestedTargetMetadata,
        NestedFirstBody.compiled_plan.validateWithNestedTargets(duplicate_targets),
    );
}

test "StaticMachine exposes a closed authored failure surface" {
    comptime {
        if (AuthoredRejectedMachine.Failure != error{Rejected}) {
            @compileError("StaticMachine Failure must contain only Body.Error");
        }
        if (AuthoredRejectedMachine.Error != error{
            ExecutionBudgetExceeded,
            OutOfMemory,
            ProgramContractViolation,
            Rejected,
        }) {
            @compileError("StaticMachine Error must be a closed machine operation error set");
        }
    }
}

test "StaticMachine completion analysis does not rewrite the legacy Program protocol" {
    try std.testing.expectEqual(@as(usize, 2), LegacyCompletionNamespaceProgram.protocol.operation_site_count);
    try std.testing.expectEqual(@as(usize, 1), LegacyCompletionNamespaceMachine.Manifest.operation_site_count);
    const LegacySite = LegacyCompletionNamespaceProgram.protocol.operationSite("reachable", "request", 0);
    const StaticSite = LegacyCompletionNamespaceMachine.EffectRow.operationSite("reachable", "request", 0);
    try std.testing.expectEqual(@as(usize, 1), LegacySite.index);
    try std.testing.expectEqual(@as(usize, 0), StaticSite.index);
    try std.testing.expectEqual(LegacySite.fingerprint, StaticSite.legacy_fingerprint);

    const state = try LegacyCompletionNamespaceMachine.initialState(std.testing.allocator, .{});
    defer LegacyCompletionNamespaceMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try LegacyCompletionNamespaceMachine.reduce(state, &fuel)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    try request.expectSite(StaticSite);
    try LegacyCompletionNamespaceMachine.@"resume"(state, request, @as(i32, 7));
    fuel = 100;
    switch (try LegacyCompletionNamespaceMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
}

test "StaticMachine EffectRow coverage follows the static site catalog" {
    const ReachableLegacySite = LegacyCompletionNamespaceProgram.protocol.operationSite(
        "reachable",
        "request",
        0,
    );
    const ReachableHandler = struct {
        fn handle(
            _: anytype,
            _: anytype,
            _: LegacyCompletionNamespaceProgram.Handler.Control,
        ) LegacyCompletionNamespaceProgram.Handler.Outcome(ReachableLegacySite) {
            return LegacyCompletionNamespaceProgram.Handler.@"resume"(
                ReachableLegacySite,
                @as(i32, 7),
            );
        }
    };
    const Interpreter = LegacyCompletionNamespaceProgram.Interpreter(.{
        LegacyCompletionNamespaceProgram.Handler.operation(
            ReachableLegacySite,
            ReachableHandler.handle,
        ),
    });

    comptime LegacyCompletionNamespaceMachine.EffectRow.assertAllSitesCoveredBy(Interpreter);
}

test "StaticMachine EffectRow coverage includes after sites" {
    const Operation = AfterProgram.protocol.operationSite("test", "after", 0);
    const After = AfterProgram.protocol.afterSite("test", "after", 0);
    const OperationHandler = struct {
        fn handle(
            _: anytype,
            _: anytype,
            _: AfterProgram.Handler.Control,
        ) AfterProgram.Handler.Outcome(Operation) {
            return AfterProgram.Handler.@"resume"(Operation, @as(i32, 10));
        }
    };
    const AfterHandler = struct {
        fn handle(
            _: anytype,
            _: anytype,
            _: AfterProgram.Handler.Control,
        ) AfterProgram.Handler.Outcome(After) {
            return AfterProgram.Handler.resumeAfter(After, @as(i32, 15));
        }
    };
    const Interpreter = AfterProgram.Interpreter(.{
        AfterProgram.Handler.operation(Operation, OperationHandler.handle),
        AfterProgram.Handler.after(After, AfterHandler.handle),
    });

    comptime AfterMachine.EffectRow.assertAllSitesCoveredBy(Interpreter);
}

test "StaticMachine canonical identity forgets nominal carrier names" {
    try std.testing.expectEqual(
        NominalCarrierMachineA.Manifest.canonical_plan_fingerprint,
        NominalCarrierMachineB.Manifest.canonical_plan_fingerprint,
    );
    try std.testing.expectEqual(
        NominalCarrierMachineA.Manifest.machine_contract_fingerprint,
        NominalCarrierMachineB.Manifest.machine_contract_fingerprint,
    );

    const state_a = try NominalCarrierMachineA.initialState(std.testing.allocator, .{NominalCarrierA{ .word = 41 }});
    defer NominalCarrierMachineA.deinitState(state_a);
    var fuel: u64 = 100;
    const request_a = switch (try NominalCarrierMachineA.reduce(state_a, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(@as(u64, 41), (try request_a.payload(NominalCarrierA)).word);

    const encoded_a = try NominalCarrierMachineA.encodeState(std.testing.allocator, state_a);
    defer std.testing.allocator.free(encoded_a);
    const state_b = try NominalCarrierMachineB.decodeState(std.testing.allocator, encoded_a);
    defer NominalCarrierMachineB.deinitState(state_b);
    const request_b = switch (try NominalCarrierMachineB.current(state_b)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(@as(u64, 41), (try request_b.payload(NominalCarrierB)).word);
    try std.testing.expectEqual(request_a.fingerprint(), request_b.fingerprint());

    const encoded_b = try NominalCarrierMachineB.encodeState(std.testing.allocator, state_b);
    defer std.testing.allocator.free(encoded_b);
    try std.testing.expectEqualSlices(u8, encoded_a, encoded_b);
}

test "StaticMachine round trips immutable string-list schema carriers" {
    const items = [_][]const u8{ "alpha", "beta" };
    const state = try ImmutableStringListCarrierMachine.initialState(
        std.testing.allocator,
        .{ImmutableStringListCarrier{ .items = &items }},
    );
    defer ImmutableStringListCarrierMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try ImmutableStringListCarrierMachine.reduce(state, &fuel)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    const payload = try request.payload(ImmutableStringListCarrier);
    try std.testing.expectEqual(@as(usize, 2), payload.items.len);
    try std.testing.expectEqualStrings("alpha", payload.items[0]);
    try std.testing.expectEqualStrings("beta", payload.items[1]);

    const encoded = try ImmutableStringListCarrierMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try ImmutableStringListCarrierMachine.decodeState(std.testing.allocator, encoded);
    defer ImmutableStringListCarrierMachine.deinitState(restored);
    const restored_request = switch (try ImmutableStringListCarrierMachine.current(restored)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    const restored_payload = try restored_request.payload(ImmutableStringListCarrier);
    try std.testing.expectEqualStrings("alpha", restored_payload.items[0]);
    try std.testing.expectEqualStrings("beta", restored_payload.items[1]);

    try ImmutableStringListCarrierMachine.@"resume"(restored, restored_request, @as(i32, 7));
    var result = switch (try ImmutableStringListCarrierMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value());
}

test "StaticMachine contract identity binds logical enum semantics" {
    try std.testing.expectEqual(
        EnumMachineA.Manifest.canonical_plan_fingerprint,
        EnumMachineB.Manifest.canonical_plan_fingerprint,
    );
    try std.testing.expectEqual(
        EnumMachineA.Manifest.canonical_plan_fingerprint,
        EnumMachineWide.Manifest.canonical_plan_fingerprint,
    );
    try std.testing.expect(EnumMachineA.Manifest.machine_contract_fingerprint != EnumMachineB.Manifest.machine_contract_fingerprint);
    try std.testing.expectEqual(
        EnumMachineA.Manifest.machine_contract_fingerprint,
        EnumMachineWide.Manifest.machine_contract_fingerprint,
    );

    const state = try EnumMachineA.initialState(std.testing.allocator, .{EnumMappingA.ready});
    defer EnumMachineA.deinitState(state);
    const encoded = try EnumMachineA.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectError(error.ProgramContractViolation, EnumMachineB.decodeState(std.testing.allocator, encoded));
    const wide_state = try EnumMachineWide.decodeState(std.testing.allocator, encoded);
    defer EnumMachineWide.deinitState(wide_state);
    const wide_encoded = try EnumMachineWide.encodeState(std.testing.allocator, wide_state);
    defer std.testing.allocator.free(wide_encoded);
    try std.testing.expectEqualSlices(u8, encoded, wide_encoded);
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
    try std.testing.expectEqual(@as(u64, 10707283190065710798), inner_after.fingerprint());

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
    try std.testing.expect(restored_inner_after.token != 0);
    try std.testing.expect(inner_after._session_id != restored_inner_after._session_id);
    try std.testing.expectEqual(inner_after.fingerprint(), restored_inner_after.fingerprint());
    const reencoded = try AfterContractMachineA.encodeState(std.testing.allocator, restored);
    defer std.testing.allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, encoded, reencoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterContractMachineA.resumeAfter(restored, inner_after, true),
    );
    var zero_token = restored_inner_after;
    zero_token.token = 0;
    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterContractMachineA.resumeAfter(restored, zero_token, true),
    );
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

test "StaticMachine after site witness binds the handler-derived output ref" {
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
    const after = switch (try AfterContractMachineA.reduce(state, &fuel)) {
        .after => |request| request,
        else => return error.UnexpectedTransition,
    };
    const Site = AfterContractMachineA.EffectRow.afterSite("inner", "inner", 0);
    try after.expectSite(Site);

    var forged = after;
    forged.output_ref = .{ .codec = .i32 };
    try std.testing.expect(!forged.matches(Site));
    try std.testing.expectError(error.ProgramContractViolation, forged.expectSite(Site));
    try std.testing.expectError(error.ProgramContractViolation, forged.as(Site));
    try std.testing.expectError(
        error.ProgramContractViolation,
        forged.responseTraceFor(Site, @as(i32, 1)),
    );
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

test "StaticMachine after closure preserves repeated-condition correlation" {
    const first_state = try MutuallyExclusiveAfterMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 0)},
    );
    defer MutuallyExclusiveAfterMachine.deinitState(first_state);
    var fuel: u64 = 100;
    const first_outer_request = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(first_state, first_outer_request, @as(i32, 0));
    const first_request = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(first_state, first_request, @as(i32, 7));
    const first_after = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.resumeAfter(first_state, first_after, true);
    const first_outer_after = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.resumeAfter(first_state, first_outer_after, @as([]const u8, "matched"));
    var first_result = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer first_result.deinit();
    try std.testing.expectEqualStrings("matched", first_result.value());

    const second_state = try MutuallyExclusiveAfterMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 1)},
    );
    defer MutuallyExclusiveAfterMachine.deinitState(second_state);
    fuel = 100;
    const second_outer_request = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(second_state, second_outer_request, @as(i32, 0));
    const second_request = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(second_state, second_request, @as(i32, 9));
    const second_after = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.resumeAfter(second_state, second_after, true);
    const second_outer_after = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.resumeAfter(second_state, second_outer_after, @as([]const u8, "matched"));
    var second_result = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer second_result.deinit();
    try std.testing.expectEqualStrings("matched", second_result.value());
}

test "StaticMachine outermost after closure preserves repeated-condition correlation" {
    const state = try CorrelatedOutermostAfterMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 0)},
    );
    defer CorrelatedOutermostAfterMachine.deinitState(state);
    var fuel: u64 = 100;
    const outer_request = switch (try CorrelatedOutermostAfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try CorrelatedOutermostAfterMachine.@"resume"(state, outer_request, @as(i32, 1));
    const inner_request = switch (try CorrelatedOutermostAfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try CorrelatedOutermostAfterMachine.@"resume"(state, inner_request, @as(i32, 7));
    const inner_after = switch (try CorrelatedOutermostAfterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try CorrelatedOutermostAfterMachine.resumeAfter(state, inner_after, true);
    const outer_after = switch (try CorrelatedOutermostAfterMachine.reduce(state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    try CorrelatedOutermostAfterMachine.resumeAfter(state, outer_after, @as([]const u8, "matched"));
    var result = switch (try CorrelatedOutermostAfterMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("matched", result.value());
}

test "StaticMachine rejects contradictory repeated-condition after segments" {
    const first_state = try MutuallyExclusiveAfterMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 0)},
    );
    defer MutuallyExclusiveAfterMachine.deinitState(first_state);
    var fuel: u64 = 100;
    const first_outer = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(first_state, first_outer, @as(i32, 0));
    const first_request = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(first_state, first_request, @as(i32, 7));
    _ = switch (try MutuallyExclusiveAfterMachine.reduce(first_state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    const first_encoded = try MutuallyExclusiveAfterMachine.encodeState(std.testing.allocator, first_state);
    defer std.testing.allocator.free(first_encoded);

    const second_state = try MutuallyExclusiveAfterMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 1)},
    );
    defer MutuallyExclusiveAfterMachine.deinitState(second_state);
    fuel = 100;
    const second_outer = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(second_state, second_outer, @as(i32, 0));
    const second_request = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try MutuallyExclusiveAfterMachine.@"resume"(second_state, second_request, @as(i32, 9));
    _ = switch (try MutuallyExclusiveAfterMachine.reduce(second_state, &fuel)) {
        .after => |after| after,
        else => return error.UnexpectedTransition,
    };
    const second_encoded = try MutuallyExclusiveAfterMachine.encodeState(std.testing.allocator, second_state);
    defer std.testing.allocator.free(second_encoded);

    const first_payload = first_encoded[0 .. first_encoded.len - 8];
    const second_payload = second_encoded[0 .. second_encoded.len - 8];
    const first_core_offset = try stateCoreOffset(first_payload);
    const second_core_offset = try stateCoreOffset(second_payload);
    try std.testing.expectEqual(first_core_offset, second_core_offset);
    const after_count_offset = first_core_offset + 8 + 8 + 1;
    const entries_offset = after_count_offset + 8;
    try std.testing.expectEqual(@as(u64, 2), std.mem.readInt(u64, first_payload[after_count_offset..][0..8], .little));
    try std.testing.expectEqual(@as(u64, 2), std.mem.readInt(u64, second_payload[after_count_offset..][0..8], .little));

    const after_entry_bytes = 6;
    const forged = try std.testing.allocator.alloc(u8, second_encoded.len + after_entry_bytes);
    defer std.testing.allocator.free(forged);
    const outer_end = entries_offset + after_entry_bytes;
    @memcpy(forged[0..outer_end], second_payload[0..outer_end]);
    @memcpy(
        forged[outer_end .. outer_end + after_entry_bytes],
        first_payload[outer_end .. outer_end + after_entry_bytes],
    );
    @memcpy(
        forged[outer_end + after_entry_bytes .. forged.len - 8],
        second_payload[outer_end..],
    );
    std.mem.writeInt(u64, forged[after_count_offset..][0..8], 3, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        MutuallyExclusiveAfterMachine.decodeState(std.testing.allocator, forged),
    );
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

fn omitCanonicalLocalValue(
    encoded: []const u8,
    local_tag_offset: usize,
    value_byte_count: usize,
) ![]u8 {
    if (local_tag_offset + 1 + value_byte_count > encoded.len - 8) return error.BadLength;
    try std.testing.expectEqual(@as(u8, 1), encoded[local_tag_offset]);
    const forged = try std.testing.allocator.alloc(u8, encoded.len - value_byte_count);
    @memcpy(forged[0..local_tag_offset], encoded[0..local_tag_offset]);
    forged[local_tag_offset] = 0;
    @memcpy(
        forged[local_tag_offset + 1 .. forged.len - 8],
        encoded[local_tag_offset + 1 + value_byte_count .. encoded.len - 8],
    );
    refreshStateChecksum(forged);
    return forged;
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

test "StaticMachine rejects alternate canonical unit presence tags" {
    const state = try UnitLocalMachine.initialState(std.testing.allocator, .{});
    defer UnitLocalMachine.deinitState(state);
    const encoded = try UnitLocalMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, encoded[locals_count_offset..][0..8], .little));
    const local_tag_offset = locals_count_offset + 8 + 2;
    const last_return_tag_offset = local_tag_offset + 1;
    try std.testing.expectEqual(@as(u8, 1), encoded[local_tag_offset]);
    try std.testing.expectEqual(@as(u8, 1), encoded[last_return_tag_offset]);

    const forged_local = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged_local);
    forged_local[local_tag_offset] = 0;
    refreshStateChecksum(forged_local);
    try std.testing.expectError(
        error.ProgramContractViolation,
        UnitLocalMachine.decodeState(std.testing.allocator, forged_local),
    );

    const forged_last_return = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged_last_return);
    forged_last_return[last_return_tag_offset] = 0;
    refreshStateChecksum(forged_last_return);
    try std.testing.expectError(
        error.ProgramContractViolation,
        UnitLocalMachine.decodeState(std.testing.allocator, forged_last_return),
    );
}

test "StaticMachine rejects a canonical state missing an entry parameter" {
    const state = try UsizeIdentityMachine.initialState(std.testing.allocator, .{@as(usize, 7)});
    defer UsizeIdentityMachine.deinitState(state);
    const encoded = try UsizeIdentityMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const local_tag_offset = locals_count_offset + 8 + 2;
    const forged = try omitCanonicalLocalValue(encoded, local_tag_offset, 8);
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        UsizeIdentityMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a canonical state missing an already computed local" {
    const state = try PureMachine.initialState(std.testing.allocator, .{});
    defer PureMachine.deinitState(state);
    var fuel: u64 = 1;
    switch (try PureMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try PureMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const local_tag_offset = locals_count_offset + 8 + 2;
    const forged = try omitCanonicalLocalValue(encoded, local_tag_offset, 4);
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        PureMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine local presence follows the exact continuation" {
    const state = try ConditionalLocalMachine.initialState(std.testing.allocator, .{@as(i32, 0)});
    defer ConditionalLocalMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try ConditionalLocalMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try ConditionalLocalMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const locals_offset = locals_count_offset + 8;
    const encoded_i32_local_size = 2 + 1 + 4;
    const encoded_bool_local_size = 2 + 1 + 1;
    const value_tag_offset = locals_offset + encoded_i32_local_size + encoded_bool_local_size + 2;
    const forged = try omitCanonicalLocalValue(encoded, value_tag_offset, 4);
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        ConditionalLocalMachine.decodeState(std.testing.allocator, forged),
    );

    const other_state = try ConditionalLocalMachine.initialState(std.testing.allocator, .{@as(i32, 1)});
    defer ConditionalLocalMachine.deinitState(other_state);
    fuel = 100;
    switch (try ConditionalLocalMachine.reduce(other_state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const other_encoded = try ConditionalLocalMachine.encodeState(std.testing.allocator, other_state);
    defer std.testing.allocator.free(other_encoded);
    const other_restored = try ConditionalLocalMachine.decodeState(std.testing.allocator, other_encoded);
    ConditionalLocalMachine.deinitState(other_restored);
}

test "StaticMachine local presence preserves repeated-condition authority" {
    const state = try CorrelatedAbsentLocalMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 1)},
    );
    defer CorrelatedAbsentLocalMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try CorrelatedAbsentLocalMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try CorrelatedAbsentLocalMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try CorrelatedAbsentLocalMachine.decodeState(std.testing.allocator, encoded);
    CorrelatedAbsentLocalMachine.deinitState(restored);
}

test "StaticMachine local presence preserves exact predicate rewrite authority" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try RewrittenPredicateAbsentLocalProgram.Session.startWithArgs(
        &runtime,
        .{},
        .{@as(i32, 1)},
    );
    defer session.deinit();
    const session_request = switch (try session.next()) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };

    const state = try RewrittenPredicateAbsentLocalMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 1)},
    );
    defer RewrittenPredicateAbsentLocalMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try RewrittenPredicateAbsentLocalMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(session_request.instruction_index, request.instruction_index);

    const encoded = try RewrittenPredicateAbsentLocalMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try RewrittenPredicateAbsentLocalMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer RewrittenPredicateAbsentLocalMachine.deinitState(restored);
    const restored_request = switch (try RewrittenPredicateAbsentLocalMachine.current(restored)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };

    try session.@"resume"(session_request, {});
    try RewrittenPredicateAbsentLocalMachine.@"resume"(restored, restored_request, {});
    var session_result = switch (try session.next()) {
        .done => |value| value,
        else => return error.UnexpectedTransition,
    };
    defer session_result.deinit();
    var result = switch (try RewrittenPredicateAbsentLocalMachine.reduce(restored, &fuel)) {
        .done => |value| value,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(session_result.value, result.value());
    try std.testing.expectEqual(@as(i32, 9), result.value());
}

test "StaticMachine control validation budgets absent locals by path states" {
    const state = try ControlValidationLocalWorkMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 0)},
    );
    defer ControlValidationLocalWorkMachine.deinitState(state);
    try ControlValidationLocalWorkMachine.validateState(state);
}

test "StaticMachine rejects a canonical state missing a resumed operation result" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.@"resume"(state, request, @as(i32, 10));
    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 1);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const local_tag_offset = locals_count_offset + 8 + 2;
    const forged = try omitCanonicalLocalValue(encoded, local_tag_offset, 4);
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        AfterMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a canonical state missing a returned helper result" {
    const state = try HelperMachine.initialState(std.testing.allocator, .{});
    defer HelperMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try HelperMachine.reduce(state, &fuel)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    try HelperMachine.@"resume"(state, request, @as(i32, 41));
    fuel = 1;
    switch (try HelperMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    fuel = 1;
    switch (try HelperMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try HelperMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const local_tag_offset = locals_count_offset + 8 + 2;
    const forged = try omitCanonicalLocalValue(encoded, local_tag_offset, 4);
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        HelperMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine validates helper locals against the effective completion codec" {
    const state = try HelperValueCompletionMachine.initialState(std.testing.allocator, .{});
    defer HelperValueCompletionMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try HelperValueCompletionMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try HelperValueCompletionMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const frame_offset = try singleFrameOffset(encoded[0 .. encoded.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const local_tag_offset = locals_count_offset + 8 + 2;
    const forged = try omitCanonicalLocalValue(encoded, local_tag_offset, 4);
    defer std.testing.allocator.free(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        HelperValueCompletionMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a forged bare usize outside the canonical domain" {
    if (@bitSizeOf(usize) <= 32) return;
    const state = try UsizeIdentityMachine.initialState(std.testing.allocator, .{@as(usize, std.math.maxInt(u32))});
    defer UsizeIdentityMachine.deinitState(state);
    const encoded = try UsizeIdentityMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, forged[locals_count_offset..][0..8], .little));
    const local_value_offset = locals_count_offset + 8 + 2 + 1;
    try std.testing.expectEqual(
        @as(u64, std.math.maxInt(u32)),
        std.mem.readInt(u64, forged[local_value_offset..][0..8], .little),
    );
    std.mem.writeInt(u64, forged[local_value_offset..][0..8], @as(u64, std.math.maxInt(u32)) + 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        UsizeIdentityMachine.decodeState(std.testing.allocator, forged),
    );
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

test "StaticMachine rejects a pending after-producing operation with a full after stack" {
    const state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    _ = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    const old_payload = encoded[0 .. encoded.len - 8];
    const core_offset = try stateCoreOffset(old_payload);
    const after_count_offset = core_offset + 8 + 8 + 1;
    const entries_offset = after_count_offset + 8;
    const entry_count = AfterMachine.Manifest.maximum_interpreter_fuel;
    const entry_bytes = try std.math.mul(usize, entry_count, 6);
    const forged = try std.testing.allocator.alloc(u8, encoded.len + entry_bytes);
    defer std.testing.allocator.free(forged);
    @memcpy(forged[0..entries_offset], old_payload[0..entries_offset]);
    std.mem.writeInt(u64, forged[after_count_offset..][0..8], @intCast(entry_count), .little);
    @memset(forged[entries_offset..][0..entry_bytes], 0);
    @memcpy(forged[entries_offset + entry_bytes .. forged.len - 8], old_payload[entries_offset..]);
    refreshStateChecksum(forged);

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

test "StaticMachine non-completing child secures unreachable parent locals" {
    const state = try NonCompletingConditionalParentMachine.initialState(
        std.testing.allocator,
        .{true},
    );
    defer NonCompletingConditionalParentMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try NonCompletingConditionalParentMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    try NonCompletingConditionalParentMachine.validateState(state);

    const encoded = try NonCompletingConditionalParentMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try NonCompletingConditionalParentMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer NonCompletingConditionalParentMachine.deinitState(restored);
    try NonCompletingConditionalParentMachine.validateState(restored);
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

test "StaticMachine rejects retained predicate authority that differs from decoded source local" {
    const state = try CorrelatedAbsentLocalMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 0)},
    );
    defer CorrelatedAbsentLocalMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try CorrelatedAbsentLocalMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try CorrelatedAbsentLocalMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    try std.testing.expectEqual(
        @as(u64, 3),
        std.mem.readInt(u64, forged[locals_count_offset..][0..8], .little),
    );
    const input_value_offset = locals_count_offset + 8 + 2 + 1;
    try std.testing.expectEqual(
        @as(i32, 0),
        std.mem.readInt(i32, forged[input_value_offset..][0..4], .little),
    );
    std.mem.writeInt(i32, forged[input_value_offset..][0..4], 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        CorrelatedAbsentLocalMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a forged earlier predicate that gates an operation suspension" {
    const state = try GatedPredicateAuthorityMachine.initialState(
        std.testing.allocator,
        .{ @as(i32, 0), @as(i32, 1) },
    );
    defer GatedPredicateAuthorityMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try GatedPredicateAuthorityMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try GatedPredicateAuthorityMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try GatedPredicateAuthorityMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    GatedPredicateAuthorityMachine.deinitState(restored);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    try std.testing.expectEqual(
        @as(u64, 3),
        std.mem.readInt(u64, forged[locals_count_offset..][0..8], .little),
    );
    const first_value_offset = locals_count_offset + 8 + 2 + 1;
    try std.testing.expectEqual(
        @as(i32, 0),
        std.mem.readInt(i32, forged[first_value_offset..][0..4], .little),
    );
    std.mem.writeInt(i32, forged[first_value_offset..][0..4], 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        GatedPredicateAuthorityMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine rejects a forged parent predicate that gates a helper suspension" {
    const state = try HelperGatedPredicateAuthorityMachine.initialState(
        std.testing.allocator,
        .{ @as(i32, 0), @as(i32, 1) },
    );
    defer HelperGatedPredicateAuthorityMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try HelperGatedPredicateAuthorityMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try HelperGatedPredicateAuthorityMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try HelperGatedPredicateAuthorityMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    HelperGatedPredicateAuthorityMachine.deinitState(restored);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const payload = forged[0 .. forged.len - 8];
    const core_offset = try stateCoreOffset(payload);
    const after_count_offset = core_offset + 8 + 8 + 1;
    try std.testing.expectEqual(
        @as(u64, 0),
        std.mem.readInt(u64, payload[after_count_offset..][0..8], .little),
    );
    const frame_count_offset = after_count_offset + 8;
    try std.testing.expectEqual(
        @as(u64, 2),
        std.mem.readInt(u64, payload[frame_count_offset..][0..8], .little),
    );
    const parent_frame_offset = frame_count_offset + 8;
    const locals_count_offset = parent_frame_offset + 6 * 8 + 2 + 2;
    try std.testing.expectEqual(
        @as(u64, 3),
        std.mem.readInt(u64, payload[locals_count_offset..][0..8], .little),
    );
    const first_value_offset = locals_count_offset + 8 + 2 + 1;
    try std.testing.expectEqual(
        @as(i32, 0),
        std.mem.readInt(i32, payload[first_value_offset..][0..4], .little),
    );
    std.mem.writeInt(i32, forged[first_value_offset..][0..4], 1, .little);
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        HelperGatedPredicateAuthorityMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine preserves in-place condition state across fuel yield" {
    const state = try InPlaceBranchCacheMachine.initialState(std.testing.allocator, .{true});
    defer InPlaceBranchCacheMachine.deinitState(state);
    var fuel: u64 = 1;
    switch (try InPlaceBranchCacheMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    try InPlaceBranchCacheMachine.validateState(state);

    const encoded = try InPlaceBranchCacheMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try InPlaceBranchCacheMachine.decodeState(std.testing.allocator, encoded);
    defer InPlaceBranchCacheMachine.deinitState(restored);
    fuel = 100;
    var result = switch (try InPlaceBranchCacheMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 2), result.value());
}

test "StaticMachine rejects a forged in-place boolean predicate source" {
    const state = try InPlaceBranchCacheMachine.initialState(std.testing.allocator, .{true});
    defer InPlaceBranchCacheMachine.deinitState(state);
    var fuel: u64 = 1;
    switch (try InPlaceBranchCacheMachine.reduce(state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const encoded = try InPlaceBranchCacheMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    try std.testing.expectEqual(
        @as(u64, 2),
        std.mem.readInt(u64, forged[locals_count_offset..][0..8], .little),
    );
    const condition_value_offset = locals_count_offset + 8 + 2 + 1;
    try std.testing.expectEqual(@as(u8, 0), forged[condition_value_offset]);
    forged[condition_value_offset] = 1;
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        InPlaceBranchCacheMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine canonical condition authority preserves cached condition" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try RewrittenSourceBranchCacheProgram.Session.startWithArgs(
        &runtime,
        .{},
        .{@as(i32, 0)},
    );
    defer session.deinit();
    const session_request = switch (try session.next()) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };

    const state = try RewrittenSourceBranchCacheMachine.initialState(
        std.testing.allocator,
        .{@as(i32, 0)},
    );
    defer RewrittenSourceBranchCacheMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try RewrittenSourceBranchCacheMachine.reduce(state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(session_request.instruction_index, request.instruction_index);
    try RewrittenSourceBranchCacheMachine.validateState(state);

    const encoded = try RewrittenSourceBranchCacheMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try RewrittenSourceBranchCacheMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer RewrittenSourceBranchCacheMachine.deinitState(restored);
    const restored_request = switch (try RewrittenSourceBranchCacheMachine.current(restored)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };

    try session.@"resume"(session_request, {});
    try RewrittenSourceBranchCacheMachine.@"resume"(restored, restored_request, {});
    var session_result = switch (try session.next()) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer session_result.deinit();
    var static_result = switch (try RewrittenSourceBranchCacheMachine.reduce(restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer static_result.deinit();
    try std.testing.expectEqual(@as(i32, 1), session_result.value);
    try std.testing.expectEqual(session_result.value, static_result.value());
}

test "StaticMachine canonical condition authority rejects incompatible sum predicates" {
    const state = try CorrelatedBinarySumMachine.initialState(
        std.testing.allocator,
        .{BinaryConditionChoice.first},
    );
    defer CorrelatedBinarySumMachine.deinitState(state);
    var fuel: u64 = 100;
    switch (try CorrelatedBinarySumMachine.reduce(state, &fuel)) {
        .request => {},
        else => return error.UnexpectedTransition,
    }
    try CorrelatedBinarySumMachine.validateState(state);

    const encoded = try CorrelatedBinarySumMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try CorrelatedBinarySumMachine.decodeState(std.testing.allocator, encoded);
    CorrelatedBinarySumMachine.deinitState(restored);

    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 0);
    const last_condition_offset = frame_offset + 6 * 8;
    try std.testing.expectEqual(@as(u8, 0), forged[last_condition_offset]);
    forged[last_condition_offset] = 1;
    refreshStateChecksum(forged);

    try std.testing.expectError(
        error.ProgramContractViolation,
        CorrelatedBinarySumMachine.decodeState(std.testing.allocator, forged),
    );
}

test "StaticMachine after contracts preserve binary sum complement correlation" {
    try std.testing.expectEqual(
        @as(usize, 4),
        CorrelatedBinarySumAfterMachine.Manifest.operation_site_count,
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        CorrelatedBinarySumAfterMachine.Manifest.after_site_count,
    );
}

test "Program.Session remains available for independent predicate families" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try InterleavedConditionPredicatesProgram.Session.startWithArgs(
        &runtime,
        .{},
        .{ @as(i32, 0), @as(i32, 1) },
    );
    defer session.deinit();
    switch (try session.next()) {
        .done => {},
        else => return error.UnexpectedTransition,
    }
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

test "StaticMachine binds the first unwind value to the completed function value" {
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
    const frame_offset = try singleFrameOffset(forged[0 .. forged.len - 8], 2);
    const locals_count_offset = frame_offset + 6 * 8 + 2;
    const locals_offset = locals_count_offset + 8;
    const encoded_i32_local_size = 2 + 1 + 4;
    const second_local_value = locals_offset + encoded_i32_local_size + 2 + 1;
    const last_return_value = locals_offset + 2 * encoded_i32_local_size + 1;
    try std.testing.expectEqual(@as(i32, 7), std.mem.readInt(i32, forged[second_local_value..][0..4], .little));
    try std.testing.expectEqual(@as(i32, 7), std.mem.readInt(i32, forged[last_return_value..][0..4], .little));
    std.mem.writeInt(i32, forged[second_local_value..][0..4], 8, .little);
    std.mem.writeInt(i32, forged[last_return_value..][0..4], 8, .little);
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

test "StaticMachine bounded validation does not allocate" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const state = try OneEffectMachine.initialState(failing.allocator(), .{});
    defer OneEffectMachine.deinitState(state);
    var fuel: u64 = 100;
    _ = switch (try OneEffectMachine.reduce(state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };

    const allocations_before = failing.allocations;
    failing.fail_index = allocations_before;
    try OneEffectMachine.validateState(state);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(allocations_before, failing.allocations);
}

test "StaticMachine after reservation failure leaves the request retryable" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const state = try AfterMachine.initialState(failing.allocator(), .{});
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try AfterMachine.reduce(state, &fuel)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    const before = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);

    failing.fail_index = failing.allocations;
    try std.testing.expectError(error.OutOfMemory, AfterMachine.@"resume"(state, request, @as(i32, 10)));
    try AfterMachine.validateState(state);
    const current = switch (try AfterMachine.current(state)) {
        .request => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(request.fingerprint(), current.fingerprint());
    const after_failure = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after_failure);
    try std.testing.expectEqualSlices(u8, before, after_failure);

    failing.fail_index = std.math.maxInt(usize);
    try AfterMachine.@"resume"(state, request, @as(i32, 10));
    const after = switch (try AfterMachine.reduce(state, &fuel)) {
        .after => |parked| parked,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.resumeAfter(state, after, @as(i32, 15));
    var result = switch (try AfterMachine.reduce(state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 15), result.value());
}

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

    const before = try StringMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    const fuel_before = fuel;
    const completed = StringMachine.reduce(state, &fuel) catch |err| switch (err) {
        error.OutOfMemory => {
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(fuel_before, fuel);
            try StringMachine.validateState(state);
            const after = try StringMachine.encodeState(std.testing.allocator, state);
            defer std.testing.allocator.free(after);
            try std.testing.expectEqualSlices(u8, before, after);
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
