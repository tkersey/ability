// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");
const std = @import("std");

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
        .label = "static-machine-cross-machine-state",
        .ir_hash = 1,
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

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("static-machine-cross-machine-state", struct {}, Body);
const MachineA = boundary.staticMachine(Program, .{});
const MachineB = boundary.staticMachine(Program, .{ .debug_metadata = true });

test "StaticMachine State handles are nominal per machine" {
    const state = try MachineA.initialState(std.testing.allocator, .{});
    defer MachineA.deinitState(state);
    var fuel: u64 = 1;
    _ = try MachineB.reduce(state, &fuel);
}
