const cir = @import("control_ir");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
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
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const ExplicitMachine = ExplicitProgram.compile(options);
const ExplicitImage = ExplicitProgram.image(options);

const CheckpointProgram = program_v2.program(
    "caller-fuel-checkpoint",
    YieldBody(.caller_fuel),
);
const CheckpointMachine = CheckpointProgram.compile(options);
const CheckpointImage = CheckpointProgram.image(options);

test "explicit yield persists the continuation before returning to the caller" {
    try std.testing.expectEqual(
        @as(usize, 2),
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
    for (checkpoint.invariantTerms()) |term| switch (term) {
        .value_copy => return error.TestUnexpectedResult,
        else => {},
    };

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

test "fixed kernel preserves explicit and caller-fuel checkpoints" {
    inline for (.{
        .{ ExplicitImage, @as(u32, 11), @as(u64, 4), true },
        .{ CheckpointImage, @as(u32, 19), @as(u64, 1), false },
    }) |fixture| {
        const Image = fixture[0];
        const input = fixture[1];
        var workspace: image_v1.ValidationWorkspace = .{};
        const image = try image_v1.validateImage(&Image.bytes, &workspace);
        var args: [4]u8 = undefined;
        std.mem.writeInt(u32, &args, input, .little);
        var state: [4096]u8 = undefined;
        const state_length = try kernel_v1.initial(
            image,
            &args,
            &state,
            &workspace,
        );
        var fuel = fixture[2];
        var next_state: [4096]u8 = undefined;
        var output: [4]u8 = undefined;
        var scratch: [12 * 1024]u8 = undefined;
        const yielded = switch (try kernel_v1.step(
            image,
            state[0..state_length],
            &fuel,
            &next_state,
            &output,
            &scratch,
            &workspace,
        )) {
            .yielded => |value| value,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(
            if (fixture[3]) @as(u64, 3) else 0,
            fuel,
        );
        var resume_fuel: u64 = 1;
        var terminal_state: [4096]u8 = undefined;
        const done = switch (try kernel_v1.step(
            image,
            yielded,
            &resume_fuel,
            &terminal_state,
            &output,
            &scratch,
            &workspace,
        )) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(
            input,
            std.mem.readInt(u32, done[0..4], .little),
        );
        try std.testing.expectEqual(@as(u64, 0), resume_fuel);
    }
}

test "KernelMachine preserves terminal execution-budget failure and prior charges" {
    const budget_options: machine.Options = .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 1,
    };
    const Direct = CheckpointProgram.compile(budget_options);
    const Kernel = CheckpointProgram.kernelMachine(budget_options);
    const direct = try Direct.initialState(std.testing.allocator, 19);
    defer Direct.deinitState(direct);
    const kernel = try Kernel.initialState(std.testing.allocator, 19);
    defer Kernel.deinitState(kernel);
    var direct_fuel: u64 = 5;
    var kernel_fuel: u64 = 5;
    try std.testing.expectEqual(
        Direct.Outcome{ .failed = .execution_budget_exceeded },
        try Direct.step(direct, &direct_fuel),
    );
    try std.testing.expectEqual(
        Kernel.Outcome{ .failed = .execution_budget_exceeded },
        try Kernel.step(kernel, &kernel_fuel),
    );
    try std.testing.expectEqual(@as(u64, 4), direct_fuel);
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
    try std.testing.expectError(
        error.ProgramContractViolation,
        Kernel.validateState(kernel),
    );
}
