const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const std = @import("std");

pub const Error = error{
    InvalidImage,
    InvalidState,
    InvalidInitialArgs,
    OutputCapacity,
    ExecutionBudgetExceeded,
    UnsupportedOperation,
    ScratchCapacity,
};

pub const state_magic = "ABL_RNF2".*;
pub const state_header_length: usize = 68;
pub const frame_header_length: usize = 8;

pub const Outcome = union(enum) {
    yielded,
    done: []const u8,
    failed: []const u8,
};

const Slot = struct {
    bytes: []const u8 = &.{},
    initialized: bool = false,
};

/// Construct the exact initial ABL_RNF2 State from canonical InitialArgs.
pub fn initial(
    image: image_v1.ValidatedImage,
    initial_args: []const u8,
    output_state: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    dynamic_value_v1.validateValue(
        image.catalogs.schemas,
        image.catalogs.initial_args_schema_id,
        initial_args,
        &workspace.value_tasks,
    ) catch return error.InvalidInitialArgs;
    const constructor = constructorRecord(
        image,
        image.catalogs.initial_constructor_id,
    ) catch return error.InvalidImage;
    const flags = readInt(u16, constructor, 10);
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    if (flags & 1 != 0 or activation_count != 0 or environment_count > 1) {
        return error.InvalidImage;
    }
    var environment_length: usize = 0;
    if (environment_count == 1) {
        const value_id = readInt(u16, constructor, 24);
        const schema_id = readInt(u32, constructor, 28);
        if (image.catalogs.entry_parameter_count != 1 or
            value_id != image.catalogs.entry_parameter_value_id or
            schema_id != image.catalogs.initial_args_schema_id)
        {
            return error.InvalidImage;
        }
        environment_length = initial_args.len;
    } else if (image.catalogs.entry_parameter_count == 1) {
        // An unused entry argument is intentionally absent from RNF State.
        environment_length = 0;
    }
    const required = state_header_length + frame_header_length +
        environment_length;
    if (required > image.catalogs.envelope.header.maximum_state_bytes) {
        return error.InvalidImage;
    }
    if (output_state.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    appendBytes(output_state, &cursor, &state_magic);
    appendInt(u16, output_state, &cursor, image_v1.state_format_version);
    appendInt(u16, output_state, &cursor, image_v1.machine_abi_version);
    appendBytes(
        output_state,
        &cursor,
        &image.catalogs.envelope.header.machine_contract_digest,
    );
    appendInt(u64, output_state, &cursor, 0);
    appendInt(u64, output_state, &cursor, 0);
    appendInt(u32, output_state, &cursor, 1);
    appendInt(u32, output_state, &cursor, 0);
    appendInt(
        u32,
        output_state,
        &cursor,
        image.catalogs.initial_constructor_id,
    );
    appendInt(u32, output_state, &cursor, environment_length);
    if (environment_length != 0) {
        appendBytes(output_state, &cursor, initial_args);
    }
    if (cursor != required) return error.InvalidImage;
    try validateState(image, output_state[0..required], workspace);
    return required;
}

/// Validate canonical State framing and every constructor environment value.
pub fn validateState(
    image: image_v1.ValidatedImage,
    state: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    if (state.len < state_header_length + frame_header_length or
        state.len > image.catalogs.envelope.header.maximum_state_bytes or
        !std.mem.eql(u8, state[0..8], &state_magic) or
        readInt(u16, state, 8) != image_v1.state_format_version or
        readInt(u16, state, 10) != image_v1.machine_abi_version or
        !std.mem.eql(
            u8,
            state[12..44],
            &image.catalogs.envelope.header.machine_contract_digest,
        ))
    {
        return error.InvalidState;
    }
    const sequence = readInt(u64, state, 44);
    const cumulative_fuel = readInt(u64, state, 52);
    const frame_count = readInt(u32, state, 60);
    if (readInt(u32, state, 64) != 0 or frame_count == 0 or
        frame_count > image.catalogs.envelope.header.maximum_frames or
        cumulative_fuel > image.catalogs.envelope.header.maximum_machine_fuel or
        sequence > cumulative_fuel)
    {
        return error.InvalidState;
    }
    var cursor: usize = state_header_length;
    var top_kind: u8 = 0;
    for (0..frame_count) |_| {
        if (state.len - cursor < frame_header_length) return error.InvalidState;
        const constructor_id = readInt(u32, state, cursor);
        const environment_length = readInt(u32, state, cursor + 4);
        cursor += frame_header_length;
        const environment_end = std.math.add(
            usize,
            cursor,
            environment_length,
        ) catch return error.InvalidState;
        if (environment_end > state.len) return error.InvalidState;
        const constructor = constructorRecord(image, constructor_id) catch
            return error.InvalidState;
        top_kind = constructor[8];
        validateEnvironment(
            image,
            constructor,
            state[cursor..environment_end],
            workspace,
        ) catch return error.InvalidState;
        cursor = environment_end;
    }
    if (cursor != state.len or (top_kind == 3 and sequence == 0)) {
        return error.InvalidState;
    }
}

/// Execute one funded atomic segment. This initial kernel slice owns terminal
/// clauses and the representation-neutral constant/copy operations.
pub fn step(
    image: image_v1.ValidatedImage,
    state: []const u8,
    caller_fuel: *u64,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const constructor_id = topConstructorId(state) catch
        return error.InvalidState;
    const constructor = constructorRecord(image, constructor_id) catch
        return error.InvalidState;
    const segment_id = readInt(u16, constructor, 12);
    const segment = segmentRecord(image, segment_id) catch
        return error.InvalidImage;
    const cost = readInt(u64, segment, 16);
    if (caller_fuel.* < cost) return .yielded;
    try validateState(image, state, workspace);
    const cumulative = readInt(u64, state, 52);
    _ = std.math.add(u64, cumulative, cost) catch
        return error.ExecutionBudgetExceeded;
    if (cumulative + cost > image.catalogs.envelope.header.maximum_machine_fuel) {
        return error.ExecutionBudgetExceeded;
    }

    var slots = [_]Slot{.{}} ** 1024;
    var scratch_cursor: usize = 0;
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    var cursor: usize = 24;
    const parameter_count = readInt(u16, segment, 10);
    const instruction_count = readInt(u32, segment, 12);
    cursor += @as(usize, parameter_count) * 2;
    for (0..instruction_count) |_| {
        const instruction_length = readInt(u32, segment, cursor);
        const operation = readInt(u16, segment, cursor + 6);
        const result = readInt(u16, segment, cursor + 8);
        const operand_count = readInt(u16, segment, cursor + 10);
        const immediate = readInt(u32, segment, cursor + 12);
        const failure: ?u32 = switch (operation) {
            0 => blk: {
                slots[result] = .{
                    .bytes = try constantBytes(image, immediate),
                    .initialized = true,
                };
                break :blk null;
            },
            1 => blk: {
                if (operand_count != 1) return error.InvalidImage;
                const operand = readInt(u16, segment, cursor + 16);
                if (!slots[operand].initialized) return error.InvalidState;
                slots[result] = slots[operand];
                break :blk null;
            },
            2...23, 57 => try executeScalarOperation(
                image,
                segment[cursor .. cursor + instruction_length],
                result,
                &slots,
                scratch,
                &scratch_cursor,
            ),
            else => return error.UnsupportedOperation,
        };
        if (failure) |failure_tag| {
            if (output_value.len < 4) return error.OutputCapacity;
            std.mem.writeInt(u32, output_value[0..4], failure_tag, .little);
            caller_fuel.* -= cost;
            return .{ .failed = output_value[0..4] };
        }
        cursor += instruction_length;
    }
    const terminator_kind = segment[cursor + 4];
    const payload = cursor + 8;
    const outcome: Outcome = switch (terminator_kind) {
        3 => blk: {
            const present = segment[payload] == 1;
            const value = readInt(u16, segment, payload + 2);
            const result = if (present) slots[value].bytes else &.{};
            if (present and !slots[value].initialized) return error.InvalidState;
            if (output_value.len < result.len) return error.OutputCapacity;
            @memcpy(output_value[0..result.len], result);
            break :blk .{ .done = output_value[0..result.len] };
        },
        5 => blk: {
            if (output_value.len < 4) return error.OutputCapacity;
            std.mem.writeInt(
                u32,
                output_value[0..4],
                readInt(u32, segment, payload),
                .little,
            );
            break :blk .{ .failed = output_value[0..4] };
        },
        6 => blk: {
            const value = readInt(u16, segment, payload);
            if (!slots[value].initialized) return error.InvalidState;
            if (output_value.len < slots[value].bytes.len) {
                return error.OutputCapacity;
            }
            @memcpy(output_value[0..slots[value].bytes.len], slots[value].bytes);
            break :blk .{ .failed = output_value[0..slots[value].bytes.len] };
        },
        else => return error.UnsupportedOperation,
    };
    caller_fuel.* -= cost;
    return outcome;
}

fn loadTopEnvironment(
    image: image_v1.ValidatedImage,
    state: []const u8,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const frame_count = readInt(u32, state, 60);
    var cursor: usize = state_header_length;
    for (0..frame_count - 1) |_| {
        cursor += frame_header_length + readInt(u32, state, cursor + 4);
    }
    const environment_length = readInt(u32, state, cursor + 4);
    const environment = state[cursor + 8 ..][0..environment_length];
    var value_cursor: usize = 0;
    if (readInt(u16, constructor, 10) & 1 != 0) value_cursor = 4;
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        const schema_id = readInt(u32, constructor, field_cursor + 4);
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema_id,
            environment[value_cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
        slots[value] = .{
            .bytes = environment[value_cursor .. value_cursor + consumed],
            .initialized = true,
        };
        value_cursor += consumed;
        field_cursor += 8;
    }
}

fn topConstructorId(state: []const u8) Error!u32 {
    if (state.len < state_header_length + frame_header_length) {
        return error.InvalidState;
    }
    const frame_count = readInt(u32, state, 60);
    if (frame_count == 0) return error.InvalidState;
    var cursor: usize = state_header_length;
    for (0..frame_count - 1) |_| {
        if (state.len - cursor < frame_header_length) return error.InvalidState;
        cursor += frame_header_length + readInt(u32, state, cursor + 4);
        if (cursor > state.len) return error.InvalidState;
    }
    return readInt(u32, state, cursor);
}

fn segmentRecord(
    image: image_v1.ValidatedImage,
    target: u16,
) Error![]const u8 {
    const bytes = image.catalogs.envelope.section(.segments);
    var cursor: usize = 4;
    for (0..image.segment_count) |id| {
        const length = readInt(u32, bytes, cursor);
        const end = cursor + length;
        if (id == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidImage;
}

fn constantBytes(
    image: image_v1.ValidatedImage,
    target: u32,
) Error![]const u8 {
    const bytes = image.catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..image.catalogs.constant_count) |id| {
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        if (id == target) return bytes[cursor..][0..length];
        cursor += length;
    }
    return error.InvalidImage;
}

fn executeScalarOperation(
    image: image_v1.ValidatedImage,
    instruction: []const u8,
    result: u16,
    slots: *[1024]Slot,
    scratch: []u8,
    scratch_cursor: *usize,
) Error!?u32 {
    const operation = readInt(u16, instruction, 6);
    const operand_count = readInt(u16, instruction, 10);
    var operands: [3]u16 = undefined;
    if (operand_count > operands.len) return error.InvalidImage;
    for (0..operand_count) |index| {
        operands[index] = readInt(u16, instruction, 16 + index * 2);
        if (!slots[operands[index]].initialized) return error.InvalidState;
    }
    if (operation == 23) {
        if (operand_count != 3 or slots[operands[0]].bytes.len != 1) {
            return error.InvalidImage;
        }
        slots[result] = slots[
            if (slots[operands[0]].bytes[0] == 1)
                operands[1]
            else
                operands[2]
        ];
        return null;
    }
    if (operation == 57) {
        if (operand_count != 1 or slots[operands[0]].bytes.len != 4) {
            return error.InvalidImage;
        }
        slots[result] = slots[operands[0]];
        return null;
    }
    const result_kind = try valueKind(image, result);
    if (operation >= 20 and operation <= 22) {
        const value = switch (operation) {
            20 => slots[operands[0]].bytes[0] == 0,
            21 => slots[operands[0]].bytes[0] == 1 and
                slots[operands[1]].bytes[0] == 1,
            22 => slots[operands[0]].bytes[0] == 1 or
                slots[operands[1]].bytes[0] == 1,
            else => unreachable,
        };
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, .bool, @intFromBool(value)),
            .initialized = true,
        };
        return null;
    }
    const left = try decodeInteger(
        try valueKind(image, operands[0]),
        slots[operands[0]].bytes,
    );
    if (operation == 2) {
        slots[result] = .{
            .bytes = try writeRaw(
                scratch,
                scratch_cursor,
                .bool,
                @intFromBool(left.raw == 0),
            ),
            .initialized = true,
        };
        return null;
    }
    if (operation == 19) {
        const converted = convertInteger(left, result_kind) orelse
            return try failureTag(image, "arithmetic_overflow");
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, converted),
            .initialized = true,
        };
        return null;
    }
    if (operation == 8) {
        const value = signedValue(left);
        const negated = std.math.sub(i128, 0, value) catch
            return try failureTag(image, "arithmetic_overflow");
        const raw = encodeSigned(negated, result_kind) orelse
            return try failureTag(image, "arithmetic_overflow");
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    if (operation == 15) {
        const raw = (~left.raw) & integerMask(left.bits);
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    const right = try decodeInteger(
        try valueKind(image, operands[1]),
        slots[operands[1]].bytes,
    );
    if (operation >= 9 and operation <= 14) {
        const relation = compareIntegers(left, right, operation);
        slots[result] = .{
            .bytes = try writeRaw(
                scratch,
                scratch_cursor,
                .bool,
                @intFromBool(relation),
            ),
            .initialized = true,
        };
        return null;
    }
    if (operation >= 16 and operation <= 18) {
        const raw = switch (operation) {
            16 => left.raw & right.raw,
            17 => left.raw | right.raw,
            18 => left.raw ^ right.raw,
            else => unreachable,
        } & integerMask(left.bits);
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    const raw = integerArithmetic(left, right, operation) catch |err| switch (err) {
        error.DivisionByZero => return try failureTag(image, "division_by_zero"),
        error.Overflow => return try failureTag(image, "arithmetic_overflow"),
    };
    slots[result] = .{
        .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
        .initialized = true,
    };
    return null;
}

const Integer = struct {
    raw: u64,
    bits: u8,
    signed: bool,
};

fn valueKind(
    image: image_v1.ValidatedImage,
    value: u16,
) Error!dynamic_value_v1.Kind {
    const schema_id = image.catalogs.valueSchemaId(value) catch
        return error.InvalidImage;
    return (image.catalogs.schemas.node(schema_id) catch
        return error.InvalidImage).kind;
}

fn decodeInteger(kind: dynamic_value_v1.Kind, bytes: []const u8) Error!Integer {
    const bits: u8 = switch (kind) {
        .i8, .u8 => 8,
        .i16, .u16 => 16,
        .i32, .u32 => 32,
        .i64, .u64 => 64,
        else => return error.InvalidImage,
    };
    if (bytes.len != bits / 8) return error.InvalidState;
    var raw: u64 = 0;
    for (bytes, 0..) |byte, index| raw |= @as(u64, byte) << @intCast(index * 8);
    return .{
        .raw = raw,
        .bits = bits,
        .signed = switch (kind) {
            .i8, .i16, .i32, .i64 => true,
            else => false,
        },
    };
}

fn signedValue(value: Integer) i128 {
    if (!value.signed) return value.raw;
    if (value.bits == 64) return @as(i64, @bitCast(value.raw));
    const sign = @as(u64, 1) << @intCast(value.bits - 1);
    return if (value.raw & sign == 0)
        value.raw
    else
        @as(i128, value.raw) - (@as(i128, 1) << @intCast(value.bits));
}

fn integerArithmetic(
    left: Integer,
    right: Integer,
    operation: u16,
) error{ DivisionByZero, Overflow }!u64 {
    if (left.signed) {
        const a = signedValue(left);
        const b = signedValue(right);
        if ((operation == 6 or operation == 7) and b == 0) {
            return error.DivisionByZero;
        }
        const value = switch (operation) {
            3 => std.math.add(i128, a, b) catch return error.Overflow,
            4 => std.math.sub(i128, a, b) catch return error.Overflow,
            5 => std.math.mul(i128, a, b) catch return error.Overflow,
            6 => @divTrunc(a, b),
            7 => @rem(a, b),
            else => return error.Overflow,
        };
        return encodeSigned(value, integerKind(left)) orelse error.Overflow;
    }
    const a: u128 = left.raw;
    const b: u128 = right.raw;
    if ((operation == 6 or operation == 7) and b == 0) {
        return error.DivisionByZero;
    }
    const value: u128 = switch (operation) {
        3 => a + b,
        4 => if (a < b) return error.Overflow else a - b,
        5 => a * b,
        6 => a / b,
        7 => a % b,
        else => return error.Overflow,
    };
    if (value > integerMask(left.bits)) return error.Overflow;
    return @intCast(value);
}

fn compareIntegers(left: Integer, right: Integer, operation: u16) bool {
    if (left.signed) {
        const a = signedValue(left);
        const b = signedValue(right);
        return switch (operation) {
            9 => a == b,
            10 => a != b,
            11 => a < b,
            12 => a <= b,
            13 => a > b,
            14 => a >= b,
            else => unreachable,
        };
    }
    return switch (operation) {
        9 => left.raw == right.raw,
        10 => left.raw != right.raw,
        11 => left.raw < right.raw,
        12 => left.raw <= right.raw,
        13 => left.raw > right.raw,
        14 => left.raw >= right.raw,
        else => unreachable,
    };
}

fn convertInteger(value: Integer, kind: dynamic_value_v1.Kind) ?u64 {
    const target = integerShape(kind) orelse return null;
    if (target.signed) return encodeSigned(signedValue(value), kind);
    const source = signedValue(value);
    if (source < 0 or @as(u128, @intCast(source)) > integerMask(target.bits)) {
        return null;
    }
    return @intCast(source);
}

fn encodeSigned(value: i128, kind: dynamic_value_v1.Kind) ?u64 {
    const target = integerShape(kind) orelse return null;
    if (!target.signed) {
        if (value < 0 or @as(u128, @intCast(value)) > integerMask(target.bits)) {
            return null;
        }
        return @intCast(value);
    }
    const minimum = -(@as(i128, 1) << @intCast(target.bits - 1));
    const maximum = (@as(i128, 1) << @intCast(target.bits - 1)) - 1;
    if (value < minimum or value > maximum) return null;
    if (target.bits == 64) return @bitCast(@as(i64, @intCast(value)));
    return @intCast(if (value < 0)
        value + (@as(i128, 1) << @intCast(target.bits))
    else
        value);
}

fn integerShape(kind: dynamic_value_v1.Kind) ?Integer {
    return switch (kind) {
        .i8 => .{ .raw = 0, .bits = 8, .signed = true },
        .i16 => .{ .raw = 0, .bits = 16, .signed = true },
        .i32 => .{ .raw = 0, .bits = 32, .signed = true },
        .i64 => .{ .raw = 0, .bits = 64, .signed = true },
        .u8 => .{ .raw = 0, .bits = 8, .signed = false },
        .u16 => .{ .raw = 0, .bits = 16, .signed = false },
        .u32 => .{ .raw = 0, .bits = 32, .signed = false },
        .u64 => .{ .raw = 0, .bits = 64, .signed = false },
        else => null,
    };
}

fn integerKind(value: Integer) dynamic_value_v1.Kind {
    return if (value.signed)
        switch (value.bits) {
            8 => .i8,
            16 => .i16,
            32 => .i32,
            64 => .i64,
            else => unreachable,
        }
    else switch (value.bits) {
        8 => .u8,
        16 => .u16,
        32 => .u32,
        64 => .u64,
        else => unreachable,
    };
}

fn integerMask(bits: u8) u64 {
    return if (bits == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(bits)) - 1;
}

fn writeRaw(
    scratch: []u8,
    cursor: *usize,
    kind: dynamic_value_v1.Kind,
    raw: u64,
) Error![]const u8 {
    const length: usize = if (kind == .bool) 1 else (integerShape(kind) orelse return error.InvalidImage).bits / 8;
    if (cursor.* > scratch.len or length > scratch.len - cursor.*) {
        return error.ScratchCapacity;
    }
    const result = scratch[cursor.*..][0..length];
    for (result, 0..) |*byte, index| byte.* = @truncate(raw >> @intCast(index * 8));
    cursor.* += length;
    return result;
}

fn failureTag(image: image_v1.ValidatedImage, name: []const u8) Error!u32 {
    const bytes = image.catalogs.envelope.section(.failures);
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |_| {
        const tag = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const candidate = bytes[cursor..][0..length];
        cursor += length;
        if (std.mem.eql(u8, candidate, name)) return tag;
    }
    return error.InvalidImage;
}

fn validateEnvironment(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
    environment: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const flags = readInt(u16, constructor, 10);
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    var value_cursor: usize = 0;
    if (flags & 1 != 0) {
        if (environment.len < 4) return error.InvalidState;
        const entry_constructor = readInt(u32, environment, 0);
        _ = constructorRecord(image, entry_constructor) catch
            return error.InvalidState;
        value_cursor = 4;
    }
    const field_count = @as(u32, activation_count) + environment_count;
    for (0..field_count) |_| {
        const schema_id = readInt(u32, constructor, field_cursor + 4);
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema_id,
            environment[value_cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
        value_cursor += consumed;
        field_cursor += 8;
    }
    if (value_cursor != environment.len) return error.InvalidState;
}

fn constructorRecord(
    image: image_v1.ValidatedImage,
    target: u32,
) Error![]const u8 {
    const bytes = image.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..image.constructor_count) |id| {
        const length = readInt(u32, bytes, cursor);
        const end = cursor + length;
        if (id == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidImage;
}

fn appendBytes(output: []u8, cursor: *usize, value: []const u8) void {
    @memcpy(output[cursor.*..][0..value.len], value);
    cursor.* += value.len;
}

fn appendInt(
    comptime T: type,
    output: []u8,
    cursor: *usize,
    value: anytype,
) void {
    std.mem.writeInt(T, output[cursor.*..][0..@sizeOf(T)], @intCast(value), .little);
    cursor.* += @sizeOf(T);
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
