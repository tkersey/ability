const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Pair = struct {
    left: u32,
    right: u32,
};
const Choice = union(enum) {
    none: void,
    value: u32,
};
const OptionalU32 = ?u32;
const Values = portable_value.Vector(u32, 3);
const PopResult = struct {
    values: Values,
    value: ?u32,
};
const Text = portable_value.Text(64);
const Bytes = portable_value.Bytes(16);
const AlgebraicResult = struct {
    pair: Pair,
    choice: Choice,
    empty_choice: Choice,
    choice_payload: u32,
    choice_matches: bool,
    none: OptionalU32,
    some: OptionalU32,
    some_matches: bool,
    values: Values,
    value_count: u32,
    value_at_one: u32,
    popped: PopResult,
    truncated: Values,
    cleared: Values,
    formatted: Text,
    copied_text: Text,
    text_comparison: i8,
    joined: Text,
    text_length: u32,
    bytes: Bytes,
    copied_bytes: Bytes,
    bytes_comparison: i8,
    bytes_length: u32,
    joined_bytes: Bytes,
    scalar_bytes: Bytes,
};

const value_types = [_]cir.ValueType{
    .{ .scalar = .u32 }, // v0  seven
    .{ .scalar = .u32 }, // v1  eight
    .{ .scalar = .u32 }, // v2  zero
    .{ .scalar = .u32 }, // v3  one
    .{ .scalar = .u32 }, // v4  two
    .{ .scalar = .i32 }, // v5  negative seven
    .{ .scalar = .u32 }, // v6  scalar !
    .{ .schema = 5 }, // v7  alpha
    .{ .schema = 5 }, // v8  separator
    .{ .schema = 5 }, // v9  beta
    .{ .schema = 6 }, // v10 bytes prefix
    .{ .schema = 6 }, // v11 bytes suffix
    .{ .scalar = .u32 }, // v12 forty two
    .{ .schema = 0 }, // v13 pair
    .{ .schema = 0 }, // v14 replaced pair
    .{ .scalar = .u32 }, // v15 pair field
    .{ .schema = 1 }, // v16 choice
    .{ .scalar = .boolean }, // v17 choice tag
    .{ .scalar = .u32 }, // v18 choice payload
    .{ .schema = 1 }, // v19 empty choice
    .{ .schema = 2 }, // v20 none
    .{ .schema = 2 }, // v21 some
    .{ .scalar = .boolean }, // v22 some tag
    .{ .schema = 3 }, // v23 vector empty
    .{ .schema = 3 }, // v24 vector one
    .{ .schema = 3 }, // v25 vector two
    .{ .schema = 3 }, // v26 vector set
    .{ .scalar = .u32 }, // v27 vector length
    .{ .scalar = .u32 }, // v28 vector item
    .{ .schema = 4 }, // v29 pop result
    .{ .schema = 3 }, // v30 popped vector
    .{ .schema = 2 }, // v31 popped value
    .{ .schema = 3 }, // v32 truncated
    .{ .schema = 3 }, // v33 cleared
    .{ .schema = 5 }, // v34 text empty
    .{ .schema = 5 }, // v35 appended text
    .{ .schema = 5 }, // v36 scalar text
    .{ .schema = 5 }, // v37 unsigned text
    .{ .schema = 5 }, // v38 signed text
    .{ .schema = 5 }, // v39 copied text
    .{ .scalar = .i8 }, // v40 text comparison
    .{ .schema = 5 }, // v41 joined text
    .{ .schema = 6 }, // v42 bytes empty
    .{ .schema = 6 }, // v43 bytes prefix
    .{ .schema = 6 }, // v44 bytes joined
    .{ .schema = 6 }, // v45 copied bytes
    .{ .scalar = .i8 }, // v46 bytes comparison
    .{ .scalar = .u8 }, // v47 scalar byte
    .{ .scalar = .u32 }, // v48 text length
    .{ .scalar = .u32 }, // v49 bytes length
    .{ .schema = 6 }, // v50 joined bytes
    .{ .schema = 6 }, // v51 scalar-appended bytes
    .{ .schema = 7 }, // v52 result
};

const instructions = [_]cir.Instruction{
    .{ .kind = .constant, .result = 0, .operation = .{ .constant = 0 } },
    .{ .kind = .constant, .result = 1, .operation = .{ .constant = 1 } },
    .{ .kind = .constant, .result = 2, .operation = .{ .constant = 2 } },
    .{ .kind = .constant, .result = 3, .operation = .{ .constant = 3 } },
    .{ .kind = .constant, .result = 4, .operation = .{ .constant = 4 } },
    .{ .kind = .constant, .result = 5, .operation = .{ .constant = 5 } },
    .{ .kind = .constant, .result = 6, .operation = .{ .constant = 6 } },
    .{ .kind = .constant, .result = 7, .operation = .{ .constant = 7 } },
    .{ .kind = .constant, .result = 8, .operation = .{ .constant = 8 } },
    .{ .kind = .constant, .result = 9, .operation = .{ .constant = 9 } },
    .{ .kind = .constant, .result = 10, .operation = .{ .constant = 10 } },
    .{ .kind = .constant, .result = 11, .operation = .{ .constant = 11 } },
    .{ .kind = .constant, .result = 12, .operation = .{ .constant = 12 } },
    .{ .kind = .pure, .result = 13, .operands = &.{ 0, 1 }, .operation = .product_construct },
    .{ .kind = .pure, .result = 14, .operands = &.{ 13, 0 }, .operation = .{ .product_replace = 1 } },
    .{ .kind = .pure, .result = 15, .operands = &.{14}, .operation = .{ .product_extract = 1 } },
    .{ .kind = .pure, .result = 16, .operands = &.{15}, .operation = .{ .sum_construct = 1 } },
    .{ .kind = .pure, .result = 17, .operands = &.{16}, .operation = .{ .sum_tag_is = 1 } },
    .{ .kind = .pure, .result = 18, .operands = &.{16}, .operation = .{ .sum_extract = 1 } },
    .{ .kind = .pure, .result = 19, .operation = .{ .sum_construct = 0 } },
    .{ .kind = .pure, .result = 20, .operation = .optional_none },
    .{ .kind = .pure, .result = 21, .operands = &.{18}, .operation = .optional_some },
    .{ .kind = .pure, .result = 22, .operands = &.{21}, .operation = .optional_is_some },
    .{ .kind = .pure, .result = 23, .operation = .vector_empty },
    .{ .kind = .pure, .result = 24, .operands = &.{ 23, 0 }, .operation = .vector_push },
    .{ .kind = .pure, .result = 25, .operands = &.{ 24, 1 }, .operation = .vector_push },
    .{ .kind = .pure, .result = 26, .operands = &.{ 25, 2, 1 }, .operation = .vector_set },
    .{ .kind = .pure, .result = 27, .operands = &.{26}, .operation = .vector_length },
    .{ .kind = .pure, .result = 28, .operands = &.{ 26, 3 }, .operation = .vector_get },
    .{ .kind = .pure, .result = 29, .operands = &.{26}, .operation = .vector_pop },
    .{ .kind = .pure, .result = 30, .operands = &.{29}, .operation = .{ .product_extract = 0 } },
    .{ .kind = .pure, .result = 31, .operands = &.{29}, .operation = .{ .product_extract = 1 } },
    .{ .kind = .pure, .result = 32, .operands = &.{ 30, 2 }, .operation = .vector_truncate },
    .{ .kind = .pure, .result = 33, .operands = &.{26}, .operation = .vector_clear },
    .{ .kind = .pure, .result = 34, .operation = .text_empty },
    .{ .kind = .pure, .result = 35, .operands = &.{ 34, 7 }, .operation = .text_append },
    .{ .kind = .pure, .result = 36, .operands = &.{ 35, 6 }, .operation = .text_append_scalar },
    .{ .kind = .pure, .result = 37, .operands = &.{ 36, 12 }, .operation = .text_append_unsigned },
    .{ .kind = .pure, .result = 38, .operands = &.{ 37, 5 }, .operation = .text_append_signed },
    .{ .kind = .pure, .result = 39, .operands = &.{ 38, 2, 4 }, .operation = .text_copy },
    .{ .kind = .pure, .result = 40, .operands = &.{ 39, 7 }, .operation = .text_compare },
    .{ .kind = .pure, .result = 41, .operands = &.{ 7, 8, 9 }, .operation = .text_join },
    .{ .kind = .pure, .result = 42, .operation = .bytes_empty },
    .{ .kind = .pure, .result = 43, .operands = &.{ 42, 10 }, .operation = .bytes_append },
    .{ .kind = .pure, .result = 44, .operands = &.{ 43, 11 }, .operation = .bytes_append },
    .{ .kind = .pure, .result = 45, .operands = &.{ 44, 2, 4 }, .operation = .bytes_copy },
    .{ .kind = .pure, .result = 46, .operands = &.{ 45, 10 }, .operation = .bytes_compare },
    .{ .kind = .constant, .result = 47, .operation = .{ .constant = 13 } },
    .{ .kind = .pure, .result = 48, .operands = &.{41}, .operation = .text_length },
    .{ .kind = .pure, .result = 49, .operands = &.{44}, .operation = .bytes_length },
    .{ .kind = .pure, .result = 50, .operands = &.{ 10, 11, 10 }, .operation = .bytes_join },
    .{ .kind = .pure, .result = 51, .operands = &.{ 50, 47 }, .operation = .bytes_append_scalar },
    .{
        .kind = .pure,
        .result = 52,
        .operands = &.{
            14, 16, 19, 18, 17, 20, 21,
            22, 26, 27, 28, 29, 32, 33,
            38, 39, 40, 41, 48, 44, 45,
            46, 49, 50, 51,
        },
        .operation = .product_construct,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &instructions,
        .terminator = .{ .return_value = 52 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = AlgebraicResult;
    pub const Failure = enum {
        arithmetic_overflow,
        capacity_exceeded,
        division_by_zero,
        invalid_index,
        invalid_utf8,
        invalid_variant,
    };
    pub const constants = .{
        @as(u32, 7),
        @as(u32, 8),
        @as(u32, 0),
        @as(u32, 1),
        @as(u32, 2),
        @as(i32, -7),
        @as(u32, '!'),
        Text.fromSlice("alpha") catch unreachable,
        Text.fromSlice("-") catch unreachable,
        Text.fromSlice("beta") catch unreachable,
        Bytes.fromSlice(&.{ 1, 2 }) catch unreachable,
        Bytes.fromSlice(&.{3}) catch unreachable,
        @as(u32, 42),
        @as(u8, 4),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{
        Pair,
        Choice,
        OptionalU32,
        Values,
        PopResult,
        Text,
        Bytes,
        AlgebraicResult,
    };
    pub const control_ir: cir.Program = .{
        .label = "algebraic-collection-operations",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 7 },
    };
};

const Machine = program_v2.program(
    "algebraic-collection-operations",
    Body,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 8192,
    .maximum_machine_fuel = 512,
});

test "compiled products sums optionals vectors text and bytes are first order" {
    const state = try Machine.initialState(std.testing.allocator, {});
    defer Machine.deinitState(state);
    var fuel: u64 = 512;
    const done = switch (try Machine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    const result = done.value();
    try std.testing.expectEqual(Pair{ .left = 7, .right = 7 }, result.pair);
    try std.testing.expect(result.choice_matches);
    try std.testing.expectEqual(@as(u32, 7), result.choice_payload);
    try std.testing.expectEqual(@as(u32, 7), result.some.?);
    try std.testing.expect(result.some_matches);
    try std.testing.expect(result.none == null);
    try std.testing.expectEqual(@as(u32, 2), result.value_count);
    try std.testing.expectEqual(@as(u32, 8), result.value_at_one);
    try std.testing.expectEqual(@as(u32, 1), result.popped.values.len());
    try std.testing.expectEqual(@as(u32, 8), result.popped.value.?);
    try std.testing.expectEqual(@as(u32, 0), result.truncated.len());
    try std.testing.expectEqual(@as(u32, 0), result.cleared.len());
    try std.testing.expectEqualStrings("alpha!42-7", result.formatted.slice());
    try std.testing.expectEqualStrings("al", result.copied_text.slice());
    try std.testing.expectEqual(@as(i8, -1), result.text_comparison);
    try std.testing.expectEqualStrings("alpha-beta", result.joined.slice());
    try std.testing.expectEqual(@as(u32, 10), result.text_length);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, result.bytes.slice());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, result.copied_bytes.slice());
    try std.testing.expectEqual(@as(i8, 0), result.bytes_comparison);
    try std.testing.expectEqual(@as(u32, 3), result.bytes_length);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 1, 2 },
        result.joined_bytes.slice(),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 1, 2, 4 },
        result.scalar_bytes.slice(),
    );
    switch (result.choice) {
        .value => |value| try std.testing.expectEqual(@as(u32, 7), value),
        .none => return error.TestUnexpectedResult,
    }
    switch (result.empty_choice) {
        .none => {},
        .value => return error.TestUnexpectedResult,
    }
}
