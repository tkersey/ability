const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const RequestPayload = portable_value.Text(16);
const payload_type: cir.ValueType = .{ .schema = 0 };
const i32_type: cir.ValueType = .{ .scalar = .i32 };

const Decide = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "performance.decide.v1";
    pub const Payload = RequestPayload;
    pub const Resume = i32;
};

const entry_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
};
const continuation_arguments = [_]cir.EdgeArgument{.@"resume"};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &entry_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &continuation_arguments,
            },
            .resume_type = i32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = i32;
    pub const Failure = enum {
        rejected,
    };
    pub const constants = .{
        RequestPayload.fromSlice("payload") catch unreachable,
    };
    pub const effect_sites = .{Decide};
    pub const schema_types = .{RequestPayload};
    pub const control_ir: cir.Program = .{
        .label = "machine-performance-one-effect",
        .value_types = &.{ payload_type, i32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = i32_type,
    };
};

const PerformanceMachine = program_v2.program(
    "machine-performance-one-effect",
    Body,
).compile(.{});

const warmup_iterations = 2_000;
const measured_iterations = 20_000;
const sample_count = 5;

fn oneEffectLifecycle() !u64 {
    const state = try PerformanceMachine.initialState(std.testing.allocator, {});
    defer PerformanceMachine.deinitState(state);
    var fuel: u64 = 100;
    const request = switch (try PerformanceMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const payload = switch (request.value) {
        .s0 => |value| value,
    };
    return payload.len();
}

fn median(input: [sample_count]u64) u64 {
    var sorted = input;
    var index: usize = 1;
    while (index < sorted.len) : (index += 1) {
        const value = sorted[index];
        var insertion = index;
        while (insertion > 0 and sorted[insertion - 1] > value) {
            sorted[insertion] = sorted[insertion - 1];
            insertion -= 1;
        }
        sorted[insertion] = value;
    }
    return sorted[sorted.len / 2];
}

test "RNF performance current one effect lifecycle" {
    var warmup_checksum: u64 = 0;
    for (0..warmup_iterations) |_| {
        warmup_checksum +%= try oneEffectLifecycle();
    }
    std.mem.doNotOptimizeAway(warmup_checksum);

    var samples: [sample_count]u64 = undefined;
    var checksum: u64 = 0;
    for (&samples) |*sample| {
        const start = std.Io.Timestamp.now(std.testing.io, .boot);
        for (0..measured_iterations) |_| {
            checksum +%= try oneEffectLifecycle();
        }
        sample.* = @intCast(
            start.durationTo(
                std.Io.Timestamp.now(std.testing.io, .boot),
            ).toNanoseconds(),
        );
    }

    const state = try PerformanceMachine.initialState(std.testing.allocator, {});
    defer PerformanceMachine.deinitState(state);
    var fuel: u64 = 100;
    _ = switch (try PerformanceMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try PerformanceMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);

    const expected_checksum =
        @as(u64, measured_iterations) * sample_count * 7;
    try std.testing.expectEqual(expected_checksum, checksum);
    std.debug.print(
        "boundary_performance_v1 implementation=rnf state_bytes={d} " ++
            "iterations={d} sample_ns=[{d},{d},{d},{d},{d}] " ++
            "median_ns={d} checksum={d}\n",
        .{
            encoded.len,
            measured_iterations,
            samples[0],
            samples[1],
            samples[2],
            samples[3],
            samples[4],
            median(samples),
            checksum,
        },
    );
}
