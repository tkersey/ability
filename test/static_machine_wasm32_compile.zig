// zlinter-disable declaration_naming no_inferred_error_unions no_swallow_error no_undefined require_doc_comment
const boundary = @import("boundary");
const std = @import("std");

fn oneEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const resumed = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_usize, .dst = payload.index, .string_literal = "4294967295" },
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), payload) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .usize,
        .result_codec = .usize,
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
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "world",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "round_trip",
        .mode = .transform,
        .payload_codec = .usize,
        .resume_codec = .usize,
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
        .locals = &.{ .{ .codec = .usize }, .{ .codec = .usize } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn enumIdentityPlan(comptime Status: type) boundary.ir.ProgramPlan {
    const schemas = boundary.ir.schema.Registry(.{Status});
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
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = "static-machine-logical-enum-identity",
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &schemas.value_schemas,
        .value_fields = &schemas.value_fields,
        .value_variants = &schemas.value_variants,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

fn EnumIdentityBody(comptime Status: type) type {
    return struct {
        pub const value_schema_types = .{Status};
        pub const compiled_plan = enumIdentityPlan(Status);
    };
}

const TargetWcharStatus = enum(std.c.wchar_t) {
    ready = 1,
    waiting = 2,
};
const LogicalStatus = enum(i64) {
    ready = 1,
    waiting = 2,
};
const TargetWcharProgram = boundary.program(
    "static-machine-logical-enum-identity",
    struct {},
    EnumIdentityBody(TargetWcharStatus),
);
const LogicalProgram = boundary.program(
    "static-machine-logical-enum-identity",
    struct {},
    EnumIdentityBody(LogicalStatus),
);
const TargetWcharMachine = boundary.staticMachine(TargetWcharProgram, .{});
const LogicalMachine = boundary.staticMachine(LogicalProgram, .{});

comptime {
    if (TargetWcharMachine.Manifest.machine_contract_fingerprint !=
        LogicalMachine.Manifest.machine_contract_fingerprint)
    {
        @compileError("logical enum identity must not depend on target-local tag storage");
    }
}

const Body = struct {
    pub const compiled_plan = oneEffectPlan("static-machine-wasm32-smoke");
};
const Program = boundary.program("static-machine-wasm32-smoke", struct {}, Body);
const Machine = boundary.staticMachine(Program, .{ .maximum_state_bytes = 128 * 1024 });

var source_storage: [64 * 1024]u8 = undefined;
var image_storage: [128 * 1024]u8 = undefined;
var restored_storage: [64 * 1024]u8 = undefined;

export fn boundaryStaticMachineWasm32Smoke() u32 {
    const expected = @as(usize, std.math.maxInt(u32));
    var source = std.heap.FixedBufferAllocator.init(&source_storage);
    const state = Machine.initialState(source.allocator(), .{}) catch return 0;
    defer Machine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (Machine.reduce(state, &fuel) catch return 0) {
        .request => |request| request,
        else => return 0,
    };
    if ((request.payload(usize) catch return 0) != expected) return 0;

    var image = std.heap.FixedBufferAllocator.init(&image_storage);
    const encoded = Machine.encodeState(image.allocator(), state) catch return 0;
    var restored = std.heap.FixedBufferAllocator.init(&restored_storage);
    const restored_state = Machine.decodeState(restored.allocator(), encoded) catch return 0;
    defer Machine.deinitState(restored_state);
    const restored_request = switch (Machine.current(restored_state) catch return 0) {
        .request => |current| current,
        else => return 0,
    };
    if ((restored_request.payload(usize) catch return 0) != expected) return 0;
    Machine.@"resume"(restored_state, restored_request, expected) catch return 0;

    var result = switch (Machine.reduce(restored_state, &fuel) catch return 0) {
        .done => |done| done,
        else => return 0,
    };
    defer result.deinit();
    return if (result.value() == expected) 1 else 0;
}
