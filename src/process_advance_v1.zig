const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const process_effect_v1 = @import("process_effect_v1");
const process_state_v1 = @import("process_state_v1");
const reducer_clause_v1 = @import("reducer_clause_v1");
const std = @import("std");

pub const kernel_semantic_version: u16 = 1;

pub const Error = image_v1.Error ||
    dynamic_value_v1.Error ||
    process_state_v1.Error ||
    process_effect_v1.Error ||
    reducer_clause_v1.Error || error{
    InvalidInitialArgs,
    InvalidProcessState,
    ResultRequestMismatch,
    ResultSchemaMismatch,
    UnexpectedEffectResult,
    UnsupportedTransition,
    InvalidBuffers,
    InvalidKernelInput,
};

pub const Instance = union(enum) {
    initial_args: []const u8,
    process_state: []const u8,
};

pub const Buffers = struct {
    output_state: []u8,
    output_value: []u8,
    output_request: []u8,
    candidate_state: []u8,
    environment: []u8,
    auxiliary_environment: []u8,
    scratch: []u8,
};

pub const Outcome = union(enum) {
    progressed: []const u8,
    requested: struct {
        state: []const u8,
        request: []const u8,
    },
    explicitly_yielded: []const u8,
    completed: []const u8,
    authored_failure: []const u8,
    needs_capacity: CapacityRequirement,
};

pub const CapacityRequirement = struct {
    minimum_input_bytes: u64,
    minimum_output_bytes: u64,
    minimum_scratch_bytes: u64,
    minimum_memory_pages: u64,
};

pub const outcome_magic = "ABL_PKO1".*;
pub const outcome_format_version: u16 = 1;
pub const outcome_header_length: usize = 32;
pub const kernel_input_magic = "ABL_PKI1".*;
pub const kernel_input_format_version: u16 = 1;
pub const kernel_input_header_length: usize = 40;

pub const KernelInputView = struct {
    image: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
};

pub fn encodeKernelInputHeader(
    instance_kind: u8,
    result_present: bool,
    image_length: u64,
    instance_length: u64,
    result_length: u64,
    output: []u8,
) Error![]const u8 {
    if (instance_kind > 1 or (!result_present and result_length != 0)) {
        return error.InvalidKernelInput;
    }
    if (output.len < kernel_input_header_length) return error.OutputCapacity;
    @memcpy(output[0..8], &kernel_input_magic);
    std.mem.writeInt(u16, output[8..10], kernel_input_format_version, .little);
    output[10] = instance_kind;
    output[11] = @intFromBool(result_present);
    std.mem.writeInt(u64, output[12..20], image_length, .little);
    std.mem.writeInt(u64, output[20..28], instance_length, .little);
    std.mem.writeInt(u64, output[28..36], result_length, .little);
    @memset(output[36..40], 0);
    return output[0..kernel_input_header_length];
}

pub fn validateKernelInput(input: []const u8) Error!KernelInputView {
    if (input.len < kernel_input_header_length or
        !std.mem.eql(u8, input[0..8], &kernel_input_magic) or
        readInt(u16, input, 8) != kernel_input_format_version or
        input[10] > 1 or input[11] & ~@as(u8, 1) != 0 or
        !allZero(input[36..40]))
    {
        return error.InvalidKernelInput;
    }
    const image_length = readInt(u64, input, 12);
    const instance_length = readInt(u64, input, 20);
    const result_length = readInt(u64, input, 28);
    const result_present = input[11] & 1 != 0;
    if (!result_present and result_length != 0) return error.InvalidKernelInput;
    const image_length_usize = std.math.cast(usize, image_length) orelse
        return error.InvalidKernelInput;
    const instance_length_usize = std.math.cast(usize, instance_length) orelse
        return error.InvalidKernelInput;
    const result_length_usize = std.math.cast(usize, result_length) orelse
        return error.InvalidKernelInput;
    var expected = std.math.add(usize, kernel_input_header_length, image_length_usize) catch
        return error.InvalidKernelInput;
    expected = std.math.add(usize, expected, instance_length_usize) catch
        return error.InvalidKernelInput;
    expected = std.math.add(usize, expected, result_length_usize) catch
        return error.InvalidKernelInput;
    if (expected != input.len) return error.InvalidKernelInput;
    var cursor: usize = kernel_input_header_length;
    const image = input[cursor..][0..image_length_usize];
    cursor += image_length_usize;
    const instance_bytes = input[cursor..][0..instance_length_usize];
    cursor += instance_length_usize;
    return .{
        .image = image,
        .instance = if (input[10] == 0)
            .{ .initial_args = instance_bytes }
        else
            .{ .process_state = instance_bytes },
        .effect_result = if (result_present)
            input[cursor..][0..result_length_usize]
        else
            null,
    };
}

pub fn encodeKernelInput(
    image: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    output: []u8,
) Error![]const u8 {
    const instance_bytes = switch (instance) {
        .initial_args => |bytes| bytes,
        .process_state => |bytes| bytes,
    };
    const instance_kind: u8 = switch (instance) {
        .initial_args => 0,
        .process_state => 1,
    };
    const result = effect_result orelse &.{};
    if (slicesOverlap(output, image) or
        slicesOverlap(output, instance_bytes) or
        slicesOverlap(output, result))
    {
        return error.InvalidBuffers;
    }
    const image_length = std.math.cast(u64, image.len) orelse
        return error.OutputCapacity;
    const instance_length = std.math.cast(u64, instance_bytes.len) orelse
        return error.OutputCapacity;
    const result_length = std.math.cast(u64, result.len) orelse
        return error.OutputCapacity;
    var required = std.math.add(
        usize,
        kernel_input_header_length,
        image.len,
    ) catch return error.OutputCapacity;
    required = std.math.add(usize, required, instance_bytes.len) catch
        return error.OutputCapacity;
    required = std.math.add(usize, required, result.len) catch
        return error.OutputCapacity;
    if (output.len < required) return error.OutputCapacity;
    _ = try encodeKernelInputHeader(
        instance_kind,
        effect_result != null,
        image_length,
        instance_length,
        result_length,
        output,
    );
    var cursor: usize = kernel_input_header_length;
    @memcpy(output[cursor..][0..image.len], image);
    cursor += image.len;
    @memcpy(output[cursor..][0..instance_bytes.len], instance_bytes);
    cursor += instance_bytes.len;
    @memcpy(output[cursor..][0..result.len], result);
    return output[0..required];
}

pub fn encodeOutcome(outcome: Outcome, output: []u8) Error![]const u8 {
    const fields: struct { kind: u8, primary: []const u8, secondary: []const u8 } =
        switch (outcome) {
            .progressed => |state| .{ .kind = 0, .primary = state, .secondary = &.{} },
            .requested => |requested| .{
                .kind = 1,
                .primary = requested.state,
                .secondary = requested.request,
            },
            .explicitly_yielded => |state| .{
                .kind = 2,
                .primary = state,
                .secondary = &.{},
            },
            .completed => |result| .{
                .kind = 3,
                .primary = result,
                .secondary = &.{},
            },
            .authored_failure => |failure| .{
                .kind = 4,
                .primary = failure,
                .secondary = &.{},
            },
            .needs_capacity => |requirement| {
                if (output.len < outcome_header_length + 32) {
                    return error.OutputCapacity;
                }
                writeOutcomeHeader(output, 5, 32, 0);
                std.mem.writeInt(
                    u64,
                    output[outcome_header_length..][0..8],
                    requirement.minimum_input_bytes,
                    .little,
                );
                std.mem.writeInt(
                    u64,
                    output[outcome_header_length + 8 ..][0..8],
                    requirement.minimum_output_bytes,
                    .little,
                );
                std.mem.writeInt(
                    u64,
                    output[outcome_header_length + 16 ..][0..8],
                    requirement.minimum_scratch_bytes,
                    .little,
                );
                std.mem.writeInt(
                    u64,
                    output[outcome_header_length + 24 ..][0..8],
                    requirement.minimum_memory_pages,
                    .little,
                );
                return output[0 .. outcome_header_length + 32];
            },
        };
    if (slicesOverlap(output, fields.primary) or
        slicesOverlap(output, fields.secondary))
    {
        return error.InvalidBuffers;
    }
    const primary_length = std.math.cast(u64, fields.primary.len) orelse
        return error.OutputCapacity;
    const secondary_length = std.math.cast(u64, fields.secondary.len) orelse
        return error.OutputCapacity;
    const payload_length = std.math.add(
        usize,
        fields.primary.len,
        fields.secondary.len,
    ) catch return error.OutputCapacity;
    const required = std.math.add(
        usize,
        outcome_header_length,
        payload_length,
    ) catch return error.OutputCapacity;
    if (output.len < required) return error.OutputCapacity;
    writeOutcomeHeader(
        output,
        fields.kind,
        primary_length,
        secondary_length,
    );
    @memcpy(
        output[outcome_header_length..][0..fields.primary.len],
        fields.primary,
    );
    @memcpy(
        output[outcome_header_length + fields.primary.len ..][0..fields.secondary.len],
        fields.secondary,
    );
    return output[0..required];
}

pub fn outcomeEncodedLength(outcome: Outcome) Error!usize {
    return switch (outcome) {
        .progressed => |state| addOutcomeLength(state.len, 0),
        .requested => |requested| addOutcomeLength(
            requested.state.len,
            requested.request.len,
        ),
        .explicitly_yielded => |state| addOutcomeLength(state.len, 0),
        .completed => |result| addOutcomeLength(result.len, 0),
        .authored_failure => |failure| addOutcomeLength(failure.len, 0),
        .needs_capacity => outcome_header_length + 32,
    };
}

pub const CapacityClass = enum { input, output, scratch };

/// A physical interpreter arena that carries its accounting class in its type.
/// Generic storage folds therefore include every declared arena automatically.
pub fn CapacityArena(
    comptime class: CapacityClass,
    comptime capacity: usize,
) type {
    return struct {
        pub const capacity_class = class;
        bytes: [capacity]u8 align(16) = undefined,
    };
}

pub fn capacityArenaCount(comptime Storage: type) usize {
    var count: usize = 0;
    inline for (std.meta.fields(Storage)) |field| {
        if (!@hasDecl(field.type, "capacity_class") or
            !@hasField(field.type, "bytes"))
        {
            @compileError("every capacity storage field must be a CapacityArena");
        }
        count += 1;
    }
    return count;
}

pub fn minimumMemoryPagesForStorage(
    storage: anytype,
    requirement: CapacityRequirement,
    live_memory_pages: u64,
) u64 {
    const Storage = @typeInfo(@TypeOf(storage)).pointer.child;
    var growth: u64 = 0;
    inline for (std.meta.fields(Storage)) |field| {
        const arena = &@field(storage.*, field.name);
        const required = switch (field.type.capacity_class) {
            .input => requirement.minimum_input_bytes,
            .output => requirement.minimum_output_bytes,
            .scratch => requirement.minimum_scratch_bytes,
        };
        const current_logical: u64 = @intCast(arena.bytes.len);
        const current_physical: u64 = @sizeOf(field.type);
        const required_physical = if (required <= current_logical)
            current_physical
        else
            alignedArenaBytes(required, @alignOf(field.type));
        growth = saturatingAddU64(
            growth,
            required_physical -| current_physical,
        );
    }
    const live_bytes = std.math.mul(
        u64,
        live_memory_pages,
        65536,
    ) catch std.math.maxInt(u64);
    return bytesToPages(saturatingAddU64(live_bytes, growth));
}

fn alignedArenaBytes(bytes: u64, alignment: comptime_int) u64 {
    const mask: u64 = alignment - 1;
    const added = std.math.add(u64, bytes, mask) catch
        return std.math.maxInt(u64);
    return added & ~mask;
}

pub fn currentCapacityForClass(
    storage: anytype,
    class: CapacityClass,
) u64 {
    const Storage = @typeInfo(@TypeOf(storage)).pointer.child;
    var current: u64 = 0;
    inline for (std.meta.fields(Storage)) |field| {
        if (field.type.capacity_class == class) {
            current = @max(
                current,
                @as(u64, @intCast(@field(storage.*, field.name).bytes.len)),
            );
        }
    }
    return current;
}

pub fn encodeOutcomeForCapacity(
    outcome: Outcome,
    input_length: usize,
    storage: anytype,
    minimum_memory_pages_floor: u64,
    output: []u8,
) Error![]const u8 {
    const required_output = try outcomeEncodedLength(outcome);
    const admitted_outcome: Outcome = switch (outcome) {
        .needs_capacity => |requirement| .{ .needs_capacity = .{
            .minimum_input_bytes = requirement.minimum_input_bytes,
            .minimum_output_bytes = requirement.minimum_output_bytes,
            .minimum_scratch_bytes = requirement.minimum_scratch_bytes,
            .minimum_memory_pages = @max(
                requirement.minimum_memory_pages,
                minimumMemoryPagesForStorage(
                    storage,
                    requirement,
                    minimum_memory_pages_floor,
                ),
            ),
        } },
        else => outcome,
    };
    return encodeOutcome(admitted_outcome, output) catch |err| switch (err) {
        error.OutputCapacity => encodeOutcome(
            .{ .needs_capacity = requirement: {
                const requirement: CapacityRequirement = .{
                    .minimum_input_bytes = @intCast(input_length),
                    .minimum_output_bytes = @intCast(required_output),
                    .minimum_scratch_bytes = currentCapacityForClass(
                        storage,
                        .scratch,
                    ),
                    .minimum_memory_pages = 0,
                };
                break :requirement .{
                    .minimum_input_bytes = requirement.minimum_input_bytes,
                    .minimum_output_bytes = requirement.minimum_output_bytes,
                    .minimum_scratch_bytes = requirement.minimum_scratch_bytes,
                    .minimum_memory_pages = minimumMemoryPagesForStorage(
                        storage,
                        requirement,
                        minimum_memory_pages_floor,
                    ),
                };
            } },
            output,
        ),
        else => err,
    };
}

fn bytesToPages(bytes: u64) u64 {
    return bytes / 65536 + @intFromBool(bytes % 65536 != 0);
}

fn addOutcomeLength(primary: usize, secondary: usize) Error!usize {
    var length = std.math.add(
        usize,
        outcome_header_length,
        primary,
    ) catch return error.OutputCapacity;
    length = std.math.add(usize, length, secondary) catch
        return error.OutputCapacity;
    return length;
}

fn writeOutcomeHeader(
    output: []u8,
    kind: u8,
    primary_length: u64,
    secondary_length: u64,
) void {
    @memcpy(output[0..outcome_magic.len], &outcome_magic);
    std.mem.writeInt(u16, output[8..10], outcome_format_version, .little);
    output[10] = kind;
    output[11] = 0;
    std.mem.writeInt(u64, output[12..20], primary_length, .little);
    std.mem.writeInt(u64, output[20..28], secondary_length, .little);
    @memset(output[28..32], 0);
}

const Slot = reducer_clause_v1.Slot;
const slicesOverlap = process_state_v1.slicesOverlap;
const CapacityTracker = reducer_clause_v1.CapacityTracker;

const LoadedEnvironment = reducer_clause_v1.LoadedEnvironment;

const FrameAdmission = struct {
    constructor: []const u8,
    loaded: LoadedEnvironment,
};

const AdmittedState = struct {
    state: process_state_v1.StateView,
    constructor: []const u8,
    slots: [1024]Slot,
    activation_slots: [1024]Slot,
    loaded: LoadedEnvironment,
};

pub fn advance(
    image_bytes: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    try validateBufferOwnership(
        image_bytes,
        instance,
        effect_result,
        buffers,
        std.mem.asBytes(workspace),
    );
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = buffers.scratch;
    defer workspace.invariant_result = prior_invariant_result;
    var capacity: CapacityTracker = .{};
    return advanceFinite(
        image_bytes,
        instance,
        effect_result,
        buffers,
        workspace,
        &capacity,
    ) catch |err| switch (err) {
        error.OutputCapacity,
        error.ScratchCapacity,
        error.CapacityExceeded,
        => .{ .needs_capacity = capacityRequirement(
            image_bytes,
            instance,
            effect_result,
            buffers,
            capacity,
            err,
        ) },
        else => err,
    };
}

pub fn validateState(
    image_bytes: []const u8,
    state_bytes: []const u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!process_state_v1.StateView {
    const workspace_bytes = std.mem.asBytes(workspace);
    if (slicesOverlap(image_bytes, invariant_scratch) or
        slicesOverlap(state_bytes, invariant_scratch) or
        slicesOverlap(image_bytes, workspace_bytes) or
        slicesOverlap(state_bytes, workspace_bytes) or
        slicesOverlap(invariant_scratch, workspace_bytes))
    {
        return error.InvalidBuffers;
    }
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    const image = try image_v1.validateImage(image_bytes, workspace);
    const state = process_state_v1.validate(
        state_bytes,
        image.catalogs.envelope.header.program_transition_digest,
    ) catch return error.InvalidProcessState;
    _ = try admitFrames(image, state, workspace);
    return state;
}

pub const testing = if (@import("builtin").is_test) struct {
    pub fn validateProducedSuffix(
        image_bytes: []const u8,
        state_bytes: []const u8,
        expected_constructor_ids: []const u32,
        invariant_scratch: []u8,
        workspace: *image_v1.ValidationWorkspace,
    ) Error!void {
        const prior_invariant_result = workspace.invariant_result;
        workspace.invariant_result = invariant_scratch;
        defer workspace.invariant_result = prior_invariant_result;
        const image = try image_v1.validateImage(image_bytes, workspace);
        const state = process_state_v1.validate(
            state_bytes,
            image.catalogs.envelope.header.program_transition_digest,
        ) catch return error.InvalidProcessState;
        _ = try admitProducedSuffix(
            image,
            state,
            expected_constructor_ids,
            workspace,
        );
    }

    pub fn validateFrame(
        image_bytes: []const u8,
        frame: process_state_v1.Frame,
        invariant_scratch: []u8,
        workspace: *image_v1.ValidationWorkspace,
    ) Error!void {
        const prior_invariant_result = workspace.invariant_result;
        workspace.invariant_result = invariant_scratch;
        defer workspace.invariant_result = prior_invariant_result;
        const image = try image_v1.validateImage(image_bytes, workspace);
        var slots = [_]Slot{.{}} ** 1024;
        var activation_slots = [_]Slot{.{}} ** 1024;
        _ = try admitFrame(
            image,
            frame,
            &slots,
            &activation_slots,
            workspace,
        );
    }
} else struct {};

/// Encode and semantically admit canonical Process State for one exact BPI1.
pub fn encodeState(
    image_bytes: []const u8,
    frames: []const process_state_v1.Frame,
    output_state: []u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!process_state_v1.StateView {
    const workspace_bytes = std.mem.asBytes(workspace);
    const frame_descriptor_bytes = std.mem.sliceAsBytes(frames);
    const mutable_arenas = [_][]const u8{
        output_state,
        invariant_scratch,
        workspace_bytes,
    };
    for (mutable_arenas, 0..) |arena, index| {
        if (slicesOverlap(image_bytes, arena)) return error.InvalidBuffers;
        if (slicesOverlap(frame_descriptor_bytes, arena)) {
            return error.InvalidBuffers;
        }
        for (mutable_arenas[index + 1 ..]) |other| {
            if (slicesOverlap(arena, other)) return error.InvalidBuffers;
        }
    }
    for (frames) |frame| {
        if (slicesOverlap(frame.environment, output_state) or
            slicesOverlap(frame.environment, invariant_scratch) or
            slicesOverlap(frame.environment, workspace_bytes))
        {
            return error.InvalidBuffers;
        }
    }
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    const image = try image_v1.validateImage(image_bytes, workspace);
    const state = try process_state_v1.encode(
        image.catalogs.envelope.header.program_transition_digest,
        frames,
        output_state,
    );
    _ = try admitFrames(image, state, workspace);
    return state;
}

pub fn validateInitialArgs(
    image_bytes: []const u8,
    initial_args: []const u8,
    output_state: []u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const workspace_bytes = std.mem.asBytes(workspace);
    const arenas = [_][]const u8{
        image_bytes,
        initial_args,
        output_state,
        invariant_scratch,
        workspace_bytes,
    };
    for (arenas, 0..) |arena, index| {
        for (arenas[index + 1 ..]) |other| {
            if (slicesOverlap(arena, other)) return error.InvalidBuffers;
        }
    }
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    const image = try image_v1.validateImage(image_bytes, workspace);
    var capacity: CapacityTracker = .{};
    const state = try initialState(
        image,
        initial_args,
        output_state,
        invariant_scratch,
        workspace,
        &capacity,
    );
    _ = try admitFrames(image, state, workspace);
}

fn advanceFinite(
    image_bytes: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!Outcome {
    const image = try image_v1.validateImage(image_bytes, workspace);
    return switch (instance) {
        .initial_args => |initial_args| blk: {
            if (effect_result != null) return error.UnexpectedEffectResult;
            const initial = try initialState(
                image,
                initial_args,
                buffers.candidate_state,
                buffers.environment,
                workspace,
                capacity,
            );
            break :blk try advanceStateView(
                image,
                initial,
                null,
                buffers,
                workspace,
                capacity,
            );
        },
        .process_state => |state_bytes| try advanceState(
            image,
            state_bytes,
            effect_result,
            buffers,
            workspace,
            capacity,
        ),
    };
}

fn capacityRequirement(
    image_bytes: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    buffers: Buffers,
    capacity: CapacityTracker,
    err: anyerror,
) CapacityRequirement {
    const instance_length: u64 = switch (instance) {
        .initial_args => |bytes| @intCast(bytes.len),
        .process_state => |bytes| @intCast(bytes.len),
    };
    const result_length: u64 = if (effect_result) |bytes|
        @intCast(bytes.len)
    else
        0;
    const input = saturatingAddU64(
        kernel_input_header_length,
        saturatingAddU64(
            saturatingAddU64(image_bytes.len, instance_length),
            result_length,
        ),
    );
    const envelope = image_v1.validateEnvelope(image_bytes) catch null;
    const current_output: u64 = @max(
        @as(u64, @intCast(buffers.output_state.len)),
        @max(
            @as(u64, @intCast(buffers.output_value.len)),
            @max(
                @as(u64, @intCast(buffers.output_request.len)),
                @max(
                    @as(u64, @intCast(buffers.candidate_state.len)),
                    @max(
                        @as(u64, @intCast(buffers.environment.len)),
                        @as(u64, @intCast(buffers.auxiliary_environment.len)),
                    ),
                ),
            ),
        ),
    );
    const observed_output = if (capacity.output_bytes == 0)
        current_output +| 1
    else
        capacity.output_bytes;
    const minimum_output = if (err == error.OutputCapacity)
        observed_output
    else
        current_output;
    const current_scratch: u64 = @intCast(buffers.scratch.len);
    const required_scratch: u64 = if (envelope) |view|
        view.header.maximum_kernel_scratch_bytes
    else
        current_scratch +| 1;
    const minimum_scratch = @max(
        if (err == error.ScratchCapacity or err == error.CapacityExceeded)
            if (capacity.scratch_bytes == 0)
                @max(required_scratch, current_scratch +| 1)
            else
                capacity.scratch_bytes
        else
            current_scratch,
        if (err == error.ScratchCapacity or err == error.CapacityExceeded)
            0
        else
            required_scratch,
    );
    const requirement: CapacityRequirement = .{
        .minimum_input_bytes = input,
        .minimum_output_bytes = minimum_output,
        .minimum_scratch_bytes = minimum_scratch,
        .minimum_memory_pages = 0,
    };
    const fixed_bytes = saturatingAddU64(
        4 << 10,
        @intCast(@sizeOf(image_v1.ValidationWorkspace)),
    );
    return .{
        .minimum_input_bytes = requirement.minimum_input_bytes,
        .minimum_output_bytes = requirement.minimum_output_bytes,
        .minimum_scratch_bytes = requirement.minimum_scratch_bytes,
        .minimum_memory_pages = minimumMemoryPagesForBuffers(
            buffers,
            requirement,
            fixed_bytes,
        ),
    };
}

fn minimumMemoryPagesForBuffers(
    buffers: Buffers,
    requirement: CapacityRequirement,
    fixed_bytes: u64,
) u64 {
    var total = saturatingAddU64(
        fixed_bytes,
        requirement.minimum_input_bytes,
    );
    inline for (std.meta.fields(Buffers)) |field| {
        const current = @field(buffers, field.name).len;
        const required = if (comptime std.mem.eql(u8, field.name, "scratch"))
            requirement.minimum_scratch_bytes
        else
            requirement.minimum_output_bytes;
        total = saturatingAddU64(
            total,
            @max(required, @as(u64, @intCast(current))),
        );
    }
    return bytesToPages(total);
}

fn validateBufferOwnership(
    image_bytes: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace_bytes: []u8,
) Error!void {
    const inputs = [_][]const u8{
        image_bytes,
        switch (instance) {
            .initial_args => |bytes| bytes,
            .process_state => |bytes| bytes,
        },
        effect_result orelse &.{},
    };
    const outputs = [_][]u8{
        buffers.output_state,
        buffers.output_value,
        buffers.output_request,
        buffers.candidate_state,
        buffers.environment,
        buffers.auxiliary_environment,
        buffers.scratch,
        workspace_bytes,
    };
    for (outputs, 0..) |output, index| {
        for (inputs) |input| {
            if (slicesOverlap(output, input)) return error.InvalidBuffers;
        }
        for (outputs[index + 1 ..]) |other| {
            if (slicesOverlap(output, other)) return error.InvalidBuffers;
        }
    }
}

fn saturatingAdd(left: usize, right: usize) usize {
    return left +| right;
}

fn saturatingAddU64(left: u64, right: u64) u64 {
    return left +| right;
}

fn initialState(
    image: image_v1.ValidatedImage,
    initial_args: []const u8,
    output: []u8,
    environment_output: []u8,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!process_state_v1.StateView {
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        image.catalogs.initial_constructor_id,
    );
    var slots = [_]Slot{.{}} ** 1024;
    var activation_slots = [_]Slot{.{}} ** 1024;
    reducer_clause_v1.bindInitialEnvironment(
        image,
        constructor,
        initial_args,
        &slots,
        &activation_slots,
        workspace,
    ) catch |err| switch (err) {
        error.ScratchCapacity => return error.ScratchCapacity,
        else => return error.InvalidInitialArgs,
    };
    const environment = try encodeEnvironment(
        constructor,
        null,
        &activation_slots,
        &slots,
        environment_output,
        capacity,
    );
    const frames = [_]process_state_v1.Frame{.{
        .constructor_id = image.catalogs.initial_constructor_id,
        .environment = environment,
    }};
    return process_state_v1.encodeTracked(
        image.catalogs.envelope.header.program_transition_digest,
        &frames,
        output,
        &capacity.output_bytes,
    );
}

fn advanceState(
    image: image_v1.ValidatedImage,
    state_bytes: []const u8,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!Outcome {
    const state = process_state_v1.validate(
        state_bytes,
        image.catalogs.envelope.header.program_transition_digest,
    ) catch return error.InvalidProcessState;
    return advanceStateView(
        image,
        state,
        effect_result,
        buffers,
        workspace,
        capacity,
    );
}

fn advanceStateView(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!Outcome {
    var admitted = try admitFrames(image, state, workspace);
    if (admitted.constructor[8] == 3) {
        if (effect_result) |result_bytes| {
            var successor = try resumePending(
                image,
                &admitted,
                result_bytes,
                buffers,
                workspace,
                capacity,
            );
            return stepState(
                image,
                &successor,
                buffers,
                workspace,
                capacity,
            );
        }
        return currentRequest(
            image,
            &admitted,
            buffers,
            workspace,
            capacity,
        );
    }
    if (effect_result != null) return error.UnexpectedEffectResult;
    return stepState(image, &admitted, buffers, workspace, capacity);
}

fn stepState(
    image: image_v1.ValidatedImage,
    admitted: *AdmittedState,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!Outcome {
    const state = admitted.state;
    var slots = admitted.slots;
    var activation_slots = admitted.activation_slots;
    const loaded = admitted.loaded;
    const segment_id = readInt(u16, admitted.constructor, 12);
    const clause = try reducer_clause_v1.evaluateClause(
        image,
        segment_id,
        &slots,
        buffers.output_value,
        buffers.scratch,
        workspace,
        capacity,
    );
    const outcome: Outcome = switch (clause) {
        .progressed => |progressed| .{ .progressed = (try transitionState(
            image,
            state,
            segment_id,
            progressed.edge_kind,
            progressed.edge,
            loaded.activation_entry,
            &activation_slots,
            &slots,
            buffers,
            workspace,
            capacity,
        )).state.bytes },
        .requested => |request| blk: {
            const await_constructor_id = try image_v1.evaluatorSuspensionConstructor(
                image,
                segment_id,
                3,
            );
            const await_constructor = try image_v1.evaluatorConstructorRecord(
                image,
                await_constructor_id,
            );
            const environment = try encodeEnvironment(
                await_constructor,
                loaded.activation_entry,
                &activation_slots,
                &slots,
                buffers.environment,
                capacity,
            );
            const parked_admitted = try replaceTopAdmitted(
                image,
                state,
                .{
                    .constructor_id = await_constructor_id,
                    .environment = environment,
                },
                buffers.output_state,
                workspace,
                capacity,
            );
            break :blk try makeRequest(
                image,
                parked_admitted.state.bytes,
                request.site_ordinal,
                request.payload,
                buffers.output_request,
                workspace,
                capacity,
            );
        },
        .explicit_yield => |continuation| .{
            .explicitly_yielded = (try transitionState(
                image,
                state,
                segment_id,
                4,
                continuation,
                loaded.activation_entry,
                &activation_slots,
                &slots,
                buffers,
                workspace,
                capacity,
            )).state.bytes,
        },
        .completed => |value| .{ .completed = value },
        .authored_failure => |failure| .{ .authored_failure = failure },
        .call => |callee| .{ .progressed = (try callState(
            image,
            state,
            segment_id,
            callee,
            loaded.activation_entry,
            &activation_slots,
            &slots,
            buffers,
            workspace,
            capacity,
        )).state.bytes },
        .return_to_caller => |return_value| .{
            .progressed = (try returnToCaller(
                image,
                state,
                return_value,
                buffers,
                workspace,
                capacity,
            )).state.bytes,
        },
    };
    return outcome;
}

fn callState(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    source_segment_id: u16,
    callee: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *[1024]Slot,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const return_constructor_id = try image_v1.evaluatorSuspensionConstructor(
        image,
        source_segment_id,
        4,
    );
    const return_constructor = try image_v1.evaluatorConstructorRecord(
        image,
        return_constructor_id,
    );
    const parent_environment = try encodeEnvironment(
        return_constructor,
        activation_entry,
        activation_slots,
        slots,
        buffers.environment,
        capacity,
    );

    const target_segment_id = readInt(u16, callee, 0);
    const target_segment = try image_v1.evaluatorSegmentRecord(
        image,
        target_segment_id,
    );
    const child_constructor_id = try image_v1.evaluatorTransitionConstructor(
        image,
        source_segment_id,
        3,
        target_segment_id,
    );
    const child_constructor = try image_v1.evaluatorConstructorRecord(
        image,
        child_constructor_id,
    );
    try applyValueEdge(
        child_constructor,
        target_segment,
        callee,
        slots,
    );
    const parent_frame = process_state_v1.Frame{
        .constructor_id = return_constructor_id,
        .environment = parent_environment,
    };
    const child_environment = try encodeEnvironment(
        child_constructor,
        child_constructor_id,
        slots,
        slots,
        buffers.auxiliary_environment,
        capacity,
    );
    return replaceTopAndAppendAdmitted(
        image,
        state,
        parent_frame,
        .{
            .constructor_id = child_constructor_id,
            .environment = child_environment,
        },
        buffers.output_state,
        workspace,
        capacity,
    );
}

fn applyValueEdge(
    constructor: []const u8,
    target_segment: []const u8,
    edge: []const u8,
    slots: *[1024]Slot,
) Error!void {
    return applyEdge(constructor, target_segment, edge, null, slots);
}

fn applyResumeEdge(
    constructor: []const u8,
    target_segment: []const u8,
    edge: []const u8,
    resume_value: []const u8,
    slots: *[1024]Slot,
) Error!void {
    return applyEdge(
        constructor,
        target_segment,
        edge,
        resume_value,
        slots,
    );
}

fn applyEdge(
    constructor: []const u8,
    target_segment: []const u8,
    edge: []const u8,
    injected_value: ?[]const u8,
    slots: *[1024]Slot,
) Error!void {
    reducer_clause_v1.applyEdge(
        constructor,
        target_segment,
        edge,
        injected_value,
        slots,
    ) catch |err| switch (err) {
        error.InvalidState, error.InvalidImage => return error.InvalidProcessState,
        error.UnsupportedOperation => return error.UnsupportedTransition,
        else => return err,
    };
}

fn returnToCaller(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    return_value: []const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const parent = try process_state_v1.parentFrame(state);
    const parent_constructor = try image_v1.evaluatorConstructorRecord(
        image,
        parent.frame.constructor_id,
    );
    if (parent_constructor[8] != 4 or parent_constructor[9] != 2) {
        return error.InvalidProcessState;
    }
    var slots = [_]Slot{.{}} ** 1024;
    var activation_slots = [_]Slot{.{}} ** 1024;
    const loaded = try decodeEnvironment(
        image,
        parent_constructor,
        parent.frame.environment,
        &slots,
        &activation_slots,
        workspace,
    );
    const parent_segment_id = readInt(u16, parent_constructor, 12);
    const parent_segment = try image_v1.evaluatorSegmentRecord(
        image,
        parent_segment_id,
    );
    const continuation = suspensionContinuation(
        parent_segment,
        image_v1.evaluatorSegmentTerminator(parent_segment),
    );
    const target_segment_id = readInt(u16, continuation, 0);
    const target_segment = try image_v1.evaluatorSegmentRecord(
        image,
        target_segment_id,
    );
    const next_constructor_id = try image_v1.evaluatorTransitionConstructor(
        image,
        parent_segment_id,
        4,
        target_segment_id,
    );
    const next_constructor = try image_v1.evaluatorConstructorRecord(
        image,
        next_constructor_id,
    );
    try applyResumeEdge(
        next_constructor,
        target_segment,
        continuation,
        return_value,
        &slots,
    );
    const environment = try encodeEnvironment(
        next_constructor,
        loaded.activation_entry,
        &activation_slots,
        &slots,
        buffers.environment,
        capacity,
    );
    return replaceParentAndDropTopAdmitted(
        image,
        state,
        .{
            .constructor_id = next_constructor_id,
            .environment = environment,
        },
        buffers.output_state,
        workspace,
        capacity,
    );
}

fn currentRequest(
    image: image_v1.ValidatedImage,
    admitted: *const AdmittedState,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!Outcome {
    const parts = try pendingRequestParts(
        image,
        admitted.constructor,
        &admitted.slots,
    );
    try capacity.requireOutput(
        buffers.output_state.len,
        admitted.state.bytes.len,
    );
    @memcpy(
        buffers.output_state[0..admitted.state.bytes.len],
        admitted.state.bytes,
    );
    return makeRequest(
        image,
        buffers.output_state[0..admitted.state.bytes.len],
        parts.site_ordinal,
        parts.payload,
        buffers.output_request,
        workspace,
        capacity,
    );
}

const PendingRequestParts = struct {
    site_ordinal: u32,
    payload: []const u8,
};

fn pendingRequestParts(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
    slots: *const [1024]Slot,
) Error!PendingRequestParts {
    const segment_id = readInt(u16, constructor, 12);
    const segment = try image_v1.evaluatorSegmentRecord(image, segment_id);
    const terminator = image_v1.evaluatorSegmentTerminator(segment);
    const suspension = reducer_clause_v1.suspensionView(
        segment,
        terminator,
    ) catch return error.InvalidProcessState;
    const effect = switch (suspension) {
        .effect => |effect| effect,
        else => return error.InvalidProcessState,
    };
    if (!slots[effect.request_value].initialized) return error.InvalidProcessState;
    return .{
        .site_ordinal = effect.site_ordinal,
        .payload = slots[effect.request_value].bytes,
    };
}

fn makeRequest(
    image: image_v1.ValidatedImage,
    parked_state: []const u8,
    site_ordinal: u32,
    payload: []const u8,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!Outcome {
    const request_input = try requestInput(
        image,
        parked_state,
        site_ordinal,
        payload,
        workspace,
    );
    const request = try process_effect_v1.encodeRequestTracked(
        request_input,
        output,
        &capacity.output_bytes,
    );
    return .{ .requested = .{ .state = parked_state, .request = request } };
}

fn requestInput(
    image: image_v1.ValidatedImage,
    parked_state: []const u8,
    site_ordinal: u32,
    payload: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!process_effect_v1.RequestInput {
    const effect = try image_v1.evaluatorEffect(image, site_ordinal);
    const payload_schema_digest = try dynamic_value_v1.schemaDigest(
        image.catalogs.schemas,
        effect.payload_schema,
        &workspace.schema_hash_tasks,
    );
    const resume_schema_digest = try dynamic_value_v1.schemaDigest(
        image.catalogs.schemas,
        effect.resume_schema,
        &workspace.schema_hash_tasks,
    );
    const state_digest = process_state_v1.artifactDigest(parked_state);
    var continuation_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    continuation_hasher.update("boundary-process-continuation-v1\x00");
    continuation_hasher.update(parked_state);
    var continuation_digest: [32]u8 = undefined;
    continuation_hasher.final(&continuation_digest);
    return .{
        .program_transition_digest = image.catalogs.envelope.header.program_transition_digest,
        .pre_request_state_digest = state_digest,
        .effect_site_semantic_digest = effect.semantic_digest,
        .payload_schema_digest = payload_schema_digest,
        .resume_schema_digest = resume_schema_digest,
        .continuation_digest = continuation_digest,
        .effect_semantic_identity = effect.semantic_identity,
        .payload = payload,
    };
}

fn resumePending(
    image: image_v1.ValidatedImage,
    admitted: *const AdmittedState,
    result_bytes: []const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const state = admitted.state;
    const constructor = admitted.constructor;
    var slots = admitted.slots;
    const activation_slots = admitted.activation_slots;
    const parts = try pendingRequestParts(
        image,
        constructor,
        &slots,
    );
    const request_input = try requestInput(
        image,
        state.bytes,
        parts.site_ordinal,
        parts.payload,
        workspace,
    );
    const request_identity = process_effect_v1.requestIdentity(request_input);
    const result = try process_effect_v1.validateResult(result_bytes);
    if (!std.mem.eql(
        u8,
        &request_identity,
        &result.request_identity_digest,
    )) return error.ResultRequestMismatch;
    if (!std.mem.eql(
        u8,
        &request_input.resume_schema_digest,
        &result.resume_schema_digest,
    )) return error.ResultSchemaMismatch;
    const segment_id = readInt(u16, constructor, 12);
    const segment = try image_v1.evaluatorSegmentRecord(image, segment_id);
    const terminator = image_v1.evaluatorSegmentTerminator(segment);
    const effect = try image_v1.evaluatorEffect(
        image,
        parts.site_ordinal,
    );
    dynamic_value_v1.validateValue(
        image.catalogs.schemas,
        effect.resume_schema,
        result.@"resume",
        &workspace.value_tasks,
    ) catch return error.InvalidResult;
    const continuation = suspensionContinuation(segment, terminator);
    const target_segment_id = readInt(u16, continuation, 0);
    const target_segment = try image_v1.evaluatorSegmentRecord(
        image,
        target_segment_id,
    );
    const target_constructor_id = try image_v1.evaluatorTransitionConstructor(
        image,
        segment_id,
        4,
        target_segment_id,
    );
    const target_constructor = try image_v1.evaluatorConstructorRecord(
        image,
        target_constructor_id,
    );
    try applyEdge(
        target_constructor,
        target_segment,
        continuation,
        result.@"resume",
        &slots,
    );
    const environment = try encodeEnvironment(
        target_constructor,
        admitted.loaded.activation_entry,
        &activation_slots,
        &slots,
        buffers.environment,
        capacity,
    );
    return replaceTopAdmitted(
        image,
        state,
        .{
            .constructor_id = target_constructor_id,
            .environment = environment,
        },
        buffers.candidate_state,
        workspace,
        capacity,
    );
}

fn transitionState(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    source_segment_id: u16,
    edge_kind: u8,
    edge: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *[1024]Slot,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const target_segment_id = readInt(u16, edge, 0);
    const target_segment = try image_v1.evaluatorSegmentRecord(
        image,
        target_segment_id,
    );
    const constructor_id = try image_v1.evaluatorTransitionConstructor(
        image,
        source_segment_id,
        edge_kind,
        target_segment_id,
    );
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        constructor_id,
    );
    try applyEdge(constructor, target_segment, edge, null, slots);
    const environment = try encodeEnvironment(
        constructor,
        activation_entry,
        activation_slots,
        slots,
        buffers.environment,
        capacity,
    );
    return replaceTopAdmitted(
        image,
        state,
        .{ .constructor_id = constructor_id, .environment = environment },
        buffers.output_state,
        workspace,
        capacity,
    );
}

fn replaceTopAdmitted(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    frame: process_state_v1.Frame,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const successor = try process_state_v1.replaceTopTracked(
        state,
        frame,
        output,
        &capacity.output_bytes,
    );
    return admitProducedSuffix(
        image,
        successor,
        &.{frame.constructor_id},
        workspace,
    );
}

fn replaceTopAndAppendAdmitted(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    parent: process_state_v1.Frame,
    child: process_state_v1.Frame,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const successor = try process_state_v1.replaceTopAndAppendTracked(
        state,
        parent,
        child,
        output,
        &capacity.output_bytes,
    );
    return admitProducedSuffix(
        image,
        successor,
        &.{ parent.constructor_id, child.constructor_id },
        workspace,
    );
}

fn replaceParentAndDropTopAdmitted(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    parent: process_state_v1.Frame,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
    capacity: *CapacityTracker,
) Error!AdmittedState {
    const successor = try process_state_v1.replaceParentAndDropTopTracked(
        state,
        parent,
        output,
        &capacity.output_bytes,
    );
    return admitProducedSuffix(
        image,
        successor,
        &.{parent.constructor_id},
        workspace,
    );
}

fn admitProducedSuffix(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    expected_constructor_ids: []const u32,
    workspace: *image_v1.ValidationWorkspace,
) Error!AdmittedState {
    if (expected_constructor_ids.len == 0 or
        expected_constructor_ids.len > state.frame_count)
    {
        return error.InvalidProcessState;
    }
    const first_changed = state.frame_count - expected_constructor_ids.len;
    var iterator = state.iterator();
    var frame_index: u64 = 0;
    var suffix_index: usize = 0;
    var saw_frame = false;
    var previous_constructor: []const u8 = &.{};
    var previous_slots = [_]Slot{.{}} ** 1024;
    var previous_activation_slots = [_]Slot{.{}} ** 1024;
    var previous_loaded: LoadedEnvironment = .{ .activation_entry = null };
    while (try iterator.next()) |frame| : (frame_index += 1) {
        if (first_changed != 0 and frame_index + 1 == first_changed) {
            var slots = [_]Slot{.{}} ** 1024;
            var activation_slots = [_]Slot{.{}} ** 1024;
            const projected = try projectFrame(
                image,
                frame,
                &slots,
                &activation_slots,
                workspace,
            );
            saw_frame = true;
            previous_constructor = projected.constructor;
            previous_slots = slots;
            previous_activation_slots = activation_slots;
            previous_loaded = projected.loaded;
            continue;
        }
        if (frame_index < first_changed) continue;
        if (suffix_index >= expected_constructor_ids.len or
            frame.constructor_id != expected_constructor_ids[suffix_index])
        {
            return error.InvalidProcessState;
        }
        var slots = [_]Slot{.{}} ** 1024;
        var activation_slots = [_]Slot{.{}} ** 1024;
        const admitted = try admitFrame(
            image,
            frame,
            &slots,
            &activation_slots,
            workspace,
        );
        if (saw_frame) {
            try validateStackPair(
                image,
                previous_constructor,
                &previous_slots,
                admitted.constructor,
                admitted.loaded.activation_entry,
                &activation_slots,
            );
        }
        saw_frame = true;
        previous_constructor = admitted.constructor;
        previous_slots = slots;
        previous_activation_slots = activation_slots;
        previous_loaded = admitted.loaded;
        suffix_index += 1;
    }
    if (suffix_index != expected_constructor_ids.len) {
        return error.InvalidProcessState;
    }
    if (!saw_frame or
        reducer_clause_v1.isAwaitCallConstructor(image, previous_constructor))
    {
        return error.InvalidProcessState;
    }
    return .{
        .state = state,
        .constructor = previous_constructor,
        .slots = previous_slots,
        .activation_slots = previous_activation_slots,
        .loaded = previous_loaded,
    };
}

fn admitFrames(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    workspace: *image_v1.ValidationWorkspace,
) Error!AdmittedState {
    var iterator = state.iterator();
    var index: u64 = 0;
    var saw_frame = false;
    var previous_constructor: []const u8 = &.{};
    var previous_slots = [_]Slot{.{}} ** 1024;
    var previous_activation_slots = [_]Slot{.{}} ** 1024;
    var previous_loaded: LoadedEnvironment = .{ .activation_entry = null };
    while (try iterator.nextSpan()) |frame_span| : (index += 1) {
        var slots = [_]Slot{.{}} ** 1024;
        var activation_slots = [_]Slot{.{}} ** 1024;
        const admitted = try admitFrame(
            image,
            frame_span.frame,
            &slots,
            &activation_slots,
            workspace,
        );
        if (index == 0) {
            const segment = try image_v1.evaluatorSegmentRecord(
                image,
                readInt(u16, admitted.constructor, 12),
            );
            if (readInt(u16, segment, 6) != 0) {
                return error.InvalidProcessState;
            }
        } else {
            try validateStackPair(
                image,
                previous_constructor,
                &previous_slots,
                admitted.constructor,
                admitted.loaded.activation_entry,
                &activation_slots,
            );
        }
        saw_frame = true;
        previous_constructor = admitted.constructor;
        previous_slots = slots;
        previous_activation_slots = activation_slots;
        previous_loaded = admitted.loaded;
    }
    if (reducer_clause_v1.isAwaitCallConstructor(image, previous_constructor)) {
        return error.InvalidProcessState;
    }
    if (!saw_frame) return error.InvalidProcessState;
    return .{
        .state = state,
        .constructor = previous_constructor,
        .slots = previous_slots,
        .activation_slots = previous_activation_slots,
        .loaded = previous_loaded,
    };
}

fn admitFrame(
    image: image_v1.ValidatedImage,
    frame: process_state_v1.Frame,
    slots: *[1024]Slot,
    activation_slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!FrameAdmission {
    if (frame.constructor_id >= image.constructor_count) {
        return error.InvalidProcessState;
    }
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        frame.constructor_id,
    );
    const loaded = try loadEnvironment(
        image,
        constructor,
        frame.environment,
        slots,
        activation_slots,
        workspace,
    );
    return .{
        .constructor = constructor,
        .loaded = loaded,
    };
}

fn projectFrame(
    image: image_v1.ValidatedImage,
    frame: process_state_v1.Frame,
    slots: *[1024]Slot,
    activation_slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!FrameAdmission {
    if (frame.constructor_id >= image.constructor_count) {
        return error.InvalidProcessState;
    }
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        frame.constructor_id,
    );
    const loaded = try decodeEnvironment(
        image,
        constructor,
        frame.environment,
        slots,
        activation_slots,
        workspace,
    );
    return .{
        .constructor = constructor,
        .loaded = loaded,
    };
}

fn validateStackPair(
    image: image_v1.ValidatedImage,
    parent_constructor: []const u8,
    parent_slots: *const [1024]Slot,
    child_constructor: []const u8,
    child_activation_entry: ?u32,
    child_slots: *const [1024]Slot,
) Error!void {
    const parent_segment_id = readInt(u16, parent_constructor, 12);
    const parent_segment = try image_v1.evaluatorSegmentRecord(
        image,
        parent_segment_id,
    );
    const callee = suspensionCallee(
        parent_segment,
        image_v1.evaluatorSegmentTerminator(parent_segment),
    );
    if (callee.len < 4) return error.InvalidProcessState;
    const expected_call_entry = try image_v1.evaluatorTransitionConstructor(
        image,
        parent_segment_id,
        3,
        readInt(u16, callee, 0),
    );
    reducer_clause_v1.validateStackPair(
        image,
        parent_constructor,
        parent_slots,
        child_constructor,
        child_activation_entry,
        child_slots,
        expected_call_entry,
    ) catch return error.InvalidProcessState;
}

fn loadEnvironment(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    activation_slots: ?*[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!LoadedEnvironment {
    const loaded = reducer_clause_v1.loadEnvironmentSlots(
        image,
        constructor,
        environment,
        slots,
        activation_slots,
        workspace,
    ) catch |err| switch (err) {
        error.ScratchCapacity => return error.ScratchCapacity,
        else => return error.InvalidProcessState,
    };
    if (loaded.activation_entry) |entry| {
        _ = image_v1.evaluatorConstructorRecord(image, entry) catch
            return error.InvalidProcessState;
    }
    return loaded;
}

fn decodeEnvironment(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    activation_slots: ?*[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!LoadedEnvironment {
    const loaded = reducer_clause_v1.decodeEnvironmentSlots(
        image,
        constructor,
        environment,
        slots,
        activation_slots,
        workspace,
    ) catch return error.InvalidProcessState;
    if (loaded.activation_entry) |entry| {
        _ = image_v1.evaluatorConstructorRecord(image, entry) catch
            return error.InvalidProcessState;
    }
    return loaded;
}

fn encodeEnvironment(
    constructor: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *const [1024]Slot,
    output: []u8,
    capacity: *CapacityTracker,
) Error![]const u8 {
    const required = reducer_clause_v1.environmentEncodedLength(
        constructor,
        activation_entry,
        activation_slots,
        slots,
    ) catch |err| switch (err) {
        error.InvalidState => return error.InvalidProcessState,
        else => return err,
    };
    try capacity.requireOutput(output.len, required);
    return reducer_clause_v1.encodeEnvironmentSlots(
        constructor,
        activation_entry,
        activation_slots,
        slots,
        output,
    ) catch |err| switch (err) {
        error.InvalidState => return error.InvalidProcessState,
        else => return err,
    };
}

const suspensionContinuation = reducer_clause_v1.suspensionContinuation;
const suspensionCallee = reducer_clause_v1.suspensionCallee;
const edgeLength = reducer_clause_v1.edgeLength;

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

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}
