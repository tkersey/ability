const control_ir = @import("control_ir");
const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const program_semantics_v1 = @import("program_semantics_v1");
const reducer_clause_v1 = @import("reducer_clause_v1");
const std = @import("std");

pub const Error = error{
    InvalidImage,
    InvalidBindings,
    ExecutionBudgetExceeded,
    UnsupportedOperation,
};

comptime {
    _ = program_semantics_v1.WireOperation;
}

pub const segment_fuel_semantic_domain =
    "segment-fuel=preflight-resource-shape-v4";
pub const dynamic_fuel_quantum_bytes: u64 = 16;
pub const await_effect_cost: u64 = 1;

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

/// Compute the exact-or-bounded canonical result size used only by Machine-v2
/// segment metering. `Backend` supplies representation-specific value access.
pub fn resultEncodedBytes(
    comptime instruction: control_ir.Instruction,
    context: anytype,
    comptime Backend: type,
) u64 {
    const maximum = Backend.maximumResultBytes(instruction);
    return switch (instruction.operation) {
        .metadata => unreachable,
        .constant => Backend.constantBytes(instruction),
        .copy => Backend.operandBytes(context, instruction.operands[0]),
        .product_construct => blk: {
            var total: u64 = 0;
            inline for (instruction.operands) |operand| {
                total +|= Backend.operandBytes(context, operand);
            }
            break :blk Backend.boundedResultBytes(instruction, total);
        },
        .product_extract => |field_index| Backend.exactProductFieldBytes(
            context,
            instruction,
            field_index,
        ) orelse maximum,
        .product_replace => maximum,
        .sum_construct => Backend.boundedResultBytes(
            instruction,
            4 +| if (instruction.operands.len == 0)
                0
            else
                Backend.operandBytes(context, instruction.operands[0]),
        ),
        .sum_extract => maximum,
        .optional_none => 1,
        .optional_some => Backend.boundedResultBytes(
            instruction,
            1 +| Backend.operandBytes(context, instruction.operands[0]),
        ),
        .select => @max(
            Backend.operandBytes(context, instruction.operands[1]),
            Backend.operandBytes(context, instruction.operands[2]),
        ),
        .vector_empty, .text_empty, .bytes_empty => 4,
        .vector_get => Backend.exactVectorElementBytes(
            context,
            instruction,
        ) orelse maximum,
        .vector_set => maximum,
        .vector_push => Backend.boundedResultBytes(
            instruction,
            Backend.operandBytes(context, instruction.operands[0]) +|
                Backend.operandBytes(context, instruction.operands[1]),
        ),
        .vector_pop => maximum,
        .vector_truncate => @min(
            maximum,
            Backend.operandBytes(context, instruction.operands[0]),
        ),
        .vector_clear => 4,
        .text_append, .bytes_append => combinedSequenceBytes(
            instruction,
            context,
            Backend,
            &.{1},
        ),
        .bytes_append_scalar => Backend.boundedResultBytes(
            instruction,
            Backend.operandBytes(context, instruction.operands[0]) +| 1,
        ),
        .text_append_scalar => Backend.boundedResultBytes(
            instruction,
            Backend.operandBytes(context, instruction.operands[0]) +| 4,
        ),
        .text_append_unsigned, .text_append_signed => Backend.boundedResultBytes(
            instruction,
            Backend.operandBytes(context, instruction.operands[0]) +| 20,
        ),
        .text_copy, .bytes_copy => @min(
            maximum,
            Backend.operandBytes(context, instruction.operands[0]),
        ),
        .text_join, .bytes_join => combinedSequenceBytes(
            instruction,
            context,
            Backend,
            &.{ 1, 2 },
        ),
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
        .enum_to_u32,
        .boolean_not,
        .boolean_and,
        .boolean_or,
        .sum_tag_is,
        .optional_is_some,
        .vector_length,
        .text_length,
        .bytes_length,
        .text_compare,
        .bytes_compare,
        .text_byte_at,
        => maximum,
    };
}

fn combinedSequenceBytes(
    comptime instruction: control_ir.Instruction,
    context: anytype,
    comptime Backend: type,
    comptime suffix_operand_indexes: []const usize,
) u64 {
    var result = Backend.operandBytes(context, instruction.operands[0]);
    inline for (suffix_operand_indexes) |operand_index| {
        result +|= Backend.operandBytes(
            context,
            instruction.operands[operand_index],
        ) -| 4;
    }
    return Backend.boundedResultBytes(instruction, result);
}

/// Preflight the exact Machine-v2 cost of one byte-level clause.
pub fn preflightSegmentCost(
    image: anytype,
    segment: []const u8,
    constructor: []const u8,
    environment: []const u8,
    slots: *const [1024]reducer_clause_v1.Slot,
    base_cost: u64,
    workspace: *image_v1.ValidationWorkspace,
) Error!u64 {
    var sizes = [_]usize{0} ** 1024;
    var initially_available = [_]bool{false} ** 1024;
    var cost = base_cost;
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var environment_field_cursor: usize = 24;
    var environment_value_cursor: usize = if (readInt(
        u16,
        constructor,
        10,
    ) & 1 != 0) 4 else 0;
    if (environment_value_cursor > environment.len) {
        return error.InvalidBindings;
    }
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, environment_field_cursor);
        if (!slots[value].initialized) return error.InvalidBindings;
        const schema_id = readInt(
            u32,
            constructor,
            environment_field_cursor + 4,
        );
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema_id,
            environment[environment_value_cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidBindings;
        sizes[value] = consumed;
        initially_available[value] = true;
        try addDynamicCostSize(image, value, consumed, &cost);
        environment_value_cursor += consumed;
        environment_field_cursor += 8;
    }
    if (environment_value_cursor != environment.len) {
        return error.InvalidBindings;
    }
    var cursor: usize = image_v1.segment_prefix_length +
        @as(usize, readInt(u16, segment, 10)) * 2;
    const instruction_count = readInt(u32, segment, 12);
    for (0..instruction_count) |_| {
        const instruction_length = readInt(u32, segment, cursor);
        const operation = readInt(u16, segment, cursor + 6);
        const result = readInt(u16, segment, cursor + 8);
        const operand_count = readInt(u16, segment, cursor + 10);
        for (0..operand_count) |operand_index| {
            const operand = readInt(u16, segment, cursor + 16 + operand_index * 2);
            try addDynamicCostSize(image, operand, sizes[operand], &cost);
        }
        sizes[result] = try preflightResultSize(
            image,
            segment,
            cursor,
            operation,
            result,
            operandsForInstruction(segment[cursor .. cursor + instruction_length]),
            slots,
            &sizes,
            &initially_available,
            workspace,
        );
        try addDynamicCostSize(image, result, sizes[result], &cost);
        cursor += instruction_length;
    }
    return cost;
}

fn addDynamicCostSize(
    image: anytype,
    value: u16,
    encoded_size: u64,
    cost: *u64,
) Error!void {
    const node = reducer_clause_v1.valueNode(image, value) catch
        return error.InvalidImage;
    if (node.minimum_encoded_size == node.maximum_encoded_size) return;
    const dynamic = std.math.divCeil(
        u64,
        encoded_size,
        dynamic_fuel_quantum_bytes,
    ) catch return error.ExecutionBudgetExceeded;
    cost.* = std.math.add(u64, cost.*, dynamic) catch
        return error.ExecutionBudgetExceeded;
}

fn operandsForInstruction(instruction: []const u8) []const u8 {
    const count = readInt(u16, instruction, 10);
    return instruction[16..][0 .. @as(usize, count) * 2];
}

fn preflightResultSize(
    image: anytype,
    segment: []const u8,
    instruction_offset: usize,
    operation: u16,
    result: u16,
    operand_bytes: []const u8,
    slots: *const [1024]reducer_clause_v1.Slot,
    sizes: *const [1024]usize,
    initially_available: *const [1024]bool,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    const result_node = reducer_clause_v1.valueNode(image, result) catch
        return error.InvalidImage;
    const maximum: usize = @intCast(result_node.maximum_encoded_size);
    const size = struct {
        fn get(bytes: []const u8, index: usize, values: *const [1024]usize) usize {
            return values[readInt(u16, bytes, index * 2)];
        }
    }.get;
    return switch (operation) {
        0 => (reducer_clause_v1.constantBytes(
            image,
            readInt(u32, segment, instruction_offset + 12),
        ) catch return error.InvalidImage).len,
        1 => size(operand_bytes, 0, sizes),
        2...22, 28, 32, 34, 47, 52, 53, 54, 57 => maximum,
        40 => 4,
        23 => @max(size(operand_bytes, 1, sizes), size(operand_bytes, 2, sizes)),
        24 => blk: {
            var total: usize = 0;
            var index: usize = 0;
            while (index < operand_bytes.len) : (index += 2) {
                total +|= sizes[readInt(u16, operand_bytes, index)];
            }
            break :blk @min(maximum, total);
        },
        25 => blk: {
            const product = readInt(u16, operand_bytes, 0);
            const field_index = readInt(u32, segment, instruction_offset + 12);
            if (initially_available[product]) {
                break :blk (reducer_clause_v1.productField(
                    image,
                    product,
                    slots[product].bytes,
                    field_index,
                    workspace,
                ) catch break :blk maximum).len;
            }
            break :blk @intCast(preflightProductFieldSize(
                image,
                segment,
                instruction_offset,
                product,
                field_index,
                slots,
                sizes,
                initially_available,
                workspace,
            ) orelse maximum);
        },
        35 => blk: {
            const vector = readInt(u16, operand_bytes, 0);
            const index = readInt(u16, operand_bytes, 2);
            if (!initially_available[vector] or !initially_available[index]) {
                break :blk maximum;
            }
            const index_kind = reducer_clause_v1.valueKind(image, index) catch
                break :blk maximum;
            const raw_index = reducer_clause_v1.decodeInteger(
                index_kind,
                slots[index].bytes,
            ) catch break :blk maximum;
            const target = std.math.cast(u32, raw_index.raw) orelse
                break :blk maximum;
            break :blk (reducer_clause_v1.vectorElement(
                image,
                vector,
                slots[vector].bytes,
                target,
                workspace,
            ) catch break :blk maximum).len;
        },
        26, 29, 36, 38 => maximum,
        27 => @min(
            maximum,
            4 + if (operand_bytes.len == 0) 0 else size(operand_bytes, 0, sizes),
        ),
        30 => 1,
        31 => @min(maximum, 1 + size(operand_bytes, 0, sizes)),
        33, 41, 49 => 4,
        37 => @min(
            maximum,
            size(operand_bytes, 0, sizes) +| size(operand_bytes, 1, sizes),
        ),
        39 => @min(maximum, size(operand_bytes, 0, sizes)),
        42, 50 => @min(
            maximum,
            size(operand_bytes, 0, sizes) +|
                (size(operand_bytes, 1, sizes) -| 4),
        ),
        43 => @min(maximum, size(operand_bytes, 0, sizes) +| 4),
        44, 45 => @min(maximum, size(operand_bytes, 0, sizes) +| 20),
        46, 51 => @min(maximum, size(operand_bytes, 0, sizes)),
        48, 56 => @min(
            maximum,
            size(operand_bytes, 0, sizes) +|
                (size(operand_bytes, 1, sizes) -| 4) +|
                (size(operand_bytes, 2, sizes) -| 4),
        ),
        55 => @min(maximum, size(operand_bytes, 0, sizes) +| 1),
        else => error.UnsupportedOperation,
    };
}

fn preflightProductFieldSize(
    image: anytype,
    segment: []const u8,
    instruction_offset: usize,
    product_value: u16,
    field_index: u32,
    slots: *const [1024]reducer_clause_v1.Slot,
    sizes: *const [1024]usize,
    initially_available: *const [1024]bool,
    workspace: *image_v1.ValidationWorkspace,
) ?usize {
    var current_value = product_value;
    var current_limit = instruction_offset;
    while (true) {
        var cursor: usize = image_v1.segment_prefix_length +
            @as(usize, readInt(u16, segment, 10)) * 2;
        var definition: ?usize = null;
        while (cursor < current_limit) {
            const length = readInt(u32, segment, cursor);
            if (readInt(u16, segment, cursor + 8) == current_value) {
                definition = cursor;
                break;
            }
            cursor += length;
        }
        const offset = definition orelse return null;
        switch (readInt(u16, segment, offset + 6)) {
            1 => {
                current_value = readInt(u16, segment, offset + 16);
                current_limit = offset;
            },
            24 => return sizes[
                readInt(
                    u16,
                    segment,
                    offset + 16 + @as(usize, field_index) * 2,
                )
            ],
            26 => {
                if (readInt(u32, segment, offset + 12) == field_index) {
                    return sizes[readInt(u16, segment, offset + 18)];
                }
                current_value = readInt(u16, segment, offset + 16);
                current_limit = offset;
            },
            35 => {
                const vector = readInt(u16, segment, offset + 16);
                const index = readInt(u16, segment, offset + 18);
                if (!initially_available[vector] or
                    !initially_available[index]) return null;
                const index_kind = reducer_clause_v1.valueKind(image, index) catch
                    return null;
                const raw_index = reducer_clause_v1.decodeInteger(
                    index_kind,
                    slots[index].bytes,
                ) catch return null;
                const target = std.math.cast(u32, raw_index.raw) orelse
                    return null;
                const element = reducer_clause_v1.vectorElement(
                    image,
                    vector,
                    slots[vector].bytes,
                    target,
                    workspace,
                ) catch return null;
                return (reducer_clause_v1.productField(
                    image,
                    current_value,
                    element,
                    field_index,
                    workspace,
                ) catch return null).len;
            },
            else => return null,
        }
    }
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
