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

const Arena = process_advance_v1.CapacityArena;
const KernelStorage = struct {
    input: Arena(.input, input_capacity) = .{},
    output: Arena(.output, output_capacity) = .{},
    state: Arena(.output, state_capacity) = .{},
    value: Arena(.output, value_capacity) = .{},
    request: Arena(.output, request_capacity) = .{},
    candidate: Arena(.output, state_capacity) = .{},
    environment: Arena(.output, environment_capacity) = .{},
    auxiliary_environment: Arena(.output, environment_capacity) = .{},
    scratch: Arena(.scratch, scratch_capacity) = .{},
};

comptime {
    if (process_advance_v1.capacityArenaCount(KernelStorage) != 9) {
        @compileError("Process kernel capacity arena topology changed");
    }
}

var storage: KernelStorage = .{};
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
    return @intCast(@intFromPtr(&storage.input.bytes));
}

pub export fn boundary_process_kernel_input_capacity() u32 {
    return input_capacity;
}

pub export fn boundary_process_kernel_input_payload_ptr() u32 {
    return @intCast(@intFromPtr(&storage.input.bytes) + input_header_length);
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
    if (required_input > storage.input.bytes.len) {
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
        &storage.input.bytes,
    ) catch return 0;
    return @intCast(total);
}

pub export fn boundary_process_kernel_output_ptr() u32 {
    return @intCast(@intFromPtr(&storage.output.bytes));
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
    if (input_length > storage.input.bytes.len) {
        setError("MalformedKernelInput");
        return 1;
    }
    return execute(storage.input.bytes[0..input_length]) catch |err| {
        setError(@errorName(err));
        return 2;
    };
}

fn execute(input: []const u8) !u32 {
    const decoded = process_advance_v1.validateKernelInput(input) catch
        return error.MalformedKernelInput;

    validation_workspace = .{};
    const attempt = try process_advance_v1.advanceAttempt(
        decoded.image,
        decoded.instance,
        decoded.effect_result,
        .{
            .output_state = &storage.state.bytes,
            .output_value = &storage.value.bytes,
            .output_request = &storage.request.bytes,
            .candidate_state = &storage.candidate.bytes,
            .environment = &storage.environment.bytes,
            .auxiliary_environment = &storage.auxiliary_environment.bytes,
            .scratch = &storage.scratch.bytes,
        },
        &validation_workspace,
    );
    const encoded = try process_advance_v1.encodeOutcomeForCapacity(
        attempt.outcome,
        attempt.capacity,
        input.len,
        &storage,
        @wasmMemorySize(0),
        &storage.output.bytes,
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
    const requirement: process_advance_v1.CapacityRequirement = .{
        .minimum_input_bytes = required_input,
        .minimum_output_bytes = process_advance_v1.outcome_header_length + 32,
        .minimum_scratch_bytes = 0,
        .minimum_memory_pages = 0,
    };
    const minimum_pages = process_advance_v1.minimumMemoryPagesForStorage(
        &storage,
        requirement,
        @wasmMemorySize(0),
    );
    const encoded = process_advance_v1.encodeOutcome(
        .{ .needs_capacity = .{
            .minimum_input_bytes = requirement.minimum_input_bytes,
            .minimum_output_bytes = requirement.minimum_output_bytes,
            .minimum_scratch_bytes = requirement.minimum_scratch_bytes,
            .minimum_memory_pages = minimum_pages,
        } },
        &storage.output.bytes,
    ) catch return;
    output_length = @intCast(encoded.len);
}
