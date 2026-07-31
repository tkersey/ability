const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const Base = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.local-after.base.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const continuation_arguments = [_]cir.EdgeArgument{
    .@"resume",
    .{ .value = 0 },
};
const after_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{ 1, 2 },
        .operation = .integer_add,
    },
};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &continuation_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .role = .after_handler,
        .parameters = &.{ 1, 2 },
        .instructions = &after_instructions,
        .terminator = .{ .return_value = 3 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const effect_sites = .{Base};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "local-after",
        .value_types = &.{
            u32_type,
            u32_type,
            u32_type,
            u32_type,
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Program = program_v2.program("local-after", Body);

test "Program.compile persists local after in RNF with zero after sites" {
    var after_count: usize = 0;
    for (Program.rnf.constructorSlice()) |constructor| {
        if (constructor.kind != .after_handler) continue;
        after_count += 1;
        try std.testing.expectEqual(@as(usize, 2), constructor.environment_len);
        try std.testing.expectEqual(
            @as(cir.ValueId, 1),
            constructor.environment[0].value,
        );
        try std.testing.expectEqual(
            @as(cir.ValueId, 2),
            constructor.environment[1].value,
        );
    }
    try std.testing.expectEqual(@as(usize, 1), after_count);

    const AfterMachine = Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    try std.testing.expectEqual(@as(usize, 0), AfterMachine.EffectRow.after_site_count);
    try std.testing.expectEqual(@as(usize, 0), AfterMachine.Manifest.after_site_count);

    const state = try AfterMachine.initialState(std.testing.allocator, 2);
    defer AfterMachine.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try AfterMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const prepared_resume = try AfterMachine.prepareResume(state, request);
    defer AfterMachine.deinitPreparedResume(prepared_resume);
    try AfterMachine.@"resume"(prepared_resume, @as(u32, 40));

    var insufficient_after_fuel: u64 = 0;
    try std.testing.expectEqual(
        AfterMachine.Outcome.yielded,
        try AfterMachine.step(state, &insufficient_after_fuel),
    );
    try std.testing.expectEqual(@as(u64, 0), insufficient_after_fuel);

    const encoded = try AfterMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try AfterMachine.decodeState(std.testing.allocator, encoded);
    defer AfterMachine.deinitState(restored);

    var completion_fuel: u64 = 3;
    const done = switch (try AfterMachine.step(restored, &completion_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 42), done.value().*);
    try std.testing.expectEqual(@as(u64, 1), completion_fuel);
}
