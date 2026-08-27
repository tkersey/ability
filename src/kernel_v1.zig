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
    maximum_state_bytes: u32,
};

const ValidatedProgram = struct {
    catalogs: image_v1.Catalogs,
    segment_count: u32,
    constructor_count: u32,
    artifact_sha256: [32]u8,
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
    machine_v2_profile_v1.validateProjection(image, profile) catch
        return error.InvalidProfile;
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
        .artifact_sha256 = image.artifact_sha256,
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
    const validated = try bindValidatedMachineV2(
        refreshed_image,
        profile_bytes,
        workspace,
    );
    return .{
        .image_bytes = image_bytes,
        .profile_bytes = profile_bytes,
        .image_sha256 = sha256(image_bytes),
        .profile_sha256 = sha256(profile_bytes),
        .maximum_state_bytes = validated.profile.maximum_state_bytes,
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

fn requireInvariantScratchDisjoint(
    binding: BoundProgram,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    try requireWorkspaceDisjoint(workspace.invariant_result, workspace);
    try requireBindingDisjoint(binding, workspace.invariant_result);
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
        .artifact_sha256 = image.artifact_sha256,
    };
}

pub fn initial(
    binding: BoundProgram,
    initial_args: []const u8,
    output_state: []u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    try requireInvariantScratchDisjoint(binding, workspace);
    try requireWorkspaceDisjoint(initial_args, workspace);
    try requireWorkspaceDisjoint(output_state, workspace);
    try requireBindingDisjoint(binding, output_state);
    try requireDisjoint(initial_args, workspace.invariant_result);
    try requireDisjoint(output_state, workspace.invariant_result);
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
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    try requireInvariantScratchDisjoint(binding, workspace);
    try requireWorkspaceDisjoint(state, workspace);
    try requireDisjoint(state, workspace.invariant_result);
    const image = try acquire(binding, workspace);
    return validateStateValidated(image, state, workspace);
}

pub fn current(
    binding: BoundProgram,
    state: []const u8,
    output_payload: []u8,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!?RequestView {
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    try requireInvariantScratchDisjoint(binding, workspace);
    try requireWorkspaceDisjoint(state, workspace);
    try requireWorkspaceDisjoint(output_payload, workspace);
    try requireBindingDisjoint(binding, output_payload);
    try requireDisjoint(state, invariant_scratch);
    try requireDisjoint(output_payload, invariant_scratch);
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
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
    const prior_invariant_result = workspace.invariant_result;
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = prior_invariant_result;
    try requireInvariantScratchDisjoint(binding, workspace);
    try requireWorkspaceDisjoint(state, workspace);
    try requireWorkspaceDisjoint(response, workspace);
    try requireWorkspaceDisjoint(output_state, workspace);
    try requireBindingDisjoint(binding, output_state);
    try requireDisjoint(state, workspace.invariant_result);
    try requireDisjoint(response, workspace.invariant_result);
    try requireDisjoint(output_state, workspace.invariant_result);
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
    const prior_invariant_result = workspace.invariant_result;
    defer workspace.invariant_result = prior_invariant_result;
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
    const constructor = constructorRecord(
        image,
        image.profile.initial_constructor_id,
    ) catch return error.InvalidImage;
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
        error.InvalidBindings => return error.InvalidInitialArgs,
        else => return error.InvalidImage,
    };
    const environment_length = reducer_clause_v1.environmentEncodedLength(
        constructor,
        null,
        &activation_slots,
        &slots,
    ) catch return error.InvalidImage;
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
    const environment = try reducer_clause_v1.encodeEnvironmentSlots(
        constructor,
        null,
        &activation_slots,
        &slots,
        output_state[cursor..][0..environment_length],
    );
    cursor += environment.len;
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
    var previous_constructor: []const u8 = &.{};
    var previous_slots = [_]Slot{.{}} ** 1024;
    for (0..frame_count) |frame_index| {
        const constructor_id = readInt(u32, state, cursor);
        const environment_length = readInt(u32, state, cursor + 4);
        cursor += frame_header_length;
        const environment_end = cursor + environment_length;
        const constructor = try constructorRecord(image, constructor_id);
        top_kind = constructor[8];
        var slots = [_]Slot{.{}} ** 1024;
        var activation_slots = [_]Slot{.{}} ** 1024;
        const loaded = validateEnvironment(
            image,
            constructor,
            state[cursor..environment_end],
            &slots,
            &activation_slots,
            workspace,
        ) catch |err| switch (err) {
            error.ScratchCapacity => return error.ScratchCapacity,
            else => return error.InvalidState,
        };
        if (frame_index == 0) {
            const segment = try segmentRecord(
                image,
                readInt(u16, constructor, 12),
            );
            if (readInt(u16, segment, 6) != 0) return error.InvalidState;
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
        cursor = environment_end;
    }
    if ((top_kind == 3 and sequence == 0) or
        reducer_clause_v1.isAwaitCallConstructor(image, previous_constructor))
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

fn validateStackPair(
    image: ValidatedProgram,
    parent_constructor: []const u8,
    parent_slots: *const [1024]Slot,
    child_constructor: []const u8,
    child_activation_entry: ?u32,
    child_slots: *const [1024]Slot,
) Error!void {
    const parent_segment_id = readInt(u16, parent_constructor, 12);
    const parent_segment = try segmentRecord(image, parent_segment_id);
    const callee = suspensionCallee(
        parent_segment,
        segmentTerminatorOffset(parent_segment),
    );
    if (callee.len < 4) return error.InvalidState;
    const expected_call_entry = try transitionConstructor(
        image,
        parent_segment_id,
        3,
        readInt(u16, callee, 0),
    );
    try reducer_clause_v1.validateStackPair(
        image,
        parent_constructor,
        parent_slots,
        child_constructor,
        child_activation_entry,
        child_slots,
        expected_call_entry,
    );
}

fn currentValidated(
    image: ValidatedProgram,
    state: []const u8,
    output_payload: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!?RequestView {
    try validateStateValidated(image, state, workspace);
    const constructor_id = try topConstructorId(state);
    const constructor = try constructorRecord(image, constructor_id);
    if (constructor[8] != 3) return null;
    const segment_id = readInt(u16, constructor, 12);
    const segment = try segmentRecord(image, segment_id);
    const terminator = segmentTerminatorOffset(segment);
    const suspension = reducer_clause_v1.suspensionView(
        segment,
        terminator,
    ) catch return error.InvalidState;
    const effect = switch (suspension) {
        .effect => |effect| effect,
        else => return error.InvalidState,
    };
    var slots = [_]Slot{.{}} ** 1024;
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    if (!slots[effect.request_value].initialized) return error.InvalidState;
    if (output_payload.len < slots[effect.request_value].bytes.len) {
        return error.OutputCapacity;
    }
    @memcpy(
        output_payload[0..slots[effect.request_value].bytes.len],
        slots[effect.request_value].bytes,
    );
    const canonical_payload = output_payload[0..slots[effect.request_value].bytes.len];
    const sequence = readInt(u64, state, 44);
    return .{
        .state = state,
        .payload = canonical_payload,
        .identity = try requestIdentity(
            image,
            state,
            constructor_id,
            effect.site_ordinal,
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
    const suspension = reducer_clause_v1.suspensionView(
        segment,
        terminator,
    ) catch return error.InvalidState;
    const effect = switch (suspension) {
        .effect => |effect| effect,
        else => return error.InvalidState,
    };
    var slots = [_]Slot{.{}} ** 1024;
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    if (!slots[effect.request_value].initialized) return error.InvalidState;
    const expected = try requestIdentity(
        image,
        state,
        constructor_id,
        effect.site_ordinal,
        slots[effect.request_value].bytes,
        readInt(u64, state, 44),
    );
    if (!requestIdentityEqual(expected, identity)) return error.InvalidState;
    const resume_schema = try effectResumeSchema(image, effect.site_ordinal);
    dynamic_value_v1.validateValue(
        image.catalogs.schemas,
        resume_schema,
        response,
        &workspace.value_tasks,
    ) catch return error.InvalidState;
    const continuation = effect.continuation;
    const target_segment = readInt(u16, continuation, 0);
    const target = try segmentRecord(image, target_segment);
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
    try reducer_clause_v1.applyEdge(
        next_constructor_record,
        target,
        continuation,
        response,
        &slots,
    );
    const successor = try encodeTopFrame(
        image,
        state,
        next_constructor,
        &slots,
        readInt(u64, state, 44),
        readInt(u64, state, 52),
        output_state,
        workspace,
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
    // Machine ABI v2 intentionally admits an unfunded short path after only
    // envelope and top-constructor validation. Environment and invariant
    // validation remains deferred until the caller funds the segment.
    if (try segmentIsUnfunded(image, state, caller_fuel.*)) {
        return .{ .yielded = state };
    }
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

fn segmentIsUnfunded(
    image: ValidatedProgram,
    state: []const u8,
    caller_fuel: u64,
) Error!bool {
    try validateStateEnvelope(image, state);
    const constructor_id = topConstructorId(state) catch
        return error.InvalidState;
    const constructor = constructorRecord(image, constructor_id) catch
        return error.InvalidState;
    if (constructor[8] == 3) return error.InvalidState;
    const segment_id = readInt(u16, constructor, 12);
    _ = segmentRecord(image, segment_id) catch return error.InvalidImage;
    const minimum_cost = image.profile.segmentCost(segment_id) catch
        return error.InvalidImage;
    return caller_fuel < minimum_cost;
}

const SegmentPreflight = struct {
    segment_id: u16,
    cumulative: u64,
    cost: u64,
    slots: [1024]Slot,
};

fn preflightCurrentSegment(
    image: ValidatedProgram,
    state: []const u8,
    caller_fuel: u64,
    workspace: *image_v1.ValidationWorkspace,
) Error!?SegmentPreflight {
    if (try segmentIsUnfunded(image, state, caller_fuel)) return null;
    try validateStateValidated(image, state, workspace);
    const constructor_id = try topConstructorId(state);
    const constructor = try constructorRecord(image, constructor_id);
    const segment_id = readInt(u16, constructor, 12);
    const segment = try segmentRecord(image, segment_id);
    const minimum_cost = image.profile.segmentCost(segment_id) catch
        return error.InvalidImage;
    var slots = [_]Slot{.{}} ** 1024;
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    const top_offset = try topFrameOffset(state);
    const environment_length = readInt(u32, state, top_offset + 4);
    const environment = state[top_offset + frame_header_length ..][0..environment_length];
    const cost = machine_v2_metering_v1.preflightSegmentCost(
        image,
        segment,
        constructor,
        environment,
        &slots,
        minimum_cost,
        workspace,
    ) catch |err| return switch (err) {
        error.InvalidBindings => error.InvalidState,
        else => err,
    };
    return .{
        .segment_id = segment_id,
        .cumulative = readInt(u64, state, 52),
        .cost = cost,
        .slots = slots,
    };
}

pub const StepAdmission = enum {
    yielded,
    funded,
    execution_budget_exceeded,
};

pub fn preflightStep(
    binding: BoundProgram,
    state: []const u8,
    caller_fuel: u64,
    invariant_scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!StepAdmission {
    const image = try acquire(binding, workspace);
    workspace.invariant_result = invariant_scratch;
    defer workspace.invariant_result = &.{};
    const preflight = preflightCurrentSegment(
        image,
        state,
        caller_fuel,
        workspace,
    ) catch |err| return switch (err) {
        error.ExecutionBudgetExceeded => .execution_budget_exceeded,
        else => err,
    };
    const prepared = preflight orelse return .yielded;
    if (caller_fuel < prepared.cost) return .yielded;
    return .funded;
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
    var prepared = (try preflightCurrentSegment(
        image,
        state,
        caller_fuel.*,
        workspace,
    )) orelse return .{ .yielded = state };
    if (caller_fuel.* < prepared.cost) return .{ .yielded = state };
    const next_cumulative = std.math.add(
        u64,
        prepared.cumulative,
        prepared.cost,
    ) catch
        return error.ExecutionBudgetExceeded;
    if (next_cumulative > image.profile.maximum_machine_fuel) {
        return error.ExecutionBudgetExceeded;
    }

    const clause = reducer_clause_v1.evaluateClause(
        programView(image),
        prepared.segment_id,
        &prepared.slots,
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
            prepared.segment_id,
            progressed.edge_kind,
            progressed.edge,
            &prepared.slots,
            next_cumulative,
            output_state,
            workspace,
        ) },
        .requested => |request| blk: {
            const sequence = std.math.add(
                u64,
                readInt(u64, state, 44),
                1,
            ) catch return error.InvalidState;
            const await_constructor = try awaitingConstructor(
                image,
                prepared.segment_id,
            );
            const parked = try encodeTopFrame(
                image,
                state,
                await_constructor,
                &prepared.slots,
                sequence,
                next_cumulative,
                output_state,
                workspace,
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
                prepared.segment_id,
            );
            const parent = try encodeTopFrame(
                image,
                state,
                return_constructor,
                &prepared.slots,
                readInt(u64, state, 44),
                next_cumulative,
                output_state,
                workspace,
            );
            const target_segment = readInt(u16, callee, 0);
            const child_constructor = try transitionConstructor(
                image,
                prepared.segment_id,
                3,
                target_segment,
            );
            try applyValueEdge(
                image,
                callee,
                target_segment,
                child_constructor,
                &prepared.slots,
            );
            break :blk .{ .next = try appendFrame(
                image,
                parent,
                child_constructor,
                &prepared.slots,
                output_state,
            ) };
        },
        .explicit_yield => |continuation| blk: {
            const next = try transitionState(
                image,
                state,
                prepared.segment_id,
                4,
                continuation,
                &prepared.slots,
                next_cumulative,
                output_state,
                workspace,
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
    switch (outcome) {
        .next => |next| try validateStateValidated(image, next, workspace),
        .requested => |requested| try validateStateValidated(
            image,
            requested.state,
            workspace,
        ),
        .yielded => |yielded| try validateStateValidated(
            image,
            yielded,
            workspace,
        ),
        .done, .failed => {},
    }
    caller_fuel.* -= prepared.cost;
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
    workspace: *image_v1.ValidationWorkspace,
) Error![]const u8 {
    const target_segment = readInt(u16, edge, 0);
    const target = try segmentRecord(image, target_segment);
    const constructor_id = try transitionConstructor(
        image,
        source_segment,
        edge_kind,
        target_segment,
    );
    const constructor = try constructorRecord(image, constructor_id);
    try reducer_clause_v1.applyEdge(
        constructor,
        target,
        edge,
        null,
        slots,
    );
    return encodeTopFrame(
        image,
        state,
        constructor_id,
        slots,
        readInt(u64, state, 44),
        cumulative_fuel,
        output,
        workspace,
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
    workspace: *image_v1.ValidationWorkspace,
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
    var activation_slots = [_]Slot{.{}} ** 1024;
    if (activation_count != 0) {
        try loadActivationSlots(
            image,
            state,
            top_offset,
            current_constructor,
            &activation_slots,
            workspace,
        );
    }
    const environment_length = reducer_clause_v1.environmentEncodedLength(
        constructor,
        activation_entry,
        &activation_slots,
        slots,
    ) catch |err| switch (err) {
        error.OutputCapacity => return error.OutputCapacity,
        else => return error.InvalidState,
    };
    const frame_length = std.math.add(
        usize,
        frame_header_length,
        environment_length,
    ) catch return error.OutputCapacity;
    const required = std.math.add(
        usize,
        top_offset,
        frame_length,
    ) catch return error.OutputCapacity;
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
    const environment = try reducer_clause_v1.encodeEnvironmentSlots(
        constructor,
        activation_entry,
        &activation_slots,
        slots,
        output[cursor..][0..environment_length],
    );
    cursor += environment.len;
    if (cursor != required) return error.InvalidState;
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

const suspensionCallee = reducer_clause_v1.suspensionCallee;

fn applyValueEdge(
    image: ValidatedProgram,
    edge: []const u8,
    target_segment: u16,
    target_constructor: u32,
    slots: *[1024]Slot,
) Error!void {
    const target = try segmentRecord(image, target_segment);
    const constructor = try constructorRecord(image, target_constructor);
    try reducer_clause_v1.applyEdge(
        constructor,
        target,
        edge,
        null,
        slots,
    );
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
    const environment_length = reducer_clause_v1.environmentEncodedLength(
        constructor,
        constructor_id,
        slots,
        slots,
    ) catch |err| switch (err) {
        error.OutputCapacity => return error.OutputCapacity,
        else => return error.InvalidState,
    };
    const frame_length = std.math.add(
        usize,
        frame_header_length,
        environment_length,
    ) catch return error.OutputCapacity;
    const required = std.math.add(
        usize,
        parent.len,
        frame_length,
    ) catch return error.OutputCapacity;
    if (required > output.len or
        required > image.profile.maximum_state_bytes)
    {
        return error.OutputCapacity;
    }
    std.mem.writeInt(u32, output[60..64], frame_count + 1, .little);
    var cursor = parent.len;
    appendInt(u32, output, &cursor, constructor_id);
    appendInt(u32, output, &cursor, environment_length);
    const environment = try reducer_clause_v1.encodeEnvironmentSlots(
        constructor,
        constructor_id,
        slots,
        slots,
        output[cursor..][0..environment_length],
    );
    cursor += environment.len;
    if (cursor != required) return error.InvalidState;
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
    try reducer_clause_v1.applyEdge(
        next_constructor_record,
        target_segment,
        continuation,
        return_value,
        &slots,
    );
    return replaceFrameAndTruncate(
        image,
        state,
        parent_offset,
        frame_count - 1,
        next_constructor,
        &slots,
        cumulative_fuel,
        output,
        workspace,
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

const edgeLength = reducer_clause_v1.edgeLength;

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
    workspace: *image_v1.ValidationWorkspace,
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
    var activation_slots = [_]Slot{.{}} ** 1024;
    if (activation_count != 0) {
        try loadActivationSlots(
            image,
            state,
            frame_offset,
            current_constructor,
            &activation_slots,
            workspace,
        );
    }
    const environment_length = reducer_clause_v1.environmentEncodedLength(
        constructor,
        activation_entry,
        &activation_slots,
        slots,
    ) catch |err| switch (err) {
        error.OutputCapacity => return error.OutputCapacity,
        else => return error.InvalidState,
    };
    const frame_length = std.math.add(
        usize,
        frame_header_length,
        environment_length,
    ) catch return error.OutputCapacity;
    const required = std.math.add(
        usize,
        frame_offset,
        frame_length,
    ) catch return error.OutputCapacity;
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
    const environment = try reducer_clause_v1.encodeEnvironmentSlots(
        constructor,
        activation_entry,
        &activation_slots,
        slots,
        output[cursor..][0..environment_length],
    );
    cursor += environment.len;
    if (cursor != required) return error.InvalidState;
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
    reducer_clause_v1.initializeZeroWidthSlots(
        programView(image),
        slots,
    ) catch return error.InvalidImage;
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
    _ = reducer_clause_v1.decodeEnvironmentSlots(
        image,
        constructor,
        environment,
        slots,
        null,
        workspace,
    ) catch |err| switch (err) {
        error.ScratchCapacity => return error.ScratchCapacity,
        else => return error.InvalidState,
    };
}

fn loadActivationSlots(
    image: ValidatedProgram,
    state: []const u8,
    frame_offset: usize,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    const environment_length = readInt(u32, state, frame_offset + 4);
    const environment = state[frame_offset + 8 ..][0..environment_length];
    var current_slots = [_]Slot{.{}} ** 1024;
    _ = reducer_clause_v1.decodeEnvironmentSlots(
        image,
        constructor,
        environment,
        &current_slots,
        slots,
        workspace,
    ) catch |err| switch (err) {
        error.ScratchCapacity => return error.ScratchCapacity,
        else => return error.InvalidState,
    };
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

const suspensionContinuation = reducer_clause_v1.suspensionContinuation;

fn validateEnvironment(
    image: anytype,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    activation_slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!reducer_clause_v1.LoadedEnvironment {
    const loaded = try reducer_clause_v1.loadEnvironmentSlots(
        image,
        constructor,
        environment,
        slots,
        activation_slots,
        workspace,
    );
    if (loaded.activation_entry) |entry_constructor| {
        _ = constructorRecord(image, entry_constructor) catch
            return error.InvalidState;
    }
    return loaded;
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
