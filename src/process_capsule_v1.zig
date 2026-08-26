const process_state_v1 = @import("process_state_v1");
const std = @import("std");

pub const magic = "ABL_CAP1".*;
pub const format_version: u16 = 1;
pub const fixed_header_length: usize = magic.len + 2 + 2 + 2 + 1 + 1;

pub const Error = process_state_v1.Error || error{
    InvalidCapsule,
};

pub const InstanceKind = enum(u8) {
    initial_args = 0,
    process_state = 1,
};

pub const Input = struct {
    required_kernel_semantic_version: u16,
    image: []const u8,
    instance_kind: InstanceKind,
    instance: []const u8,
};

pub const View = struct {
    bytes: []const u8,
    required_kernel_semantic_version: u16,
    image: []const u8,
    instance_kind: InstanceKind,
    instance: []const u8,
};

pub fn encodedLength(input: Input) Error!usize {
    if (input.image.len == 0) return error.InvalidCapsule;
    var length = try addLength(
        fixed_header_length,
        process_state_v1.naturalEncodedLength(input.image.len),
    );
    length = try addLength(length, input.image.len);
    length = try addLength(
        length,
        process_state_v1.naturalEncodedLength(input.instance.len),
    );
    return addLength(length, input.instance.len);
}

pub fn encode(input: Input, output: []u8) Error![]const u8 {
    const required = try encodedLength(input);
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    append(output, &cursor, &magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    appendInt(
        u16,
        output,
        &cursor,
        input.required_kernel_semantic_version,
    );
    output[cursor] = @intFromEnum(input.instance_kind);
    cursor += 1;
    output[cursor] = 0;
    cursor += 1;
    cursor += try process_state_v1.writeNatural(input.image.len, output[cursor..]);
    append(output, &cursor, input.image);
    cursor += try process_state_v1.writeNatural(input.instance.len, output[cursor..]);
    append(output, &cursor, input.instance);
    if (cursor != required) return error.InvalidCapsule;
    const encoded = output[0..required];
    _ = try validate(encoded);
    return encoded;
}

pub fn validate(bytes: []const u8) Error!View {
    if (bytes.len < fixed_header_length + 2 or
        !std.mem.eql(u8, bytes[0..magic.len], &magic))
    {
        return error.InvalidCapsule;
    }
    if (readInt(u16, bytes, magic.len) != format_version) {
        return error.UnsupportedVersion;
    }
    if (readInt(u16, bytes, magic.len + 2) != 0) {
        return error.UnknownFlags;
    }
    const kernel_version = readInt(u16, bytes, magic.len + 4);
    const kind = std.enums.fromInt(InstanceKind, bytes[magic.len + 6]) orelse
        return error.InvalidCapsule;
    if (bytes[magic.len + 7] != 0) return error.UnknownFlags;
    var cursor = fixed_header_length;
    const image_length = try process_state_v1.readNatural(bytes[cursor..]);
    cursor = try addLength(cursor, image_length.length);
    const image_size = std.math.cast(usize, image_length.value) orelse
        return error.InvalidCapsule;
    const image_end = try addLength(cursor, image_size);
    if (image_size == 0 or image_end > bytes.len) return error.InvalidCapsule;
    const image = bytes[cursor..image_end];
    cursor = image_end;
    const instance_length = try process_state_v1.readNatural(bytes[cursor..]);
    cursor = try addLength(cursor, instance_length.length);
    const instance_size = std.math.cast(usize, instance_length.value) orelse
        return error.InvalidCapsule;
    const instance_end = try addLength(cursor, instance_size);
    if (instance_end != bytes.len) return error.InvalidCapsule;
    return .{
        .bytes = bytes,
        .required_kernel_semantic_version = kernel_version,
        .image = image,
        .instance_kind = kind,
        .instance = bytes[cursor..instance_end],
    };
}

fn addLength(left: usize, right: usize) Error!usize {
    return std.math.add(usize, left, right) catch error.LengthOverflow;
}

fn append(output: []u8, cursor: *usize, bytes: []const u8) void {
    @memcpy(output[cursor.*..][0..bytes.len], bytes);
    cursor.* += bytes.len;
}

fn appendInt(
    comptime T: type,
    output: []u8,
    cursor: *usize,
    value: T,
) void {
    std.mem.writeInt(T, output[cursor.*..][0..@sizeOf(T)], value, .little);
    cursor.* += @sizeOf(T);
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
