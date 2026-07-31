const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Title = portable_value.Text(16);
const Digest = portable_value.Text(32);
const Item = struct {
    title: Title,
    score: u32,
};
const Items = portable_value.Vector(Item, 2);
const PureResult = struct {
    items: Items,
    digest: Digest,
    total: u32,
};

const title = Title.fromSlice("alpha") catch unreachable;
const value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .scalar = .u32 },
    .{ .schema = 1 },
    .{ .schema = 2 },
    .{ .schema = 2 },
    .{ .schema = 3 },
    .{ .schema = 3 },
    .{ .scalar = .u32 },
    .{ .scalar = .u32 },
    .{ .schema = 4 },
};
const instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .product_construct,
    },
    .{
        .kind = .pure,
        .result = 3,
        .operation = .vector_empty,
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 3, 2 },
        .operation = .vector_push,
    },
    .{
        .kind = .pure,
        .result = 5,
        .operation = .text_empty,
    },
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{ 5, 0 },
        .operation = .text_append,
    },
    .{
        .kind = .constant,
        .result = 7,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{ 1, 7 },
        .operation = .integer_add,
    },
    .{
        .kind = .pure,
        .result = 9,
        .operands = &.{ 4, 6, 8 },
        .operation = .product_construct,
    },
};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &instructions,
        .terminator = .{ .return_value = 9 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = PureResult;
    pub const Failure = enum {
        arithmetic_overflow,
        capacity_exceeded,
        invalid_index,
    };
    pub const contract_bytes = "pure-operation-algebra\x00v1";
    pub const constants = .{
        title,
        @as(u32, 7),
        @as(u32, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ Title, Item, Items, Digest, PureResult };
    pub const control_ir: cir.Program = .{
        .label = "pure-operation-algebra",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 4 },
    };
};

const Program = program_v2.program("pure-operation-algebra", Body);
const PureMachine = Program.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 128,
});

test "compiled pure operations construct products vectors and text" {
    const state = try PureMachine.initialState(std.testing.allocator, {});
    defer PureMachine.deinitState(state);

    const before = try PureMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var insufficient_fuel: u64 = 10;
    try std.testing.expectEqual(
        PureMachine.Outcome.yielded,
        try PureMachine.step(state, &insufficient_fuel),
    );
    try std.testing.expectEqual(@as(u64, 10), insufficient_fuel);
    const after_yield = try PureMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(after_yield);
    try std.testing.expectEqualSlices(u8, before, after_yield);

    var fuel: u64 = 64;
    const done = switch (try PureMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();

    const result = done.value();
    try std.testing.expectEqual(@as(u32, 1), result.items.len());
    const item = result.items.get(0).?;
    try std.testing.expectEqualStrings("alpha", item.title.slice());
    try std.testing.expectEqual(@as(u32, 7), item.score);
    try std.testing.expectEqualStrings("alpha", result.digest.slice());
    try std.testing.expectEqual(@as(u32, 8), result.total);
}

const failure_blocks = [_]cir.Block{
    .{
        .id = 0,
        .terminator = .{ .fail = 7 },
    },
};

fn FailureBody(comptime FailureType: type) type {
    return struct {
        pub const InitialArgs = void;
        pub const Result = void;
        pub const Failure = FailureType;
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "non-dense-failure-tags",
            .value_types = &.{},
            .blocks = &failure_blocks,
            .entry = 0,
            .result_type = .{ .scalar = .unit },
        };
    };
}

const FailureA = enum(u16) {
    rejected = 7,
    other = 11,
};
const FailureB = enum(u16) {
    other = 7,
    rejected = 11,
};
const FailureMachineA =
    program_v2.program("non-dense-failure-tags", FailureBody(FailureA))
        .compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 8,
    });
const FailureMachineB =
    program_v2.program("non-dense-failure-tags", FailureBody(FailureB))
        .compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 8,
    });

test "non-dense failure tags retain name-bound runtime and identity semantics" {
    const state = try FailureMachineA.initialState(std.testing.allocator, {});
    defer FailureMachineA.deinitState(state);
    var fuel: u64 = 1;
    switch (try FailureMachineA.step(state, &fuel)) {
        .failed => |failure| switch (failure) {
            .authored => |authored| {
                try std.testing.expectEqual(
                    @as(u16, 7),
                    @intFromEnum(authored),
                );
                try std.testing.expectEqualStrings(
                    "rejected",
                    @tagName(authored),
                );
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(!std.mem.eql(
        u8,
        &FailureMachineA.Manifest.machine_contract_digest,
        &FailureMachineB.Manifest.machine_contract_digest,
    ));
}
