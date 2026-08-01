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

test "dynamic fuel addition overflow commits terminal failure" {
    const state = try OverflowMachine.initialState(
        std.testing.allocator,
        try Text.fromSlice("a"),
    );
    defer OverflowMachine.deinitState(state);
    var caller_fuel: u64 = std.math.maxInt(u64);

    try std.testing.expectEqual(
        OverflowMachine.Outcome{ .failed = .execution_budget_exceeded },
        try OverflowMachine.step(state, &caller_fuel),
    );
    try std.testing.expectEqual(std.math.maxInt(u64), caller_fuel);
    try std.testing.expectError(
        error.ProgramContractViolation,
        OverflowMachine.encodeState(std.testing.allocator, state),
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        OverflowMachine.cloneState(std.testing.allocator, state),
    );
    var retry_fuel: u64 = std.math.maxInt(u64);
    try std.testing.expectError(
        error.ProgramContractViolation,
        OverflowMachine.step(state, &retry_fuel),
    );
    try std.testing.expectEqual(std.math.maxInt(u64), retry_fuel);
}

const TextPair = struct {
    left: Text,
    right: Text,
};
const Texts = portable_value.Vector(Text, 2);
const VectorSelection = struct {
    values: Texts,
    index: u32,
};
const u32_type: cir.ValueType = .{ .scalar = .u32 };
const pair_type: cir.ValueType = .{ .schema = 0 };
const pair_text_type: cir.ValueType = .{ .schema = 1 };
const texts_type: cir.ValueType = .{ .schema = 0 };
const selection_type: cir.ValueType = .{ .schema = 1 };
const selection_text_type: cir.ValueType = .{ .schema = 2 };
const helper_return_arguments = [_]cir.EdgeArgument{.@"resume"};

const pair_call_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
const pair_helper_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{1},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{2},
        .operation = .text_length,
    },
};
const pair_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &pair_call_arguments,
            },
            .continuation = .{
                .target = 2,
                .arguments = &helper_return_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .parameters = &.{1},
        .instructions = &pair_helper_instructions,
        .terminator = .{ .return_to_caller = 3 },
    },
    .{
        .id = 2,
        .role = .terminal_handoff,
        .parameters = &.{4},
        .terminator = .{ .return_value = 4 },
    },
};
const PairBody = struct {
    pub const InitialArgs = TextPair;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{ TextPair, Text };
    pub const control_ir: cir.Program = .{
        .label = "helper-product-exact-sizing",
        .value_types = &.{
            pair_type,
            pair_type,
            pair_text_type,
            u32_type,
            u32_type,
        },
        .blocks = &pair_blocks,
        .entry = 0,
        .result_type = u32_type,
        .functions = &.{
            .{ .id = 0, .entry = 0, .result_type = u32_type },
            .{ .id = 1, .entry = 1, .result_type = u32_type },
        },
    };
};
const PairMachine = program_v2.program(
    "helper-product-exact-sizing",
    PairBody,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 4096,
});

const selection_root_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{0},
        .operation = .{ .product_extract = 1 },
    },
};
const selection_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 1 },
    .{ .value = 2 },
};
const selection_helper_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 5,
        .operands = &.{ 3, 4 },
        .operation = .vector_get,
    },
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{5},
        .operation = .text_length,
    },
};
const selection_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &selection_root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &selection_call_arguments,
            },
            .continuation = .{
                .target = 2,
                .arguments = &helper_return_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .parameters = &.{ 3, 4 },
        .instructions = &selection_helper_instructions,
        .terminator = .{ .return_to_caller = 6 },
    },
    .{
        .id = 2,
        .role = .terminal_handoff,
        .parameters = &.{7},
        .terminator = .{ .return_value = 7 },
    },
};
const SelectionBody = struct {
    pub const InitialArgs = VectorSelection;
    pub const Result = u32;
    pub const Failure = enum { invalid_index };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{ Texts, VectorSelection, Text };
    pub const control_ir: cir.Program = .{
        .label = "helper-vector-exact-sizing",
        .value_types = &.{
            selection_type,
            texts_type,
            u32_type,
            texts_type,
            u32_type,
            selection_text_type,
            u32_type,
            u32_type,
        },
        .blocks = &selection_blocks,
        .entry = 0,
        .result_type = u32_type,
        .functions = &.{
            .{ .id = 0, .entry = 0, .result_type = u32_type },
            .{ .id = 1, .entry = 1, .result_type = u32_type },
        },
    };
};
const SelectionMachine = program_v2.program(
    "helper-vector-exact-sizing",
    SelectionBody,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 4096,
});

fn requiredHelperFuel(comptime HelperMachine: type, input: anytype, expected: u32) !u64 {
    const state = try HelperMachine.initialState(std.testing.allocator, input);
    defer HelperMachine.deinitState(state);
    const initial = try HelperMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(initial);

    var entry_fuel: u64 = 0;
    entry: while (entry_fuel <= 4096) : (entry_fuel += 1) {
        var fuel = entry_fuel;
        switch (try HelperMachine.step(state, &fuel)) {
            .yielded => {
                const after = try HelperMachine.encodeState(
                    std.testing.allocator,
                    state,
                );
                defer std.testing.allocator.free(after);
                if (std.mem.eql(u8, initial, after)) {
                    try std.testing.expectEqual(entry_fuel, fuel);
                    continue;
                }
                try std.testing.expectEqual(@as(u64, 0), fuel);
                break :entry;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    if (entry_fuel > 4096) return error.TestUnexpectedResult;

    const before = try HelperMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var supplied: u64 = 0;
    while (supplied <= 4096) : (supplied += 1) {
        var fuel = supplied;
        switch (try HelperMachine.step(state, &fuel)) {
            .yielded => {
                const after = try HelperMachine.encodeState(
                    std.testing.allocator,
                    state,
                );
                defer std.testing.allocator.free(after);
                if (std.mem.eql(u8, before, after)) {
                    try std.testing.expectEqual(supplied, fuel);
                    continue;
                }
                try std.testing.expectEqual(@as(u64, 0), fuel);
                var completion_fuel: u64 = 4096;
                const result = switch (try HelperMachine.step(
                    state,
                    &completion_fuel,
                )) {
                    .done => |done| done,
                    else => return error.TestUnexpectedResult,
                };
                defer result.deinit();
                try std.testing.expectEqual(expected, result.value().*);
                return supplied;
            },
            .done => |result| {
                defer result.deinit();
                try std.testing.expectEqual(@as(u64, 0), fuel);
                try std.testing.expectEqual(expected, result.value().*);
                return supplied;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    return error.TestUnexpectedResult;
}

test "helper activation exact sizing uses materialized product and vector values" {
    const short = try Text.fromSlice("a");
    const long = try Text.fromSlice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN");

    const short_product_fuel = try requiredHelperFuel(
        PairMachine,
        TextPair{ .left = short, .right = long },
        1,
    );
    const long_product_fuel = try requiredHelperFuel(
        PairMachine,
        TextPair{ .left = long, .right = short },
        40,
    );
    try std.testing.expect(long_product_fuel > short_product_fuel);

    var short_first = Texts.empty();
    try short_first.push(short);
    try short_first.push(long);
    var long_first = Texts.empty();
    try long_first.push(long);
    try long_first.push(short);
    const short_vector_fuel = try requiredHelperFuel(
        SelectionMachine,
        VectorSelection{ .values = short_first, .index = 0 },
        1,
    );
    const long_vector_fuel = try requiredHelperFuel(
        SelectionMachine,
        VectorSelection{ .values = long_first, .index = 0 },
        40,
    );
    try std.testing.expect(long_vector_fuel > short_vector_fuel);
}
