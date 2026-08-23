const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const std = @import("std");

pub const abi_version: u32 = 1;
const input_capacity = 24 << 20;
const output_capacity = 8 << 20;
const state_capacity = 4 << 20;
const value_capacity = 2 << 20;
const scratch_capacity = 68 << 20;
const error_capacity = 4 << 10;
const input_header_length = 40;
const output_header_length = 40;

var input_storage: [input_capacity]u8 align(16) = undefined;
var output_storage: [output_capacity]u8 align(16) = undefined;
var state_storage: [state_capacity]u8 align(16) = undefined;
var value_storage: [value_capacity]u8 align(16) = undefined;
var scratch_storage: [scratch_capacity]u8 align(16) = undefined;
var error_storage: [error_capacity]u8 align(16) = undefined;
var validation_workspace: image_v1.ValidationWorkspace = .{};
var output_length: u32 = 0;
var error_length: u32 = 0;

pub export fn boundary_kernel_abi_version() u32 {
    return abi_version;
}

pub export fn boundary_kernel_input_ptr() u32 {
    return @intCast(@intFromPtr(&input_storage));
}

pub export fn boundary_kernel_input_capacity() u32 {
    return input_capacity;
}

pub export fn boundary_kernel_output_ptr() u32 {
    return @intCast(@intFromPtr(&output_storage));
}

pub export fn boundary_kernel_output_len() u32 {
    return output_length;
}

pub export fn boundary_kernel_error_ptr() u32 {
    return @intCast(@intFromPtr(&error_storage));
}

pub export fn boundary_kernel_error_len() u32 {
    return error_length;
}

pub export fn boundary_kernel_execute(input_length: u32) u32 {
    output_length = 0;
    error_length = 0;
    if (input_length > input_storage.len) {
        setError("MalformedKernelInput");
        return 1;
    }
    return execute(input_storage[0..input_length]) catch |err| {
        setError(@errorName(err));
        return errorCode(err);
    };
}

pub export fn boundary_kernel_reset() u32 {
    @memset(&input_storage, 0);
    @memset(&output_storage, 0);
    @memset(&state_storage, 0);
    @memset(&value_storage, 0);
    @memset(&scratch_storage, 0);
    @memset(&error_storage, 0);
    validation_workspace = .{};
    output_length = 0;
    error_length = 0;
    return 0;
}

const ExecuteError = image_v1.Error || kernel_v1.Error || error{
    MalformedKernelInput,
    OutputCapacity,
};

fn execute(input: []const u8) ExecuteError!u32 {
    validation_workspace.invariant_result = &value_storage;
    if (input.len < input_header_length or
        !std.mem.eql(u8, input[0..8], "ABL_KIN1") or
        readInt(u16, input, 8) != 1 or
        readInt(u32, input, 12) != 0 or
        readInt(u32, input, 36) != 0)
    {
        return error.MalformedKernelInput;
    }
    const command = readInt(u16, input, 10);
    const caller_fuel = readInt(u64, input, 16);
    const image_length = readInt(u32, input, 24);
    const state_length = readInt(u32, input, 28);
    const auxiliary_length = readInt(u32, input, 32);
    var expected = std.math.add(
        usize,
        input_header_length,
        image_length,
    ) catch return error.MalformedKernelInput;
    expected = std.math.add(usize, expected, state_length) catch
        return error.MalformedKernelInput;
    expected = std.math.add(usize, expected, auxiliary_length) catch
        return error.MalformedKernelInput;
    if (expected != input.len) return error.MalformedKernelInput;
    const image_start = input_header_length;
    const state_start = std.math.add(usize, image_start, image_length) catch
        return error.MalformedKernelInput;
    const auxiliary_start = std.math.add(usize, state_start, state_length) catch
        return error.MalformedKernelInput;
    const image_bytes = input[image_start..state_start];
    const state_bytes = input[state_start..auxiliary_start];
    const auxiliary = input[auxiliary_start..];
    const image = try image_v1.validateImage(
        image_bytes,
        &validation_workspace,
    );
    return switch (command) {
        0 => try writeOutput(command, 0, caller_fuel, &.{}, &.{}, &.{}),
        1 => blk: {
            const length = try kernel_v1.initial(
                image,
                auxiliary,
                &state_storage,
                &validation_workspace,
            );
            break :blk try writeOutput(
                command,
                1,
                caller_fuel,
                state_storage[0..length],
                &.{},
                &.{},
            );
        },
        2 => blk: {
            try kernel_v1.validateState(
                image,
                state_bytes,
                &validation_workspace,
            );
            break :blk try writeOutput(command, 0, caller_fuel, &.{}, &.{}, &.{});
        },
        3 => try executeCurrent(image, command, caller_fuel, state_bytes),
        4 => try executeStep(image, command, caller_fuel, state_bytes),
        5 => try executeResume(image, command, caller_fuel, state_bytes, auxiliary),
        else => error.MalformedKernelInput,
    };
}

fn executeCurrent(
    image: image_v1.ValidatedImage,
    command: u16,
    caller_fuel: u64,
    state: []const u8,
) ExecuteError!u32 {
    const request = try kernel_v1.current(
        image,
        state,
        &value_storage,
        &validation_workspace,
    ) orelse return writeOutput(command, 2, caller_fuel, &.{}, &.{}, &.{});
    var identity: [176]u8 = undefined;
    encodeIdentity(request.identity, &identity);
    return writeOutput(
        command,
        3,
        caller_fuel,
        request.state,
        request.payload,
        &identity,
    );
}

fn executeStep(
    image: image_v1.ValidatedImage,
    command: u16,
    fuel: u64,
    state: []const u8,
) ExecuteError!u32 {
    var remaining = fuel;
    const outcome = try kernel_v1.step(
        image,
        state,
        &remaining,
        &state_storage,
        &value_storage,
        &scratch_storage,
        &validation_workspace,
    );
    return switch (outcome) {
        .requested => |request| blk: {
            var identity: [176]u8 = undefined;
            encodeIdentity(request.identity, &identity);
            break :blk try writeOutput(
                command,
                3,
                remaining,
                request.state,
                request.payload,
                &identity,
            );
        },
        .yielded => |next| try writeOutput(
            command,
            4,
            remaining,
            next,
            &.{},
            &.{},
        ),
        .done => |value| try writeOutput(
            command,
            5,
            remaining,
            &.{},
            value,
            &.{},
        ),
        .failed => |failure| try writeOutput(
            command,
            6,
            remaining,
            &.{},
            failure,
            &.{},
        ),
        .machine_failed => |failure| switch (failure.failure) {
            .execution_budget_exceeded => error.ExecutionBudgetExceeded,
            .frame_depth_exceeded => error.FrameDepthExceeded,
        },
    };
}

fn executeResume(
    image: image_v1.ValidatedImage,
    command: u16,
    caller_fuel: u64,
    state: []const u8,
    auxiliary: []const u8,
) ExecuteError!u32 {
    if (auxiliary.len < 184) return error.MalformedKernelInput;
    const response_length = readInt(u32, auxiliary, 176);
    if (readInt(u32, auxiliary, 180) != 0 or
        auxiliary.len != 184 + @as(usize, response_length))
    {
        return error.MalformedKernelInput;
    }
    const length = try kernel_v1.@"resume"(
        image,
        state,
        decodeIdentity(auxiliary[0..176]),
        auxiliary[184..],
        &state_storage,
        &validation_workspace,
    );
    return writeOutput(
        command,
        1,
        caller_fuel,
        state_storage[0..length],
        &.{},
        &.{},
    );
}

fn writeOutput(
    command: u16,
    outcome: u16,
    remaining_fuel: u64,
    state: []const u8,
    value: []const u8,
    metadata: []const u8,
) ExecuteError!u32 {
    const required = output_header_length + state.len + value.len + metadata.len;
    if (required > output_storage.len) return error.OutputCapacity;
    @memset(output_storage[0..output_header_length], 0);
    @memcpy(output_storage[0..8], "ABL_KOU1");
    writeInt(u16, &output_storage, 8, 1);
    writeInt(u16, &output_storage, 10, command);
    writeInt(u16, &output_storage, 12, outcome);
    writeInt(u64, &output_storage, 16, remaining_fuel);
    writeInt(u32, &output_storage, 24, state.len);
    writeInt(u32, &output_storage, 28, value.len);
    writeInt(u32, &output_storage, 32, metadata.len);
    var cursor: usize = output_header_length;
    @memcpy(output_storage[cursor..][0..state.len], state);
    cursor += state.len;
    @memcpy(output_storage[cursor..][0..value.len], value);
    cursor += value.len;
    @memcpy(output_storage[cursor..][0..metadata.len], metadata);
    output_length = @intCast(required);
    return 0;
}

fn encodeIdentity(identity: kernel_v1.RequestIdentity, output: *[176]u8) void {
    @memcpy(output[0..32], &identity.machine_contract_digest);
    writeInt(u64, output, 32, identity.sequence);
    writeInt(u32, output, 40, identity.constructor_id);
    writeInt(u32, output, 44, identity.site_ordinal);
    @memcpy(output[48..80], &identity.effect_site_digest);
    @memcpy(output[80..112], &identity.payload_digest);
    @memcpy(output[112..144], &identity.continuation_digest);
    @memcpy(output[144..176], &identity.digest);
}

fn decodeIdentity(bytes: *const [176]u8) kernel_v1.RequestIdentity {
    return .{
        .machine_contract_digest = bytes[0..32].*,
        .sequence = readInt(u64, bytes, 32),
        .constructor_id = readInt(u32, bytes, 40),
        .site_ordinal = readInt(u32, bytes, 44),
        .effect_site_digest = bytes[48..80].*,
        .payload_digest = bytes[80..112].*,
        .continuation_digest = bytes[112..144].*,
        .digest = bytes[144..176].*,
    };
}

fn errorCode(err: ExecuteError) u32 {
    return switch (err) {
        error.MalformedKernelInput => 1,
        error.InvalidMagic,
        error.UnsupportedImageVersion,
        error.UnsupportedMachineAbi,
        error.UnsupportedStateFormat,
        error.UnsupportedKernelSemantics,
        error.UnknownFlags,
        error.InvalidHeaderLength,
        error.InvalidSectionCount,
        error.InvalidSectionOrder,
        error.InvalidSectionOffset,
        error.InvalidSectionLength,
        error.InvalidSchema,
        error.InvalidRoot,
        error.InvalidFailureMap,
        error.InvalidConstant,
        error.InvalidEffect,
        error.InvalidValue,
        error.InvalidFunction,
        error.InvalidSegment,
        error.InvalidInstruction,
        error.InvalidTerminator,
        error.InvalidConstructor,
        error.InvalidInvariant,
        error.InvalidTransition,
        error.UnreachableEntry,
        error.MachineContractDigestMismatch,
        error.ProgramSemanticDigestMismatch,
        error.DigestMismatch,
        error.ScratchRequirementMismatch,
        error.DuplicateFailureName,
        error.DuplicateFailureTag,
        error.DuplicateConstant,
        error.DuplicateEffectIdentity,
        => 2,
        error.InvalidState => 3,
        error.InvalidInitialArgs => 4,
        error.OutputCapacity => 5,
        error.LimitExceeded,
        error.LengthOverflow,
        error.LengthMismatch,
        error.TrailingBytes,
        error.ScratchCapacity,
        error.ExecutionBudgetExceeded,
        error.CapacityExceeded,
        error.UnsupportedOperation,
        error.InvalidImage,
        error.InvalidUtf8,
        error.FrameDepthExceeded,
        => 6,
    };
}

fn setError(message: []const u8) void {
    const length = @min(message.len, error_storage.len);
    @memcpy(error_storage[0..length], message[0..length]);
    error_length = @intCast(length);
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

fn writeInt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    value: anytype,
) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], @intCast(value), .little);
}
