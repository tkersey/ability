const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const u32_type: cir.ValueType = .{ .scalar = .u32 };

fn YieldBody(comptime kind: cir.SuspensionKind) type {
    return struct {
        const value_types = [_]cir.ValueType{
            u32_type,
            u32_type,
        };
        const continuation_arguments = [_]cir.EdgeArgument{
            .{ .value = 0 },
        };
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = kind,
                    .continuation = .{
                        .target = 1,
                        .arguments = &continuation_arguments,
                    },
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = @tagName(kind),
            .value_types = &value_types,
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const ExplicitProgram = program_v2.program(
    "explicit-yield",
    YieldBody(.explicit_yield),
);
const ExplicitMachine = ExplicitProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const CheckpointProgram = program_v2.program(
    "caller-fuel-checkpoint",
    YieldBody(.caller_fuel),
);
const CheckpointMachine = CheckpointProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

test "explicit yield persists the continuation before returning to the caller" {
    try std.testing.expectEqual(
        @as(usize, 3),
        ExplicitProgram.rnf.constructor_count,
    );
    const checkpoint = &ExplicitProgram.rnf.constructors[1];
    try std.testing.expectEqual(.caller_fuel_yield, checkpoint.kind);
    try std.testing.expectEqual(@as(cir.BlockId, 1), checkpoint.source_block);
    try std.testing.expectEqual(@as(usize, 1), checkpoint.environment_len);
    try std.testing.expectEqual(
        @as(cir.ValueId, 1),
        checkpoint.environment[0].value,
    );

    const state = try ExplicitMachine.initialState(std.testing.allocator, 11);
    defer ExplicitMachine.deinitState(state);
    var fuel: u64 = 4;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try ExplicitMachine.step(state, &fuel)),
    );
    try std.testing.expectEqual(@as(u64, 3), fuel);

    const encoded = try ExplicitMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try ExplicitMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer ExplicitMachine.deinitState(restored);

    var resume_fuel: u64 = 1;
    const done = switch (try ExplicitMachine.step(restored, &resume_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 11), done.value().*);
    try std.testing.expectEqual(@as(u64, 0), resume_fuel);
}

test "caller-fuel checkpoint yields only when the next segment is unfunded" {
    const state = try CheckpointMachine.initialState(
        std.testing.allocator,
        19,
    );
    defer CheckpointMachine.deinitState(state);
    var one_segment: u64 = 1;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try CheckpointMachine.step(
            state,
            &one_segment,
        )),
    );
    try std.testing.expectEqual(@as(u64, 0), one_segment);

    var resume_fuel: u64 = 1;
    const resumed = switch (try CheckpointMachine.step(state, &resume_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer resumed.deinit();
    try std.testing.expectEqual(@as(u32, 19), resumed.value().*);

    const uninterrupted = try CheckpointMachine.initialState(
        std.testing.allocator,
        23,
    );
    defer CheckpointMachine.deinitState(uninterrupted);
    var two_segments: u64 = 2;
    const done = switch (try CheckpointMachine.step(
        uninterrupted,
        &two_segments,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 23), done.value().*);
    try std.testing.expectEqual(@as(u64, 0), two_segments);
}
