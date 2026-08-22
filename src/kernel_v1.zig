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
        switch (operation) {
            0 => slots[result] = .{
                .bytes = try constantBytes(image, immediate),
                .initialized = true,
            },
            1 => {
                if (operand_count != 1) return error.InvalidImage;
                const operand = readInt(u16, segment, cursor + 16);
                if (!slots[operand].initialized) return error.InvalidState;
                slots[result] = slots[operand];
            },
            else => return error.UnsupportedOperation,
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
