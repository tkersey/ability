const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const ArithmeticResult = struct {
    add: i32,
    subtract: i32,
    multiply: i32,
    divide: i32,
    remainder: i32,
    negate: i32,
    equal: bool,
    not_equal: bool,
    less: bool,
    less_equal: bool,
    greater: bool,
    greater_equal: bool,
    bit_not: u8,
    bit_and: u8,
    bit_or: u8,
    bit_xor: u8,
    converted: i8,
    boolean_not: bool,
    boolean_and: bool,
    boolean_or: bool,
    selected: i32,
};

const value_types = [_]cir.ValueType{
    .{ .scalar = .i32 }, // v0  a
    .{ .scalar = .i32 }, // v1  b
    .{ .scalar = .boolean }, // v2  true
    .{ .scalar = .boolean }, // v3  false
    .{ .scalar = .u8 }, // v4  mask
    .{ .scalar = .u8 }, // v5  mask2
    .{ .scalar = .i32 }, // v6  add
    .{ .scalar = .i32 }, // v7  subtract
    .{ .scalar = .i32 }, // v8  multiply
    .{ .scalar = .i32 }, // v9  divide
    .{ .scalar = .i32 }, // v10 remainder
    .{ .scalar = .i32 }, // v11 negate
    .{ .scalar = .boolean }, // v12 equal
    .{ .scalar = .boolean }, // v13 not equal
    .{ .scalar = .boolean }, // v14 less
    .{ .scalar = .boolean }, // v15 less equal
    .{ .scalar = .boolean }, // v16 greater
    .{ .scalar = .boolean }, // v17 greater equal
    .{ .scalar = .u8 }, // v18 bit not
    .{ .scalar = .u8 }, // v19 bit and
    .{ .scalar = .u8 }, // v20 bit or
    .{ .scalar = .u8 }, // v21 bit xor
    .{ .scalar = .i8 }, // v22 converted
    .{ .scalar = .boolean }, // v23 boolean not
    .{ .scalar = .boolean }, // v24 boolean and
    .{ .scalar = .boolean }, // v25 boolean or
    .{ .scalar = .i32 }, // v26 selected
    .{ .schema = 0 }, // v27 result
};

const instructions = [_]cir.Instruction{
    .{ .kind = .constant, .result = 0, .operation = .{ .constant = 0 } },
    .{ .kind = .constant, .result = 1, .operation = .{ .constant = 1 } },
    .{ .kind = .constant, .result = 2, .operation = .{ .constant = 2 } },
    .{ .kind = .constant, .result = 3, .operation = .{ .constant = 3 } },
    .{ .kind = .constant, .result = 4, .operation = .{ .constant = 4 } },
    .{ .kind = .constant, .result = 5, .operation = .{ .constant = 5 } },
    .{ .kind = .pure, .result = 6, .operands = &.{ 0, 1 }, .operation = .integer_add },
    .{ .kind = .pure, .result = 7, .operands = &.{ 0, 1 }, .operation = .integer_subtract },
    .{ .kind = .pure, .result = 8, .operands = &.{ 0, 1 }, .operation = .integer_multiply },
    .{ .kind = .pure, .result = 9, .operands = &.{ 0, 1 }, .operation = .integer_divide },
    .{ .kind = .pure, .result = 10, .operands = &.{ 0, 1 }, .operation = .integer_remainder },
    .{ .kind = .pure, .result = 11, .operands = &.{1}, .operation = .integer_negate },
    .{ .kind = .pure, .result = 12, .operands = &.{ 0, 1 }, .operation = .integer_equal },
    .{ .kind = .pure, .result = 13, .operands = &.{ 0, 1 }, .operation = .integer_not_equal },
    .{ .kind = .pure, .result = 14, .operands = &.{ 1, 0 }, .operation = .integer_less_than },
    .{ .kind = .pure, .result = 15, .operands = &.{ 1, 0 }, .operation = .integer_less_equal },
    .{ .kind = .pure, .result = 16, .operands = &.{ 0, 1 }, .operation = .integer_greater_than },
    .{ .kind = .pure, .result = 17, .operands = &.{ 0, 1 }, .operation = .integer_greater_equal },
    .{ .kind = .pure, .result = 18, .operands = &.{4}, .operation = .integer_bit_not },
    .{ .kind = .pure, .result = 19, .operands = &.{ 4, 5 }, .operation = .integer_bit_and },
    .{ .kind = .pure, .result = 20, .operands = &.{ 4, 5 }, .operation = .integer_bit_or },
    .{ .kind = .pure, .result = 21, .operands = &.{ 4, 5 }, .operation = .integer_bit_xor },
    .{ .kind = .pure, .result = 22, .operands = &.{1}, .operation = .integer_convert },
    .{ .kind = .pure, .result = 23, .operands = &.{3}, .operation = .boolean_not },
    .{ .kind = .pure, .result = 24, .operands = &.{ 2, 3 }, .operation = .boolean_and },
    .{ .kind = .pure, .result = 25, .operands = &.{ 2, 3 }, .operation = .boolean_or },
    .{ .kind = .pure, .result = 26, .operands = &.{ 2, 6, 7 }, .operation = .select },
    .{
        .kind = .pure,
        .result = 27,
        .operands = &.{
            6,  7,  8,  9,  10, 11, 12,
            13, 14, 15, 16, 17, 18, 19,
            20, 21, 22, 23, 24, 25, 26,
        },
        .operation = .product_construct,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &instructions,
        .terminator = .{ .return_value = 27 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = ArithmeticResult;
    pub const Failure = enum {
        arithmetic_overflow,
        division_by_zero,
    };
    pub const constants = .{
        @as(i32, 20),
        @as(i32, 6),
        true,
        false,
        @as(u8, 0x0f),
        @as(u8, 0x33),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ArithmeticResult};
    pub const control_ir: cir.Program = .{
        .label = "integer-boolean-operations",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};

const Machine = program_v2.program(
    "integer-boolean-operations",
    Body,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 128,
});

test "compiled integer and boolean algebra is deterministic" {
    const state = try Machine.initialState(std.testing.allocator, {});
    defer Machine.deinitState(state);
    var fuel: u64 = 64;
    const done = switch (try Machine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    const result = done.value();
    try std.testing.expectEqual(@as(i32, 26), result.add);
    try std.testing.expectEqual(@as(i32, 14), result.subtract);
    try std.testing.expectEqual(@as(i32, 120), result.multiply);
    try std.testing.expectEqual(@as(i32, 3), result.divide);
    try std.testing.expectEqual(@as(i32, 2), result.remainder);
    try std.testing.expectEqual(@as(i32, -6), result.negate);
    try std.testing.expect(!result.equal);
    try std.testing.expect(result.not_equal);
    try std.testing.expect(result.less);
    try std.testing.expect(result.less_equal);
    try std.testing.expect(result.greater);
    try std.testing.expect(result.greater_equal);
    try std.testing.expectEqual(@as(u8, 0xf0), result.bit_not);
    try std.testing.expectEqual(@as(u8, 0x03), result.bit_and);
    try std.testing.expectEqual(@as(u8, 0x3f), result.bit_or);
    try std.testing.expectEqual(@as(u8, 0x3c), result.bit_xor);
    try std.testing.expectEqual(@as(i8, 6), result.converted);
    try std.testing.expect(result.boolean_not);
    try std.testing.expect(!result.boolean_and);
    try std.testing.expect(result.boolean_or);
    try std.testing.expectEqual(@as(i32, 26), result.selected);
}
