const image_v1 = @import("image_v1");
const process_advance_v1 = @import("process_advance_v1");
const process_kernel_options = @import("process_kernel_options");
const std = @import("std");

pub const abi_version: u32 = 1;
pub const input_magic = process_advance_v1.kernel_input_magic;
pub const input_format_version = process_advance_v1.kernel_input_format_version;
pub const input_header_length = process_advance_v1.kernel_input_header_length;

const input_capacity = process_kernel_options.input_capacity;
const output_capacity = process_kernel_options.output_capacity;
const state_capacity = process_kernel_options.state_capacity;
const value_capacity = process_kernel_options.value_capacity;
const request_capacity = process_kernel_options.request_capacity;
const environment_capacity = process_kernel_options.environment_capacity;
const scratch_capacity = process_kernel_options.scratch_capacity;
const error_capacity = process_kernel_options.error_capacity;

var input_storage: [input_capacity]u8 align(16) = undefined;
var output_storage: [output_capacity]u8 align(16) = undefined;
var state_storage: [state_capacity]u8 align(16) = undefined;
var value_storage: [value_capacity]u8 align(16) = undefined;
var request_storage: [request_capacity]u8 align(16) = undefined;
var candidate_storage: [state_capacity]u8 align(16) = undefined;
var environment_storage: [environment_capacity]u8 align(16) = undefined;
var auxiliary_environment_storage: [environment_capacity]u8 align(16) = undefined;
var scratch_storage: [scratch_capacity]u8 align(16) = undefined;
var error_storage: [error_capacity]u8 align(16) = undefined;
var validation_workspace: image_v1.ValidationWorkspace = .{};
var output_length: u32 = 0;
var error_length: u32 = 0;

pub export fn boundary_process_kernel_abi_version() u32 {
    return abi_version;
}

/// This fixed implementation has a statically addressed input arena. Returning
/// zero tells the embedding environment to transfer to a larger conforming
/// kernel when the requested input does not fit.
pub export fn boundary_process_kernel_reserve(required_input_bytes: u32) u32 {
    return @intFromBool(required_input_bytes <= input_capacity);
}

pub export fn boundary_process_kernel_input_ptr() u32 {
    return @intCast(@intFromPtr(&input_storage));
}

pub export fn boundary_process_kernel_input_capacity() u32 {
    return input_capacity;
}

pub export fn boundary_process_kernel_output_ptr() u32 {
    return @intCast(@intFromPtr(&output_storage));
}

pub export fn boundary_process_kernel_output_len() u32 {
    return output_length;
}

pub export fn boundary_process_kernel_error_ptr() u32 {
    return @intCast(@intFromPtr(&error_storage));
}

pub export fn boundary_process_kernel_error_len() u32 {
    return error_length;
}

pub export fn boundary_process_kernel_execute(input_length: u32) u32 {
    output_length = 0;
    error_length = 0;
    if (input_length > input_storage.len) {
        setError("MalformedKernelInput");
        return 1;
    }
    return execute(input_storage[0..input_length]) catch |err| {
        setError(@errorName(err));
        return 2;
    };
}

fn execute(input: []const u8) !u32 {
    if (input.len < input_header_length or
        !std.mem.eql(u8, input[0..8], &input_magic) or
        readInt(u16, input, 8) != input_format_version or
        input[10] > 1 or
        input[11] & ~@as(u8, 1) != 0 or
        !allZero(input[24..28]))
    {
        return error.MalformedKernelInput;
    }
    const image_length = readInt(u32, input, 12);
    const instance_length = readInt(u32, input, 16);
    const result_length = readInt(u32, input, 20);
    const result_present = input[11] & 1 != 0;
    if (!result_present and result_length != 0) {
        return error.MalformedKernelInput;
    }
    var expected = std.math.add(
        usize,
        input_header_length,
        image_length,
    ) catch return error.MalformedKernelInput;
    expected = std.math.add(usize, expected, instance_length) catch
        return error.MalformedKernelInput;
    expected = std.math.add(usize, expected, result_length) catch
        return error.MalformedKernelInput;
    if (expected != input.len) return error.MalformedKernelInput;

    var cursor: usize = input_header_length;
    const image = input[cursor .. cursor + image_length];
    cursor += image_length;
    const instance_bytes = input[cursor .. cursor + instance_length];
    cursor += instance_length;
    const effect_result = if (result_present)
        input[cursor .. cursor + result_length]
    else
        null;
    const instance: process_advance_v1.Instance = if (input[10] == 0)
        .{ .initial_args = instance_bytes }
    else
        .{ .process_state = instance_bytes };

    validation_workspace = .{};
    const outcome = try process_advance_v1.advance(
        image,
        instance,
        effect_result,
        .{
            .output_state = &state_storage,
            .output_value = &value_storage,
            .output_request = &request_storage,
            .candidate_state = &candidate_storage,
            .environment = &environment_storage,
            .auxiliary_environment = &auxiliary_environment_storage,
            .scratch = &scratch_storage,
        },
        &validation_workspace,
    );
    const declared_base_memory = (process_advance_v1.KernelArenaLayout{
        .state_bytes = @sizeOf(@TypeOf(state_storage)),
        .candidate_state_bytes = @sizeOf(@TypeOf(candidate_storage)),
        .value_bytes = @sizeOf(@TypeOf(value_storage)),
        .request_bytes = @sizeOf(@TypeOf(request_storage)),
        .environment_bytes = @sizeOf(@TypeOf(environment_storage)),
        .auxiliary_environment_bytes = @sizeOf(@TypeOf(auxiliary_environment_storage)),
        .scratch_bytes = @sizeOf(@TypeOf(scratch_storage)),
        .error_bytes = @sizeOf(@TypeOf(error_storage)),
        .validation_workspace_bytes = @sizeOf(@TypeOf(validation_workspace)),
    }).baseMemoryWithoutOutput(input.len);
    const encoded = try process_advance_v1.encodeOutcomeForCapacity(
        outcome,
        input.len,
        scratch_capacity,
        declared_base_memory,
        @wasmMemorySize(0),
        &output_storage,
    );
    output_length = @intCast(encoded.len);
    return 0;
}

fn setError(message: []const u8) void {
    const length = @min(message.len, error_storage.len);
    @memcpy(error_storage[0..length], message[0..length]);
    error_length = @intCast(length);
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
