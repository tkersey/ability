const control_ir = @import("control_ir");
const std = @import("std");

pub const segment_fuel_semantic_domain =
    "segment-fuel=preflight-resource-shape-v4";
pub const dynamic_fuel_quantum_bytes: u64 = 16;
pub const await_effect_cost: u64 = 1;

pub const FailureRole = enum {
    arithmetic_overflow,
    division_by_zero,
    capacity_exceeded,
    invalid_utf8,
    invalid_index,
    invalid_variant,
};

pub fn failureName(comptime role: FailureRole) []const u8 {
    return @tagName(role);
}

pub const WireOperation = enum(u16) {
    constant = 0,
    copy = 1,
    compare_eq_zero = 2,
    integer_add = 3,
    integer_subtract = 4,
    integer_multiply = 5,
    integer_divide = 6,
    integer_remainder = 7,
    integer_negate = 8,
    integer_equal = 9,
    integer_not_equal = 10,
    integer_less_than = 11,
    integer_less_equal = 12,
    integer_greater_than = 13,
    integer_greater_equal = 14,
    integer_bit_not = 15,
    integer_bit_and = 16,
    integer_bit_or = 17,
    integer_bit_xor = 18,
    integer_convert = 19,
    boolean_not = 20,
    boolean_and = 21,
    boolean_or = 22,
    select = 23,
    product_construct = 24,
    product_extract = 25,
    product_replace = 26,
    sum_construct = 27,
    sum_tag_is = 28,
    sum_extract = 29,
    optional_none = 30,
    optional_some = 31,
    optional_is_some = 32,
    vector_empty = 33,
    vector_length = 34,
    vector_get = 35,
    vector_set = 36,
    vector_push = 37,
    vector_pop = 38,
    vector_truncate = 39,
    vector_clear = 40,
    text_empty = 41,
    text_append = 42,
    text_append_scalar = 43,
    text_append_unsigned = 44,
    text_append_signed = 45,
    text_copy = 46,
    text_compare = 47,
    text_join = 48,
    bytes_empty = 49,
    bytes_append = 50,
    bytes_copy = 51,
    bytes_compare = 52,
    text_length = 53,
    bytes_length = 54,
    bytes_append_scalar = 55,
    bytes_join = 56,
    enum_to_u32 = 57,
};

pub fn wireOperation(
    comptime operation: control_ir.InstructionOperation,
) WireOperation {
    return switch (operation) {
        .metadata => @compileError("metadata is not an executable operation"),
        .constant => .constant,
        .copy => .copy,
        .compare_eq_zero => .compare_eq_zero,
        .integer_add => .integer_add,
        .integer_subtract => .integer_subtract,
        .integer_multiply => .integer_multiply,
        .integer_divide => .integer_divide,
        .integer_remainder => .integer_remainder,
        .integer_negate => .integer_negate,
        .integer_equal => .integer_equal,
        .integer_not_equal => .integer_not_equal,
        .integer_less_than => .integer_less_than,
        .integer_less_equal => .integer_less_equal,
        .integer_greater_than => .integer_greater_than,
        .integer_greater_equal => .integer_greater_equal,
        .integer_bit_not => .integer_bit_not,
        .integer_bit_and => .integer_bit_and,
        .integer_bit_or => .integer_bit_or,
        .integer_bit_xor => .integer_bit_xor,
        .integer_convert => .integer_convert,
        .boolean_not => .boolean_not,
        .boolean_and => .boolean_and,
        .boolean_or => .boolean_or,
        .select => .select,
        .product_construct => .product_construct,
        .product_extract => .product_extract,
        .product_replace => .product_replace,
        .sum_construct => .sum_construct,
        .sum_tag_is => .sum_tag_is,
        .sum_extract => .sum_extract,
        .optional_none => .optional_none,
        .optional_some => .optional_some,
        .optional_is_some => .optional_is_some,
        .vector_empty => .vector_empty,
        .vector_length => .vector_length,
        .vector_get => .vector_get,
        .vector_set => .vector_set,
        .vector_push => .vector_push,
        .vector_pop => .vector_pop,
        .vector_truncate => .vector_truncate,
        .vector_clear => .vector_clear,
        .text_empty => .text_empty,
        .text_append => .text_append,
        .text_append_scalar => .text_append_scalar,
        .text_append_unsigned => .text_append_unsigned,
        .text_append_signed => .text_append_signed,
        .text_copy => .text_copy,
        .text_compare => .text_compare,
        .text_join => .text_join,
        .bytes_empty => .bytes_empty,
        .bytes_append => .bytes_append,
        .bytes_copy => .bytes_copy,
        .bytes_compare => .bytes_compare,
        .text_length => .text_length,
        .bytes_length => .bytes_length,
        .bytes_append_scalar => .bytes_append_scalar,
        .bytes_join => .bytes_join,
        .enum_to_u32 => .enum_to_u32,
    };
}

pub fn wireTag(
    comptime operation: control_ir.InstructionOperation,
) u16 {
    return @intFromEnum(wireOperation(operation));
}

pub fn currentSemanticTag(
    operation: control_ir.InstructionOperation,
) u8 {
    return @intCast(@intFromEnum(std.meta.activeTag(operation)));
}

pub fn canonicalInstructionKind(
    comptime operation: control_ir.InstructionOperation,
) control_ir.InstructionKind {
    return switch (operation) {
        .metadata => @compileError("metadata is not an executable operation"),
        .constant => .constant,
        .copy => .copy,
        .compare_eq_zero => .compare_eq_zero,
        else => .pure,
    };
}

pub fn failureRoles(
    comptime operation: control_ir.InstructionOperation,
) []const FailureRole {
    return switch (operation) {
        .integer_add,
        .integer_subtract,
        .integer_multiply,
        .integer_negate,
        .integer_convert,
        => &.{.arithmetic_overflow},
        .integer_divide, .integer_remainder => &.{
            .arithmetic_overflow,
            .division_by_zero,
        },
        .sum_extract => &.{.invalid_variant},
        .vector_get, .vector_set => &.{.invalid_index},
        .text_append_scalar, .text_copy => &.{
            .capacity_exceeded,
            .invalid_utf8,
        },
        .vector_push,
        .text_append,
        .text_append_unsigned,
        .text_append_signed,
        .text_join,
        .bytes_append,
        .bytes_append_scalar,
        .bytes_copy,
        .bytes_join,
        => &.{.capacity_exceeded},
        else => &.{},
    };
}

pub fn minimumBlockCost(comptime block: control_ir.Block) u64 {
    return @intCast(block.instructions.len + 1);
}

pub fn dynamicBytesCost(variable_size: bool, canonical_bytes: u64) u64 {
    if (!variable_size) return 0;
    return std.math.divCeil(
        u64,
        canonical_bytes,
        dynamic_fuel_quantum_bytes,
    ) catch std.math.maxInt(u64);
}
