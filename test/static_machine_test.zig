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

const TinyStateMachine = boundary.staticMachine(OneEffectProgram, .{ .maximum_state_bytes = 32 });

test "StaticMachine executes a pure scalar program" {
    var state = try PureMachine.initialState(std.testing.allocator, .{});
    defer PureMachine.deinitState(&state);
    var fuel: u64 = 100;
    var result = switch (try PureMachine.reduce(&state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value);
}

test "StaticMachine state survives a canonical parked-state round trip" {
    var state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(&state);

    var fuel: u64 = 100;
    const request = switch (try OneEffectMachine.reduce(&state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqualStrings("payload", try request.payload([]const u8));

    const encoded = try OneEffectMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(encoded);
    var restored = try OneEffectMachine.decodeState(std.testing.allocator, encoded);
    defer OneEffectMachine.deinitState(&restored);

    const restored_request = switch (try OneEffectMachine.current(&restored)) {
        .request => |current| current,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(request.trace().operation_site_fingerprint, restored_request.trace().operation_site_fingerprint);
    try std.testing.expectEqualStrings("payload", try restored_request.payload([]const u8));

    try OneEffectMachine.@"resume"(&restored, restored_request, @as(i32, 41));
    var result = switch (try OneEffectMachine.reduce(&restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "StaticMachine preserves helper suspension across state bytes" {
    var state = try HelperMachine.initialState(std.testing.allocator, .{});
    defer HelperMachine.deinitState(&state);

    var fuel: u64 = 100;
    _ = switch (try HelperMachine.reduce(&state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    const encoded = try HelperMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(encoded);
    var restored = try HelperMachine.decodeState(std.testing.allocator, encoded);
    defer HelperMachine.deinitState(&restored);

    const request = switch (try HelperMachine.current(&restored)) {
        .request => |current| current,
        else => return error.UnexpectedTransition,
    };
    try HelperMachine.@"resume"(&restored, request, @as(i32, 40));
    var result = switch (try HelperMachine.reduce(&restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "StaticMachine matches Program.Session observations" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var session = try OneEffectProgram.Session.start(&runtime, .{});
    defer session.deinit();
    var state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(&state);

    const session_request = switch (try session.next()) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    var fuel: u64 = 100;
    const static_request = switch (try OneEffectMachine.reduce(&state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectEqual(session_request.trace().operation_site_fingerprint, static_request.trace().operation_site_fingerprint);
    try std.testing.expectEqualStrings(try session_request.payload([]const u8), try static_request.payload([]const u8));

    try session.@"resume"(session_request, @as(i32, 41));
    try OneEffectMachine.@"resume"(&state, static_request, @as(i32, 41));
    var session_result = switch (try session.next()) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer session_result.deinit();
    var static_result = switch (try OneEffectMachine.reduce(&state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer static_result.deinit();
    try std.testing.expectEqual(session_result.value, static_result.value);
}

test "StaticMachine fuel yield is explicit and non-mutating" {
    var state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(&state);
    const before = try OneEffectMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(before);

    var fuel: u64 = 0;
    switch (try OneEffectMachine.reduce(&state, &fuel)) {
        .yielded_fuel => {},
        else => return error.UnexpectedTransition,
    }
    const after = try OneEffectMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "StaticMachine resumes from partial deterministic fuel" {
    var state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(&state);

    var yield_count: usize = 0;
    var request: ?OneEffectMachine.Request = null;
    for (0..8) |_| {
        var fuel: u64 = 1;
        switch (try OneEffectMachine.reduce(&state, &fuel)) {
            .yielded_fuel => {
                yield_count += 1;
                const encoded = try OneEffectMachine.encodeState(std.testing.allocator, &state);
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
    var state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(&state);
    var fuel: u64 = 100;
    const original = switch (try OneEffectMachine.reduce(&state, &fuel)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(&state, original, @as(bool, true)),
    );

    const encoded = try OneEffectMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(encoded);
    var restored = try OneEffectMachine.decodeState(std.testing.allocator, encoded);
    defer OneEffectMachine.deinitState(&restored);
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(&restored, original, @as(i32, 41)),
    );
    const current = switch (try OneEffectMachine.current(&restored)) {
        .request => |request| request,
        else => return error.UnexpectedTransition,
    };
    try OneEffectMachine.@"resume"(&restored, current, @as(i32, 41));
    try std.testing.expectError(
        error.ProgramContractViolation,
        OneEffectMachine.@"resume"(&restored, current, @as(i32, 41)),
    );
}

test "StaticMachine state codec rejects changed and trailing bytes" {
    var state = try OneEffectMachine.initialState(std.testing.allocator, .{});
    defer OneEffectMachine.deinitState(&state);
    var fuel: u64 = 100;
    _ = try OneEffectMachine.reduce(&state, &fuel);
    const encoded = try OneEffectMachine.encodeState(std.testing.allocator, &state);
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
    var state = try StringMachine.initialState(std.testing.allocator, .{});
    defer StringMachine.deinitState(&state);
    var fuel: u64 = 100;
    const request = switch (try StringMachine.reduce(&state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };

    const response = try std.testing.allocator.dupe(u8, "owned response");
    try StringMachine.@"resume"(&state, request, @as([]const u8, response));
    @memset(response, 'x');
    std.testing.allocator.free(response);

    var result = switch (try StringMachine.reduce(&state, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("owned response", result.value);
}

test "StaticMachine authored budget failure is terminal and never a fuel yield" {
    var state = try AuthoredBudgetMachine.initialState(std.testing.allocator, .{});
    defer AuthoredBudgetMachine.deinitState(&state);
    var fuel: u64 = 100;
    try std.testing.expectError(error.ExecutionBudgetExceeded, AuthoredBudgetMachine.reduce(&state, &fuel));
    try std.testing.expectError(error.ExecutionBudgetExceeded, AuthoredBudgetMachine.reduce(&state, &fuel));
    try std.testing.expectError(
        error.ProgramContractViolation,
        AuthoredBudgetMachine.encodeState(std.testing.allocator, &state),
    );
}

test "StaticMachine state surface does not expose the session core" {
    try std.testing.expect(!@hasDecl(OneEffectMachine.State, "next"));
    try std.testing.expect(!@hasDecl(OneEffectMachine.State, "nextWithFuel"));
    try std.testing.expect(!@hasDecl(OneEffectMachine.State, "encodeState"));
    try std.testing.expect(!@hasDecl(OneEffectMachine.State, "decodeState"));
}

test "StaticMachine enforces the state byte limit during encoding" {
    var state = try TinyStateMachine.initialState(std.testing.allocator, .{});
    defer TinyStateMachine.deinitState(&state);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TinyStateMachine.encodeState(std.testing.allocator, &state),
    );
}

test "StaticMachine canonical state ignores equal-value alias topology" {
    comptime {
        if (PairArgsMachine.InitialArgs != struct { []const u8, []const u8 }) {
            @compileError("StaticMachine InitialArgs must derive from Program entry parameters");
        }
    }

    const shared = "same";
    var shared_state = try PairArgsMachine.initialState(std.testing.allocator, .{ shared, shared });
    defer PairArgsMachine.deinitState(&shared_state);

    const first = try std.testing.allocator.dupe(u8, "same");
    defer std.testing.allocator.free(first);
    const second = try std.testing.allocator.dupe(u8, "same");
    defer std.testing.allocator.free(second);
    var separate_state = try PairArgsMachine.initialState(std.testing.allocator, .{ first, second });
    defer PairArgsMachine.deinitState(&separate_state);

    const shared_bytes = try PairArgsMachine.encodeState(std.testing.allocator, &shared_state);
    defer std.testing.allocator.free(shared_bytes);
    const separate_bytes = try PairArgsMachine.encodeState(std.testing.allocator, &separate_state);
    defer std.testing.allocator.free(separate_bytes);
    try std.testing.expectEqualSlices(u8, shared_bytes, separate_bytes);
}

test "StaticMachine validates and restores a resumed after checkpoint" {
    var state = try AfterMachine.initialState(std.testing.allocator, .{});
    defer AfterMachine.deinitState(&state);
    var fuel: u64 = 100;
    const request = switch (try AfterMachine.reduce(&state, &fuel)) {
        .request => |value| value,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.@"resume"(&state, request, @as(i32, 10));
    const after = switch (try AfterMachine.reduce(&state, &fuel)) {
        .after => |value| value,
        else => return error.UnexpectedTransition,
    };
    try AfterMachine.resumeAfter(&state, after, @as(i32, 15));

    const encoded = try AfterMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(encoded);
    var restored = try AfterMachine.decodeState(std.testing.allocator, encoded);
    defer AfterMachine.deinitState(&restored);
    var result = switch (try AfterMachine.reduce(&restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 15), result.value);
}

test "StaticMachine accepts and round trips a zero-instruction program" {
    var state = try ZeroMachine.initialState(std.testing.allocator, .{});
    defer ZeroMachine.deinitState(&state);
    const encoded = try ZeroMachine.encodeState(std.testing.allocator, &state);
    defer std.testing.allocator.free(encoded);
    var restored = try ZeroMachine.decodeState(std.testing.allocator, encoded);
    defer ZeroMachine.deinitState(&restored);
    var fuel: u64 = 10;
    var result = switch (try ZeroMachine.reduce(&restored, &fuel)) {
        .done => |done| done,
        else => return error.UnexpectedTransition,
    };
    defer result.deinit();
    try std.testing.expectEqual({}, result.value);
}

test "StaticMachine state binds the complete nested target contract" {
    try std.testing.expect(NestedFirstMachine.Manifest.machine_contract_fingerprint != NestedSecondMachine.Manifest.machine_contract_fingerprint);
    var state = try NestedFirstMachine.initialState(std.testing.allocator, .{});
    defer NestedFirstMachine.deinitState(&state);
    const encoded = try NestedFirstMachine.encodeState(std.testing.allocator, &state);
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
