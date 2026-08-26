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

pub fn encodeOutcomeForCapacity(
    outcome: Outcome,
    input_length: usize,
    minimum_scratch_bytes: usize,
    base_memory_without_output: usize,
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
                @as(u64, @intCast(
                    (saturatingAdd(
                        base_memory_without_output,
                        @intCast(requirement.minimum_output_bytes),
                    ) +| 65535) / 65536,
                )),
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
                .minimum_memory_pages = @intCast(
                    (saturatingAdd(
                        base_memory_without_output,
                        required_output,
                    ) +| 65535) / 65536,
                ),
            } },
            output,
        ),
        else => err,
    };
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

const LoadedEnvironment = struct {
    activation_entry: ?u32,
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
    const required_scratch = if (envelope) |view|
        std.math.cast(usize, view.header.maximum_kernel_scratch_bytes) orelse
            std.math.maxInt(usize)
    else
        saturatingAdd(buffers.scratch.len, 1);
    const minimum_scratch = @max(
        required_scratch,
        if (err == error.ScratchCapacity or err == error.CapacityExceeded)
            saturatingAdd(buffers.scratch.len, 1)
        else
            buffers.scratch.len,
    );
    const all_output_arenas = std.math.mul(
        usize,
        minimum_output,
        7,
    ) catch std.math.maxInt(usize);
    const total = saturatingAdd(
        saturatingAdd(input, all_output_arenas),
        saturatingAdd(
            saturatingAdd(minimum_scratch, 4 << 10),
            @sizeOf(image_v1.ValidationWorkspace),
        ),
    );
    return .{
        .minimum_input_bytes = @intCast(input),
        .minimum_output_bytes = @intCast(minimum_output),
        .minimum_scratch_bytes = @intCast(minimum_scratch),
        .minimum_memory_pages = @intCast((total +| 65535) / 65536),
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

fn initialState(
    image: image_v1.ValidatedImage,
    initial_args: []const u8,
    output: []u8,
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
    const environment = if (environment_count == 0) &.{} else blk: {
        const value = readInt(u16, constructor, 24);
        const schema = readInt(u32, constructor, 28);
        if (image.catalogs.entry_parameter_count != 1 or
            value != image.catalogs.entry_parameter_value_id or
            schema != image.catalogs.initial_args_schema_id)
        {
            return error.InvalidInitialArgs;
        }
        break :blk initial_args;
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
    try validateFrames(image, state, workspace);
    const top = try process_state_v1.topFrame(state);
    const constructor = try image_v1.evaluatorConstructorRecord(
        image,
        top.frame.constructor_id,
    );
    var slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    const loaded = try loadEnvironment(
        image,
        constructor,
        top.frame.environment,
        &slots,
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
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    const loaded = try loadEnvironment(
        image,
        parent_constructor,
        parent.frame.environment,
        &slots,
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
    const segment_id = readInt(u16, constructor, 12);
    const segment = try image_v1.evaluatorSegmentRecord(image, segment_id);
    const terminator = image_v1.evaluatorSegmentTerminator(segment);
    if (segment[terminator + 4] != 2 or segment[terminator + 8] != 0) {
        return error.InvalidProcessState;
    }
    const payload = terminator + 8;
    const site_ordinal = readInt(u32, segment, payload + 4);
    if (readInt(u16, segment, payload + 10) != 1) {
        return error.InvalidProcessState;
    }
    const request_value = readInt(u16, segment, payload + 12);
    var slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    _ = try loadEnvironment(
        image,
        constructor,
        top.frame.environment,
        &slots,
        workspace,
    );
    if (!slots[request_value].initialized) return error.InvalidProcessState;
    return makeRequest(
        image,
        state.bytes,
        site_ordinal,
        slots[request_value].bytes,
        buffers.output_request,
        workspace,
    );
}

fn makeRequest(
    image: image_v1.ValidatedImage,
    parked_state: []const u8,
    site_ordinal: u32,
    payload: []const u8,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
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
    const request = try process_effect_v1.encodeRequest(.{
        .program_transition_digest = image.catalogs.envelope.header.program_transition_digest,
        .pre_request_state_digest = state_digest,
        .effect_site_semantic_digest = effect.semantic_digest,
        .payload_schema_digest = payload_schema_digest,
        .resume_schema_digest = resume_schema_digest,
        .continuation_digest = continuation_digest,
        .effect_semantic_identity = effect.semantic_identity,
        .payload = payload,
    }, output);
    return .{ .requested = .{ .state = parked_state, .request = request } };
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
    const request_outcome = try currentRequest(
        image,
        state,
        top,
        constructor,
        buffers,
        workspace,
    );
    const request = try process_effect_v1.validateRequest(
        request_outcome.requested.request,
        image.catalogs.envelope.header.program_transition_digest,
    );
    const result = try process_effect_v1.validateResult(result_bytes);
    if (!std.mem.eql(
        u8,
        &request.request_identity_digest,
        &result.request_identity_digest,
    )) return error.ResultRequestMismatch;
    if (!std.mem.eql(
        u8,
        &request.resume_schema_digest,
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
    var slots = [_]Slot{.{}} ** 1024;
    try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
    const loaded = try loadEnvironment(
        image,
        constructor,
        top.frame.environment,
        &slots,
        workspace,
    );
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
    return process_state_v1.validate(
        successor,
        image.catalogs.envelope.header.program_transition_digest,
    );
}

fn transitionState(
    image: image_v1.ValidatedImage,
    state: process_state_v1.StateView,
    source_segment_id: u16,
    edge_kind: u8,
    edge: []const u8,
    activation_entry: ?u32,
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
    var previous: ?process_state_v1.Frame = null;
    var previous_constructor: []const u8 = &.{};
    while (try iterator.next()) |frame| : (index += 1) {
        if (frame.constructor_id >= image.constructor_count) {
            return error.InvalidProcessState;
        }
        const constructor = try image_v1.evaluatorConstructorRecord(
            image,
            frame.constructor_id,
        );
        var slots = [_]Slot{.{}} ** 1024;
        try reducer_clause_v1.initializeZeroWidthSlots(image, &slots);
        _ = try loadEnvironment(
            image,
            constructor,
            frame.environment,
            &slots,
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
                previous.?,
                previous_constructor,
                frame,
                constructor,
                workspace,
            );
        }
        previous = frame;
        previous_constructor = constructor;
    }
    if (isAwaitCallConstructor(image, previous_constructor)) {
        return error.InvalidProcessState;
    }
}

fn validateStackPair(
    image: image_v1.ValidatedImage,
    parent: process_state_v1.Frame,
    parent_constructor: []const u8,
    child: process_state_v1.Frame,
    child_constructor: []const u8,
    workspace: *image_v1.ValidationWorkspace,
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
        parent.environment,
        child_constructor,
        child.environment,
        expected_call_entry,
        workspace,
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
    return segment[terminator + 4] == 2 and segment[terminator + 8] == 1;
}

fn loadEnvironment(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!LoadedEnvironment {
    const flags = readInt(u16, constructor, 10);
    var cursor: usize = 0;
    const activation_entry: ?u32 = if (flags & 1 != 0) blk: {
        if (environment.len < 4) return error.InvalidProcessState;
        const entry = readInt(u32, environment, 0);
        _ = try image_v1.evaluatorConstructorRecord(image, entry);
        cursor = 4;
        break :blk entry;
    } else null;
    const field_count = @as(u32, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..field_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        const schema = readInt(u32, constructor, field_cursor + 4);
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema,
            environment[cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidProcessState;
        slots[value] = .{
            .bytes = environment[cursor .. cursor + consumed],
            .initialized = true,
        };
        cursor += consumed;
        field_cursor += 8;
    }
    if (cursor != environment.len) return error.InvalidProcessState;
    reducer_clause_v1.validatePathInvariants(
        image,
        constructor,
        slots,
        workspace,
    ) catch |err| switch (err) {
        error.ScratchCapacity => return error.ScratchCapacity,
        else => return error.InvalidProcessState,
    };
    return .{ .activation_entry = activation_entry };
}

fn encodeEnvironment(
    constructor: []const u8,
    activation_entry: ?u32,
    slots: *const [1024]Slot,
    output: []u8,
) Error![]const u8 {
    const flags = readInt(u16, constructor, 10);
    var cursor: usize = 0;
    if (flags & 1 != 0) {
        const entry = activation_entry orelse return error.InvalidProcessState;
        if (output.len < 4) return error.OutputCapacity;
        appendInt(u32, output, &cursor, entry);
    }
    const field_count = @as(u32, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..field_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        if (!slots[value].initialized) return error.InvalidProcessState;
        const bytes = slots[value].bytes;
        if (output.len - cursor < bytes.len) return error.OutputCapacity;
        @memcpy(output[cursor..][0..bytes.len], bytes);
        cursor += bytes.len;
        field_cursor += 8;
    }
    return output[0..cursor];
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

fn suspensionContinuation(segment: []const u8, terminator: usize) []const u8 {
    const payload = terminator + 8;
    const request_count = readInt(u16, segment, payload + 10);
    var cursor = payload + 12 + @as(usize, request_count) * 2;
    const callee_present = segment[cursor] == 1;
    cursor += 4;
    if (callee_present) cursor += edgeLength(segment[cursor..]);
    return segment[cursor..];
}

fn suspensionCallee(segment: []const u8, terminator: usize) []const u8 {
    const payload = terminator + 8;
    const request_count = readInt(u16, segment, payload + 10);
    const cursor = payload + 12 + @as(usize, request_count) * 2;
    if (segment[cursor] != 1) return &.{};
    return segment[cursor + 4 ..];
}

fn edgeLength(edge: []const u8) usize {
    return 4 + @as(usize, readInt(u16, edge, 2)) * 4;
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
