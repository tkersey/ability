// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const Input = struct {
    value: i32,
};
const Schemas = boundary.ir.schema.Registry(.{Input});

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const input = boundary.ir.builder.local(root, 0);
    const first = boundary.ir.builder.local(root, 1);
    const second = boundary.ir.builder.local(root, 2);
    const condition = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .product_extract_field, .dst = first.index, .operand = input.index, .aux = 0 },
        .{ .kind = .product_extract_field, .dst = second.index, .operand = input.index, .aux = 0 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = first.index },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = second.index },
        boundary.ir.builder.returnValue(root, first) catch unreachable,
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
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = "static-machine-product-extract-predicate-copy",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &Schemas.value_schemas,
        .value_fields = &Schemas.value_fields,
        .value_variants = &Schemas.value_variants,
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .bool },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
    pub const value_schema_types = Schemas.value_schema_types;
};
const Program = boundary.program("static-machine-product-extract-predicate-copy", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

comptime {
    _ = Machine.Manifest;
}
