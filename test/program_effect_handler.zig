const cir = @import("control_ir");
const effect = @import("effect_v2");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const LocalLookup = effect.site(
    0,
    "local.lookup.v1",
    u32,
    u32,
);

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const helper_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
const helper_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 2, 3 },
        .operation = .integer_add,
    },
};
const handled_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .role = .terminal_handoff,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{2},
        .instructions = &helper_instructions,
        .terminator = .{ .return_to_caller = 4 },
    },
};
const direct_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 2,
                .arguments = &helper_arguments,
            },
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .role = .terminal_handoff,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{2},
        .instructions = &helper_instructions,
        .terminator = .{ .return_to_caller = 4 },
    },
};
const functions = [_]cir.Function{
    .{
        .id = 0,
        .entry = 0,
        .result_type = u32_type,
    },
    .{
        .id = 1,
        .entry = 2,
        .result_type = u32_type,
    },
};
const value_types = [_]cir.ValueType{
    u32_type,
    u32_type,
    u32_type,
    u32_type,
    u32_type,
};

fn HandledBody() type {
    return struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { arithmetic_overflow };
        pub const constants = .{@as(u32, 1)};
        pub const effect_sites = .{LocalLookup};
        pub const effect_handlers = .{
            effect.handler(0, 1),
        };
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "effect-handler",
            .value_types = &value_types,
            .blocks = &handled_blocks,
            .entry = 0,
            .result_type = u32_type,
            .functions = &functions,
        };
    };
}

fn DirectBody() type {
    return struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { arithmetic_overflow };
        pub const constants = .{@as(u32, 1)};
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "effect-handler",
            .value_types = &value_types,
            .blocks = &direct_blocks,
            .entry = 0,
            .result_type = u32_type,
            .functions = &functions,
        };
    };
}

const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const HandledProgram = program_v2.program(
    "handled-effect",
    HandledBody(),
);
const Handled = HandledProgram.compile(options);
const Direct = program_v2.program(
    "direct-helper-call",
    DirectBody(),
).compile(options);

test "built-in effect handler normalizes to one canonical direct call" {
    try std.testing.expectEqual(@as(usize, 0), Handled.EffectRow.operation_site_count);
    try std.testing.expectEqualSlices(
        u8,
        &Direct.Manifest.machine_contract_digest,
        &Handled.Manifest.machine_contract_digest,
    );

    var call_return_count: usize = 0;
    for (HandledProgram.rnf.constructorSlice()) |constructor| {
        if (constructor.kind == .call_return and
            constructor.resume_target != constructor.source_block)
        {
            call_return_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), call_return_count);

    const state = try Handled.initialState(std.testing.allocator, 41);
    defer Handled.deinitState(state);
    var fuel: u64 = 8;
    const done = switch (try Handled.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 42), done.value().*);
}
