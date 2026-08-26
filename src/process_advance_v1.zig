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
pub const outcome_header_length: usize = 24;
pub const kernel_input_magic = "ABL_PKI1".*;
pub const kernel_input_format_version: u16 = 1;
pub const kernel_input_header_length: usize = 28;

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
    const image_length = std.math.cast(u32, image.len) orelse
        return error.OutputCapacity;
    const instance_length = std.math.cast(u32, instance_bytes.len) orelse
        return error.OutputCapacity;
    const result_length = std.math.cast(u32, result.len) orelse
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
    @memcpy(output[0..8], &kernel_input_magic);
    std.mem.writeInt(
        u16,
        output[8..10],
        kernel_input_format_version,
        .little,
    );
    output[10] = instance_kind;
    output[11] = @intFromBool(effect_result != null);
    std.mem.writeInt(u32, output[12..16], image_length, .little);
    std.mem.writeInt(u32, output[16..20], instance_length, .little);
    std.mem.writeInt(u32, output[20..24], result_length, .little);
    @memset(output[24..28], 0);
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
    const primary_length = std.math.cast(u32, fields.primary.len) orelse
        return error.OutputCapacity;
    const secondary_length = std.math.cast(u32, fields.secondary.len) orelse
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

/// Physical arenas retained by one fixed Process-kernel invocation.
///
/// The kernel and native capacity witness both derive accounting from their
/// actual storage objects through this one formula. Output is excluded because
/// `encodeOutcomeForCapacity` substitutes the minimum required output size.
pub const KernelArenaLayout = struct {
    state_bytes: usize,
    candidate_state_bytes: usize,
    value_bytes: usize,
    request_bytes: usize,
    environment_bytes: usize,
    auxiliary_environment_bytes: usize,
    scratch_bytes: usize,
    error_bytes: usize,
    validation_workspace_bytes: usize,

    pub fn baseMemoryWithoutOutput(
        self: @This(),
        input_bytes: usize,
    ) usize {
        var total = input_bytes;
        inline for (.{
            self.state_bytes,
            self.candidate_state_bytes,
            self.value_bytes,
            self.request_bytes,
            self.environment_bytes,
            self.auxiliary_environment_bytes,
            self.scratch_bytes,
            self.error_bytes,
            self.validation_workspace_bytes,
        }) |bytes| total = saturatingAdd(total, bytes);
        return total;
    }
};

pub fn encodeOutcomeForCapacity(
    outcome: Outcome,
    input_length: usize,
    minimum_scratch_bytes: usize,
    base_memory_without_output: usize,
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
                capacityPages(
                    base_memory_without_output,
                    output.len,
                    requirement.minimum_output_bytes,
                    minimum_memory_pages_floor,
                ),
            ),
        } },
        else => outcome,
    };
    return encodeOutcome(admitted_outcome, output) catch |err| switch (err) {
        error.OutputCapacity => encodeOutcome(
            .{ .needs_capacity = .{
                .minimum_input_bytes = @intCast(input_length),
                .minimum_output_bytes = @intCast(required_output),
                .minimum_scratch_bytes = @intCast(minimum_scratch_bytes),
                .minimum_memory_pages = capacityPages(
                    base_memory_without_output,
                    output.len,
                    @intCast(required_output),
                    minimum_memory_pages_floor,
                ),
            } },
            output,
        ),
        else => err,
    };
}

fn capacityPages(
    base_memory_without_output: usize,
    current_output_bytes: usize,
    required_output_bytes: u64,
    live_memory_pages: u64,
) u64 {
    const declared_total = saturatingAddU64(
        @intCast(base_memory_without_output),
        required_output_bytes,
    );
    const live_bytes = std.math.mul(
        u64,
        live_memory_pages,
        65536,
    ) catch std.math.maxInt(u64);
    const growth = required_output_bytes -|
        @as(u64, @intCast(current_output_bytes));
    const live_grown = saturatingAddU64(live_bytes, growth);
    return @max(bytesToPages(declared_total), bytesToPages(live_grown));
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
    primary_length: u32,
    secondary_length: u32,
) void {
    @memcpy(output[0..outcome_magic.len], &outcome_magic);
    std.mem.writeInt(u16, output[8..10], outcome_format_version, .little);
    output[10] = kind;
    output[11] = 0;
    std.mem.writeInt(u32, output[12..16], primary_length, .little);
    std.mem.writeInt(u32, output[16..20], secondary_length, .little);
    @memset(output[20..24], 0);
}

const Slot = reducer_clause_v1.Slot;
const slicesOverlap = process_state_v1.slicesOverlap;

const LoadedEnvironment = reducer_clause_v1.LoadedEnvironment;

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
    return advanceFinite(
        image_bytes,
        instance,
        effect_result,
        buffers,
        workspace,
    ) catch |err| switch (err) {
        error.OutputCapacity,
        error.ScratchCapacity,
        error.CapacityExceeded,
        => .{ .needs_capacity = capacityRequirement(
            image_bytes,
            instance,
            effect_result,
            buffers,
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
    try validateFrames(image, state, workspace);
    return state;
}

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
    const encoded = try process_state_v1.encode(
        image.catalogs.envelope.header.program_transition_digest,
        frames,
        output_state,
    );
    const state = process_state_v1.validate(
        encoded,
        image.catalogs.envelope.header.program_transition_digest,
    ) catch return error.InvalidProcessState;
    try validateFrames(image, state, workspace);
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
    const encoded = try initialState(
        image,
        initial_args,
        output_state,
        invariant_scratch,
        workspace,
    );
    const state = try process_state_v1.validate(
        encoded,
        image.catalogs.envelope.header.program_transition_digest,
    );
    try validateFrames(image, state, workspace);
}

fn advanceFinite(
    image_bytes: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
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
            );
            break :blk try advanceState(
                image,
                initial,
                null,
                buffers,
                workspace,
            );
        },
        .process_state => |state_bytes| try advanceState(
            image,
            state_bytes,
            effect_result,
            buffers,
            workspace,
        ),
    };
}

fn capacityRequirement(
    image_bytes: []const u8,
    instance: Instance,
    effect_result: ?[]const u8,
    buffers: Buffers,
    err: anyerror,
) CapacityRequirement {
    const instance_length = switch (instance) {
        .initial_args => |bytes| bytes.len,
        .process_state => |bytes| bytes.len,
    };
    const result_length = if (effect_result) |bytes| bytes.len else 0;
    const input = saturatingAdd(
        kernel_input_header_length,
        saturatingAdd(
            saturatingAdd(image_bytes.len, instance_length),
            result_length,
        ),
    );
    const envelope = image_v1.validateEnvelope(image_bytes) catch null;
    const maximum_value = if (envelope) |view|
        @as(usize, view.header.maximum_single_value_bytes)
    else
        saturatingAdd(buffers.output_value.len, 1);
    const maximum_environment = saturatingAdd(
        4,
        std.math.mul(usize, maximum_value, 2048) catch
            std.math.maxInt(usize),
    );
    const maximum_call_environments = std.math.mul(
        usize,
        maximum_environment,
        2,
    ) catch std.math.maxInt(usize);
    const maximum_state = saturatingAdd(
        saturatingAdd(instance_length, maximum_call_environments),
        256,
    );
    const maximum_request = saturatingAdd(
        saturatingAdd(image_bytes.len, maximum_value),
        512,
    );
    const required_output = saturatingAdd(
        saturatingAdd(maximum_state, maximum_request),
        outcome_header_length,
    );
    const current_output = @max(
        buffers.output_state.len,
        buffers.output_value.len,
        buffers.output_request.len,
        buffers.candidate_state.len,
        buffers.environment.len,
        buffers.auxiliary_environment.len,
    );
    const minimum_output = @max(
        required_output,
        if (err == error.OutputCapacity)
            saturatingAdd(current_output, 1)
        else
            current_output,
    );
    const current_scratch: u64 = @intCast(buffers.scratch.len);
    const required_scratch: u64 = if (envelope) |view|
        view.header.maximum_kernel_scratch_bytes
    else
        current_scratch +| 1;
    const minimum_scratch = @max(
        required_scratch,
        if (err == error.ScratchCapacity or err == error.CapacityExceeded)
            current_scratch +| 1
        else
            current_scratch,
    );
    const minimum_output_u64: u64 = @intCast(minimum_output);
    const all_output_arenas = std.math.mul(
        u64,
        minimum_output_u64,
        7,
    ) catch std.math.maxInt(u64);
    const total = saturatingAddU64(
        saturatingAddU64(@intCast(input), all_output_arenas),
        saturatingAddU64(
            minimum_scratch +| (4 << 10),
            @intCast(@sizeOf(image_v1.ValidationWorkspace)),
        ),
    );
    return .{
        .minimum_input_bytes = @intCast(input),
        .minimum_output_bytes = minimum_output_u64,
        .minimum_scratch_bytes = minimum_scratch,
        .minimum_memory_pages = bytesToPages(total),
    };
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
) Error![]const u8 {
    dynamic_value_v1.validateValue(
        image.catalogs.schemas,
        image.catalogs.initial_args_schema_id,
        initial_args,
        &workspace.value_tasks,
    ) catch return error.InvalidInitialArgs;
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        image.catalogs.initial_constructor_id,
    );
    const flags = readInt(u16, constructor, 10);
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    if (flags & 1 != 0 or activation_count != 0 or environment_count > 1) {
        return error.InvalidInitialArgs;
    }
    var slots = [_]Slot{.{}} ** 1024;
    var activation_slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    try reducer_clause_v1.initializeZeroWidthSlots(image, &activation_slots);
    if (environment_count == 1) {
        const value = readInt(u16, constructor, 24);
        const schema = readInt(u32, constructor, 28);
        if (image.catalogs.entry_parameter_count != 1 or
            value != image.catalogs.entry_parameter_value_id or
            schema != image.catalogs.initial_args_schema_id)
        {
            return error.InvalidInitialArgs;
        }
        slots[value] = .{ .bytes = initial_args, .initialized = true };
    }
    const environment = reducer_clause_v1.encodeEnvironmentSlots(
        constructor,
        null,
        &activation_slots,
        &slots,
        environment_output,
    ) catch |err| switch (err) {
        error.OutputCapacity => return error.OutputCapacity,
        else => return error.InvalidInitialArgs,
    };
    const frames = [_]process_state_v1.Frame{.{
        .constructor_id = image.catalogs.initial_constructor_id,
        .environment = environment,
    }};
    return process_state_v1.encode(
        image.catalogs.envelope.header.program_transition_digest,
        &frames,
        output,
    );
}

fn advanceState(
    image: image_v1.ValidatedImage,
    state_bytes: []const u8,
    effect_result: ?[]const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const state = process_state_v1.validate(
        state_bytes,
        image.catalogs.envelope.header.program_transition_digest,
    ) catch return error.InvalidProcessState;
    try validateFrames(image, state, workspace);
    const top = try process_state_v1.topFrame(state);
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        top.frame.constructor_id,
    );
    if (constructor[8] == 3) {
        if (effect_result) |result_bytes| {
            const successor = try resumePending(
                image,
                state,
                top,
                constructor,
                result_bytes,
                buffers,
                workspace,
            );
            return stepState(image, successor, buffers, workspace);
        }
        return currentRequest(
            image,
            state,
            top,
            constructor,
            buffers,
            workspace,
        );
    }
    if (effect_result != null) return error.UnexpectedEffectResult;
    return stepState(image, state, buffers, workspace);
}

fn stepState(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const top = try process_state_v1.topFrame(state);
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        top.frame.constructor_id,
    );
    var slots = [_]Slot{.{}} ** 1024;
    var activation_slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    const loaded = try loadEnvironment(
        image,
        constructor,
        top.frame.environment,
        &slots,
        &activation_slots,
        workspace,
    );
    const segment_id = readInt(u16, constructor, 12);
    const clause = try reducer_clause_v1.evaluateClause(
        image,
        segment_id,
        &slots,
        buffers.output_value,
        buffers.scratch,
        workspace,
    );
    const outcome: Outcome = switch (clause) {
        .progressed => |progressed| .{ .progressed = try transitionState(
            image,
            state,
            segment_id,
            progressed.edge_kind,
            progressed.edge,
            loaded.activation_entry,
            &activation_slots,
            &slots,
            buffers,
        ) },
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
            );
            const parked = try process_state_v1.replaceTop(
                state,
                .{
                    .constructor_id = await_constructor_id,
                    .environment = environment,
                },
                buffers.output_state,
            );
            break :blk try makeRequest(
                image,
                parked,
                request.site_ordinal,
                request.payload,
                buffers.output_request,
                workspace,
            );
        },
        .explicit_yield => |continuation| .{
            .explicitly_yielded = try transitionState(
                image,
                state,
                segment_id,
                4,
                continuation,
                loaded.activation_entry,
                &activation_slots,
                &slots,
                buffers,
            ),
        },
        .completed => |value| .{ .completed = value },
        .authored_failure => |failure| .{ .authored_failure = failure },
        .call => |callee| .{ .progressed = try callState(
            image,
            state,
            segment_id,
            callee,
            loaded.activation_entry,
            &activation_slots,
            &slots,
            buffers,
        ) },
        .return_to_caller => |return_value| blk: {
            const stable_return = try stabilizeValue(
                return_value,
                buffers.output_value,
            );
            break :blk .{ .progressed = try returnToCaller(
                image,
                state,
                stable_return,
                buffers,
                workspace,
            ) };
        },
    };
    try validateOutcomeStates(image, outcome, workspace);
    return outcome;
}

fn stabilizeValue(value: []const u8, output: []u8) Error![]const u8 {
    if (slicesOverlap(value, output)) return value;
    if (output.len < value.len) return error.OutputCapacity;
    @memcpy(output[0..value.len], value);
    return output[0..value.len];
}

fn validateOutcomeStates(
    image: image_v1.ValidatedImage,
    outcome: Outcome,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const state_bytes: ?[]const u8 = switch (outcome) {
        .progressed => |state| state,
        .requested => |requested| requested.state,
        .explicitly_yielded => |state| state,
        .completed, .authored_failure, .needs_capacity => null,
    };
    if (state_bytes) |bytes| {
        const state = process_state_v1.validate(
            bytes,
            image.catalogs.envelope.header.program_transition_digest,
        ) catch return error.InvalidProcessState;
        try validateFrames(image, state, workspace);
    }
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
) Error![]const u8 {
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
    );
    return process_state_v1.replaceTopAndAppend(
        state,
        parent_frame,
        .{
            .constructor_id = child_constructor_id,
            .environment = child_environment,
        },
        buffers.output_state,
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
) Error![]const u8 {
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
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    const loaded = try loadEnvironment(
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
    );
    return process_state_v1.replaceParentAndDropTop(
        state,
        .{
            .constructor_id = next_constructor_id,
            .environment = environment,
        },
        buffers.output_state,
    );
}

fn currentRequest(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    top: process_state_v1.FrameSpan,
    constructor: []const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    var slots = [_]Slot{.{}} ** 1024;
    var activation_slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    _ = try loadEnvironment(
        image,
        constructor,
        top.frame.environment,
        &slots,
        &activation_slots,
        workspace,
    );
    const parts = try pendingRequestParts(
        image,
        constructor,
        &slots,
    );
    return makeRequest(
        image,
        state.bytes,
        parts.site_ordinal,
        parts.payload,
        buffers.output_request,
        workspace,
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
    if (suspension.kind != 0 or suspension.request_values.len != 2) {
        return error.InvalidProcessState;
    }
    const request_value = readInt(u16, suspension.request_values, 0);
    if (!slots[request_value].initialized) return error.InvalidProcessState;
    return .{
        .site_ordinal = suspension.site_ordinal,
        .payload = slots[request_value].bytes,
    };
}

fn makeRequest(
    image: image_v1.ValidatedImage,
    parked_state: []const u8,
    site_ordinal: u32,
    payload: []const u8,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const request_input = try requestInput(
        image,
        parked_state,
        site_ordinal,
        payload,
        workspace,
    );
    const request = try process_effect_v1.encodeRequest(
        request_input,
        output,
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
    state: process_state_v1.StateView,
    top: process_state_v1.FrameSpan,
    constructor: []const u8,
    result_bytes: []const u8,
    buffers: Buffers,
    workspace: *image_v1.ValidationWorkspace,
) Error!process_state_v1.StateView {
    var slots = [_]Slot{.{}} ** 1024;
    var activation_slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    const loaded = try loadEnvironment(
        image,
        constructor,
        top.frame.environment,
        &slots,
        &activation_slots,
        workspace,
    );
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
        readInt(u32, segment, terminator + 12),
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
        loaded.activation_entry,
        &activation_slots,
        &slots,
        buffers.environment,
    );
    const successor = try process_state_v1.replaceTop(
        state,
        .{
            .constructor_id = target_constructor_id,
            .environment = environment,
        },
        buffers.candidate_state,
    );
    const successor_state = try process_state_v1.validate(
        successor,
        image.catalogs.envelope.header.program_transition_digest,
    );
    try validateFrames(image, successor_state, workspace);
    return successor_state;
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
) Error![]const u8 {
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
    );
    return process_state_v1.replaceTop(
        state,
        .{ .constructor_id = constructor_id, .environment = environment },
        buffers.output_state,
    );
}

fn validateFrames(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    var iterator = state.iterator();
    var index: u64 = 0;
    var previous_constructor: []const u8 = &.{};
    var previous_slots = [_]Slot{.{}} ** 1024;
    while (try iterator.next()) |frame| : (index += 1) {
        if (frame.constructor_id >= image.constructor_count) {
            return error.InvalidProcessState;
        }
        const constructor = try image_v1.evaluatorConstructorRecord(
            image,
            frame.constructor_id,
        );
        var slots = [_]Slot{.{}} ** 1024;
        var activation_slots = [_]Slot{.{}} ** 1024;
        try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
        const loaded = try loadEnvironment(
            image,
            constructor,
            frame.environment,
            &slots,
            &activation_slots,
            workspace,
        );
        if (index == 0) {
            const segment = try image_v1.evaluatorSegmentRecord(
                image,
                readInt(u16, constructor, 12),
            );
            if (readInt(u16, segment, 6) != 0) {
                return error.InvalidProcessState;
            }
        } else {
            try validateStackPair(
                image,
                previous_constructor,
                &previous_slots,
                constructor,
                loaded.activation_entry,
                &activation_slots,
            );
        }
        previous_constructor = constructor;
        previous_slots = slots;
    }
    if (isAwaitCallConstructor(image, previous_constructor)) {
        return error.InvalidProcessState;
    }
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

fn isAwaitCallConstructor(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
) bool {
    if (constructor.len < 24 or constructor[8] != 4 or constructor[9] != 2) {
        return false;
    }
    const segment = image_v1.evaluatorSegmentRecord(
        image,
        readInt(u16, constructor, 12),
    ) catch return false;
    const terminator = image_v1.evaluatorSegmentTerminator(segment);
    const suspension = reducer_clause_v1.suspensionView(
        segment,
        terminator,
    ) catch return false;
    return suspension.kind == 1;
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

fn encodeEnvironment(
    constructor: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *const [1024]Slot,
    output: []u8,
) Error![]const u8 {
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

fn constructorRetainsValue(constructor: []const u8, value: u16) bool {
    const field_count = @as(u32, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    var cursor: usize = 24;
    for (0..field_count) |_| {
        if (readInt(u16, constructor, cursor) == value) return true;
        cursor += 8;
    }
    return false;
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
