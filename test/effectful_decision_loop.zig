const agent_profile = @import("agent_profile");
const cir = @import("control_ir");
const std = @import("std");

const ModelInput = struct {
    observation: u32,
    remaining_budget: u32,
};

const Action = union(enum) {
    tool: u32,
    final: u32,
};

const AgentResult = struct {
    value: u32,
    remaining_budget: u32,
};

const ModelDecision = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.model-decision.v1";
    pub const Payload = ModelInput;
    pub const Resume = Action;
};

const ToolInvoke = struct {
    pub const id: u32 = 1;
    pub const semantic_identity = "test.tool-invoke.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const bool_type: cir.ValueType = .{ .scalar = .boolean };
const value_types = [_]cir.ValueType{
    u32_type, // v0 observation at loop header
    u32_type, // v1 remaining budget at loop header
    bool_type, // v2 budget exhausted
    u32_type, // v3 model observation
    u32_type, // v4 model budget
    .{ .schema = 0 }, // v5 ModelInput
    .{ .schema = 1 }, // v6 Action
    u32_type, // v7 budget after model response
    bool_type, // v8 action is final
    .{ .schema = 1 }, // v9 final Action
    u32_type, // v10 final budget
    u32_type, // v11 final value
    .{ .schema = 2 }, // v12 AgentResult
    .{ .schema = 1 }, // v13 tool Action
    u32_type, // v14 tool budget
    u32_type, // v15 tool payload
    u32_type, // v16 tool observation
    u32_type, // v17 budget before decrement
    u32_type, // v18 one
    u32_type, // v19 decremented budget
    .{ .schema = 0 }, // v20 entry ModelInput
    .{ .schema = 0 }, // v21 next ModelInput
};

const loop_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 0,
        .operands = &.{20},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{20},
        .operation = .{ .product_extract = 1 },
    },
    .{
        .kind = .compare_eq_zero,
        .result = 2,
        .operands = &.{1},
        .operation = .compare_eq_zero,
    },
};
const to_model = [_]cir.EdgeArgument{
    .{ .value = 0 },
    .{ .value = 1 },
};
const model_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 5,
        .operands = &.{ 3, 4 },
        .operation = .product_construct,
    },
};
const after_model = [_]cir.EdgeArgument{
    .@"resume",
    .{ .value = 4 },
};
const decide_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{6},
        .operation = .{ .sum_tag_is = 1 },
    },
};
const to_final = [_]cir.EdgeArgument{
    .{ .value = 6 },
    .{ .value = 7 },
};
const to_tool = [_]cir.EdgeArgument{
    .{ .value = 6 },
    .{ .value = 7 },
};
const final_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 11,
        .operands = &.{9},
        .operation = .{ .sum_extract = 1 },
    },
    .{
        .kind = .pure,
        .result = 12,
        .operands = &.{ 11, 10 },
        .operation = .product_construct,
    },
};
const tool_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 15,
        .operands = &.{13},
        .operation = .{ .sum_extract = 0 },
    },
};
const after_tool = [_]cir.EdgeArgument{
    .@"resume",
    .{ .value = 14 },
};
const decrement_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 18,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 19,
        .operands = &.{ 17, 18 },
        .operation = .integer_subtract,
    },
    .{
        .kind = .pure,
        .result = 21,
        .operands = &.{ 16, 19 },
        .operation = .product_construct,
    },
};
const repeat_loop = [_]cir.EdgeArgument{
    .{ .value = 21 },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .role = .loop_header,
        .parameters = &.{20},
        .instructions = &loop_instructions,
        .terminator = .{ .branch = .{
            .condition = 2,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2, .arguments = &to_model },
        } },
    },
    .{
        .id = 1,
        .role = .terminal_handoff,
        .terminator = .{ .fail = 0 },
    },
    .{
        .id = 2,
        .parameters = &.{ 3, 4 },
        .instructions = &model_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{5},
            .continuation = .{
                .target = 3,
                .arguments = &after_model,
            },
            .resume_type = .{ .schema = 1 },
        } },
    },
    .{
        .id = 3,
        .parameters = &.{ 6, 7 },
        .instructions = &decide_instructions,
        .terminator = .{ .branch = .{
            .condition = 8,
            .then_edge = .{ .target = 4, .arguments = &to_final },
            .else_edge = .{ .target = 5, .arguments = &to_tool },
        } },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{ 9, 10 },
        .instructions = &final_instructions,
        .terminator = .{ .return_value = 12 },
    },
    .{
        .id = 5,
        .parameters = &.{ 13, 14 },
        .instructions = &tool_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{15},
            .continuation = .{
                .target = 6,
                .arguments = &after_tool,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 6,
        .parameters = &.{ 16, 17 },
        .instructions = &decrement_instructions,
        .terminator = .{ .jump = .{
            .target = 0,
            .arguments = &repeat_loop,
        } },
    },
};

const Body = struct {
    pub const InitialArgs = ModelInput;
    pub const Result = AgentResult;
    pub const Failure = enum {
        budget_exhausted,
        arithmetic_overflow,
        invalid_variant,
    };
    pub const constants = .{@as(u32, 1)};
    pub const effect_sites = .{ ModelDecision, ToolInvoke };
    pub const schema_types = .{ ModelInput, Action, AgentResult };
    pub const control_ir: cir.Program = .{
        .label = "typed-agent-loop",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 2 },
    };
};

const Program = agent_profile.program("typed-agent-loop", Body);
const AgentMachine = Program.compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 128,
});

fn freshInstance(state: *AgentMachine.State) !void {
    const encoded = try AgentMachine.encodeState(
        std.testing.allocator,
        state.*,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try AgentMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    AgentMachine.deinitState(state.*);
    state.* = restored;
}

test "agent loop survives repeated typed effect boundaries" {
    var state = try AgentMachine.initialState(std.testing.allocator, .{
        .observation = 1,
        .remaining_budget = 2,
    });
    defer AgentMachine.deinitState(state);

    var fuel: u64 = 64;
    const first_model = switch (try AgentMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u64, 1), first_model.sequence);
    switch (first_model.value) {
        .s0 => |payload| {
            try std.testing.expectEqual(@as(u32, 1), payload.observation);
            try std.testing.expectEqual(@as(u32, 2), payload.remaining_budget);
        },
        else => return error.TestUnexpectedResult,
    }
    try freshInstance(&state);
    {
        const first_prepared_resume = try AgentMachine.prepareResume(
            state,
            first_model,
        );
        defer AgentMachine.deinitPreparedResume(first_prepared_resume);
        try AgentMachine.@"resume"(
            first_prepared_resume,
            Action{ .tool = 9 },
        );
    }

    const tool = switch (try AgentMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u64, 2), tool.sequence);
    switch (tool.value) {
        .s1 => |payload| try std.testing.expectEqual(@as(u32, 9), payload),
        else => return error.TestUnexpectedResult,
    }
    try freshInstance(&state);
    {
        const tool_prepared_resume = try AgentMachine.prepareResume(state, tool);
        defer AgentMachine.deinitPreparedResume(tool_prepared_resume);
        try AgentMachine.@"resume"(tool_prepared_resume, @as(u32, 42));
    }

    const second_model = switch (try AgentMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u64, 3), second_model.sequence);
    switch (second_model.value) {
        .s0 => |payload| {
            try std.testing.expectEqual(@as(u32, 42), payload.observation);
            try std.testing.expectEqual(@as(u32, 1), payload.remaining_budget);
        },
        else => return error.TestUnexpectedResult,
    }
    try freshInstance(&state);

    const before_stale = try AgentMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(before_stale);
    try std.testing.expectError(
        error.ProgramContractViolation,
        AgentMachine.prepareResume(state, first_model),
    );
    const after_stale = try AgentMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(after_stale);
    try std.testing.expectEqualSlices(u8, before_stale, after_stale);

    {
        const second_prepared_resume = try AgentMachine.prepareResume(
            state,
            second_model,
        );
        defer AgentMachine.deinitPreparedResume(second_prepared_resume);
        try AgentMachine.@"resume"(
            second_prepared_resume,
            Action{ .final = 77 },
        );
    }
    const done = switch (try AgentMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 77), done.value().value);
    try std.testing.expectEqual(
        @as(u32, 1),
        done.value().remaining_budget,
    );
}

test "agent loop rejects an exhausted authored budget before effects" {
    const state = try AgentMachine.initialState(std.testing.allocator, .{
        .observation = 5,
        .remaining_budget = 0,
    });
    defer AgentMachine.deinitState(state);
    var fuel: u64 = 8;
    const failure = switch (try AgentMachine.step(state, &fuel)) {
        .failed => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (failure) {
        .authored => |authored| try std.testing.expectEqual(
            .budget_exhausted,
            authored,
        ),
        else => return error.TestUnexpectedResult,
    }
}
