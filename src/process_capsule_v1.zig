const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const process_advance_v1 = @import("process_advance_v1");
const process_state_v1 = @import("process_state_v1");
const std = @import("std");
const slicesOverlap = process_state_v1.slicesOverlap;

pub const magic = "ABL_CAP1".*;
pub const format_version: u16 = 1;
pub const fixed_header_length: usize = magic.len + 2 + 2 + 2 + 1 + 1;

pub const Error = process_advance_v1.Error ||
    dynamic_value_v1.Error ||
    image_v1.Error ||
    process_state_v1.Error || error{
    InvalidCapsule,
    UnsupportedKernelSemanticVersion,
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

pub fn encode(
    input: Input,
    output: []u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error![]const u8 {
    if (slicesOverlap(output, input.image) or
        slicesOverlap(output, input.instance) or
        slicesOverlap(output, invariant_scratch) or
        slicesOverlap(input.image, invariant_scratch) or
        slicesOverlap(input.instance, invariant_scratch) or
        slicesOverlap(output, std.mem.asBytes(workspace)) or
        slicesOverlap(input.image, std.mem.asBytes(workspace)) or
        slicesOverlap(input.instance, std.mem.asBytes(workspace)) or
        slicesOverlap(invariant_scratch, std.mem.asBytes(workspace)))
    {
        return error.InvalidCapsule;
    }
    const required = try encodedLength(input);
    if (output.len < required) return error.OutputCapacity;
    var image_length_bytes: [10]u8 = undefined;
    const image_length = try process_state_v1.writeNatural(
        input.image.len,
        &image_length_bytes,
    );
    var instance_length_bytes: [10]u8 = undefined;
    const instance_length = try process_state_v1.writeNatural(
        input.instance.len,
        &instance_length_bytes,
    );
    try validateInput(input, invariant_scratch, workspace);
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
    append(output, &cursor, image_length_bytes[0..image_length]);
    append(output, &cursor, input.image);
    append(output, &cursor, instance_length_bytes[0..instance_length]);
    append(output, &cursor, input.instance);
    std.debug.assert(cursor == required);
    return output[0..required];
}

pub fn validate(
    bytes: []const u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!View {
    if (slicesOverlap(bytes, invariant_scratch) or
        slicesOverlap(bytes, std.mem.asBytes(workspace)) or
        slicesOverlap(invariant_scratch, std.mem.asBytes(workspace)))
    {
        return error.InvalidCapsule;
    }
    const view = try decode(bytes);
    try validateInput(.{
        .required_kernel_semantic_version = view.required_kernel_semantic_version,
        .image = view.image,
        .instance_kind = view.instance_kind,
        .instance = view.instance,
    }, invariant_scratch, workspace);
    return view;
}

fn validateInput(
    input: Input,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    if (input.required_kernel_semantic_version !=
        process_advance_v1.kernel_semantic_version)
    {
        return error.UnsupportedKernelSemanticVersion;
    }
    switch (input.instance_kind) {
        .process_state => _ = try process_advance_v1.validateState(
            input.image,
            input.instance,
            invariant_scratch,
            workspace,
        ),
        .initial_args => {
            const arenas = try initialValidationArenas(
                input.instance.len,
                invariant_scratch,
            );
            process_advance_v1.validateInitialArgs(
                input.image,
                input.instance,
                arenas.candidate_state,
                arenas.environment_and_invariants,
                workspace,
            ) catch |err| switch (err) {
                error.InvalidInitialArgs, error.InvalidProcessState => return error.InvalidCapsule,
                else => return err,
            };
        },
    }
}

const InitialValidationArenas = struct {
    candidate_state: []u8,
    environment_and_invariants: []u8,
};

fn initialValidationArenas(
    initial_args_length: usize,
    scratch: []u8,
) Error!InitialValidationArenas {
    const state_capacity = std.math.add(
        usize,
        initial_args_length,
        128,
    ) catch return error.ScratchCapacity;
    const required = std.math.add(
        usize,
        state_capacity,
        initial_args_length,
    ) catch return error.ScratchCapacity;
    if (scratch.len < required) return error.ScratchCapacity;
    return .{
        .candidate_state = scratch[0..state_capacity],
        .environment_and_invariants = scratch[state_capacity..],
    };
}

test "initial Capsule scratch reserves candidate State and retained environment" {
    var exact: [136]u8 = undefined;
    const arenas = try initialValidationArenas(4, &exact);
    try std.testing.expectEqual(@as(usize, 132), arenas.candidate_state.len);
    try std.testing.expectEqual(
        @as(usize, 4),
        arenas.environment_and_invariants.len,
    );
    try std.testing.expectError(
        error.ScratchCapacity,
        initialValidationArenas(4, exact[0 .. exact.len - 1]),
    );
}

fn decode(bytes: []const u8) Error!View {
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
