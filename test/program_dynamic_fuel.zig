const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Text = portable_value.Text(64);
const text_type: cir.ValueType = .{ .schema = 0 };

const instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .text_append,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &instructions,
        .terminator = .{ .return_value = 2 },
    },
};

fn BodyWithBlockCost(comptime block_cost: u64) type {
    return struct {
        pub const InitialArgs = Text;
        pub const Result = Text;
        pub const Failure = enum {
            capacity_exceeded,
            invalid_utf8,
        };
        pub const constants = .{
            Text.fromSlice("!") catch unreachable,
        };
        pub const effect_sites = .{};
        pub const schema_types = .{Text};
        pub const block_costs = [_]u64{block_cost};
        pub const control_ir: cir.Program = .{
            .label = "dynamic-fuel",
            .value_types = &.{ text_type, text_type, text_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = text_type,
        };
    };
}

const Body = BodyWithBlockCost(3);

const Machine = program_v2.program("dynamic-fuel", Body).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});

const OverflowMachine = program_v2.program(
    "dynamic-fuel-overflow",
    BodyWithBlockCost(std.math.maxInt(u64)),
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = std.math.maxInt(u64),
});

fn requiredFuel(input: Text, expected: []const u8) !u64 {
    const state = try Machine.initialState(std.testing.allocator, input);
    defer Machine.deinitState(state);
    const before = try Machine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);

    var supplied: u64 = 0;
    while (supplied <= 64) : (supplied += 1) {
        var fuel = supplied;
        switch (try Machine.step(state, &fuel)) {
            .yielded => {
                try std.testing.expectEqual(supplied, fuel);
                const after = try Machine.encodeState(
                    std.testing.allocator,
                    state,
                );
                defer std.testing.allocator.free(after);
                try std.testing.expectEqualSlices(u8, before, after);
            },
            .done => |result| {
                defer result.deinit();
                try std.testing.expectEqual(@as(u64, 0), fuel);
                try std.testing.expectEqualStrings(
                    expected,
                    result.value().slice(),
                );
                return supplied;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    return error.TestUnexpectedResult;
}

test "canonical dynamic size changes fuel without changing transactional yield" {
    const short_fuel = try requiredFuel(
        try Text.fromSlice("a"),
        "a!",
    );
    const long_fuel = try requiredFuel(
        try Text.fromSlice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"),
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN!",
    );
    try std.testing.expect(long_fuel > short_fuel);
}

test "dynamic fuel addition overflow fails before mutation" {
    const state = try OverflowMachine.initialState(
        std.testing.allocator,
        try Text.fromSlice("a"),
    );
    defer OverflowMachine.deinitState(state);
    const before = try OverflowMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var caller_fuel: u64 = std.math.maxInt(u64);

    try std.testing.expectEqual(
        OverflowMachine.Outcome{ .failed = .execution_budget_exceeded },
        try OverflowMachine.step(state, &caller_fuel),
    );
    try std.testing.expectEqual(std.math.maxInt(u64), caller_fuel);
    const after = try OverflowMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
