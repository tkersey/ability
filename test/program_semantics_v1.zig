const control_ir = @import("control_ir");
const reducer = @import("program_semantics_v1");
const rnf = @import("rnf");
const std = @import("std");

const operations = [_]control_ir.InstructionOperation{
    .{ .constant = 0 },
    .copy,
    .compare_eq_zero,
    .integer_add,
    .integer_subtract,
    .integer_multiply,
    .integer_divide,
    .integer_remainder,
    .integer_negate,
    .integer_equal,
    .integer_not_equal,
    .integer_less_than,
    .integer_less_equal,
    .integer_greater_than,
    .integer_greater_equal,
    .integer_bit_not,
    .integer_bit_and,
    .integer_bit_or,
    .integer_bit_xor,
    .integer_convert,
    .boolean_not,
    .boolean_and,
    .boolean_or,
    .select,
    .product_construct,
    .{ .product_extract = 0 },
    .{ .product_replace = 0 },
    .{ .sum_construct = 0 },
    .{ .sum_tag_is = 0 },
    .{ .sum_extract = 0 },
    .optional_none,
    .optional_some,
    .optional_is_some,
    .vector_empty,
    .vector_length,
    .vector_get,
    .vector_set,
    .vector_push,
    .vector_pop,
    .vector_truncate,
    .vector_clear,
    .text_empty,
    .text_append,
    .text_append_scalar,
    .text_append_unsigned,
    .text_append_signed,
    .text_copy,
    .text_compare,
    .text_join,
    .bytes_empty,
    .bytes_append,
    .bytes_copy,
    .bytes_compare,
    .text_length,
    .bytes_length,
    .bytes_append_scalar,
    .bytes_join,
    .enum_to_u32,
};

test "BPI1 operation tags are exhaustive and independent of current enum tags" {
    try std.testing.expectEqual(@as(usize, 58), operations.len);
    inline for (operations, 0..) |operation, expected_tag| {
        try std.testing.expectEqual(
            @as(u16, @intCast(expected_tag)),
            reducer.wireTag(operation),
        );
        try std.testing.expectEqual(
            reducer.currentSemanticTag(operation),
            reducer.currentSemanticTagForWire(
                reducer.wireOperation(operation),
            ),
        );
    }
    try std.testing.expectEqual(
        control_ir.InstructionKind.constant,
        reducer.canonicalInstructionKind(operations[0]),
    );
    try std.testing.expectEqual(
        control_ir.InstructionKind.copy,
        reducer.canonicalInstructionKind(operations[1]),
    );
    try std.testing.expectEqual(
        control_ir.InstructionKind.compare_eq_zero,
        reducer.canonicalInstructionKind(operations[2]),
    );
    inline for (operations[3..]) |operation| {
        try std.testing.expectEqual(
            control_ir.InstructionKind.pure,
            reducer.canonicalInstructionKind(operation),
        );
    }
}

test "operation failure roles have one pure owner" {
    try std.testing.expectEqualSlices(
        reducer.FailureRole,
        &.{.arithmetic_overflow},
        reducer.failureRoles(.integer_add),
    );
    try std.testing.expectEqualSlices(
        reducer.FailureRole,
        &.{ .arithmetic_overflow, .division_by_zero },
        reducer.failureRoles(.integer_divide),
    );
    try std.testing.expectEqualSlices(
        reducer.FailureRole,
        &.{ .capacity_exceeded, .invalid_utf8 },
        reducer.failureRoles(.text_copy),
    );
    try std.testing.expectEqualSlices(
        reducer.FailureRole,
        &.{},
        reducer.failureRoles(.integer_equal),
    );
}

test "BPI1 control and RNF wire tags are pinned" {
    const jump = control_ir.Terminator{ .jump = .{ .target = 0 } };
    try std.testing.expectEqual(
        @as(u8, 0),
        @intFromEnum(reducer.wireTerminator(jump)),
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        @intFromEnum(reducer.WireSuspension.explicit_yield),
    );
    const invariant = rnf.InvariantTerm{ .boolean = .{
        .value = 0,
        .expected = true,
    } };
    try std.testing.expectEqual(
        @as(u8, 0),
        @intFromEnum(reducer.wireInvariant(invariant)),
    );
    try std.testing.expectEqual(
        @as(u8, 7),
        @intFromEnum(reducer.WireConstructorKind.terminal_handoff),
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        @intFromEnum(reducer.wireConstructorOrigin(.suspension)),
    );
    try std.testing.expectEqual(
        @as(u8, 4),
        @intFromEnum(reducer.wireIncomingEdge(.suspension_continuation)),
    );
}
