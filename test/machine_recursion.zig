const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const root_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 0 },
    .{ .value = 1 },
    .{ .value = 2 },
};
const root_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const recurse_body_arguments = [_]cir.EdgeArgument{
    .{ .value = 3 },
    .{ .value = 4 },
    .{ .value = 5 },
};
const recurse_done_arguments = [_]cir.EdgeArgument{
    .{ .value = 5 },
};
const recursive_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 7 },
    .{ .value = 11 },
    .{ .value = 12 },
};
const recursive_return_arguments = [_]cir.EdgeArgument{.@"resume"};

const root_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 0 },
    },
};
const recurse_header_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{ 4, 3 },
        .operation = .integer_less_than,
    },
};
const recurse_body_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 10,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 11,
        .operands = &.{ 8, 10 },
        .operation = .integer_add,
    },
    .{
        .kind = .pure,
        .result = 12,
        .operands = &.{ 9, 11 },
        .operation = .integer_add,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &root_call_arguments,
            },
            .continuation = .{
                .target = 4,
                .arguments = &root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .role = .loop_header,
        .parameters = &.{ 3, 4, 5 },
        .instructions = &recurse_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 6,
            .then_edge = .{
                .target = 2,
                .arguments = &recurse_body_arguments,
            },
            .else_edge = .{
                .target = 3,
                .arguments = &recurse_done_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{ 7, 8, 9 },
        .instructions = &recurse_body_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &recursive_call_arguments,
            },
            .continuation = .{
                .target = 5,
                .arguments = &recursive_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{14},
        .terminator = .{ .return_to_caller = 14 },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{15},
        .terminator = .{ .return_value = 15 },
    },
    .{
        .id = 5,
        .function_id = 1,
        .role = .call_return,
        .parameters = &.{13},
        .terminator = .{ .return_to_caller = 13 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{
        @as(u32, 0),
        @as(u32, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "bounded-recursive-helper",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const Program = program_v2.program("bounded-recursive-helper", Body);

const self_target_call_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
const self_target_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const self_target_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &self_target_call_arguments,
            },
            .continuation = .{
                .target = 0,
                .arguments = &self_target_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_to_caller = 1 },
    },
};

const SelfTargetBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "self-target-call-continuation",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &self_target_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const SelfTargetProgram = program_v2.program(
    "self-target-call-continuation",
    SelfTargetBody,
);

const backedge_root_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 1 },
    .{ .value = 0 },
};
const backedge_root_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const backedge_body_arguments = [_]cir.EdgeArgument{
    .{ .value = 2 },
    .{ .value = 3 },
};
const backedge_done_arguments = [_]cir.EdgeArgument{.{ .value = 2 }};
const backedge_repeat_arguments = [_]cir.EdgeArgument{
    .{ .value = 8 },
    .{ .value = 6 },
};
const backedge_root_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 1,
    .operation = .{ .constant = 0 },
}};
const backedge_header_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 4,
    .operands = &.{ 2, 3 },
    .operation = .integer_less_than,
}};
const backedge_increment_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 7,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{ 5, 7 },
        .operation = .integer_add,
    },
};
const helper_backedge_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &backedge_root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &backedge_root_call_arguments,
            },
            .continuation = .{
                .target = 4,
                .arguments = &backedge_root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .role = .loop_header,
        .parameters = &.{ 2, 3 },
        .instructions = &backedge_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 4,
            .then_edge = .{
                .target = 2,
                .arguments = &backedge_body_arguments,
            },
            .else_edge = .{
                .target = 3,
                .arguments = &backedge_done_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{ 5, 6 },
        .instructions = &backedge_increment_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 1,
                .arguments = &backedge_repeat_arguments,
            },
        } },
    },
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{9},
        .terminator = .{ .return_to_caller = 9 },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{10},
        .terminator = .{ .return_value = 10 },
    },
};

const HelperBackedgeBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{
        @as(u32, 0),
        @as(u32, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "helper-entry-backedge",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &helper_backedge_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const HelperBackedgeProgram = program_v2.program(
    "helper-entry-backedge",
    HelperBackedgeBody,
);

test "compiled bounded recursive frames survive canonical round trip" {
    var call_return_count: usize = 0;
    for (Program.rnf.constructorSlice()) |constructor| {
        if (constructor.kind == .call_return and
            constructor.origin == .suspension)
        {
            call_return_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), call_return_count);

    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try RecursiveMachine.initialState(std.testing.allocator, 3);
    defer RecursiveMachine.deinitState(state);

    var split_fuel: u64 = 3;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(state, &split_fuel),
    );
    try std.testing.expectEqual(@as(u64, 0), split_fuel);

    const encoded = try RecursiveMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try RecursiveMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer RecursiveMachine.deinitState(restored);

    var completion_fuel: u64 = 32;
    const done = switch (try RecursiveMachine.step(restored, &completion_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 6), done.value().*);
    try std.testing.expectEqual(@as(u64, 7), completion_fuel);
}

test "helper entry backedges persist only future-local callee state" {
    const BackedgeMachine = HelperBackedgeProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try BackedgeMachine.initialState(std.testing.allocator, 2);
    defer BackedgeMachine.deinitState(state);

    var caller_fuel: u64 = 16;
    try std.testing.expectEqual(
        BackedgeMachine.Outcome.yielded,
        try BackedgeMachine.step(state, &caller_fuel),
    );
    const encoded = try BackedgeMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try BackedgeMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer BackedgeMachine.deinitState(restored);

    try std.testing.expectEqual(
        BackedgeMachine.Outcome.yielded,
        try BackedgeMachine.step(restored, &caller_fuel),
    );
    const done = switch (try BackedgeMachine.step(restored, &caller_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 2), done.value().*);
}

test "shallow recursive stepping allocates from logical depth" {
    const WideMachine = HelperBackedgeProgram.compile(.{
        .maximum_frames = 1 << 20,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const backing = try std.testing.allocator.alloc(u8, 64 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const state = try WideMachine.initialState(fixed.allocator(), 2);
    defer WideMachine.deinitState(state);

    var caller_fuel: u64 = 16;
    try std.testing.expectEqual(
        WideMachine.Outcome.yielded,
        try WideMachine.step(state, &caller_fuel),
    );
    const retained_high_water = fixed.end_index;
    var no_fuel: u64 = 0;
    try std.testing.expectEqual(
        WideMachine.Outcome.yielded,
        try WideMachine.step(state, &no_fuel),
    );
    try std.testing.expectEqual(retained_high_water, fixed.end_index);
}

test "multi-frame commits reuse fixed-buffer transaction storage" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const state = try RecursiveMachine.initialState(fixed.allocator(), 3);
    defer RecursiveMachine.deinitState(state);

    var enter_helper_fuel: u64 = 1;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(state, &enter_helper_fuel),
    );
    const retained_high_water = fixed.end_index;

    for (0..32) |_| {
        var no_fuel: u64 = 0;
        try std.testing.expectEqual(
            RecursiveMachine.Outcome.yielded,
            try RecursiveMachine.step(state, &no_fuel),
        );
        try std.testing.expectEqual(
            retained_high_water,
            fixed.end_index,
        );
    }
}

test "fixed-buffer state owns every recursive growth predecessor" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 16,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 128,
    });
    const backing = try std.testing.allocator.alloc(u8, 2 << 20);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const state = try RecursiveMachine.initialState(fixed.allocator(), 8);

    var done: ?*RecursiveMachine.OwnedResult = null;
    for (0..128) |_| {
        var caller_fuel: u64 = 4;
        switch (try RecursiveMachine.step(state, &caller_fuel)) {
            .yielded => try RecursiveMachine.validateState(state),
            .done => |result| {
                done = result;
                break;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    const result = done orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 36), result.value().*);
    result.deinit();
    RecursiveMachine.deinitState(state);
    try std.testing.expectEqual(@as(usize, 0), fixed.end_index);
}

test "fixed-buffer decoded terminal state fully releases in ownership order" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const source = try RecursiveMachine.initialState(std.testing.allocator, 3);
    defer RecursiveMachine.deinitState(source);

    var split_fuel: u64 = 3;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(source, &split_fuel),
    );
    const encoded = try RecursiveMachine.encodeState(
        std.testing.allocator,
        source,
    );
    defer std.testing.allocator.free(encoded);

    const backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const restored = try RecursiveMachine.decodeState(
        fixed.allocator(),
        encoded,
    );

    var completion_fuel: u64 = 32;
    const done = switch (try RecursiveMachine.step(
        restored,
        &completion_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u32, 6), done.value().*);
    done.deinit();
    RecursiveMachine.deinitState(restored);
    try std.testing.expectEqual(@as(usize, 0), fixed.end_index);

    const state_first_backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(state_first_backing);
    var state_first_fixed = std.heap.FixedBufferAllocator.init(
        state_first_backing,
    );
    const state_first = try RecursiveMachine.decodeState(
        state_first_fixed.allocator(),
        encoded,
    );
    var state_first_fuel: u64 = 32;
    const state_first_done = switch (try RecursiveMachine.step(
        state_first,
        &state_first_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    RecursiveMachine.deinitState(state_first);
    try std.testing.expectEqual(@as(u32, 6), state_first_done.value().*);
    state_first_done.deinit();
    try std.testing.expectEqual(
        @as(usize, 0),
        state_first_fixed.end_index,
    );
}

test "decode allocation follows logical frames instead of configured ceiling" {
    const TightMachine = Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const WideMachine = Program.compile(.{
        .maximum_frames = 16,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });

    const tight_source = try TightMachine.initialState(
        std.testing.allocator,
        3,
    );
    defer TightMachine.deinitState(tight_source);
    var tight_fuel: u64 = 3;
    try std.testing.expectEqual(
        TightMachine.Outcome.yielded,
        try TightMachine.step(tight_source, &tight_fuel),
    );
    const tight_encoded = try TightMachine.encodeState(
        std.testing.allocator,
        tight_source,
    );
    defer std.testing.allocator.free(tight_encoded);

    const wide_source = try WideMachine.initialState(
        std.testing.allocator,
        3,
    );
    defer WideMachine.deinitState(wide_source);
    var wide_fuel: u64 = 3;
    try std.testing.expectEqual(
        WideMachine.Outcome.yielded,
        try WideMachine.step(wide_source, &wide_fuel),
    );
    const wide_encoded = try WideMachine.encodeState(
        std.testing.allocator,
        wide_source,
    );
    defer std.testing.allocator.free(wide_encoded);
    try std.testing.expectEqual(tight_encoded.len, wide_encoded.len);

    const tight_backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(tight_backing);
    var tight_fixed = std.heap.FixedBufferAllocator.init(tight_backing);
    const tight_restored = try TightMachine.decodeState(
        tight_fixed.allocator(),
        tight_encoded,
    );
    const tight_peak = tight_fixed.end_index;
    TightMachine.deinitState(tight_restored);
    try std.testing.expectEqual(@as(usize, 0), tight_fixed.end_index);

    const wide_backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(wide_backing);
    var wide_fixed = std.heap.FixedBufferAllocator.init(wide_backing);
    const wide_restored = try WideMachine.decodeState(
        wide_fixed.allocator(),
        wide_encoded,
    );
    const wide_peak = wide_fixed.end_index;
    WideMachine.deinitState(wide_restored);
    try std.testing.expectEqual(@as(usize, 0), wide_fixed.end_index);

    try std.testing.expectEqual(tight_peak, wide_peak);
}

test "call continuation may return to its own source block" {
    var block_entry_count: usize = 0;
    var suspension_count: usize = 0;
    for (SelfTargetProgram.rnf.constructorSlice()) |constructor| {
        if (constructor.source_block != 0 or constructor.resume_target != 0) {
            continue;
        }
        switch (constructor.origin) {
            .block_entry => block_entry_count += 1,
            .suspension => suspension_count += 1,
        }
    }
    try std.testing.expectEqual(@as(usize, 1), block_entry_count);
    try std.testing.expectEqual(@as(usize, 1), suspension_count);

    const SelfTargetMachine = SelfTargetProgram.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 8,
    });
    const state = try SelfTargetMachine.initialState(std.testing.allocator, 7);
    defer SelfTargetMachine.deinitState(state);

    var caller_fuel: u64 = 1;
    try std.testing.expectEqual(
        SelfTargetMachine.Outcome.yielded,
        try SelfTargetMachine.step(state, &caller_fuel),
    );
    const encoded = try SelfTargetMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try SelfTargetMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer SelfTargetMachine.deinitState(restored);
    try SelfTargetMachine.validateState(restored);
}

test "compiled frame-depth failure preserves state and caller fuel" {
    const ShallowMachine = Program.compile(.{
        .maximum_frames = 3,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try ShallowMachine.initialState(std.testing.allocator, 3);
    defer ShallowMachine.deinitState(state);

    const before = try ShallowMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var caller_fuel: u64 = 20;
    switch (try ShallowMachine.step(state, &caller_fuel)) {
        .failed => |failure| try std.testing.expectEqual(
            ShallowMachine.Failure.frame_depth_exceeded,
            failure,
        ),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(u64, 20), caller_fuel);

    const after = try ShallowMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
