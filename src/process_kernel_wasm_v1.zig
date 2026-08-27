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
pub export fn boundary_process_kernel_reserve(required_input_bytes: u64) u32 {
    return @intFromBool(required_input_bytes <= input_capacity);
}

pub export fn boundary_process_kernel_input_ptr() u32 {
    return @intCast(@intFromPtr(&input_storage));
}

pub export fn boundary_process_kernel_input_capacity() u32 {
    return input_capacity;
}

pub export fn boundary_process_kernel_input_payload_ptr() u32 {
    return @intCast(@intFromPtr(&input_storage) + input_header_length);
}

pub export fn boundary_process_kernel_prepare_input(
    instance_kind: u32,
    image_length: u64,
    instance_length: u64,
    result_present: u32,
    result_length: u64,
) u32 {
    output_length = 0;
    error_length = 0;
    if (instance_kind > 1 or result_present > 1 or
        (result_present == 0 and result_length != 0))
    {
        return 0;
    }
    const required_input = @as(u64, input_header_length) +|
        image_length +|
        instance_length +|
        result_length;
    if (required_input > input_storage.len) {
        reportInputCapacity(required_input);
        return 0;
    }
    const total: usize = @intCast(required_input);
    _ = process_advance_v1.encodeKernelInputHeader(
        @intCast(instance_kind),
        result_present == 1,
        image_length,
        instance_length,
        result_length,
        &input_storage,
    ) catch return 0;
    return @intCast(total);
}

pub export fn boundary_process_kernel_output_ptr() u32 {
    return @intCast(@intFromPtr(&output_storage));
}

pub export fn boundary_process_kernel_output_len() u64 {
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
    const decoded = process_advance_v1.validateKernelInput(input) catch
        return error.MalformedKernelInput;

    validation_workspace = .{};
    const outcome = try process_advance_v1.advance(
        decoded.image,
        decoded.instance,
        decoded.effect_result,
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
    const layout: process_advance_v1.KernelArenaLayout = .{
        .input_bytes = @sizeOf(@TypeOf(input_storage)),
        .output_bytes = @sizeOf(@TypeOf(output_storage)),
        .state_bytes = @sizeOf(@TypeOf(state_storage)),
        .candidate_state_bytes = @sizeOf(@TypeOf(candidate_storage)),
        .value_bytes = @sizeOf(@TypeOf(value_storage)),
        .request_bytes = @sizeOf(@TypeOf(request_storage)),
        .environment_bytes = @sizeOf(@TypeOf(environment_storage)),
        .auxiliary_environment_bytes = @sizeOf(@TypeOf(auxiliary_environment_storage)),
        .scratch_bytes = @sizeOf(@TypeOf(scratch_storage)),
    };
    const encoded = try process_advance_v1.encodeOutcomeForCapacity(
        outcome,
        input.len,
        layout,
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

fn reportInputCapacity(required_input: u64) void {
    const growth = required_input - input_storage.len;
    const page_bytes: u64 = 64 * 1024;
    const growth_pages = growth / page_bytes + @intFromBool(growth % page_bytes != 0);
    const minimum_pages = @as(u64, @wasmMemorySize(0)) +| growth_pages;
    const encoded = process_advance_v1.encodeOutcome(
        .{ .needs_capacity = .{
            .minimum_input_bytes = required_input,
            .minimum_output_bytes = process_advance_v1.outcome_header_length + 32,
            .minimum_scratch_bytes = 0,
            .minimum_memory_pages = minimum_pages,
        } },
        &output_storage,
    ) catch return;
    output_length = @intCast(encoded.len);
}
