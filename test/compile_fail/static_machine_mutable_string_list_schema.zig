// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const Payload = struct {
    items: [][]const u8,
};
const Schemas = boundary.ir.schema.Registry(.{Payload});

fn plan() boundary.ir.ProgramPlan {
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
        .label = "static-machine-mutable-string-list-schema",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &Schemas.value_schemas,
        .value_fields = &Schemas.value_fields,
        .value_variants = &Schemas.value_variants,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

const Body = struct {
    pub const value_schema_types = .{Payload};
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-mutable-string-list-schema", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

test "StaticMachine rejects mutable string-list carriers inside schemas" {
    _ = Machine;
}
