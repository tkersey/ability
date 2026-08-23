const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const machine_v2_metering_v1 = @import("machine_v2_metering_v1");
const machine_v2_profile_v1 = @import("machine_v2_profile_v1");
const reducer_clause_v1 = @import("reducer_clause_v1");
const std = @import("std");

pub const Error = error{
    InvalidImage,
    InvalidBindings,
    InvalidProfile,
    InvalidState,
    InvalidInitialArgs,
    OutputCapacity,
    ExecutionBudgetExceeded,
    UnsupportedOperation,
    ScratchCapacity,
    CapacityExceeded,
    FrameDepthExceeded,
};

pub const MachineFailure = enum {
    execution_budget_exceeded,
    frame_depth_exceeded,
};

pub const state_magic = "ABL_RNF2".*;
pub const state_header_length: usize = 68;
pub const frame_header_length: usize = 8;

pub const Outcome = union(enum) {
    requested: RequestView,
    yielded: []const u8,
    done: []const u8,
    failed: []const u8,
    machine_failed: struct {
        state: []const u8,
        failure: MachineFailure,
    },
};

const SegmentOutcome = union(enum) {
    requested: RequestView,
    next: []const u8,
    yielded: []const u8,
    done: []const u8,
    failed: []const u8,
};

pub const RequestIdentity = struct {
    machine_contract_digest: [32]u8,
    sequence: u64,
    constructor_id: u32,
    site_ordinal: u32,
    effect_site_digest: [32]u8,
    payload_digest: [32]u8,
    continuation_digest: [32]u8,
    digest: [32]u8,
};

pub const RequestView = struct {
    state: []const u8,
    payload: []const u8,
    identity: RequestIdentity,
};

const Slot = reducer_clause_v1.Slot;

/// Immutable binding certificate for one exact BPI1/profile byte pair.
/// Execution reacquires a validated view in caller workspace on every command.
pub const BoundProgram = struct {
    image_bytes: []const u8,
    profile_bytes: []const u8,
    image_sha256: [32]u8,
    profile_sha256: [32]u8,
};

const ValidatedProgram = struct {
    catalogs: image_v1.Catalogs,
    segment_count: u32,
    constructor_count: u32,
    profile: machine_v2_profile_v1.Validated,
};

fn bindValidatedMachineV2(
    image: image_v1.ValidatedImage,
    profile_bytes: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!ValidatedProgram {
    const profile = machine_v2_profile_v1.validate(
        profile_bytes,
        image.catalogs.envelope.header.program_transition_digest,
    ) catch return error.InvalidProfile;
    if (profile.segment_count != image.segment_count) return error.InvalidProfile;
    const semantic_digest = machine_v2_profile_v1.semanticDigestForImage(
        image,
        profile,
        &workspace.schema_hash_tasks,
    ) catch return error.InvalidProfile;
    if (!std.mem.eql(
        u8,
        &semantic_digest,
        &profile.machine_v2_semantic_digest,
    )) return error.InvalidProfile;
    if (profile.bpi_constructor_count != image.constructor_count or
        profile.maximum_state_bytes < try minimumInitialStateBytes(image, profile))
    {
        return error.InvalidProfile;
    }
    return .{
        .catalogs = image.catalogs,
        .segment_count = image.segment_count,
        .constructor_count = profile.constructor_count,
        .profile = profile,
    };
}

pub fn bindMachineV2(
    image: image_v1.ValidatedImage,
    profile_bytes: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!BoundProgram {
    const image_bytes = image.catalogs.envelope.image;
    try requireWorkspaceDisjoint(image_bytes, workspace);
    try requireWorkspaceDisjoint(profile_bytes, workspace);
    const refreshed_image = image_v1.validateImage(
        image_bytes,
        workspace,
    ) catch return error.InvalidImage;
    _ = try bindValidatedMachineV2(
        refreshed_image,
        profile_bytes,
        workspace,
    );
    return .{
        .image_bytes = image_bytes,
        .profile_bytes = profile_bytes,
        .image_sha256 = sha256(image_bytes),
        .profile_sha256 = sha256(profile_bytes),
    };
}

fn acquire(
    binding: BoundProgram,
    workspace: *image_v1.ValidationWorkspace,
) Error!ValidatedProgram {
    try requireWorkspaceDisjoint(binding.image_bytes, workspace);
    try requireWorkspaceDisjoint(binding.profile_bytes, workspace);
    const image_sha256 = sha256(binding.image_bytes);
    if (!std.mem.eql(u8, &image_sha256, &binding.image_sha256)) {
        return error.InvalidImage;
    }
    const profile_sha256 = sha256(binding.profile_bytes);
    if (!std.mem.eql(u8, &profile_sha256, &binding.profile_sha256)) {
        return error.InvalidProfile;
    }
    const image = image_v1.validateImage(
        binding.image_bytes,
        workspace,
    ) catch return error.InvalidImage;
    return bindValidatedMachineV2(image, binding.profile_bytes, workspace);
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn requireWorkspaceDisjoint(
    bytes: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    if (rangesOverlap(bytes, std.mem.asBytes(workspace))) {
        return error.InvalidBindings;
    }
}

fn requireBindingDisjoint(
    binding: BoundProgram,
    bytes: []const u8,
) Error!void {
    if (rangesOverlap(binding.image_bytes, bytes) or
        rangesOverlap(binding.profile_bytes, bytes))
    {
        return error.InvalidBindings;
    }
}

fn requireDisjoint(left: []const u8, right: []const u8) Error!void {
    if (rangesOverlap(left, right)) return error.InvalidBindings;
}

fn rangesOverlap(left: []const u8, right: []const u8) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_end = std.math.add(usize, left_start, left.len) catch return true;
    const right_end = std.math.add(usize, right_start, right.len) catch return true;
    return left_start < right_end and right_start < left_end;
}

fn minimumInitialStateBytes(
    image: image_v1.ValidatedImage,
    profile: machine_v2_profile_v1.Validated,
) Error!u64 {
    const constructors = image.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    var constructor: []const u8 = &.{};
    const mapped_initial = profile.mappedConstructor(
        profile.initial_constructor_id,
    ) catch return error.InvalidProfile;
    for (0..image.constructor_count) |id| {
        const length = readInt(u32, constructors, cursor);
        if (id == mapped_initial) {
            constructor = constructors[cursor .. cursor + length];
            break;
        }
        cursor += length;
    }
    if (constructor.len < 24) return error.InvalidImage;
    var total: u64 = state_header_length + frame_header_length;
    if (readInt(u16, constructor, 10) & 1 != 0) total += 4;
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    cursor = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const schema = image.catalogs.schemas.node(
            readInt(u32, constructor, cursor + 4),
        ) catch return error.InvalidImage;
        total = std.math.add(
            u64,
            total,
            schema.minimum_encoded_size,
        ) catch return error.InvalidImage;
        cursor += 8;
    }
    return total;
}

fn programView(image: ValidatedProgram) image_v1.ValidatedImage {
    return .{
        .catalogs = image.catalogs,
        .segment_count = image.segment_count,
        .constructor_count = image.constructor_count,
    };
}

pub fn initial(
    binding: BoundProgram,
    initial_args: []const u8,
    output_state: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    try requireWorkspaceDisjoint(initial_args, workspace);
    try requireWorkspaceDisjoint(output_state, workspace);
    try requireBindingDisjoint(binding, output_state);
    try requireDisjoint(initial_args, output_state);
    const image = try acquire(binding, workspace);
    return initialValidated(
        image,
        initial_args,
        output_state,
        workspace,
    );
}

pub fn validateState(
    binding: BoundProgram,
    state: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    try requireWorkspaceDisjoint(state, workspace);
    const image = try acquire(binding, workspace);
    return validateStateValidated(image, state, workspace);
}

pub fn current(
    binding: BoundProgram,
    state: []const u8,
    output_payload: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!?RequestView {
    try requireWorkspaceDisjoint(state, workspace);
    try requireWorkspaceDisjoint(output_payload, workspace);
    try requireBindingDisjoint(binding, output_payload);
    try requireDisjoint(state, output_payload);
    const image = try acquire(binding, workspace);
    return currentValidated(
        image,
        state,
        output_payload,
        workspace,
    );
}

pub fn @"resume"(
    binding: BoundProgram,
    state: []const u8,
    identity: RequestIdentity,
    response: []const u8,
    output_state: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    try requireWorkspaceDisjoint(state, workspace);
    try requireWorkspaceDisjoint(response, workspace);
    try requireWorkspaceDisjoint(output_state, workspace);
    try requireBindingDisjoint(binding, output_state);
    try requireDisjoint(state, output_state);
    try requireDisjoint(response, output_state);
    const image = try acquire(binding, workspace);
    return resumeValidated(
        image,
        state,
        identity,
        response,
        output_state,
        workspace,
    );
}

pub fn step(
    binding: BoundProgram,
    state: []const u8,
    caller_fuel: *u64,
    output_state: []u8,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const fuel_bytes = std.mem.asBytes(caller_fuel);
    try requireWorkspaceDisjoint(state, workspace);
    try requireWorkspaceDisjoint(fuel_bytes, workspace);
    try requireWorkspaceDisjoint(output_state, workspace);
    try requireWorkspaceDisjoint(output_value, workspace);
    try requireWorkspaceDisjoint(scratch, workspace);
    try requireBindingDisjoint(binding, output_state);
    try requireBindingDisjoint(binding, output_value);
    try requireBindingDisjoint(binding, scratch);
    try requireBindingDisjoint(binding, fuel_bytes);
    try requireDisjoint(state, fuel_bytes);
    try requireDisjoint(fuel_bytes, output_state);
    try requireDisjoint(fuel_bytes, output_value);
    try requireDisjoint(fuel_bytes, scratch);
    try requireDisjoint(state, output_state);
    try requireDisjoint(state, output_value);
    try requireDisjoint(state, scratch);
    try requireDisjoint(output_state, output_value);
    try requireDisjoint(output_state, scratch);
    try requireDisjoint(output_value, scratch);
    const image = try acquire(binding, workspace);
    return stepValidated(
        image,
        state,
        caller_fuel,
        output_state,
        output_value,
        scratch,
        workspace,
    );
}

pub fn maximumResumeStateSize(
    binding: BoundProgram,
    state: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    try requireWorkspaceDisjoint(state, workspace);
    const image = try acquire(binding, workspace);
    return maximumResumeStateSizeValidated(image, state);
}

/// Construct the exact initial ABL_RNF2 State from canonical InitialArgs.
fn initialValidated(
    image: ValidatedProgram,
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
        image.profile.initial_constructor_id,
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
    if (required > image.profile.maximum_state_bytes) {
        return error.InvalidImage;
    }
    if (output_state.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    appendBytes(output_state, &cursor, &state_magic);
    appendInt(
        u16,
        output_state,
        &cursor,
        machine_v2_profile_v1.state_format_version,
    );
    appendInt(
        u16,
        output_state,
        &cursor,
        machine_v2_profile_v1.machine_abi_version,
    );
    appendBytes(
        output_state,
        &cursor,
        &image.profile.machine_v2_contract_digest,
    );
    appendInt(u64, output_state, &cursor, 0);
    appendInt(u64, output_state, &cursor, 0);
    appendInt(u32, output_state, &cursor, 1);
    appendInt(u32, output_state, &cursor, 0);
    appendInt(
        u32,
        output_state,
        &cursor,
        image.profile.initial_constructor_id,
    );
    appendInt(u32, output_state, &cursor, environment_length);
    if (environment_length != 0) {
        appendBytes(output_state, &cursor, initial_args);
    }
    if (cursor != required) return error.InvalidImage;
    try validateStateValidated(image, output_state[0..required], workspace);
    return required;
}

/// Validate canonical State framing and every constructor environment value.
fn validateStateValidated(
    image: ValidatedProgram,
    state: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    try validateStateEnvelope(image, state);
    const sequence = readInt(u64, state, 44);
    const frame_count = readInt(u32, state, 60);
    var cursor: usize = state_header_length;
    var top_kind: u8 = 0;
    var previous_offset: ?usize = null;
    var previous_constructor: []const u8 = &.{};
    for (0..frame_count) |frame_index| {
        const frame_offset = cursor;
        const constructor_id = readInt(u32, state, cursor);
        const environment_length = readInt(u32, state, cursor + 4);
        cursor += frame_header_length;
        const environment_end = cursor + environment_length;
        const constructor = try constructorRecord(image, constructor_id);
        top_kind = constructor[8];
        validateEnvironment(
            image,
            constructor,
            state[cursor..environment_end],
            workspace,
        ) catch return error.InvalidState;
        if (frame_index == 0) {
            const segment = try segmentRecord(
                image,
                readInt(u16, constructor, 12),
            );
            if (readInt(u16, segment, 6) != 0) return error.InvalidState;
        } else {
            try validateStackPair(
                image,
                state,
                previous_offset.?,
                previous_constructor,
                frame_offset,
                constructor,
                workspace,
            );
        }
        previous_offset = frame_offset;
        previous_constructor = constructor;
        cursor = environment_end;
    }
    if ((top_kind == 3 and sequence == 0) or
        isAwaitCallConstructor(image, previous_constructor))
    {
        return error.InvalidState;
    }
}

fn validateStateEnvelope(
    image: ValidatedProgram,
    state: []const u8,
) Error!void {
    if (state.len < state_header_length + frame_header_length or
        state.len > image.profile.maximum_state_bytes or
        !std.mem.eql(u8, state[0..8], &state_magic) or
        readInt(u16, state, 8) != machine_v2_profile_v1.state_format_version or
        readInt(u16, state, 10) != machine_v2_profile_v1.machine_abi_version or
        !std.mem.eql(
            u8,
            state[12..44],
            &image.profile.machine_v2_contract_digest,
        ))
    {
        return error.InvalidState;
    }
    const sequence = readInt(u64, state, 44);
    const cumulative_fuel = readInt(u64, state, 52);
    const frame_count = readInt(u32, state, 60);
    if (readInt(u32, state, 64) != 0 or frame_count == 0 or
        frame_count > image.profile.maximum_frames or
        cumulative_fuel > image.profile.maximum_machine_fuel or
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
        cursor = environment_end;
    }
    if (cursor != state.len or (top_kind == 3 and sequence == 0)) {
        return error.InvalidState;
    }
}

fn isAwaitCallConstructor(
    image: ValidatedProgram,
    constructor: []const u8,
) bool {
    if (constructor.len < 24 or constructor[8] != 4 or constructor[9] != 2) {
        return false;
    }
    const segment = segmentRecord(
        image,
        readInt(u16, constructor, 12),
    ) catch return false;
    const terminator = segmentTerminatorOffset(segment);
    return segment[terminator + 4] == 2 and segment[terminator + 8] == 1;
}

fn validateStackPair(
    image: ValidatedProgram,
    state: []const u8,
    parent_offset: usize,
    parent_constructor: []const u8,
    child_offset: usize,
    child_constructor: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    if (!isAwaitCallConstructor(image, parent_constructor)) {
        return error.InvalidState;
    }
    const parent_segment_id = readInt(u16, parent_constructor, 12);
    const parent_segment = try segmentRecord(image, parent_segment_id);
    const terminator = segmentTerminatorOffset(parent_segment);
    const payload = terminator + 8;
    const callee_function = readInt(u16, parent_segment, payload + 8);
    const callee = suspensionCallee(parent_segment, terminator);
    if (callee.len < 4) return error.InvalidState;
    const target_segment_id = readInt(u16, callee, 0);
    const child_segment = try segmentRecord(
        image,
        readInt(u16, child_constructor, 12),
    );
    if (readInt(u16, child_segment, 6) != callee_function or
        readInt(u16, child_constructor, 10) & 1 == 0)
    {
        return error.InvalidState;
    }
    const child_environment_length = readInt(u32, state, child_offset + 4);
    const child_environment = state[child_offset + 8 ..][0..child_environment_length];
    if (child_environment.len < 4) return error.InvalidState;
    const call_entry_constructor = try transitionConstructor(
        image,
        parent_segment_id,
        3,
        target_segment_id,
    );
    if (readInt(u32, child_environment, 0) != call_entry_constructor) {
        return error.InvalidState;
    }

    var parent_slots = [_]Slot{.{}} ** 1024;
    var child_slots = [_]Slot{.{}} ** 1024;
    try initializeZeroWidthSlots(image, &parent_slots);
    try initializeZeroWidthSlots(image, &child_slots);
    try loadFrameEnvironment(
        image,
        state,
        parent_offset,
        parent_constructor,
        &parent_slots,
        workspace,
    );
    try loadFrameEnvironment(
        image,
        state,
        child_offset,
        child_constructor,
        &child_slots,
        workspace,
    );
    const target_segment = try segmentRecord(image, target_segment_id);
    const count = readInt(u16, callee, 2);
    if (count != readInt(u16, target_segment, 10)) return error.InvalidState;
    for (0..count) |index| {
        const argument = 4 + index * 4;
        if (callee[argument] != 0) return error.InvalidState;
        const source_value = readInt(u16, callee, argument + 2);
        const target_value = readInt(u16, target_segment, image_v1.segment_prefix_length + index * 2);
        if (!constructorRetainsActivationValue(
            child_constructor,
            target_value,
        )) continue;
        if (!parent_slots[source_value].initialized or
            !child_slots[target_value].initialized or
            !std.mem.eql(
                u8,
                parent_slots[source_value].bytes,
                child_slots[target_value].bytes,
            ))
        {
            return error.InvalidState;
        }
    }
}

fn constructorRetainsActivationValue(
    constructor: []const u8,
    value: u16,
) bool {
    const activation_count = readInt(u16, constructor, 16);
    var cursor: usize = 24;
    for (0..activation_count) |_| {
        if (readInt(u16, constructor, cursor) == value) return true;
        cursor += 8;
    }
    return false;
}

fn currentValidated(
    image: ValidatedProgram,
    state: []const u8,
    output_payload: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!?RequestView {
    workspace.invariant_result = output_payload;
    try validateStateValidated(image, state, workspace);
    const constructor_id = try topConstructorId(state);
    const constructor = try constructorRecord(image, constructor_id);
    if (constructor[8] != 3) return null;
    const segment_id = readInt(u16, constructor, 12);
    const segment = try segmentRecord(image, segment_id);
    const terminator = segmentTerminatorOffset(segment);
    if (segment[terminator + 4] != 2 or segment[terminator + 8] != 0) {
        return error.InvalidState;
    }
    const payload = terminator + 8;
    const site_ordinal = readInt(u32, segment, payload + 4);
    const request_count = readInt(u16, segment, payload + 10);
    if (request_count != 1) return error.InvalidImage;
    const request_value = readInt(u16, segment, payload + 12);
    var slots = [_]Slot{.{}} ** 1024;
    try initializeZeroWidthSlots(image, &slots);
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    if (!slots[request_value].initialized) return error.InvalidState;
    if (output_payload.len < slots[request_value].bytes.len) {
        return error.OutputCapacity;
    }
    @memcpy(
        output_payload[0..slots[request_value].bytes.len],
        slots[request_value].bytes,
    );
    const canonical_payload = output_payload[0..slots[request_value].bytes.len];
    const sequence = readInt(u64, state, 44);
    return .{
        .state = state,
        .payload = canonical_payload,
        .identity = try requestIdentity(
            image,
            state,
            constructor_id,
            site_ordinal,
            canonical_payload,
            sequence,
        ),
    };
}

fn resumeValidated(
    image: ValidatedProgram,
    state: []const u8,
    identity: RequestIdentity,
    response: []const u8,
    output_state: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    try validateStateValidated(image, state, workspace);
    const constructor_id = try topConstructorId(state);
    const constructor = try constructorRecord(image, constructor_id);
    if (constructor[8] != 3) return error.InvalidState;
    const segment_id = readInt(u16, constructor, 12);
    const segment = try segmentRecord(image, segment_id);
    const terminator = segmentTerminatorOffset(segment);
    const payload = terminator + 8;
    const site_ordinal = readInt(u32, segment, payload + 4);
    const request_value = readInt(u16, segment, payload + 12);
    var slots = [_]Slot{.{}} ** 1024;
    try initializeZeroWidthSlots(image, &slots);
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    if (!slots[request_value].initialized) return error.InvalidState;
    const expected = try requestIdentity(
        image,
        state,
        constructor_id,
        site_ordinal,
        slots[request_value].bytes,
        readInt(u64, state, 44),
    );
    if (!requestIdentityEqual(expected, identity)) return error.InvalidState;
    const resume_schema = try effectResumeSchema(image, site_ordinal);
    dynamic_value_v1.validateValue(
        image.catalogs.schemas,
        resume_schema,
        response,
        &workspace.value_tasks,
    ) catch return error.InvalidState;
    const continuation = suspensionContinuation(segment, terminator);
    const target_segment = readInt(u16, continuation, 0);
    const target = try segmentRecord(image, target_segment);
    const argument_count = readInt(u16, continuation, 2);
    if (argument_count != readInt(u16, target, 10)) return error.InvalidImage;
    const next_constructor = try transitionConstructor(
        image,
        segment_id,
        4,
        target_segment,
    );
    const next_constructor_record = try constructorRecord(
        image,
        next_constructor,
    );
    for (0..argument_count) |index| {
        const argument_offset = 4 + index * 4;
        const target_value = readInt(u16, target, image_v1.segment_prefix_length + index * 2);
        if (!constructorRetainsValue(next_constructor_record, target_value)) {
            continue;
        }
        switch (continuation[argument_offset]) {
            0 => {
                const source_value = readInt(u16, continuation, argument_offset + 2);
                if (!slots[source_value].initialized) return error.InvalidState;
                slots[target_value] = slots[source_value];
            },
            1 => slots[target_value] = .{
                .bytes = response,
                .initialized = true,
            },
            else => return error.InvalidImage,
        }
    }
    const successor = try encodeTopFrame(
        image,
        state,
        next_constructor,
        &slots,
        readInt(u64, state, 44),
        readInt(u64, state, 52),
        output_state,
    );
    try validateStateValidated(image, successor, workspace);
    return successor.len;
}

fn stepValidated(
    image: ValidatedProgram,
    state: []const u8,
    caller_fuel: *u64,
    output_state: []u8,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const maximum_state: usize = image.profile.maximum_state_bytes;
    if (scratch.len < maximum_state) return error.ScratchCapacity;
    const temporary_state = scratch[0..maximum_state];
    const value_scratch = scratch[maximum_state..];
    workspace.invariant_result = value_scratch;
    var current_state = state;
    var remaining = caller_fuel.*;
    var next_uses_output = true;
    while (true) {
        const target = if (next_uses_output) output_state else temporary_state;
        const outcome = stepSegment(
            image,
            current_state,
            &remaining,
            target,
            output_value,
            value_scratch,
            workspace,
        ) catch |err| switch (err) {
            error.ExecutionBudgetExceeded => {
                const canonical = if (current_state.ptr == output_state.ptr)
                    current_state
                else blk: {
                    if (output_state.len < current_state.len) {
                        return error.OutputCapacity;
                    }
                    @memcpy(output_state[0..current_state.len], current_state);
                    break :blk output_state[0..current_state.len];
                };
                caller_fuel.* = remaining;
                return .{ .machine_failed = .{
                    .state = canonical,
                    .failure = .execution_budget_exceeded,
                } };
            },
            error.FrameDepthExceeded => return .{ .machine_failed = .{
                .state = state,
                .failure = .frame_depth_exceeded,
            } },
            else => return err,
        };
        switch (outcome) {
            .next => |next| {
                current_state = next;
                next_uses_output = !next_uses_output;
            },
            .yielded => |yielded| {
                const canonical = if (yielded.ptr == output_state.ptr)
                    yielded
                else blk: {
                    if (output_state.len < yielded.len) return error.OutputCapacity;
                    @memcpy(output_state[0..yielded.len], yielded);
                    break :blk output_state[0..yielded.len];
                };
                caller_fuel.* = remaining;
                return .{ .yielded = canonical };
            },
            .requested => |requested| {
                const canonical_state = if (requested.state.ptr == output_state.ptr)
                    requested.state
                else blk: {
                    if (output_state.len < requested.state.len) {
                        return error.OutputCapacity;
                    }
                    @memcpy(
                        output_state[0..requested.state.len],
                        requested.state,
                    );
                    break :blk output_state[0..requested.state.len];
                };
                caller_fuel.* = remaining;
                return .{ .requested = .{
                    .state = canonical_state,
                    .payload = requested.payload,
                    .identity = requested.identity,
                } };
            },
            .done => |done| {
                caller_fuel.* = remaining;
                return .{ .done = done };
            },
            .failed => |failed| {
                caller_fuel.* = remaining;
                return .{ .failed = failed };
            },
        }
    }
}

/// Execute one funded atomic segment under Machine ABI v2 policy.
fn stepSegment(
    image: ValidatedProgram,
    state: []const u8,
    caller_fuel: *u64,
    output_state: []u8,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!SegmentOutcome {
    try validateStateEnvelope(image, state);
    const constructor_id = topConstructorId(state) catch
        return error.InvalidState;
    const constructor = constructorRecord(image, constructor_id) catch
        return error.InvalidState;
    if (constructor[8] == 3) return error.InvalidState;
    const segment_id = readInt(u16, constructor, 12);
    const segment = segmentRecord(image, segment_id) catch
        return error.InvalidImage;
    const minimum_cost = image.profile.segmentCost(segment_id) catch
        return error.InvalidImage;
    // BPI1 section 28.2 intentionally validates only the State envelope and
    // top constructor before an unfunded segment. Environment and invariant
    // validation remains deferred until the caller funds the atomic segment.
    if (caller_fuel.* < minimum_cost) return .{ .yielded = state };
    try validateStateValidated(image, state, workspace);
    const cumulative = readInt(u64, state, 52);
    var slots = [_]Slot{.{}} ** 1024;
    try initializeZeroWidthSlots(image, &slots);
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    const cost = machine_v2_metering_v1.preflightSegmentCost(
        image,
        segment,
        constructor,
        &slots,
        minimum_cost,
        workspace,
    ) catch |err| return switch (err) {
        error.InvalidBindings => error.InvalidState,
        else => err,
    };
    if (caller_fuel.* < cost) return .{ .yielded = state };
    const next_cumulative = std.math.add(u64, cumulative, cost) catch
        return error.ExecutionBudgetExceeded;
    if (next_cumulative > image.profile.maximum_machine_fuel) {
        return error.ExecutionBudgetExceeded;
    }

    const clause = reducer_clause_v1.evaluateClause(
        programView(image),
        segment_id,
        &slots,
        output_value,
        scratch,
        workspace,
    ) catch |err| return switch (err) {
        error.InvalidBindings => error.InvalidState,
        else => err,
    };
    const outcome: SegmentOutcome = switch (clause) {
        .progressed => |progressed| .{ .next = try transitionState(
            image,
            state,
            segment_id,
            progressed.edge_kind,
            progressed.edge,
            &slots,
            next_cumulative,
            output_state,
        ) },
        .requested => |request| blk: {
            const sequence = std.math.add(
                u64,
                readInt(u64, state, 44),
                1,
            ) catch return error.InvalidState;
            const await_constructor = try awaitingConstructor(
                image,
                segment_id,
            );
            const parked = try encodeTopFrame(
                image,
                state,
                await_constructor,
                &slots,
                sequence,
                next_cumulative,
                output_state,
            );
            if (try maximumResumeStateSizeValidated(image, parked) >
                image.profile.maximum_state_bytes)
            {
                return error.InvalidState;
            }
            break :blk .{ .requested = .{
                .state = parked,
                .payload = request.payload,
                .identity = try requestIdentity(
                    image,
                    parked,
                    await_constructor,
                    request.site_ordinal,
                    request.payload,
                    sequence,
                ),
            } };
        },
        .call => |callee| blk: {
            const return_constructor = try awaitCallConstructor(
                image,
                segment_id,
            );
            const parent = try encodeTopFrame(
                image,
                state,
                return_constructor,
                &slots,
                readInt(u64, state, 44),
                next_cumulative,
                output_state,
            );
            const target_segment = readInt(u16, callee, 0);
            const child_constructor = try transitionConstructor(
                image,
                segment_id,
                3,
                target_segment,
            );
            try applyValueEdge(
                image,
                callee,
                target_segment,
                child_constructor,
                &slots,
            );
            break :blk .{ .next = try appendFrame(
                image,
                parent,
                child_constructor,
                &slots,
                output_state,
            ) };
        },
        .explicit_yield => |continuation| blk: {
            const next = try transitionState(
                image,
                state,
                segment_id,
                4,
                continuation,
                &slots,
                next_cumulative,
                output_state,
            );
            break :blk .{ .yielded = next };
        },
        .return_to_caller => |return_value| blk: {
            break :blk .{ .next = try returnToCaller(
                image,
                state,
                return_value,
                next_cumulative,
                output_state,
                workspace,
            ) };
        },
        .completed => |result| .{ .done = result },
        .authored_failure => |failure| .{ .failed = failure },
    };
    caller_fuel.* -= cost;
    return outcome;
}

fn maximumResumeStateSizeValidated(
    image: ValidatedProgram,
    state: []const u8,
) Error!usize {
    try validateStateEnvelope(image, state);
    const constructor_id = try topConstructorId(state);
    const constructor = try constructorRecord(image, constructor_id);
    if (constructor[8] != 3) return error.InvalidState;
    const segment_id = readInt(u16, constructor, 12);
    const segment = try segmentRecord(image, segment_id);
    const continuation = suspensionContinuation(
        segment,
        segmentTerminatorOffset(segment),
    );
    const target_segment = readInt(u16, continuation, 0);
    const next_constructor_id = try transitionConstructor(
        image,
        segment_id,
        4,
        target_segment,
    );
    const next_constructor = try constructorRecord(
        image,
        next_constructor_id,
    );
    var maximum_environment: usize = if (readInt(u16, next_constructor, 10) & 1 != 0)
        4
    else
        0;
    const activation_count = readInt(u16, next_constructor, 16);
    const environment_count = readInt(u16, next_constructor, 18);
    var field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const schema_id = readInt(u32, next_constructor, field_cursor + 4);
        const schema = image.catalogs.schemas.node(schema_id) catch
            return error.InvalidImage;
        const maximum = std.math.cast(
            usize,
            schema.maximum_encoded_size,
        ) orelse return error.InvalidImage;
        maximum_environment = std.math.add(
            usize,
            maximum_environment,
            maximum,
        ) catch return error.InvalidImage;
        field_cursor += 8;
    }
    const top_offset = try topFrameOffset(state);
    const current_environment = readInt(u32, state, top_offset + 4);
    const current_top = std.math.add(
        usize,
        frame_header_length,
        current_environment,
    ) catch return error.InvalidState;
    const without_top = std.math.sub(
        usize,
        state.len,
        current_top,
    ) catch return error.InvalidState;
    const maximum_top = std.math.add(
        usize,
        frame_header_length,
        maximum_environment,
    ) catch return error.InvalidImage;
    return std.math.add(
        usize,
        without_top,
        maximum_top,
    ) catch return error.InvalidImage;
}

fn transitionState(
    image: ValidatedProgram,
    state: []const u8,
    source_segment: u16,
    edge_kind: u8,
    edge: []const u8,
    slots: *[1024]Slot,
    cumulative_fuel: u64,
    output: []u8,
) Error![]const u8 {
    const target_segment = readInt(u16, edge, 0);
    const argument_count = readInt(u16, edge, 2);
    const target = try segmentRecord(image, target_segment);
    const parameter_count = readInt(u16, target, 10);
    if (argument_count != parameter_count) return error.InvalidImage;
    const constructor_id = try transitionConstructor(
        image,
        source_segment,
        edge_kind,
        target_segment,
    );
    const constructor = try constructorRecord(image, constructor_id);
    for (0..argument_count) |index| {
        const argument_offset = 4 + index * 4;
        if (edge[argument_offset] != 0) return error.UnsupportedOperation;
        const source_value = readInt(u16, edge, argument_offset + 2);
        const target_value = readInt(u16, target, image_v1.segment_prefix_length + index * 2);
        if (!constructorRetainsValue(constructor, target_value)) continue;
        if (!slots[source_value].initialized) return error.InvalidState;
        slots[target_value] = slots[source_value];
    }
    return encodeTopFrame(
        image,
        state,
        constructor_id,
        slots,
        readInt(u64, state, 44),
        cumulative_fuel,
        output,
    );
}

fn constructorRetainsValue(constructor: []const u8, value: u16) bool {
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        if (readInt(u16, constructor, cursor) == value) return true;
        cursor += 8;
    }
    return false;
}

fn encodeTopFrame(
    image: ValidatedProgram,
    state: []const u8,
    constructor_id: u32,
    slots: *const [1024]Slot,
    sequence: u64,
    cumulative_fuel: u64,
    output: []u8,
) Error![]const u8 {
    const constructor = try constructorRecord(image, constructor_id);
    const top_offset = try topFrameOffset(state);
    const current_constructor = try constructorRecord(
        image,
        readInt(u32, state, top_offset),
    );
    const current_environment_length = readInt(u32, state, top_offset + 4);
    const current_environment = state[top_offset + 8 ..][0..current_environment_length];
    const target_flags = readInt(u16, constructor, 10);
    var activation_entry: ?u32 = null;
    if (target_flags & 1 != 0) {
        if (readInt(u16, current_constructor, 10) & 1 == 0 or
            current_environment.len < 4)
        {
            return error.InvalidState;
        }
        activation_entry = readInt(u32, current_environment, 0);
    }
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var environment_length: usize = if (activation_entry != null) 4 else 0;
    var field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        if (!slots[value].initialized) return error.InvalidState;
        environment_length = std.math.add(
            usize,
            environment_length,
            slots[value].bytes.len,
        ) catch return error.InvalidState;
        field_cursor += 8;
    }
    const required = top_offset + frame_header_length + environment_length;
    if (required > output.len or
        required > image.profile.maximum_state_bytes)
    {
        return error.OutputCapacity;
    }
    @memcpy(output[0..top_offset], state[0..top_offset]);
    std.mem.writeInt(u64, output[44..52], sequence, .little);
    std.mem.writeInt(u64, output[52..60], cumulative_fuel, .little);
    var cursor = top_offset;
    appendInt(u32, output, &cursor, constructor_id);
    appendInt(u32, output, &cursor, environment_length);
    if (activation_entry) |entry| appendInt(u32, output, &cursor, entry);
    field_cursor = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        appendBytes(output, &cursor, slots[value].bytes);
        field_cursor += 8;
    }
    return output[0..required];
}

fn transitionConstructor(
    image: ValidatedProgram,
    source: u16,
    edge_kind: u8,
    target: u16,
) Error!u32 {
    const bytes = image.catalogs.envelope.section(.entry_transitions);
    const count = readInt(u32, bytes, 0);
    for (0..count) |index| {
        const offset = 4 + index * 12;
        if (readInt(u16, bytes, offset) == source and
            bytes[offset + 2] == edge_kind and
            readInt(u16, bytes, offset + 4) == target)
        {
            return image.profile.transitionConstructor(@intCast(index)) catch
                return error.InvalidProfile;
        }
    }
    return error.InvalidImage;
}

fn awaitingConstructor(
    image: ValidatedProgram,
    source_segment: u16,
) Error!u32 {
    for (0..image.constructor_count) |id| {
        const constructor = try constructorRecord(image, @intCast(id));
        if (constructor[8] == 3 and
            readInt(u16, constructor, 12) == source_segment)
        {
            return @intCast(id);
        }
    }
    return error.InvalidImage;
}

fn awaitCallConstructor(
    image: ValidatedProgram,
    source_segment: u16,
) Error!u32 {
    for (0..image.constructor_count) |id| {
        const constructor = try constructorRecord(image, @intCast(id));
        if (constructor[8] == 4 and constructor[9] == 2 and
            readInt(u16, constructor, 12) == source_segment)
        {
            return @intCast(id);
        }
    }
    return error.InvalidImage;
}

fn suspensionCallee(segment: []const u8, terminator: usize) []const u8 {
    const payload = terminator + 8;
    const request_count = readInt(u16, segment, payload + 10);
    const cursor = payload + 12 + @as(usize, request_count) * 2;
    if (segment[cursor] != 1) return &.{};
    return segment[cursor + 4 ..];
}

fn applyValueEdge(
    image: ValidatedProgram,
    edge: []const u8,
    target_segment: u16,
    target_constructor: u32,
    slots: *[1024]Slot,
) Error!void {
    const target = try segmentRecord(image, target_segment);
    const constructor = try constructorRecord(image, target_constructor);
    const count = readInt(u16, edge, 2);
    if (count != readInt(u16, target, 10)) return error.InvalidImage;
    for (0..count) |index| {
        const argument = 4 + index * 4;
        if (edge[argument] != 0) return error.InvalidImage;
        const source_value = readInt(u16, edge, argument + 2);
        const target_value = readInt(u16, target, image_v1.segment_prefix_length + index * 2);
        if (!constructorRetainsValue(constructor, target_value)) continue;
        if (!slots[source_value].initialized) return error.InvalidState;
        slots[target_value] = slots[source_value];
    }
}

fn appendFrame(
    image: ValidatedProgram,
    parent: []const u8,
    constructor_id: u32,
    slots: *const [1024]Slot,
    output: []u8,
) Error![]const u8 {
    const frame_count = readInt(u32, parent, 60);
    if (frame_count >= image.profile.maximum_frames) {
        return error.FrameDepthExceeded;
    }
    const constructor = try constructorRecord(image, constructor_id);
    if (readInt(u16, constructor, 10) & 1 == 0) return error.InvalidImage;
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var environment_length: usize = 4;
    var field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        if (!slots[value].initialized) return error.InvalidState;
        environment_length += slots[value].bytes.len;
        field_cursor += 8;
    }
    const required = parent.len + frame_header_length + environment_length;
    if (required > output.len or
        required > image.profile.maximum_state_bytes)
    {
        return error.OutputCapacity;
    }
    std.mem.writeInt(u32, output[60..64], frame_count + 1, .little);
    var cursor = parent.len;
    appendInt(u32, output, &cursor, constructor_id);
    appendInt(u32, output, &cursor, environment_length);
    appendInt(u32, output, &cursor, constructor_id);
    field_cursor = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        appendBytes(output, &cursor, slots[value].bytes);
        field_cursor += 8;
    }
    return output[0..required];
}

fn returnToCaller(
    image: ValidatedProgram,
    state: []const u8,
    return_value: []const u8,
    cumulative_fuel: u64,
    output: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error![]const u8 {
    const frame_count = readInt(u32, state, 60);
    if (frame_count < 2) return error.InvalidState;
    const parent_offset = try frameOffset(state, frame_count - 2);
    const parent_constructor_id = readInt(u32, state, parent_offset);
    const parent_constructor = try constructorRecord(image, parent_constructor_id);
    if (parent_constructor[8] != 4 or parent_constructor[9] != 2) {
        return error.InvalidState;
    }
    var slots = [_]Slot{.{}} ** 1024;
    try initializeZeroWidthSlots(image, &slots);
    try loadFrameEnvironment(
        image,
        state,
        parent_offset,
        parent_constructor,
        &slots,
        workspace,
    );
    const parent_segment_id = readInt(u16, parent_constructor, 12);
    const parent_segment = try segmentRecord(image, parent_segment_id);
    const continuation = suspensionContinuation(
        parent_segment,
        segmentTerminatorOffset(parent_segment),
    );
    const target_segment_id = readInt(u16, continuation, 0);
    const target_segment = try segmentRecord(image, target_segment_id);
    const argument_count = readInt(u16, continuation, 2);
    if (argument_count != readInt(u16, target_segment, 10)) {
        return error.InvalidImage;
    }
    const next_constructor = try transitionConstructor(
        image,
        parent_segment_id,
        4,
        target_segment_id,
    );
    const next_constructor_record = try constructorRecord(
        image,
        next_constructor,
    );
    for (0..argument_count) |index| {
        const argument = 4 + index * 4;
        const target_value = readInt(u16, target_segment, image_v1.segment_prefix_length + index * 2);
        if (!constructorRetainsValue(next_constructor_record, target_value)) {
            continue;
        }
        switch (continuation[argument]) {
            0 => {
                const source_value = readInt(u16, continuation, argument + 2);
                if (!slots[source_value].initialized) return error.InvalidState;
                slots[target_value] = slots[source_value];
            },
            1 => slots[target_value] = .{
                .bytes = return_value,
                .initialized = true,
            },
            else => return error.InvalidImage,
        }
    }
    return replaceFrameAndTruncate(
        image,
        state,
        parent_offset,
        frame_count - 1,
        next_constructor,
        &slots,
        cumulative_fuel,
        output,
    );
}

fn requestIdentity(
    image: ValidatedProgram,
    parked_state: []const u8,
    constructor_id: u32,
    site_ordinal: u32,
    payload: []const u8,
    sequence: u64,
) Error!RequestIdentity {
    const effect_site_digest = try effectOrdinalDigest(image, site_ordinal);
    var payload_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &payload_digest, .{});
    var continuation_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        parked_state,
        &continuation_digest,
        .{},
    );
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("boundary-request-identity-v2\x00");
    hasher.update(&image.profile.machine_v2_contract_digest);
    hashInt(&hasher, u64, sequence);
    hashInt(&hasher, u32, constructor_id);
    hashInt(&hasher, u32, site_ordinal);
    hasher.update(&effect_site_digest);
    hasher.update(&payload_digest);
    hasher.update(&continuation_digest);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return .{
        .machine_contract_digest = image.profile.machine_v2_contract_digest,
        .sequence = sequence,
        .constructor_id = constructor_id,
        .site_ordinal = site_ordinal,
        .effect_site_digest = effect_site_digest,
        .payload_digest = payload_digest,
        .continuation_digest = continuation_digest,
        .digest = digest,
    };
}

fn effectOrdinalDigest(
    image: ValidatedProgram,
    target: u32,
) Error![32]u8 {
    const bytes = image.catalogs.envelope.section(.effects);
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |ordinal| {
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4 + identity_length + 8 + 4 + 32;
        const digest = bytes[cursor..][0..32].*;
        if (ordinal == target) return digest;
        cursor += 32;
    }
    return error.InvalidImage;
}

fn effectResumeSchema(
    image: ValidatedProgram,
    target: u32,
) Error!u32 {
    const bytes = image.catalogs.envelope.section(.effects);
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |ordinal| {
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4 + identity_length;
        const resume_schema = readInt(u32, bytes, cursor + 4);
        if (ordinal == target) return resume_schema;
        cursor += 8 + 4 + 64;
    }
    return error.InvalidImage;
}

fn requestIdentityEqual(left: RequestIdentity, right: RequestIdentity) bool {
    return left.sequence == right.sequence and
        left.constructor_id == right.constructor_id and
        left.site_ordinal == right.site_ordinal and
        std.mem.eql(
            u8,
            &left.machine_contract_digest,
            &right.machine_contract_digest,
        ) and
        std.mem.eql(u8, &left.effect_site_digest, &right.effect_site_digest) and
        std.mem.eql(u8, &left.payload_digest, &right.payload_digest) and
        std.mem.eql(
            u8,
            &left.continuation_digest,
            &right.continuation_digest,
        ) and
        std.mem.eql(u8, &left.digest, &right.digest);
}

fn hashInt(
    hasher: *std.crypto.hash.sha2.Sha256,
    comptime T: type,
    value: T,
) void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    hasher.update(&bytes);
}

fn edgeLength(edge: []const u8) usize {
    return 4 + @as(usize, readInt(u16, edge, 2)) * 4;
}

fn topFrameOffset(state: []const u8) Error!usize {
    const frame_count = readInt(u32, state, 60);
    if (frame_count == 0) return error.InvalidState;
    var cursor: usize = state_header_length;
    for (0..frame_count - 1) |_| {
        if (state.len - cursor < frame_header_length) return error.InvalidState;
        cursor += frame_header_length + readInt(u32, state, cursor + 4);
        if (cursor > state.len) return error.InvalidState;
    }
    return cursor;
}

fn frameOffset(state: []const u8, target: u32) Error!usize {
    const frame_count = readInt(u32, state, 60);
    if (target >= frame_count) return error.InvalidState;
    var cursor: usize = state_header_length;
    for (0..target) |_| {
        if (state.len - cursor < frame_header_length) return error.InvalidState;
        cursor += frame_header_length + readInt(u32, state, cursor + 4);
        if (cursor > state.len) return error.InvalidState;
    }
    return cursor;
}

fn replaceFrameAndTruncate(
    image: ValidatedProgram,
    state: []const u8,
    frame_offset: usize,
    frame_count: u32,
    constructor_id: u32,
    slots: *const [1024]Slot,
    cumulative_fuel: u64,
    output: []u8,
) Error![]const u8 {
    const constructor = try constructorRecord(image, constructor_id);
    const current_constructor = try constructorRecord(
        image,
        readInt(u32, state, frame_offset),
    );
    const current_environment_length = readInt(u32, state, frame_offset + 4);
    const current_environment = state[frame_offset + 8 ..][0..current_environment_length];
    var activation_entry: ?u32 = null;
    if (readInt(u16, constructor, 10) & 1 != 0) {
        if (readInt(u16, current_constructor, 10) & 1 == 0 or
            current_environment.len < 4)
        {
            return error.InvalidState;
        }
        activation_entry = readInt(u32, current_environment, 0);
    }
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var environment_length: usize = if (activation_entry != null) 4 else 0;
    var field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        if (!slots[value].initialized) return error.InvalidState;
        environment_length += slots[value].bytes.len;
        field_cursor += 8;
    }
    const required = frame_offset + frame_header_length + environment_length;
    if (required > output.len or
        required > image.profile.maximum_state_bytes)
    {
        return error.OutputCapacity;
    }
    @memcpy(output[0..frame_offset], state[0..frame_offset]);
    std.mem.writeInt(u64, output[52..60], cumulative_fuel, .little);
    std.mem.writeInt(u32, output[60..64], frame_count, .little);
    var cursor = frame_offset;
    appendInt(u32, output, &cursor, constructor_id);
    appendInt(u32, output, &cursor, environment_length);
    if (activation_entry) |entry| appendInt(u32, output, &cursor, entry);
    field_cursor = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        appendBytes(output, &cursor, slots[value].bytes);
        field_cursor += 8;
    }
    return output[0..required];
}

fn loadTopEnvironment(
    image: ValidatedProgram,
    state: []const u8,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    return loadFrameEnvironment(
        image,
        state,
        try topFrameOffset(state),
        constructor,
        slots,
        workspace,
    );
}

fn initializeZeroWidthSlots(
    image: ValidatedProgram,
    slots: *[1024]Slot,
) Error!void {
    for (0..image.catalogs.value_count) |value| {
        const schema_id = image.catalogs.valueSchemaId(@intCast(value)) catch
            return error.InvalidImage;
        const schema = image.catalogs.schemas.node(schema_id) catch
            return error.InvalidImage;
        if (schema.maximum_encoded_size == 0) {
            slots[value] = .{ .bytes = &.{}, .initialized = true };
        }
    }
}

fn loadFrameEnvironment(
    image: ValidatedProgram,
    state: []const u8,
    frame_offset: usize,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const environment_length = readInt(u32, state, frame_offset + 4);
    const environment = state[frame_offset + 8 ..][0..environment_length];
    var value_cursor: usize = 0;
    if (readInt(u16, constructor, 10) & 1 != 0) value_cursor = 4;
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        const schema_id = readInt(u32, constructor, field_cursor + 4);
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema_id,
            environment[value_cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
        slots[value] = .{
            .bytes = environment[value_cursor .. value_cursor + consumed],
            .initialized = true,
        };
        value_cursor += consumed;
        field_cursor += 8;
    }
}

fn topConstructorId(state: []const u8) Error!u32 {
    if (state.len < state_header_length + frame_header_length) {
        return error.InvalidState;
    }
    const frame_count = readInt(u32, state, 60);
    if (frame_count == 0) return error.InvalidState;
    var cursor: usize = state_header_length;
    for (0..frame_count - 1) |_| {
        if (state.len - cursor < frame_header_length) return error.InvalidState;
        cursor += frame_header_length + readInt(u32, state, cursor + 4);
        if (cursor > state.len) return error.InvalidState;
    }
    return readInt(u32, state, cursor);
}

fn segmentRecord(
    image: anytype,
    target: u16,
) Error![]const u8 {
    const bytes = image.catalogs.envelope.section(.segments);
    var cursor: usize = 4;
    for (0..image.segment_count) |id| {
        const length = readInt(u32, bytes, cursor);
        const end = cursor + length;
        if (id == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidImage;
}

fn segmentTerminatorOffset(segment: []const u8) usize {
    var cursor: usize = image_v1.segment_prefix_length + @as(usize, readInt(u16, segment, 10)) * 2;
    for (0..readInt(u32, segment, 12)) |_| {
        cursor += readInt(u32, segment, cursor);
    }
    return cursor;
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

fn validateEnvironment(
    image: anytype,
    constructor: []const u8,
    environment: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const flags = readInt(u16, constructor, 10);
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    var value_cursor: usize = 0;
    var slots = [_]Slot{.{}} ** 1024;
    if (flags & 1 != 0) {
        if (environment.len < 4) return error.InvalidState;
        const entry_constructor = readInt(u32, environment, 0);
        _ = constructorRecord(image, entry_constructor) catch
            return error.InvalidState;
        value_cursor = 4;
    }
    const field_count = @as(u32, activation_count) + environment_count;
    for (0..field_count) |_| {
        const value = readInt(u16, constructor, field_cursor);
        const schema_id = readInt(u32, constructor, field_cursor + 4);
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema_id,
            environment[value_cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
        slots[value] = .{
            .bytes = environment[value_cursor .. value_cursor + consumed],
            .initialized = true,
        };
        value_cursor += consumed;
        field_cursor += 8;
    }
    if (value_cursor != environment.len) return error.InvalidState;
    try validatePathInvariants(image, constructor, &slots, workspace);
}

fn validatePathInvariants(
    image: anytype,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    const invariant_count = readInt(u16, constructor, 20);
    var cursor: usize = 24 +
        (@as(usize, activation_count) + environment_count) * 8;
    for (0..invariant_count) |_| {
        const length = readInt(u32, constructor, cursor);
        const tag = constructor[cursor + 4];
        const payload = cursor + 8;
        const accepted = switch (tag) {
            0 => blk: {
                const value = readInt(u16, constructor, payload);
                break :blk slots[value].initialized and
                    slots[value].bytes.len == 1 and
                    (slots[value].bytes[0] == 1) ==
                        (constructor[payload + 2] == 1);
            },
            1, 5 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                1,
                0,
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            2 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                20,
                0,
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            3 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                21 + constructor[payload + 6],
                0,
                &.{
                    readInt(u16, constructor, payload + 2),
                    readInt(u16, constructor, payload + 4),
                },
                slots,
                workspace,
            ),
            4, 7 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                23,
                0,
                &.{
                    readInt(u16, constructor, payload + 2),
                    readInt(u16, constructor, payload + 4),
                    readInt(u16, constructor, payload + 6),
                },
                slots,
                workspace,
            ),
            6 => try validateInvariantConstant(
                image,
                readInt(u16, constructor, payload),
                constructor[payload + 4],
                readInt(u64, constructor, payload + 12),
                slots,
            ),
            8 => blk: {
                const result = readInt(u16, constructor, payload);
                const definition = readInt(u16, constructor, payload + 2);
                const operand_count = readInt(u16, constructor, payload + 4);
                var operands: [1024]u16 = undefined;
                if (operand_count > operands.len) return error.InvalidState;
                for (0..operand_count) |index| {
                    operands[index] = readInt(
                        u16,
                        constructor,
                        payload + 8 + index * 2,
                    );
                }
                const instruction = try definingInstruction(image, definition);
                break :blk try validateComputedResult(
                    image,
                    result,
                    readInt(u16, instruction, 6),
                    readInt(u32, instruction, 12),
                    operands[0..operand_count],
                    slots,
                    workspace,
                );
            },
            9 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                25,
                readInt(u16, constructor, payload + 4),
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            10 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                29,
                readInt(u16, constructor, payload + 4),
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            11 => blk: {
                const bounded = readInt(u16, constructor, payload + 2);
                const operation: u16 = switch ((try reducer_clause_v1.valueNode(image, bounded)).kind) {
                    .vector => 34,
                    .text => 53,
                    .bytes => 54,
                    else => return error.InvalidState,
                };
                break :blk try validateComputedResult(
                    image,
                    readInt(u16, constructor, payload),
                    operation,
                    0,
                    &.{bounded},
                    slots,
                    workspace,
                );
            },
            12 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                if (constructor[payload + 4] == 0) 8 else 15,
                0,
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            13 => blk: {
                const operations = [_]u16{ 3, 4, 5, 6, 7, 16, 17, 18 };
                const operation = constructor[payload + 6];
                if (operation >= operations.len) return error.InvalidState;
                break :blk try validateComputedResult(
                    image,
                    readInt(u16, constructor, payload),
                    operations[operation],
                    0,
                    &.{
                        readInt(u16, constructor, payload + 2),
                        readInt(u16, constructor, payload + 4),
                    },
                    slots,
                    workspace,
                );
            },
            14 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                19,
                0,
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            15 => blk: {
                const value = readInt(u16, constructor, payload);
                if (!slots[value].initialized) break :blk false;
                var zero = true;
                for (slots[value].bytes) |byte| zero = zero and byte == 0;
                break :blk zero == (constructor[payload + 2] == 1);
            },
            16 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                2,
                0,
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            17 => blk: {
                const left_id = readInt(u16, constructor, payload);
                const right_id = readInt(u16, constructor, payload + 2);
                if (!slots[left_id].initialized or !slots[right_id].initialized) {
                    break :blk false;
                }
                const left = reducer_clause_v1.decodeInteger(
                    try reducer_clause_v1.valueKind(image, left_id),
                    slots[left_id].bytes,
                ) catch break :blk false;
                const right = reducer_clause_v1.decodeInteger(
                    try reducer_clause_v1.valueKind(image, right_id),
                    slots[right_id].bytes,
                ) catch break :blk false;
                const operation: u16 = 9 + constructor[payload + 4];
                break :blk reducer_clause_v1.compareIntegers(left, right, operation) ==
                    (constructor[payload + 5] == 1);
            },
            18 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                9 + constructor[payload + 6],
                0,
                &.{
                    readInt(u16, constructor, payload + 2),
                    readInt(u16, constructor, payload + 4),
                },
                slots,
                workspace,
            ),
            19 => blk: {
                const value = readInt(u16, constructor, payload);
                if (!slots[value].initialized) break :blk false;
                const actual = algebraicCaseIndex(
                    image,
                    value,
                    slots[value].bytes,
                ) catch break :blk false;
                break :blk (actual == readInt(u16, constructor, payload + 2)) ==
                    (constructor[payload + 4] == 1);
            },
            20 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                28,
                readInt(u16, constructor, payload + 4),
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
            ),
            else => return error.InvalidState,
        };
        if (!accepted) return error.InvalidState;
        cursor += length;
    }
}

fn definingInstruction(
    image: anytype,
    definition: u16,
) Error![]const u8 {
    for (0..image.segment_count) |segment_id| {
        const segment = try segmentRecord(image, @intCast(segment_id));
        var cursor: usize = image_v1.segment_prefix_length + @as(usize, readInt(u16, segment, 10)) * 2;
        for (0..readInt(u32, segment, 12)) |_| {
            const length = readInt(u32, segment, cursor);
            if (readInt(u16, segment, cursor + 8) == definition) {
                return segment[cursor .. cursor + length];
            }
            cursor += length;
        }
    }
    return error.InvalidState;
}

fn validateComputedResult(
    image: anytype,
    result: u16,
    operation: u16,
    immediate: u32,
    operands: []const u16,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!bool {
    if (!slots[result].initialized or operands.len > 1024) return false;
    const instruction_length = 16 + operands.len * 2;
    if (instruction_length > workspace.invariant_instruction.len) {
        return error.ScratchCapacity;
    }
    const instruction = workspace.invariant_instruction[0..instruction_length];
    @memset(instruction, 0);
    std.mem.writeInt(u32, instruction[0..4], @intCast(instruction_length), .little);
    std.mem.writeInt(u16, instruction[6..8], operation, .little);
    std.mem.writeInt(u16, instruction[8..10], result, .little);
    std.mem.writeInt(u16, instruction[10..12], @intCast(operands.len), .little);
    std.mem.writeInt(u32, instruction[12..16], immediate, .little);
    for (operands, 0..) |operand, index| {
        std.mem.writeInt(
            u16,
            instruction[16 + index * 2 ..][0..2],
            operand,
            .little,
        );
    }
    const expected = slots[result];
    defer slots[result] = expected;
    var scratch_cursor: usize = 0;
    const failure = if (operation == 0) blk: {
        slots[result] = .{
            .bytes = try reducer_clause_v1.constantBytes(image, immediate),
            .initialized = true,
        };
        break :blk null;
    } else if (operation == 1) blk: {
        if (operands.len != 1 or !slots[operands[0]].initialized) return false;
        slots[result] = slots[operands[0]];
        break :blk null;
    } else if (operation <= 23 or operation == 57)
        try reducer_clause_v1.executeScalarOperation(
            image,
            instruction,
            result,
            slots,
            workspace.invariant_result,
            &scratch_cursor,
        )
    else if (operation <= 56)
        try reducer_clause_v1.executeCompositeOperation(
            image,
            instruction,
            result,
            slots,
            workspace.invariant_result,
            &scratch_cursor,
            workspace,
        )
    else
        return error.InvalidState;
    return failure == null and slots[result].initialized and
        std.mem.eql(u8, expected.bytes, slots[result].bytes);
}

fn validateInvariantConstant(
    image: anytype,
    result: u16,
    kind: u8,
    payload: u64,
    slots: *const [1024]Slot,
) Error!bool {
    if (!slots[result].initialized) return false;
    return switch (kind) {
        0 => slots[result].bytes.len == 1 and
            slots[result].bytes[0] == @as(u8, @intCast(payload)),
        1 => blk: {
            const value = try reducer_clause_v1.decodeInteger(
                try reducer_clause_v1.valueKind(image, result),
                slots[result].bytes,
            );
            break :blk value.signed and reducer_clause_v1.signedValue(value) == @as(i64, @bitCast(payload));
        },
        2 => blk: {
            const value = try reducer_clause_v1.decodeInteger(
                try reducer_clause_v1.valueKind(image, result),
                slots[result].bytes,
            );
            break :blk !value.signed and value.raw == payload;
        },
        3 => (try algebraicCaseIndex(
            image,
            result,
            slots[result].bytes,
        )) == payload,
        else => error.InvalidState,
    };
}

fn algebraicCaseIndex(
    image: anytype,
    value: u16,
    bytes: []const u8,
) Error!u16 {
    const node = try reducer_clause_v1.valueNode(image, value);
    return switch (node.kind) {
        .optional => if (bytes[0] == 0) 0 else 1,
        .sum => blk: {
            const tag = readInt(u32, bytes, 0);
            const count = readInt(u32, node.payload, 4);
            for (0..count) |index| {
                if (readInt(u32, node.payload, 8 + index * 8) == tag) {
                    break :blk @intCast(index);
                }
            }
            return error.InvalidState;
        },
        else => error.InvalidState,
    };
}

fn constructorRecord(
    image: ValidatedProgram,
    target: u32,
) Error![]const u8 {
    const mapped = image.profile.mappedConstructor(target) catch
        return error.InvalidProfile;
    const bytes = image.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..image.profile.bpi_constructor_count) |id| {
        const length = readInt(u32, bytes, cursor);
        const end = cursor + length;
        if (id == mapped) return bytes[cursor..end];
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
