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

const Body = struct {
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
    pub const control_ir: cir.Program = .{
        .label = "dynamic-fuel",
        .value_types = &.{ text_type, text_type, text_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = text_type,
    };
};

const Machine = program_v2.program("dynamic-fuel", Body).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});

test "canonical dynamic size changes fuel without changing transactional yield" {
    const short = try Text.fromSlice("a");
    const short_state = try Machine.initialState(std.testing.allocator, short);
    defer Machine.deinitState(short_state);
    var short_fuel: u64 = 7;
    const short_done = switch (try Machine.step(short_state, &short_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer short_done.deinit();
    try std.testing.expectEqual(@as(u64, 0), short_fuel);
    try std.testing.expectEqualStrings("a!", short_done.value().slice());

    const long = try Text.fromSlice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN");
    const long_state = try Machine.initialState(std.testing.allocator, long);
    defer Machine.deinitState(long_state);
    const before = try Machine.encodeState(std.testing.allocator, long_state);
    defer std.testing.allocator.free(before);

    var insufficient_fuel: u64 = 7;
    try std.testing.expectEqual(
        Machine.Outcome.yielded,
        try Machine.step(long_state, &insufficient_fuel),
    );
    try std.testing.expectEqual(@as(u64, 7), insufficient_fuel);
    const after = try Machine.encodeState(std.testing.allocator, long_state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);

    var exact_fuel: u64 = 11;
    const long_done = switch (try Machine.step(long_state, &exact_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer long_done.deinit();
    try std.testing.expectEqual(@as(u64, 0), exact_fuel);
    try std.testing.expectEqualStrings(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN!",
        long_done.value().slice(),
    );
}
