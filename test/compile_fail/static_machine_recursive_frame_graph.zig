// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const nested_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const helper = boundary.ir.builder.function(1);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callHelper(root, null, helper, null) catch unreachable,
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(boundary.ir.ValueCodec.unit),
            .string_literal = nested_metadata,
        },
    };
    const functions = [_]boundary.ir.plan.Function{
        .{ .symbol_name = "run", .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 0, .first_block = 0, .entry_block = 0, .block_count = 1, .first_instruction = 0, .instruction_count = 1 },
        .{ .symbol_name = "loop", .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 0, .first_block = 1, .entry_block = 0, .block_count = 1, .first_instruction = 1, .instruction_count = 1 },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{ .{ .kind = .return_unit }, .{ .kind = .return_unit } };
    return boundary.ir.builder.finish(.{
        .label = "static-machine-recursive-frame-graph",
        .ir_hash = 2,
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

const Body = struct {
    pub const compiled_plan = plan();
    pub const nested_with_targets = .{boundary.ir.NestedWithTarget{
        .metadata = nested_metadata,
        .function_index = 0,
    }};
};
const Program = boundary.program("static-machine-recursive-frame-graph", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{});

test "StaticMachine rejects recursive helper and nested-provider frame graphs" {
    _ = Machine;
}
