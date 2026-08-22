const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const std = @import("std");

pub const Error = error{
    InvalidImage,
    InvalidState,
    InvalidInitialArgs,
    OutputCapacity,
};

pub const state_magic = "ABL_RNF2".*;
pub const state_header_length: usize = 68;
pub const frame_header_length: usize = 8;

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
