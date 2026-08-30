const control_ir = @import("control_ir");
const portable_value = @import("portable_value");
const rnf = @import("rnf");
const std = @import("std");

pub const FailureRole = enum {
    arithmetic_overflow,
    division_by_zero,
    capacity_exceeded,
    invalid_utf8,
    invalid_index,
    invalid_variant,
};

pub const WireTerminator = enum(u8) {
    jump = 0,
    branch = 1,
    @"suspend" = 2,
    return_value = 3,
    return_to_caller = 4,
    fail = 5,
    fail_value = 6,
};

pub const WireSuspension = enum(u8) {
    effect = 0,
    call = 1,
    explicit_yield = 2,
};

pub const WireInvariant = enum(u8) {
    boolean = 0,
    boolean_copy = 1,
    boolean_not = 2,
    boolean_binary = 3,
    boolean_select = 4,
    value_copy = 5,
    value_constant = 6,
    value_select = 7,
    instruction_result = 8,
    product_extract_result = 9,
    sum_extract_result = 10,
    bounded_length_result = 11,
    integer_unary_result = 12,
    integer_binary_result = 13,
    integer_convert_result = 14,
    integer_zero = 15,
    integer_zero_result = 16,
    integer_relation = 17,
    integer_relation_result = 18,
    sum_case = 19,
    sum_case_result = 20,
};

pub const WireConstructorKind = enum(u8) {
    entry = 0,
    segment_entry = 1,
    loop_header = 2,
    await_effect = 3,
    call_return = 4,
    after_handler = 5,
    explicit_yield = 6,
    terminal_handoff = 7,
};

pub const WireConstructorOrigin = enum(u8) {
    block_entry = 0,
    call_entry = 1,
    suspension = 2,
};

pub const WireIncomingEdge = enum(u8) {
    jump = 0,
    branch_then = 1,
    branch_else = 2,
    call = 3,
    suspension_continuation = 4,
};

pub fn wireTerminator(terminator: control_ir.Terminator) WireTerminator {
    return switch (terminator) {
        .jump => .jump,
        .branch => .branch,
        .@"suspend" => .@"suspend",
        .return_value => .return_value,
        .return_to_caller => .return_to_caller,
        .fail => .fail,
        .fail_value => .fail_value,
    };
}

pub fn wireInvariant(invariant: rnf.InvariantTerm) WireInvariant {
    return switch (invariant) {
        .boolean => .boolean,
        .boolean_copy => .boolean_copy,
        .boolean_not => .boolean_not,
        .boolean_binary => .boolean_binary,
        .boolean_select => .boolean_select,
        .value_copy => .value_copy,
        .value_constant => .value_constant,
        .value_select => .value_select,
        .instruction_result => .instruction_result,
        .product_extract_result => .product_extract_result,
        .sum_extract_result => .sum_extract_result,
        .bounded_length_result => .bounded_length_result,
        .integer_unary_result => .integer_unary_result,
        .integer_binary_result => .integer_binary_result,
        .integer_convert_result => .integer_convert_result,
        .integer_zero => .integer_zero,
        .integer_zero_result => .integer_zero_result,
        .integer_relation => .integer_relation,
        .integer_relation_result => .integer_relation_result,
        .sum_case => .sum_case,
        .sum_case_result => .sum_case_result,
    };
}

pub fn wireConstructorOrigin(
    origin: rnf.ConstructorOrigin,
) WireConstructorOrigin {
    return switch (origin) {
        .block_entry => .block_entry,
        .call_entry => .call_entry,
        .suspension => .suspension,
    };
}

pub fn wireIncomingEdge(kind: rnf.IncomingEdgeKind) WireIncomingEdge {
    return switch (kind) {
        .jump => .jump,
        .branch_then => .branch_then,
        .branch_else => .branch_else,
        .call => .call,
        .suspension_continuation => .suspension_continuation,
    };
}

pub fn failureName(comptime role: FailureRole) []const u8 {
    return failureRoleName(role);
}

pub fn failureRoleName(role: FailureRole) []const u8 {
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

/// Canonical fixed arity for BPI1 operation tags. Product and sum
/// construction derive their arity from the result schema.
pub fn fixedOperandCount(operation: WireOperation) ?u16 {
    return switch (operation) {
        .product_construct, .sum_construct => null,
        .constant,
        .optional_none,
        .vector_empty,
        .text_empty,
        .bytes_empty,
        => 0,
        .copy,
        .compare_eq_zero,
        .integer_negate,
        .integer_bit_not,
        .integer_convert,
        .boolean_not,
        .product_extract,
        .sum_tag_is,
        .sum_extract,
        .optional_some,
        .optional_is_some,
        .vector_length,
        .vector_pop,
        .vector_clear,
        .text_length,
        .bytes_length,
        .enum_to_u32,
        => 1,
        .integer_add,
        .integer_subtract,
        .integer_multiply,
        .integer_divide,
        .integer_remainder,
        .integer_equal,
        .integer_not_equal,
        .integer_less_than,
        .integer_less_equal,
        .integer_greater_than,
        .integer_greater_equal,
        .integer_bit_and,
        .integer_bit_or,
        .integer_bit_xor,
        .boolean_and,
        .boolean_or,
        .product_replace,
        .vector_get,
        .vector_push,
        .vector_truncate,
        .text_append,
        .text_append_scalar,
        .text_append_unsigned,
        .text_append_signed,
        .text_compare,
        .bytes_append,
        .bytes_append_scalar,
        .bytes_compare,
        => 2,
        .select,
        .vector_set,
        .text_copy,
        .text_join,
        .bytes_copy,
        .bytes_join,
        => 3,
    };
}

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

/// Map a BPI1 operation tag back to the frozen current-v4 semantic tag.
pub fn currentSemanticTagForWire(operation: WireOperation) u8 {
    return @intCast(@intFromEnum(operation) + 1);
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
    return failureRolesForWire(wireOperation(operation));
}

pub fn validOperandCount(
    comptime operation: control_ir.InstructionOperation,
    actual: usize,
    base: usize,
) bool {
    return control_ir.validInstructionOperandCount(operation, actual, base);
}

pub fn usesAuthoredFailures(
    comptime operation: control_ir.InstructionOperation,
    operand_count: usize,
) bool {
    const base = fixedOperandCount(wireOperation(operation)) orelse return false;
    const failure_count = failureRoles(operation).len;
    return failure_count != 0 and operand_count == base + failure_count;
}

fn failureForInstruction(
    comptime Body: type,
    comptime Backend: type,
    comptime instruction: control_ir.Instruction,
    store: anytype,
    comptime role: FailureRole,
) Body.Failure {
    if (comptime !usesAuthoredFailures(
        instruction.operation,
        instruction.operands.len,
    )) {
        return Backend.failure(role);
    }
    const base = comptime fixedOperandCount(wireOperation(instruction.operation)).?;
    const roles = comptime failureRoles(instruction.operation);
    inline for (roles, 0..) |candidate, index| {
        if (candidate == role) {
            return @field(
                store,
                Backend.valueName(instruction.operands[base + index]),
            );
        }
    }
    unreachable;
}

pub fn failureRolesForWire(operation: WireOperation) []const FailureRole {
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
        .constant,
        .copy,
        .compare_eq_zero,
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
        .boolean_not,
        .boolean_and,
        .boolean_or,
        .select,
        .product_construct,
        .product_extract,
        .product_replace,
        .sum_construct,
        .sum_tag_is,
        .optional_none,
        .optional_some,
        .optional_is_some,
        .vector_empty,
        .vector_length,
        .vector_pop,
        .vector_truncate,
        .vector_clear,
        .text_empty,
        .text_compare,
        .bytes_empty,
        .bytes_compare,
        .text_length,
        .bytes_length,
        .enum_to_u32,
        => &.{},
    };
}

pub noinline fn executeTypedInstructions(
    comptime Body: type,
    comptime ValueCatalog: type,
    comptime Backend: type,
    comptime block: control_ir.Block,
    store: anytype,
) ?Body.Failure {
    inline for (block.instructions) |instruction| {
        const result_name = comptime Backend.valueName(instruction.result);
        switch (instruction.operation) {
            .metadata => unreachable,
            .constant => |constant_index| {
                const Constant = @TypeOf(Body.constants[constant_index]);
                const canonical = comptime portable_value.canonicalValue(
                    Constant,
                    Body.constants[constant_index],
                ) catch unreachable;
                @field(store, result_name) = canonical;
            },
            .copy => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
            },
            .compare_eq_zero => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) == 0;
            },
            .integer_add => {
                const ResultType = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = std.math.add(
                    ResultType,
                    @field(store, Backend.valueName(instruction.operands[0])),
                    @field(store, Backend.valueName(instruction.operands[1])),
                ) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .arithmetic_overflow,
                );
            },
            .integer_subtract => {
                const ResultType = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = std.math.sub(
                    ResultType,
                    @field(store, Backend.valueName(instruction.operands[0])),
                    @field(store, Backend.valueName(instruction.operands[1])),
                ) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .arithmetic_overflow,
                );
            },
            .integer_multiply => {
                const ResultType = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = std.math.mul(
                    ResultType,
                    @field(store, Backend.valueName(instruction.operands[0])),
                    @field(store, Backend.valueName(instruction.operands[1])),
                ) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .arithmetic_overflow,
                );
            },
            .integer_divide => {
                const ResultType = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = std.math.divTrunc(
                    ResultType,
                    @field(store, Backend.valueName(instruction.operands[0])),
                    @field(store, Backend.valueName(instruction.operands[1])),
                ) catch |err| return switch (err) {
                    error.DivisionByZero => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .division_by_zero,
                    ),
                    error.Overflow => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .arithmetic_overflow,
                    ),
                };
            },
            .integer_remainder => {
                const ResultType = @FieldType(ValueCatalog, result_name);
                const left = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const right = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                _ = std.math.divTrunc(
                    ResultType,
                    left,
                    right,
                ) catch |err| return switch (err) {
                    error.DivisionByZero => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .division_by_zero,
                    ),
                    error.Overflow => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .arithmetic_overflow,
                    ),
                };
                @field(store, result_name) = @rem(left, right);
            },
            .integer_negate => {
                @field(store, result_name) = std.math.negate(@field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                )) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .arithmetic_overflow,
                );
            },
            .integer_equal => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) == @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_not_equal => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) != @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_less_than => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) < @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_less_equal => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) <= @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_greater_than => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) > @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_greater_equal => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) >= @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_bit_not => {
                @field(store, result_name) = ~@field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
            },
            .integer_bit_and => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) & @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_bit_or => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) | @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_bit_xor => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) ^ @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .integer_convert => {
                const ResultType = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = std.math.cast(
                    ResultType,
                    @field(store, Backend.valueName(instruction.operands[0])),
                ) orelse return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .arithmetic_overflow,
                );
            },
            .enum_to_u32 => {
                @field(store, result_name) = @intCast(@intFromEnum(@field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                )));
            },
            .boolean_not => {
                @field(store, result_name) = !@field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
            },
            .boolean_and => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) and @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .boolean_or => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) or @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
            },
            .select => {
                @field(store, result_name) = if (@field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ))
                    @field(
                        store,
                        Backend.valueName(instruction.operands[1]),
                    )
                else
                    @field(
                        store,
                        Backend.valueName(instruction.operands[2]),
                    );
            },
            .product_construct => {
                const Product = @FieldType(ValueCatalog, result_name);
                var product: Product = undefined;
                inline for (
                    std.meta.fields(Product),
                    instruction.operands,
                ) |field, operand| {
                    @field(product, field.name) = @field(
                        store,
                        Backend.valueName(operand),
                    );
                }
                @field(store, result_name) = product;
            },
            .product_extract => |field_index| {
                const Product = @FieldType(
                    ValueCatalog,
                    Backend.valueName(instruction.operands[0]),
                );
                const field = std.meta.fields(Product)[field_index];
                @field(store, result_name) = @field(
                    @field(
                        store,
                        Backend.valueName(instruction.operands[0]),
                    ),
                    field.name,
                );
            },
            .product_replace => |field_index| {
                var product = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const Product = @TypeOf(product);
                const field = std.meta.fields(Product)[field_index];
                @field(product, field.name) = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                @field(store, result_name) = product;
            },
            .sum_construct => |variant_index| {
                const Sum = @FieldType(ValueCatalog, result_name);
                const field = std.meta.fields(Sum)[variant_index];
                @field(store, result_name) = @unionInit(
                    Sum,
                    field.name,
                    if (field.type == void) {} else @field(
                        store,
                        Backend.valueName(instruction.operands[0]),
                    ),
                );
            },
            .sum_tag_is => |variant_index| {
                const Sum = @FieldType(
                    ValueCatalog,
                    Backend.valueName(instruction.operands[0]),
                );
                const Tag = @typeInfo(Sum).@"union".tag_type.?;
                const field = std.meta.fields(Sum)[variant_index];
                @field(store, result_name) = std.meta.activeTag(@field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                )) == @field(Tag, field.name);
            },
            .sum_extract => |variant_index| {
                const sum = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const Sum = @TypeOf(sum);
                const Tag = @typeInfo(Sum).@"union".tag_type.?;
                const field = std.meta.fields(Sum)[variant_index];
                if (std.meta.activeTag(sum) != @field(Tag, field.name)) {
                    return failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .invalid_variant,
                    );
                }
                @field(store, result_name) = @field(sum, field.name);
            },
            .optional_none => {
                @field(store, result_name) = null;
            },
            .optional_some => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
            },
            .optional_is_some => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ) != null;
            },
            .vector_empty => {
                const Vector = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = Vector.empty();
            },
            .vector_length => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ).len() catch unreachable;
            },
            .vector_get => {
                const observed = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ).get(@field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                )) catch unreachable;
                @field(store, result_name) = observed orelse
                    return failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .invalid_index,
                    );
            },
            .vector_set => {
                var vector = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                vector.set(
                    @field(
                        store,
                        Backend.valueName(instruction.operands[1]),
                    ),
                    @field(
                        store,
                        Backend.valueName(instruction.operands[2]),
                    ),
                ) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .invalid_index,
                );
                @field(store, result_name) = vector;
            },
            .vector_push => {
                var vector = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                vector.push(@field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                )) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .capacity_exceeded,
                );
                @field(store, result_name) = vector;
            },
            .vector_pop => {
                var vector = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const popped = vector.pop() catch unreachable;
                const Product = @FieldType(ValueCatalog, result_name);
                const fields = std.meta.fields(Product);
                var product: Product = undefined;
                @field(product, fields[0].name) = vector;
                @field(product, fields[1].name) = popped;
                @field(store, result_name) = product;
            },
            .vector_truncate => {
                var vector = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                vector.truncate(@field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                ));
                @field(store, result_name) = vector;
            },
            .vector_clear => {
                var vector = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                vector.clear();
                @field(store, result_name) = vector;
            },
            .text_empty => {
                const Text = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = Text.empty();
            },
            .text_length => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ).len() catch unreachable;
            },
            .text_append => {
                var text = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const suffix = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                text.append(suffix.slice() catch unreachable) catch
                    return failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .capacity_exceeded,
                    );
                @field(store, result_name) = text;
            },
            .text_append_scalar => {
                var text = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const scalar = std.math.cast(
                    u21,
                    @field(
                        store,
                        Backend.valueName(instruction.operands[1]),
                    ),
                ) orelse return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .invalid_utf8,
                );
                text.appendScalar(scalar) catch |err| return switch (err) {
                    error.InvalidUtf8 => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .invalid_utf8,
                    ),
                    error.CapacityExceeded => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .capacity_exceeded,
                    ),
                    else => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .capacity_exceeded,
                    ),
                };
                @field(store, result_name) = text;
            },
            .text_append_unsigned => {
                var text = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                text.appendUnsigned(@intCast(@field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                ))) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .capacity_exceeded,
                );
                @field(store, result_name) = text;
            },
            .text_append_signed => {
                var text = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                text.appendSigned(@intCast(@field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                ))) catch return failureForInstruction(
                    Body,
                    Backend,
                    instruction,
                    store,
                    .capacity_exceeded,
                );
                @field(store, result_name) = text;
            },
            .text_copy => {
                const Source = @FieldType(
                    ValueCatalog,
                    Backend.valueName(instruction.operands[0]),
                );
                _ = Source;
                const ResultText = @FieldType(
                    ValueCatalog,
                    result_name,
                );
                const source = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                @field(store, result_name) = source.copyRange(
                    ResultText.maximum_length,
                    @field(
                        store,
                        Backend.valueName(instruction.operands[1]),
                    ),
                    @field(
                        store,
                        Backend.valueName(instruction.operands[2]),
                    ),
                ) catch |err| return switch (err) {
                    error.InvalidUtf8 => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .invalid_utf8,
                    ),
                    error.CapacityExceeded => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .capacity_exceeded,
                    ),
                    else => failureForInstruction(
                        Body,
                        Backend,
                        instruction,
                        store,
                        .capacity_exceeded,
                    ),
                };
            },
            .text_compare => {
                const left = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const right = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                @field(store, result_name) = switch (std.mem.order(
                    u8,
                    left.slice() catch unreachable,
                    right.slice() catch unreachable,
                )) {
                    .lt => -1,
                    .eq => 0,
                    .gt => 1,
                };
            },
            .text_join => {
                var text = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const separator = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                const right = @field(
                    store,
                    Backend.valueName(instruction.operands[2]),
                );
                text.append(separator.slice() catch unreachable) catch
                    return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
                text.append(right.slice() catch unreachable) catch
                    return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
                @field(store, result_name) = text;
            },
            .bytes_empty => {
                const Bytes = @FieldType(ValueCatalog, result_name);
                @field(store, result_name) = Bytes.empty();
            },
            .bytes_length => {
                @field(store, result_name) = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                ).len() catch unreachable;
            },
            .bytes_append => {
                var bytes = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const suffix = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                bytes.append(suffix.slice() catch unreachable) catch
                    return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
                @field(store, result_name) = bytes;
            },
            .bytes_append_scalar => {
                var bytes = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const scalar = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                bytes.append(&.{scalar}) catch
                    return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
                @field(store, result_name) = bytes;
            },
            .bytes_copy => {
                const ResultBytes = @FieldType(
                    ValueCatalog,
                    result_name,
                );
                const source = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                @field(store, result_name) = source.copyRange(
                    ResultBytes.maximum_length,
                    @field(
                        store,
                        Backend.valueName(instruction.operands[1]),
                    ),
                    @field(
                        store,
                        Backend.valueName(instruction.operands[2]),
                    ),
                ) catch return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
            },
            .bytes_compare => {
                const left = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const right = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                @field(store, result_name) = switch (std.mem.order(
                    u8,
                    left.slice() catch unreachable,
                    right.slice() catch unreachable,
                )) {
                    .lt => -1,
                    .eq => 0,
                    .gt => 1,
                };
            },
            .bytes_join => {
                var bytes = @field(
                    store,
                    Backend.valueName(instruction.operands[0]),
                );
                const separator = @field(
                    store,
                    Backend.valueName(instruction.operands[1]),
                );
                const right = @field(
                    store,
                    Backend.valueName(instruction.operands[2]),
                );
                bytes.append(separator.slice() catch unreachable) catch
                    return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
                bytes.append(right.slice() catch unreachable) catch
                    return failureForInstruction(Body, Backend, instruction, store, .capacity_exceeded);
                @field(store, result_name) = bytes;
            },
        }
    }
    return null;
}
