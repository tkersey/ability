const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const std = @import("std");

pub const Error = error{
    InvalidImage,
    InvalidState,
    InvalidInitialArgs,
    OutputCapacity,
    ExecutionBudgetExceeded,
    UnsupportedOperation,
    ScratchCapacity,
    CapacityExceeded,
};

pub const state_magic = "ABL_RNF2".*;
pub const state_header_length: usize = 68;
pub const frame_header_length: usize = 8;

pub const Outcome = union(enum) {
    requested: RequestView,
    yielded: []const u8,
    done: []const u8,
    failed: []const u8,
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

const Slot = struct {
    bytes: []const u8 = &.{},
    initialized: bool = false,
};

/// Construct the exact initial ABL_RNF2 State from canonical InitialArgs.
pub fn initial(
    image: image_v1.ValidatedImage,
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
        image.catalogs.initial_constructor_id,
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
    if (required > image.catalogs.envelope.header.maximum_state_bytes) {
        return error.InvalidImage;
    }
    if (output_state.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    appendBytes(output_state, &cursor, &state_magic);
    appendInt(u16, output_state, &cursor, image_v1.state_format_version);
    appendInt(u16, output_state, &cursor, image_v1.machine_abi_version);
    appendBytes(
        output_state,
        &cursor,
        &image.catalogs.envelope.header.machine_contract_digest,
    );
    appendInt(u64, output_state, &cursor, 0);
    appendInt(u64, output_state, &cursor, 0);
    appendInt(u32, output_state, &cursor, 1);
    appendInt(u32, output_state, &cursor, 0);
    appendInt(
        u32,
        output_state,
        &cursor,
        image.catalogs.initial_constructor_id,
    );
    appendInt(u32, output_state, &cursor, environment_length);
    if (environment_length != 0) {
        appendBytes(output_state, &cursor, initial_args);
    }
    if (cursor != required) return error.InvalidImage;
    try validateState(image, output_state[0..required], workspace);
    return required;
}

/// Validate canonical State framing and every constructor environment value.
pub fn validateState(
    image: image_v1.ValidatedImage,
    state: []const u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    if (state.len < state_header_length + frame_header_length or
        state.len > image.catalogs.envelope.header.maximum_state_bytes or
        !std.mem.eql(u8, state[0..8], &state_magic) or
        readInt(u16, state, 8) != image_v1.state_format_version or
        readInt(u16, state, 10) != image_v1.machine_abi_version or
        !std.mem.eql(
            u8,
            state[12..44],
            &image.catalogs.envelope.header.machine_contract_digest,
        ))
    {
        return error.InvalidState;
    }
    const sequence = readInt(u64, state, 44);
    const cumulative_fuel = readInt(u64, state, 52);
    const frame_count = readInt(u32, state, 60);
    if (readInt(u32, state, 64) != 0 or frame_count == 0 or
        frame_count > image.catalogs.envelope.header.maximum_frames or
        cumulative_fuel > image.catalogs.envelope.header.maximum_machine_fuel or
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
        validateEnvironment(
            image,
            constructor,
            state[cursor..environment_end],
            workspace,
        ) catch return error.InvalidState;
        cursor = environment_end;
    }
    if (cursor != state.len or (top_kind == 3 and sequence == 0)) {
        return error.InvalidState;
    }
}

pub fn current(
    image: image_v1.ValidatedImage,
    state: []const u8,
    output_payload: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!?RequestView {
    try validateState(image, state, workspace);
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

pub fn @"resume"(
    image: image_v1.ValidatedImage,
    state: []const u8,
    identity: RequestIdentity,
    response: []const u8,
    output_state: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!usize {
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
    for (0..argument_count) |index| {
        const argument_offset = 4 + index * 4;
        const target_value = readInt(u16, target, 24 + index * 2);
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
    const next_constructor = try transitionConstructor(
        image,
        segment_id,
        4,
        target_segment,
    );
    const successor = try encodeTopFrame(
        image,
        state,
        next_constructor,
        &slots,
        readInt(u64, state, 44),
        readInt(u64, state, 52),
        output_state,
    );
    try validateState(image, successor, workspace);
    return successor.len;
}

pub fn step(
    image: image_v1.ValidatedImage,
    state: []const u8,
    caller_fuel: *u64,
    output_state: []u8,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    const maximum_state: usize = image.catalogs.envelope.header.maximum_state_bytes;
    if (scratch.len < maximum_state) return error.ScratchCapacity;
    const temporary_state = scratch[0..maximum_state];
    const value_scratch = scratch[maximum_state..];
    var current_state = state;
    var remaining = caller_fuel.*;
    var next_uses_output = true;
    while (true) {
        const target = if (next_uses_output) output_state else temporary_state;
        const outcome = try stepSegment(
            image,
            current_state,
            &remaining,
            target,
            output_value,
            value_scratch,
            workspace,
        );
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

/// Execute one funded atomic segment.
fn stepSegment(
    image: image_v1.ValidatedImage,
    state: []const u8,
    caller_fuel: *u64,
    output_state: []u8,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!SegmentOutcome {
    const constructor_id = topConstructorId(state) catch
        return error.InvalidState;
    const constructor = constructorRecord(image, constructor_id) catch
        return error.InvalidState;
    const segment_id = readInt(u16, constructor, 12);
    const segment = segmentRecord(image, segment_id) catch
        return error.InvalidImage;
    const minimum_cost = readInt(u64, segment, 16);
    if (caller_fuel.* < minimum_cost) return .{ .yielded = state };
    try validateState(image, state, workspace);
    const cumulative = readInt(u64, state, 52);
    var slots = [_]Slot{.{}} ** 1024;
    var preflight_sizes = [_]usize{0} ** 1024;
    var initially_available = [_]bool{false} ** 1024;
    var scratch_cursor: usize = 0;
    try loadTopEnvironment(image, state, constructor, &slots, workspace);
    var cost = minimum_cost;
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    var environment_field_cursor: usize = 24;
    for (0..@as(u32, activation_count) + environment_count) |_| {
        const value = readInt(u16, constructor, environment_field_cursor);
        preflight_sizes[value] = slots[value].bytes.len;
        initially_available[value] = true;
        try addDynamicCostSize(image, value, preflight_sizes[value], &cost);
        environment_field_cursor += 8;
    }
    var cursor: usize = 24;
    const parameter_count = readInt(u16, segment, 10);
    const instruction_count = readInt(u32, segment, 12);
    cursor += @as(usize, parameter_count) * 2;
    for (0..instruction_count) |_| {
        const instruction_length = readInt(u32, segment, cursor);
        const operation = readInt(u16, segment, cursor + 6);
        const result = readInt(u16, segment, cursor + 8);
        const operand_count = readInt(u16, segment, cursor + 10);
        const immediate = readInt(u32, segment, cursor + 12);
        for (0..operand_count) |operand_index| {
            const operand = readInt(u16, segment, cursor + 16 + operand_index * 2);
            try addDynamicCostSize(
                image,
                operand,
                preflight_sizes[operand],
                &cost,
            );
        }
        const failure: ?u32 = switch (operation) {
            0 => blk: {
                slots[result] = .{
                    .bytes = try constantBytes(image, immediate),
                    .initialized = true,
                };
                break :blk null;
            },
            1 => blk: {
                if (operand_count != 1) return error.InvalidImage;
                const operand = readInt(u16, segment, cursor + 16);
                if (!slots[operand].initialized) return error.InvalidState;
                slots[result] = slots[operand];
                break :blk null;
            },
            2...23, 57 => try executeScalarOperation(
                image,
                segment[cursor .. cursor + instruction_length],
                result,
                &slots,
                scratch,
                &scratch_cursor,
            ),
            24...56 => try executeCompositeOperation(
                image,
                segment[cursor .. cursor + instruction_length],
                result,
                &slots,
                scratch,
                &scratch_cursor,
                workspace,
            ),
            else => return error.UnsupportedOperation,
        };
        if (slots[result].initialized) {
            preflight_sizes[result] = try preflightResultSize(
                image,
                segment,
                cursor,
                operation,
                result,
                operandsForInstruction(
                    segment[cursor .. cursor + instruction_length],
                ),
                &slots,
                &preflight_sizes,
                &initially_available,
            );
            try addDynamicCostSize(
                image,
                result,
                preflight_sizes[result],
                &cost,
            );
        }
        if (failure) |failure_tag| {
            if (caller_fuel.* < cost) return .{ .yielded = state };
            const failure_cumulative = std.math.add(u64, cumulative, cost) catch
                return error.ExecutionBudgetExceeded;
            if (failure_cumulative >
                image.catalogs.envelope.header.maximum_machine_fuel)
            {
                return error.ExecutionBudgetExceeded;
            }
            if (output_value.len < 4) return error.OutputCapacity;
            std.mem.writeInt(u32, output_value[0..4], failure_tag, .little);
            caller_fuel.* -= cost;
            return .{ .failed = output_value[0..4] };
        }
        cursor += instruction_length;
    }
    if (caller_fuel.* < cost) return .{ .yielded = state };
    const next_cumulative = std.math.add(u64, cumulative, cost) catch
        return error.ExecutionBudgetExceeded;
    if (next_cumulative > image.catalogs.envelope.header.maximum_machine_fuel) {
        return error.ExecutionBudgetExceeded;
    }
    const terminator_kind = segment[cursor + 4];
    const payload = cursor + 8;
    const outcome: SegmentOutcome = switch (terminator_kind) {
        0 => .{ .next = try transitionState(
            image,
            state,
            segment_id,
            0,
            segment[payload..],
            &slots,
            next_cumulative,
            output_state,
        ) },
        1 => blk: {
            const condition = readInt(u16, segment, payload);
            if (!slots[condition].initialized or slots[condition].bytes.len != 1) {
                return error.InvalidState;
            }
            const then_edge = payload + 4;
            const else_edge = then_edge + edgeLength(segment[then_edge..]);
            const selected = if (slots[condition].bytes[0] == 1)
                .{ @as(u8, 1), segment[then_edge..] }
            else
                .{ @as(u8, 2), segment[else_edge..] };
            break :blk .{ .next = try transitionState(
                image,
                state,
                segment_id,
                selected[0],
                selected[1],
                &slots,
                next_cumulative,
                output_state,
            ) };
        },
        2 => blk: {
            const suspension_kind = segment[payload];
            if (suspension_kind == 0) {
                const site_ordinal = readInt(u32, segment, payload + 4);
                const request_count = readInt(u16, segment, payload + 10);
                if (request_count != 1) return error.InvalidImage;
                const request_value = readInt(u16, segment, payload + 12);
                if (!slots[request_value].initialized) return error.InvalidState;
                const request_payload = slots[request_value].bytes;
                if (output_value.len < request_payload.len) {
                    return error.OutputCapacity;
                }
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
                @memcpy(output_value[0..request_payload.len], request_payload);
                const canonical_payload = output_value[0..request_payload.len];
                break :blk .{ .requested = .{
                    .state = parked,
                    .payload = canonical_payload,
                    .identity = try requestIdentity(
                        image,
                        parked,
                        await_constructor,
                        site_ordinal,
                        canonical_payload,
                        sequence,
                    ),
                } };
            }
            if (suspension_kind == 1) {
                const callee = suspensionCallee(segment, cursor);
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
                try applyValueEdge(image, callee, target_segment, &slots);
                const child_constructor = try transitionConstructor(
                    image,
                    segment_id,
                    3,
                    target_segment,
                );
                break :blk .{ .next = try appendFrame(
                    image,
                    parent,
                    child_constructor,
                    &slots,
                    output_state,
                ) };
            }
            if (suspension_kind != 2 and suspension_kind != 3) {
                return error.UnsupportedOperation;
            }
            const request_count = readInt(u16, segment, payload + 10);
            var continuation = payload + 12 + @as(usize, request_count) * 2;
            if (segment[continuation] != 0) return error.InvalidImage;
            continuation += 4;
            const next = try transitionState(
                image,
                state,
                segment_id,
                4,
                segment[continuation..],
                &slots,
                next_cumulative,
                output_state,
            );
            break :blk if (suspension_kind == 2)
                .{ .yielded = next }
            else
                .{ .next = next };
        },
        4 => blk: {
            const return_value = readInt(u16, segment, payload);
            if (!slots[return_value].initialized) return error.InvalidState;
            break :blk .{ .next = try returnToCaller(
                image,
                state,
                slots[return_value].bytes,
                next_cumulative,
                output_state,
                workspace,
            ) };
        },
        3 => blk: {
            const present = segment[payload] == 1;
            const value = readInt(u16, segment, payload + 2);
            const result = if (present) slots[value].bytes else &.{};
            if (present and !slots[value].initialized) return error.InvalidState;
            if (output_value.len < result.len) return error.OutputCapacity;
            @memcpy(output_value[0..result.len], result);
            break :blk .{ .done = output_value[0..result.len] };
        },
        5 => blk: {
            if (output_value.len < 4) return error.OutputCapacity;
            std.mem.writeInt(
                u32,
                output_value[0..4],
                readInt(u32, segment, payload),
                .little,
            );
            break :blk .{ .failed = output_value[0..4] };
        },
        6 => blk: {
            const value = readInt(u16, segment, payload);
            if (!slots[value].initialized) return error.InvalidState;
            if (output_value.len < slots[value].bytes.len) {
                return error.OutputCapacity;
            }
            @memcpy(output_value[0..slots[value].bytes.len], slots[value].bytes);
            break :blk .{ .failed = output_value[0..slots[value].bytes.len] };
        },
        else => return error.UnsupportedOperation,
    };
    caller_fuel.* -= cost;
    return outcome;
}

fn transitionState(
    image: image_v1.ValidatedImage,
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
    for (0..argument_count) |index| {
        const argument_offset = 4 + index * 4;
        if (edge[argument_offset] != 0) return error.UnsupportedOperation;
        const source_value = readInt(u16, edge, argument_offset + 2);
        const target_value = readInt(u16, target, 24 + index * 2);
        if (!slots[source_value].initialized) return error.InvalidState;
        slots[target_value] = slots[source_value];
    }
    const constructor_id = try transitionConstructor(
        image,
        source_segment,
        edge_kind,
        target_segment,
    );
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

fn encodeTopFrame(
    image: image_v1.ValidatedImage,
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
        required > image.catalogs.envelope.header.maximum_state_bytes)
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
    image: image_v1.ValidatedImage,
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
            return readInt(u32, bytes, offset + 8);
        }
    }
    return error.InvalidImage;
}

fn awaitingConstructor(
    image: image_v1.ValidatedImage,
    source_segment: u16,
) Error!u32 {
    const bytes = image.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..image.constructor_count) |id| {
        const length = readInt(u32, bytes, cursor);
        if (bytes[cursor + 8] == 3 and
            readInt(u16, bytes, cursor + 12) == source_segment)
        {
            return @intCast(id);
        }
        cursor += length;
    }
    return error.InvalidImage;
}

fn awaitCallConstructor(
    image: image_v1.ValidatedImage,
    source_segment: u16,
) Error!u32 {
    const bytes = image.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..image.constructor_count) |id| {
        const length = readInt(u32, bytes, cursor);
        if (bytes[cursor + 8] == 4 and bytes[cursor + 9] == 2 and
            readInt(u16, bytes, cursor + 12) == source_segment)
        {
            return @intCast(id);
        }
        cursor += length;
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
    image: image_v1.ValidatedImage,
    edge: []const u8,
    target_segment: u16,
    slots: *[1024]Slot,
) Error!void {
    const target = try segmentRecord(image, target_segment);
    const count = readInt(u16, edge, 2);
    if (count != readInt(u16, target, 10)) return error.InvalidImage;
    for (0..count) |index| {
        const argument = 4 + index * 4;
        if (edge[argument] != 0) return error.InvalidImage;
        const source_value = readInt(u16, edge, argument + 2);
        const target_value = readInt(u16, target, 24 + index * 2);
        if (!slots[source_value].initialized) return error.InvalidState;
        slots[target_value] = slots[source_value];
    }
}

fn appendFrame(
    image: image_v1.ValidatedImage,
    parent: []const u8,
    constructor_id: u32,
    slots: *const [1024]Slot,
    output: []u8,
) Error![]const u8 {
    const frame_count = readInt(u32, parent, 60);
    if (frame_count >= image.catalogs.envelope.header.maximum_frames) {
        return error.ExecutionBudgetExceeded;
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
        required > image.catalogs.envelope.header.maximum_state_bytes)
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
    image: image_v1.ValidatedImage,
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
    const argument_count = readInt(u16, continuation, 2);
    if (argument_count != readInt(u16, target_segment, 10)) {
        return error.InvalidImage;
    }
    for (0..argument_count) |index| {
        const argument = 4 + index * 4;
        const target_value = readInt(u16, target_segment, 24 + index * 2);
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
    const next_constructor = try transitionConstructor(
        image,
        parent_segment_id,
        4,
        target_segment_id,
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
    );
}

fn requestIdentity(
    image: image_v1.ValidatedImage,
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
    hasher.update(&image.catalogs.envelope.header.machine_contract_digest);
    hashInt(&hasher, u64, sequence);
    hashInt(&hasher, u32, constructor_id);
    hashInt(&hasher, u32, site_ordinal);
    hasher.update(&effect_site_digest);
    hasher.update(&payload_digest);
    hasher.update(&continuation_digest);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return .{
        .machine_contract_digest = image.catalogs.envelope.header.machine_contract_digest,
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
    image: image_v1.ValidatedImage,
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
    image: image_v1.ValidatedImage,
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
    image: image_v1.ValidatedImage,
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
        required > image.catalogs.envelope.header.maximum_state_bytes)
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
    image: image_v1.ValidatedImage,
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

fn loadFrameEnvironment(
    image: image_v1.ValidatedImage,
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
    image: image_v1.ValidatedImage,
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
    var cursor: usize = 24 + @as(usize, readInt(u16, segment, 10)) * 2;
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

fn constantBytes(
    image: image_v1.ValidatedImage,
    target: u32,
) Error![]const u8 {
    const bytes = image.catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..image.catalogs.constant_count) |id| {
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        if (id == target) return bytes[cursor..][0..length];
        cursor += length;
    }
    return error.InvalidImage;
}

fn executeScalarOperation(
    image: image_v1.ValidatedImage,
    instruction: []const u8,
    result: u16,
    slots: *[1024]Slot,
    scratch: []u8,
    scratch_cursor: *usize,
) Error!?u32 {
    const operation = readInt(u16, instruction, 6);
    const operand_count = readInt(u16, instruction, 10);
    var operands: [3]u16 = undefined;
    if (operand_count > operands.len) return error.InvalidImage;
    for (0..operand_count) |index| {
        operands[index] = readInt(u16, instruction, 16 + index * 2);
        if (!slots[operands[index]].initialized) return error.InvalidState;
    }
    if (operation == 23) {
        if (operand_count != 3 or slots[operands[0]].bytes.len != 1) {
            return error.InvalidImage;
        }
        slots[result] = slots[
            if (slots[operands[0]].bytes[0] == 1)
                operands[1]
            else
                operands[2]
        ];
        return null;
    }
    if (operation == 57) {
        if (operand_count != 1 or slots[operands[0]].bytes.len != 4) {
            return error.InvalidImage;
        }
        slots[result] = slots[operands[0]];
        return null;
    }
    const result_kind = try valueKind(image, result);
    if (operation >= 20 and operation <= 22) {
        const value = switch (operation) {
            20 => slots[operands[0]].bytes[0] == 0,
            21 => slots[operands[0]].bytes[0] == 1 and
                slots[operands[1]].bytes[0] == 1,
            22 => slots[operands[0]].bytes[0] == 1 or
                slots[operands[1]].bytes[0] == 1,
            else => unreachable,
        };
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, .bool, @intFromBool(value)),
            .initialized = true,
        };
        return null;
    }
    const left = try decodeInteger(
        try valueKind(image, operands[0]),
        slots[operands[0]].bytes,
    );
    if (operation == 2) {
        slots[result] = .{
            .bytes = try writeRaw(
                scratch,
                scratch_cursor,
                .bool,
                @intFromBool(left.raw == 0),
            ),
            .initialized = true,
        };
        return null;
    }
    if (operation == 19) {
        const converted = convertInteger(left, result_kind) orelse
            return try failureTag(image, "arithmetic_overflow");
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, converted),
            .initialized = true,
        };
        return null;
    }
    if (operation == 8) {
        const value = signedValue(left);
        const negated = std.math.sub(i128, 0, value) catch
            return try failureTag(image, "arithmetic_overflow");
        const raw = encodeSigned(negated, result_kind) orelse
            return try failureTag(image, "arithmetic_overflow");
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    if (operation == 15) {
        const raw = (~left.raw) & integerMask(left.bits);
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    const right = try decodeInteger(
        try valueKind(image, operands[1]),
        slots[operands[1]].bytes,
    );
    if (operation >= 9 and operation <= 14) {
        const relation = compareIntegers(left, right, operation);
        slots[result] = .{
            .bytes = try writeRaw(
                scratch,
                scratch_cursor,
                .bool,
                @intFromBool(relation),
            ),
            .initialized = true,
        };
        return null;
    }
    if (operation >= 16 and operation <= 18) {
        const raw = switch (operation) {
            16 => left.raw & right.raw,
            17 => left.raw | right.raw,
            18 => left.raw ^ right.raw,
            else => unreachable,
        } & integerMask(left.bits);
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    const raw = integerArithmetic(left, right, operation) catch |err| switch (err) {
        error.DivisionByZero => return try failureTag(image, "division_by_zero"),
        error.Overflow => return try failureTag(image, "arithmetic_overflow"),
    };
    slots[result] = .{
        .bytes = try writeRaw(scratch, scratch_cursor, result_kind, raw),
        .initialized = true,
    };
    return null;
}

fn executeCompositeOperation(
    image: image_v1.ValidatedImage,
    instruction: []const u8,
    result: u16,
    slots: *[1024]Slot,
    scratch: []u8,
    scratch_cursor: *usize,
    workspace: *image_v1.ValidationWorkspace,
) Error!?u32 {
    const operation = readInt(u16, instruction, 6);
    const operand_count = readInt(u16, instruction, 10);
    const immediate = readInt(u32, instruction, 12);
    var operands: [1024]u16 = undefined;
    if (operand_count > operands.len) return error.InvalidImage;
    for (0..operand_count) |index| {
        operands[index] = readInt(u16, instruction, 16 + index * 2);
        if (!slots[operands[index]].initialized) return error.InvalidState;
    }
    switch (operation) {
        24 => {
            var length: usize = 0;
            for (operands[0..operand_count]) |operand| {
                length = std.math.add(
                    usize,
                    length,
                    slots[operand].bytes.len,
                ) catch return error.ScratchCapacity;
            }
            const output = try allocateScratch(scratch, scratch_cursor, length);
            var cursor: usize = 0;
            for (operands[0..operand_count]) |operand| {
                @memcpy(
                    output[cursor..][0..slots[operand].bytes.len],
                    slots[operand].bytes,
                );
                cursor += slots[operand].bytes.len;
            }
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        25 => {
            const field = try productField(
                image,
                operands[0],
                slots[operands[0]].bytes,
                immediate,
                workspace,
            );
            slots[result] = .{ .bytes = field, .initialized = true };
        },
        26 => {
            const product = slots[operands[0]].bytes;
            const field = try productField(
                image,
                operands[0],
                product,
                immediate,
                workspace,
            );
            const prefix_length = @intFromPtr(field.ptr) - @intFromPtr(product.ptr);
            const replacement = slots[operands[1]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                product.len - field.len + replacement.len,
            );
            @memcpy(output[0..prefix_length], product[0..prefix_length]);
            @memcpy(output[prefix_length..][0..replacement.len], replacement);
            @memcpy(
                output[prefix_length + replacement.len ..],
                product[prefix_length + field.len ..],
            );
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        27 => {
            const node = try valueNode(image, result);
            if (node.kind != .sum) return error.InvalidImage;
            const case_count = readInt(u32, node.payload, 4);
            if (immediate >= case_count) return error.InvalidImage;
            const case_offset = 8 + @as(usize, immediate) * 8;
            const tag = readInt(u32, node.payload, case_offset);
            const payload = if (operand_count == 0) &.{} else slots[operands[0]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                4 + payload.len,
            );
            std.mem.writeInt(u32, output[0..4], tag, .little);
            @memcpy(output[4..], payload);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        28, 29 => {
            const node = try valueNode(image, operands[0]);
            if (node.kind != .sum) return error.InvalidImage;
            const case_count = readInt(u32, node.payload, 4);
            if (immediate >= case_count) return error.InvalidImage;
            const expected = readInt(
                u32,
                node.payload,
                8 + @as(usize, immediate) * 8,
            );
            const matches = readInt(u32, slots[operands[0]].bytes, 0) == expected;
            if (operation == 28) {
                slots[result] = .{
                    .bytes = try writeRaw(
                        scratch,
                        scratch_cursor,
                        .bool,
                        @intFromBool(matches),
                    ),
                    .initialized = true,
                };
            } else {
                if (!matches) return try failureTag(image, "invalid_variant");
                slots[result] = .{
                    .bytes = slots[operands[0]].bytes[4..],
                    .initialized = true,
                };
            }
        },
        30 => {
            const output = try allocateScratch(scratch, scratch_cursor, 1);
            output[0] = 0;
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        31 => {
            const payload = slots[operands[0]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                1 + payload.len,
            );
            output[0] = 1;
            @memcpy(output[1..], payload);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        32 => {
            slots[result] = .{
                .bytes = try writeRaw(
                    scratch,
                    scratch_cursor,
                    .bool,
                    @intFromBool(slots[operands[0]].bytes[0] == 1),
                ),
                .initialized = true,
            };
        },
        33, 41, 49 => {
            const output = try allocateScratch(scratch, scratch_cursor, 4);
            @memset(output, 0);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        37 => {
            const vector = slots[operands[0]].bytes;
            const element = slots[operands[1]].bytes;
            const schema = try valueNode(image, operands[0]);
            const length = readInt(u32, vector, 0);
            if (length >= readInt(u32, schema.payload, 0)) {
                return try failureTag(image, "capacity_exceeded");
            }
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                vector.len + element.len,
            );
            std.mem.writeInt(u32, output[0..4], length + 1, .little);
            @memcpy(output[4..vector.len], vector[4..]);
            @memcpy(output[vector.len..], element);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        34, 53, 54 => {
            const length = readInt(u32, slots[operands[0]].bytes, 0);
            slots[result] = .{
                .bytes = try writeRaw(
                    scratch,
                    scratch_cursor,
                    .u32,
                    length,
                ),
                .initialized = true,
            };
        },
        35 => {
            const index = readInt(u32, slots[operands[1]].bytes, 0);
            const element = vectorElement(
                image,
                operands[0],
                slots[operands[0]].bytes,
                index,
                workspace,
            ) catch return try failureTag(image, "invalid_index");
            slots[result] = .{ .bytes = element, .initialized = true };
        },
        36 => {
            const vector = slots[operands[0]].bytes;
            const index = readInt(u32, slots[operands[1]].bytes, 0);
            const element = vectorElement(
                image,
                operands[0],
                vector,
                index,
                workspace,
            ) catch return try failureTag(image, "invalid_index");
            const prefix_length = @intFromPtr(element.ptr) - @intFromPtr(vector.ptr);
            const replacement = slots[operands[2]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                vector.len - element.len + replacement.len,
            );
            @memcpy(output[0..prefix_length], vector[0..prefix_length]);
            @memcpy(output[prefix_length..][0..replacement.len], replacement);
            @memcpy(
                output[prefix_length + replacement.len ..],
                vector[prefix_length + element.len ..],
            );
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        38 => {
            const vector = slots[operands[0]].bytes;
            const length = readInt(u32, vector, 0);
            const popped = if (length == 0)
                null
            else
                try vectorElement(
                    image,
                    operands[0],
                    vector,
                    length - 1,
                    workspace,
                );
            const prefix_length = if (popped) |element|
                @intFromPtr(element.ptr) - @intFromPtr(vector.ptr)
            else
                vector.len;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                prefix_length + 1 + if (popped) |element| element.len else 0,
            );
            std.mem.writeInt(
                u32,
                output[0..4],
                if (length == 0) 0 else length - 1,
                .little,
            );
            @memcpy(output[4..prefix_length], vector[4..prefix_length]);
            output[prefix_length] = @intFromBool(popped != null);
            if (popped) |element| @memcpy(output[prefix_length + 1 ..], element);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        39 => {
            const vector = slots[operands[0]].bytes;
            const current_length = readInt(u32, vector, 0);
            const requested = readInt(u32, slots[operands[1]].bytes, 0);
            if (requested >= current_length) {
                slots[result] = slots[operands[0]];
            } else {
                const first_removed = try vectorElement(
                    image,
                    operands[0],
                    vector,
                    requested,
                    workspace,
                );
                const prefix_length = @intFromPtr(first_removed.ptr) -
                    @intFromPtr(vector.ptr);
                const output = try allocateScratch(
                    scratch,
                    scratch_cursor,
                    prefix_length,
                );
                @memcpy(output, vector[0..prefix_length]);
                std.mem.writeInt(u32, output[0..4], requested, .little);
                slots[result] = .{ .bytes = output, .initialized = true };
            }
        },
        40 => {
            const output = try allocateScratch(scratch, scratch_cursor, 4);
            @memset(output, 0);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        42, 50 => {
            const destination = slots[operands[0]].bytes;
            const suffix = slots[operands[1]].bytes;
            const destination_length = readInt(u32, destination, 0);
            const suffix_length = readInt(u32, suffix, 0);
            const combined = std.math.add(
                u32,
                destination_length,
                suffix_length,
            ) catch return try failureTag(image, "capacity_exceeded");
            const schema = try valueNode(image, result);
            if (combined > readInt(u32, schema.payload, 0)) {
                return try failureTag(image, "capacity_exceeded");
            }
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                4 + @as(usize, combined),
            );
            std.mem.writeInt(u32, output[0..4], combined, .little);
            @memcpy(
                output[4..][0..destination_length],
                destination[4..][0..destination_length],
            );
            @memcpy(
                output[4 + destination_length ..][0..suffix_length],
                suffix[4..][0..suffix_length],
            );
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        43 => {
            const raw = readInt(u32, slots[operands[1]].bytes, 0);
            if (raw > std.math.maxInt(u21)) {
                return try failureTag(image, "invalid_utf8");
            }
            var encoded: [4]u8 = undefined;
            const encoded_length = std.unicode.utf8Encode(
                @intCast(raw),
                &encoded,
            ) catch return try failureTag(image, "invalid_utf8");
            slots[result] = .{
                .bytes = appendSequence(
                    image,
                    result,
                    slots[operands[0]].bytes,
                    &.{encoded[0..encoded_length]},
                    scratch,
                    scratch_cursor,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try failureTag(image, "capacity_exceeded"),
                    else => return err,
                },
                .initialized = true,
            };
        },
        44, 45 => {
            const integer = try decodeInteger(
                try valueKind(image, operands[1]),
                slots[operands[1]].bytes,
            );
            var formatted_storage: [20]u8 = undefined;
            const formatted = if (operation == 44)
                std.fmt.bufPrint(
                    &formatted_storage,
                    "{d}",
                    .{integer.raw},
                ) catch return try failureTag(image, "capacity_exceeded")
            else
                std.fmt.bufPrint(
                    &formatted_storage,
                    "{d}",
                    .{signedValue(integer)},
                ) catch return try failureTag(image, "capacity_exceeded");
            slots[result] = .{
                .bytes = appendSequence(
                    image,
                    result,
                    slots[operands[0]].bytes,
                    &.{formatted},
                    scratch,
                    scratch_cursor,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try failureTag(image, "capacity_exceeded"),
                    else => return err,
                },
                .initialized = true,
            };
        },
        46, 51 => {
            const source = slots[operands[0]].bytes;
            const start = readInt(u32, slots[operands[1]].bytes, 0);
            const end = readInt(u32, slots[operands[2]].bytes, 0);
            const source_length = readInt(u32, source, 0);
            if (start > end or end > source_length) {
                return try failureTag(image, "capacity_exceeded");
            }
            const copied = source[4 + start .. 4 + end];
            const node = try valueNode(image, result);
            if (copied.len > readInt(u32, node.payload, 0)) {
                return try failureTag(image, "capacity_exceeded");
            }
            if (operation == 46 and !std.unicode.utf8ValidateSlice(copied)) {
                return try failureTag(image, "invalid_utf8");
            }
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                4 + copied.len,
            );
            std.mem.writeInt(u32, output[0..4], @intCast(copied.len), .little);
            @memcpy(output[4..], copied);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        47, 52 => {
            const left = sequencePayload(slots[operands[0]].bytes);
            const right = sequencePayload(slots[operands[1]].bytes);
            const ordered: i8 = switch (std.mem.order(u8, left, right)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
            slots[result] = .{
                .bytes = try writeRaw(
                    scratch,
                    scratch_cursor,
                    .i8,
                    @as(u8, @bitCast(ordered)),
                ),
                .initialized = true,
            };
        },
        48, 56 => {
            slots[result] = .{
                .bytes = appendSequence(
                    image,
                    result,
                    slots[operands[0]].bytes,
                    &.{
                        sequencePayload(slots[operands[1]].bytes),
                        sequencePayload(slots[operands[2]].bytes),
                    },
                    scratch,
                    scratch_cursor,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try failureTag(image, "capacity_exceeded"),
                    else => return err,
                },
                .initialized = true,
            };
        },
        55 => {
            slots[result] = .{
                .bytes = appendSequence(
                    image,
                    result,
                    slots[operands[0]].bytes,
                    &.{slots[operands[1]].bytes[0..1]},
                    scratch,
                    scratch_cursor,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try failureTag(image, "capacity_exceeded"),
                    else => return err,
                },
                .initialized = true,
            };
        },
        else => return error.UnsupportedOperation,
    }
    return null;
}

fn appendSequence(
    image: image_v1.ValidatedImage,
    result_value: u16,
    prefix: []const u8,
    suffixes: []const []const u8,
    scratch: []u8,
    scratch_cursor: *usize,
) Error![]const u8 {
    var logical_length: usize = readInt(u32, prefix, 0);
    for (suffixes) |suffix| {
        logical_length = std.math.add(usize, logical_length, suffix.len) catch
            return error.CapacityExceeded;
    }
    const node = try valueNode(image, result_value);
    if (logical_length > readInt(u32, node.payload, 0)) {
        return error.CapacityExceeded;
    }
    const output = try allocateScratch(
        scratch,
        scratch_cursor,
        4 + logical_length,
    );
    std.mem.writeInt(u32, output[0..4], @intCast(logical_length), .little);
    const prefix_payload = sequencePayload(prefix);
    @memcpy(output[4..][0..prefix_payload.len], prefix_payload);
    var cursor = 4 + prefix_payload.len;
    for (suffixes) |suffix| {
        @memcpy(output[cursor..][0..suffix.len], suffix);
        cursor += suffix.len;
    }
    return output;
}

fn sequencePayload(value: []const u8) []const u8 {
    return value[4..][0..readInt(u32, value, 0)];
}

fn productField(
    image: image_v1.ValidatedImage,
    product_value: u16,
    product: []const u8,
    field_index: u32,
    workspace: *image_v1.ValidationWorkspace,
) Error![]const u8 {
    const node = try valueNode(image, product_value);
    if (node.kind != .product or field_index >= readInt(u32, node.payload, 0)) {
        return error.InvalidImage;
    }
    var cursor: usize = 0;
    for (0..field_index) |index| {
        const schema_id = readInt(u32, node.payload, 4 + index * 4);
        cursor += dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema_id,
            product[cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
    }
    const schema_id = readInt(u32, node.payload, 4 + @as(usize, field_index) * 4);
    const length = dynamic_value_v1.validateValuePrefix(
        image.catalogs.schemas,
        schema_id,
        product[cursor..],
        &workspace.value_tasks,
    ) catch return error.InvalidState;
    return product[cursor..][0..length];
}

fn vectorElement(
    image: image_v1.ValidatedImage,
    vector_value: u16,
    vector: []const u8,
    target: u32,
    workspace: *image_v1.ValidationWorkspace,
) Error![]const u8 {
    const node = try valueNode(image, vector_value);
    if (node.kind != .vector) return error.InvalidImage;
    const length = readInt(u32, vector, 0);
    if (target >= length) return error.InvalidState;
    const element_schema = readInt(u32, node.payload, 4);
    var cursor: usize = 4;
    for (0..target) |_| {
        cursor += dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            element_schema,
            vector[cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
    }
    const element_length = dynamic_value_v1.validateValuePrefix(
        image.catalogs.schemas,
        element_schema,
        vector[cursor..],
        &workspace.value_tasks,
    ) catch return error.InvalidState;
    return vector[cursor..][0..element_length];
}

fn addDynamicCost(
    image: image_v1.ValidatedImage,
    value: u16,
    slot: Slot,
    cost: *u64,
) Error!void {
    if (!slot.initialized) return error.InvalidState;
    try addDynamicCostSize(image, value, slot.bytes.len, cost);
}

fn addDynamicCostSize(
    image: image_v1.ValidatedImage,
    value: u16,
    encoded_size: u64,
    cost: *u64,
) Error!void {
    const node = try valueNode(image, value);
    if (node.minimum_encoded_size == node.maximum_encoded_size) return;
    const dynamic = std.math.divCeil(u64, encoded_size, 16) catch
        return error.ExecutionBudgetExceeded;
    cost.* = std.math.add(u64, cost.*, dynamic) catch
        return error.ExecutionBudgetExceeded;
}

fn operandsForInstruction(instruction: []const u8) []const u8 {
    const count = readInt(u16, instruction, 10);
    return instruction[16..][0 .. @as(usize, count) * 2];
}

fn preflightResultSize(
    image: image_v1.ValidatedImage,
    segment: []const u8,
    instruction_offset: usize,
    operation: u16,
    result: u16,
    operand_bytes: []const u8,
    slots: *const [1024]Slot,
    sizes: *const [1024]usize,
    initially_available: *const [1024]bool,
) Error!usize {
    const maximum: usize = @intCast((try valueNode(image, result)).maximum_encoded_size);
    const size = struct {
        fn get(bytes: []const u8, index: usize, values: *const [1024]usize) usize {
            return values[readInt(u16, bytes, index * 2)];
        }
    }.get;
    return switch (operation) {
        0, 1, 2...22, 28, 32, 34, 40, 47, 52, 53, 54, 57 => slots[result].bytes.len,
        23 => @max(size(operand_bytes, 1, sizes), size(operand_bytes, 2, sizes)),
        24 => blk: {
            var total: usize = 0;
            var index: usize = 0;
            while (index < operand_bytes.len) : (index += 2) {
                total +|= sizes[readInt(u16, operand_bytes, index)];
            }
            break :blk @min(maximum, total);
        },
        25 => @intCast(preflightProductFieldSize(
            segment,
            instruction_offset,
            readInt(u16, operand_bytes, 0),
            readInt(u32, segment, instruction_offset + 12),
            sizes,
        ) orelse maximum),
        35 => if (initially_available[readInt(u16, operand_bytes, 0)] and
            initially_available[readInt(u16, operand_bytes, 2)])
            slots[result].bytes.len
        else
            maximum,
        26, 29, 36, 38 => maximum,
        27 => @min(
            maximum,
            4 + if (operand_bytes.len == 0) 0 else size(operand_bytes, 0, sizes),
        ),
        30 => 1,
        31 => @min(maximum, 1 + size(operand_bytes, 0, sizes)),
        33, 41, 49 => 4,
        37 => @min(
            maximum,
            size(operand_bytes, 0, sizes) +| size(operand_bytes, 1, sizes),
        ),
        39 => @min(maximum, size(operand_bytes, 0, sizes)),
        42, 50 => @min(
            maximum,
            size(operand_bytes, 0, sizes) +|
                (size(operand_bytes, 1, sizes) -| 4),
        ),
        43 => @min(maximum, size(operand_bytes, 0, sizes) +| 4),
        44, 45 => @min(maximum, size(operand_bytes, 0, sizes) +| 20),
        46, 51 => @min(maximum, size(operand_bytes, 0, sizes)),
        48, 56 => @min(
            maximum,
            size(operand_bytes, 0, sizes) +|
                (size(operand_bytes, 1, sizes) -| 4) +|
                (size(operand_bytes, 2, sizes) -| 4),
        ),
        55 => @min(maximum, size(operand_bytes, 0, sizes) +| 1),
        else => return error.UnsupportedOperation,
    };
}

fn preflightProductFieldSize(
    segment: []const u8,
    instruction_offset: usize,
    product_value: u16,
    field_index: u32,
    sizes: *const [1024]usize,
) ?usize {
    var current_value = product_value;
    var current_limit = instruction_offset;
    while (true) {
        var cursor: usize = 24 + @as(usize, readInt(u16, segment, 10)) * 2;
        var definition: ?usize = null;
        while (cursor < current_limit) {
            const length = readInt(u32, segment, cursor);
            if (readInt(u16, segment, cursor + 8) == current_value) {
                definition = cursor;
                break;
            }
            cursor += length;
        }
        const offset = definition orelse return null;
        switch (readInt(u16, segment, offset + 6)) {
            1 => {
                current_value = readInt(u16, segment, offset + 16);
                current_limit = offset;
            },
            24 => return sizes[
                readInt(
                    u16,
                    segment,
                    offset + 16 + @as(usize, field_index) * 2,
                )
            ],
            26 => {
                if (readInt(u32, segment, offset + 12) == field_index) {
                    return sizes[readInt(u16, segment, offset + 18)];
                }
                current_value = readInt(u16, segment, offset + 16);
                current_limit = offset;
            },
            else => return null,
        }
    }
}

fn valueNode(
    image: image_v1.ValidatedImage,
    value: u16,
) Error!dynamic_value_v1.Node {
    const schema_id = image.catalogs.valueSchemaId(value) catch
        return error.InvalidImage;
    return image.catalogs.schemas.node(schema_id) catch error.InvalidImage;
}

fn allocateScratch(
    scratch: []u8,
    cursor: *usize,
    length: usize,
) Error![]u8 {
    if (cursor.* > scratch.len or length > scratch.len - cursor.*) {
        return error.ScratchCapacity;
    }
    const result = scratch[cursor.*..][0..length];
    cursor.* += length;
    return result;
}

const Integer = struct {
    raw: u64,
    bits: u8,
    signed: bool,
};

fn valueKind(
    image: image_v1.ValidatedImage,
    value: u16,
) Error!dynamic_value_v1.Kind {
    const schema_id = image.catalogs.valueSchemaId(value) catch
        return error.InvalidImage;
    return (image.catalogs.schemas.node(schema_id) catch
        return error.InvalidImage).kind;
}

fn decodeInteger(kind: dynamic_value_v1.Kind, bytes: []const u8) Error!Integer {
    const bits: u8 = switch (kind) {
        .i8, .u8 => 8,
        .i16, .u16 => 16,
        .i32, .u32 => 32,
        .i64, .u64 => 64,
        else => return error.InvalidImage,
    };
    if (bytes.len != bits / 8) return error.InvalidState;
    var raw: u64 = 0;
    for (bytes, 0..) |byte, index| raw |= @as(u64, byte) << @intCast(index * 8);
    return .{
        .raw = raw,
        .bits = bits,
        .signed = switch (kind) {
            .i8, .i16, .i32, .i64 => true,
            else => false,
        },
    };
}

fn signedValue(value: Integer) i128 {
    if (!value.signed) return value.raw;
    if (value.bits == 64) return @as(i64, @bitCast(value.raw));
    const sign = @as(u64, 1) << @intCast(value.bits - 1);
    return if (value.raw & sign == 0)
        value.raw
    else
        @as(i128, value.raw) - (@as(i128, 1) << @intCast(value.bits));
}

fn integerArithmetic(
    left: Integer,
    right: Integer,
    operation: u16,
) error{ DivisionByZero, Overflow }!u64 {
    if (left.signed) {
        const a = signedValue(left);
        const b = signedValue(right);
        if ((operation == 6 or operation == 7) and b == 0) {
            return error.DivisionByZero;
        }
        const value = switch (operation) {
            3 => std.math.add(i128, a, b) catch return error.Overflow,
            4 => std.math.sub(i128, a, b) catch return error.Overflow,
            5 => std.math.mul(i128, a, b) catch return error.Overflow,
            6 => @divTrunc(a, b),
            7 => @rem(a, b),
            else => return error.Overflow,
        };
        return encodeSigned(value, integerKind(left)) orelse error.Overflow;
    }
    const a: u128 = left.raw;
    const b: u128 = right.raw;
    if ((operation == 6 or operation == 7) and b == 0) {
        return error.DivisionByZero;
    }
    const value: u128 = switch (operation) {
        3 => a + b,
        4 => if (a < b) return error.Overflow else a - b,
        5 => a * b,
        6 => a / b,
        7 => a % b,
        else => return error.Overflow,
    };
    if (value > integerMask(left.bits)) return error.Overflow;
    return @intCast(value);
}

fn compareIntegers(left: Integer, right: Integer, operation: u16) bool {
    if (left.signed) {
        const a = signedValue(left);
        const b = signedValue(right);
        return switch (operation) {
            9 => a == b,
            10 => a != b,
            11 => a < b,
            12 => a <= b,
            13 => a > b,
            14 => a >= b,
            else => unreachable,
        };
    }
    return switch (operation) {
        9 => left.raw == right.raw,
        10 => left.raw != right.raw,
        11 => left.raw < right.raw,
        12 => left.raw <= right.raw,
        13 => left.raw > right.raw,
        14 => left.raw >= right.raw,
        else => unreachable,
    };
}

fn convertInteger(value: Integer, kind: dynamic_value_v1.Kind) ?u64 {
    const target = integerShape(kind) orelse return null;
    if (target.signed) return encodeSigned(signedValue(value), kind);
    const source = signedValue(value);
    if (source < 0 or @as(u128, @intCast(source)) > integerMask(target.bits)) {
        return null;
    }
    return @intCast(source);
}

fn encodeSigned(value: i128, kind: dynamic_value_v1.Kind) ?u64 {
    const target = integerShape(kind) orelse return null;
    if (!target.signed) {
        if (value < 0 or @as(u128, @intCast(value)) > integerMask(target.bits)) {
            return null;
        }
        return @intCast(value);
    }
    const minimum = -(@as(i128, 1) << @intCast(target.bits - 1));
    const maximum = (@as(i128, 1) << @intCast(target.bits - 1)) - 1;
    if (value < minimum or value > maximum) return null;
    if (target.bits == 64) return @bitCast(@as(i64, @intCast(value)));
    return @intCast(if (value < 0)
        value + (@as(i128, 1) << @intCast(target.bits))
    else
        value);
}

fn integerShape(kind: dynamic_value_v1.Kind) ?Integer {
    return switch (kind) {
        .i8 => .{ .raw = 0, .bits = 8, .signed = true },
        .i16 => .{ .raw = 0, .bits = 16, .signed = true },
        .i32 => .{ .raw = 0, .bits = 32, .signed = true },
        .i64 => .{ .raw = 0, .bits = 64, .signed = true },
        .u8 => .{ .raw = 0, .bits = 8, .signed = false },
        .u16 => .{ .raw = 0, .bits = 16, .signed = false },
        .u32 => .{ .raw = 0, .bits = 32, .signed = false },
        .u64 => .{ .raw = 0, .bits = 64, .signed = false },
        else => null,
    };
}

fn integerKind(value: Integer) dynamic_value_v1.Kind {
    return if (value.signed)
        switch (value.bits) {
            8 => .i8,
            16 => .i16,
            32 => .i32,
            64 => .i64,
            else => unreachable,
        }
    else switch (value.bits) {
        8 => .u8,
        16 => .u16,
        32 => .u32,
        64 => .u64,
        else => unreachable,
    };
}

fn integerMask(bits: u8) u64 {
    return if (bits == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(bits)) - 1;
}

fn writeRaw(
    scratch: []u8,
    cursor: *usize,
    kind: dynamic_value_v1.Kind,
    raw: u64,
) Error![]const u8 {
    const length: usize = if (kind == .bool) 1 else (integerShape(kind) orelse return error.InvalidImage).bits / 8;
    if (cursor.* > scratch.len or length > scratch.len - cursor.*) {
        return error.ScratchCapacity;
    }
    const result = scratch[cursor.*..][0..length];
    for (result, 0..) |*byte, index| byte.* = @truncate(raw >> @intCast(index * 8));
    cursor.* += length;
    return result;
}

fn failureTag(image: image_v1.ValidatedImage, name: []const u8) Error!u32 {
    const bytes = image.catalogs.envelope.section(.failures);
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |_| {
        const tag = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const candidate = bytes[cursor..][0..length];
        cursor += length;
        if (std.mem.eql(u8, candidate, name)) return tag;
    }
    return error.InvalidImage;
}

fn validateEnvironment(
    image: image_v1.ValidatedImage,
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
    try validatePathInvariants(image, constructor, &slots);
}

fn validatePathInvariants(
    image: image_v1.ValidatedImage,
    constructor: []const u8,
    slots: *const [1024]Slot,
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
            15 => blk: {
                const value = readInt(u16, constructor, payload);
                if (!slots[value].initialized) break :blk false;
                var zero = true;
                for (slots[value].bytes) |byte| zero = zero and byte == 0;
                break :blk zero == (constructor[payload + 2] == 1);
            },
            17 => blk: {
                const left_id = readInt(u16, constructor, payload);
                const right_id = readInt(u16, constructor, payload + 2);
                if (!slots[left_id].initialized or !slots[right_id].initialized) {
                    break :blk false;
                }
                const left = decodeInteger(
                    try valueKind(image, left_id),
                    slots[left_id].bytes,
                ) catch break :blk false;
                const right = decodeInteger(
                    try valueKind(image, right_id),
                    slots[right_id].bytes,
                ) catch break :blk false;
                const operation: u16 = 9 + constructor[payload + 4];
                break :blk compareIntegers(left, right, operation) ==
                    (constructor[payload + 5] == 1);
            },
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
            else => true,
        };
        if (!accepted) return error.InvalidState;
        cursor += length;
    }
}

fn algebraicCaseIndex(
    image: image_v1.ValidatedImage,
    value: u16,
    bytes: []const u8,
) Error!u16 {
    const node = try valueNode(image, value);
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
    image: image_v1.ValidatedImage,
    target: u32,
) Error![]const u8 {
    const bytes = image.catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..image.constructor_count) |id| {
        const length = readInt(u32, bytes, cursor);
        const end = cursor + length;
        if (id == target) return bytes[cursor..end];
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
