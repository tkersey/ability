const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const program_semantics_v1 = @import("program_semantics_v1");
const std = @import("std");

comptime {
    _ = program_semantics_v1.WireOperation;
    _ = program_semantics_v1.WireTerminator;
}

pub const Error = error{
    InvalidImage,
    InvalidBindings,
    InvalidState,
    OutputCapacity,
    UnsupportedOperation,
    ScratchCapacity,
    CapacityExceeded,
};

pub const Slot = struct {
    bytes: []const u8 = &.{},
    initialized: bool = false,
};

/// Invocation-local operational capacity evidence. Semantic evaluation records
/// the exact bytes required at the producer before returning a capacity error.
pub const CapacityTracker = struct {
    output_bytes: *u64,
    scratch_bytes: *u64,

    pub fn requireOutput(
        self: *@This(),
        available: usize,
        required: usize,
    ) Error!void {
        self.output_bytes.* = @max(self.output_bytes.*, required);
        if (available < required) return error.OutputCapacity;
    }

    pub fn requireScratch(
        self: *@This(),
        available: usize,
        required: u64,
    ) Error!void {
        self.scratch_bytes.* = @max(self.scratch_bytes.*, required);
        if (@as(u64, available) < required) return error.ScratchCapacity;
    }
};

/// Apply one Control IR edge as a parallel assignment from the pre-edge slot
/// store. Resume/call-return edges may inject exactly one supplied value.
pub fn applyEdge(
    constructor: []const u8,
    target_segment: []const u8,
    edge: []const u8,
    injected_value: ?[]const u8,
    slots: *[1024]Slot,
) Error!void {
    const argument_count = readInt(u16, edge, 2);
    if (argument_count != readInt(u16, target_segment, 10)) {
        return error.InvalidImage;
    }
    const source_slots = slots.*;
    for (0..argument_count) |index| {
        const argument = 4 + index * 4;
        const target_value = readInt(
            u16,
            target_segment,
            image_v1.segment_prefix_length + index * 2,
        );
        if (!constructorRetainsValue(constructor, target_value)) continue;
        switch (edge[argument]) {
            0 => {
                const source_value = readInt(u16, edge, argument + 2);
                if (!source_slots[source_value].initialized) {
                    return error.InvalidState;
                }
                slots[target_value] = source_slots[source_value];
            },
            1 => slots[target_value] = .{
                .bytes = injected_value orelse
                    return error.UnsupportedOperation,
                .initialized = true,
            },
            else => return error.UnsupportedOperation,
        }
    }
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

/// Validate the semantic relationship between one parked call parent and its
/// active child. Callers provide the ABI-specific call-entry constructor id;
/// all remaining stack-pair meaning is shared across Machine and Process.
pub fn validateStackPair(
    image: anytype,
    parent_constructor: []const u8,
    parent_slots: *const [1024]Slot,
    child_constructor: []const u8,
    child_activation_entry: ?u32,
    child_slots: *const [1024]Slot,
    expected_call_entry_constructor: u32,
) Error!void {
    if (parent_constructor.len < 24 or
        parent_constructor[8] != 4 or
        parent_constructor[9] != 2 or
        child_activation_entry != expected_call_entry_constructor)
    {
        return error.InvalidState;
    }
    const parent_segment_id = readInt(u16, parent_constructor, 12);
    const parent_segment = try segmentRecord(image, parent_segment_id);
    const terminator = segmentTerminatorOffset(parent_segment);
    if (parent_segment[terminator + 4] != 2 or
        parent_segment[terminator + 8] != 1)
    {
        return error.InvalidState;
    }
    const payload = terminator + 8;
    const callee_function = readInt(u16, parent_segment, payload + 8);
    const callee = suspensionCallee(parent_segment, terminator);
    if (callee.len < 4) return error.InvalidState;
    const target_segment_id = readInt(u16, callee, 0);
    const child_segment = try segmentRecord(
        image,
        readInt(u16, child_constructor, 12),
    );
    const target_segment = try segmentRecord(image, target_segment_id);
    if (readInt(u16, child_segment, 6) != callee_function or
        readInt(u16, child_constructor, 10) & 1 == 0)
    {
        return error.InvalidState;
    }
    const count = readInt(u16, callee, 2);
    if (count != readInt(u16, target_segment, 10)) {
        return error.InvalidState;
    }
    for (0..count) |index| {
        const argument = 4 + index * 4;
        if (callee[argument] != 0) return error.InvalidState;
        const source_value = readInt(u16, callee, argument + 2);
        const target_value = readInt(
            u16,
            target_segment,
            image_v1.segment_prefix_length + index * 2,
        );
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

pub fn productConstructMatches(
    expected: []const u8,
    operand_bytes: []const u8,
    operand_count: u16,
    slots: *const [1024]Slot,
) bool {
    if (operand_bytes.len != @as(usize, operand_count) * 2) return false;
    var cursor: usize = 0;
    for (0..operand_count) |index| {
        const operand = std.mem.readInt(
            u16,
            operand_bytes[index * 2 ..][0..2],
            .little,
        );
        if (operand >= slots.len or !slots[operand].initialized) return false;
        const end = std.math.add(
            usize,
            cursor,
            slots[operand].bytes.len,
        ) catch return false;
        if (end > expected.len or !std.mem.eql(
            u8,
            expected[cursor..end],
            slots[operand].bytes,
        )) return false;
        cursor = end;
    }
    return cursor == expected.len;
}

/// One finite program-owned reducer-clause result.
pub const ClauseOutcome = union(enum) {
    progressed: struct { edge_kind: u8, edge: []const u8 },
    call: []const u8,
    return_to_caller: []const u8,
    requested: struct { site_ordinal: u32, payload: []const u8 },
    explicit_yield: []const u8,
    completed: []const u8,
    authored_failure: []const u8,
};

/// Evaluate exactly one finite BPI1 reducer clause.
/// Callers supply the constructor bindings; the result contains only program
/// structure and authored value/failure data.
pub fn evaluateClause(
    image: image_v1.ValidatedImage,
    segment_id: u16,
    slots: *[1024]Slot,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
    capacity: ?*CapacityTracker,
) Error!ClauseOutcome {
    try initializeZeroWidthSlots(image, slots);
    const segment = segmentRecord(image, segment_id) catch
        return error.InvalidImage;
    var cursor: usize = image_v1.segment_prefix_length +
        @as(usize, readInt(u16, segment, 10)) * 2;
    const instruction_count = readInt(u32, segment, 12);
    var scratch_cursor: usize = 0;
    for (0..instruction_count) |_| {
        const instruction_length = readInt(u32, segment, cursor);
        const operation = readInt(u16, segment, cursor + 6);
        const result = readInt(u16, segment, cursor + 8);
        const operand_count = readInt(u16, segment, cursor + 10);
        const immediate = readInt(u32, segment, cursor + 12);
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
                if (!slots[operand].initialized) return error.InvalidBindings;
                slots[result] = slots[operand];
                break :blk null;
            },
            2...23, 57 => try executeScalarOperation(
                image,
                segment[cursor .. cursor + instruction_length],
                result,
                slots,
                scratch,
                &scratch_cursor,
                capacity,
            ),
            24...56 => try executeCompositeOperation(
                image,
                segment[cursor .. cursor + instruction_length],
                result,
                slots,
                scratch,
                &scratch_cursor,
                workspace,
                capacity,
            ),
            else => return error.UnsupportedOperation,
        };
        if (failure) |failure_tag| {
            try requireOutput(capacity, output_value.len, 4);
            std.mem.writeInt(u32, output_value[0..4], failure_tag, .little);
            return .{ .authored_failure = output_value[0..4] };
        }
        cursor += instruction_length;
    }
    const terminator_kind = segment[cursor + 4];
    const payload = cursor + 8;
    return switch (terminator_kind) {
        0 => .{ .progressed = .{
            .edge_kind = 0,
            .edge = segment[payload..],
        } },
        1 => blk: {
            const condition = readInt(u16, segment, payload);
            if (!slots[condition].initialized or slots[condition].bytes.len != 1) {
                return error.InvalidBindings;
            }
            const then_edge = payload + 4;
            const else_edge = then_edge + edgeLength(segment[then_edge..]);
            break :blk .{ .progressed = if (slots[condition].bytes[0] == 1)
                .{ .edge_kind = 1, .edge = segment[then_edge..] }
            else
                .{ .edge_kind = 2, .edge = segment[else_edge..] } };
        },
        2 => blk: {
            const suspension = try suspensionView(segment, cursor);
            break :blk switch (suspension) {
                .effect => |effect| request: {
                    if (!slots[effect.request_value].initialized) {
                        return error.InvalidBindings;
                    }
                    const bytes = slots[effect.request_value].bytes;
                    try requireOutput(capacity, output_value.len, bytes.len);
                    @memcpy(output_value[0..bytes.len], bytes);
                    break :request .{ .requested = .{
                        .site_ordinal = effect.site_ordinal,
                        .payload = output_value[0..bytes.len],
                    } };
                },
                .call => |call| .{ .call = call.callee },
                .explicit_yield => |yielded| .{
                    .explicit_yield = yielded.continuation,
                },
            };
        },
        3 => blk: {
            if (segment[payload] == 0) break :blk .{ .completed = &.{} };
            const value = readInt(u16, segment, payload + 2);
            if (!slots[value].initialized) return error.InvalidBindings;
            const bytes = slots[value].bytes;
            try requireOutput(capacity, output_value.len, bytes.len);
            @memcpy(output_value[0..bytes.len], bytes);
            break :blk .{ .completed = output_value[0..bytes.len] };
        },
        4 => blk: {
            const value = readInt(u16, segment, payload);
            if (!slots[value].initialized) return error.InvalidBindings;
            break :blk .{ .return_to_caller = slots[value].bytes };
        },
        5 => blk: {
            try requireOutput(capacity, output_value.len, 4);
            std.mem.writeInt(
                u32,
                output_value[0..4],
                readInt(u32, segment, payload),
                .little,
            );
            break :blk .{ .authored_failure = output_value[0..4] };
        },
        6 => blk: {
            const value = readInt(u16, segment, payload);
            if (!slots[value].initialized) return error.InvalidBindings;
            const bytes = slots[value].bytes;
            try requireOutput(capacity, output_value.len, bytes.len);
            @memcpy(output_value[0..bytes.len], bytes);
            break :blk .{ .authored_failure = output_value[0..bytes.len] };
        },
        else => error.UnsupportedOperation,
    };
}

fn requireOutput(
    capacity: ?*CapacityTracker,
    available: usize,
    required: usize,
) Error!void {
    if (capacity) |tracker| return tracker.requireOutput(available, required);
    if (available < required) return error.OutputCapacity;
}

fn requireScratch(
    capacity: ?*CapacityTracker,
    available: usize,
    required: u64,
) Error!void {
    if (capacity) |tracker| return tracker.requireScratch(available, required);
    if (@as(u64, available) < required) return error.ScratchCapacity;
}

pub fn initializeZeroWidthSlots(
    image: anytype,
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

pub const LoadedEnvironment = struct {
    activation_entry: ?u32,
};

/// Validate and bind InitialArgs to the canonical initial constructor slot map.
pub fn bindInitialEnvironment(
    image: anytype,
    constructor: []const u8,
    initial_args: []const u8,
    slots: *[1024]Slot,
    activation_slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    try initializeZeroWidthSlots(image, slots);
    try initializeZeroWidthSlots(image, activation_slots);
    dynamic_value_v1.validateValue(
        image.catalogs.schemas,
        image.catalogs.initial_args_schema_id,
        initial_args,
        &workspace.value_tasks,
    ) catch return error.InvalidBindings;
    const flags = readInt(u16, constructor, 10);
    const activation_count = readInt(u16, constructor, 16);
    const environment_count = readInt(u16, constructor, 18);
    if (flags & 1 != 0 or activation_count != 0 or environment_count > 1) {
        return error.InvalidImage;
    }
    if (environment_count == 0) return;
    const value = readInt(u16, constructor, 24);
    const schema = readInt(u32, constructor, 28);
    if (image.catalogs.entry_parameter_count != 1 or
        value != image.catalogs.entry_parameter_value_id or
        schema != image.catalogs.initial_args_schema_id)
    {
        return error.InvalidImage;
    }
    slots[value] = .{ .bytes = initial_args, .initialized = true };
}

pub fn environmentEncodedLength(
    constructor: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *const [1024]Slot,
) Error!usize {
    return std.math.cast(
        usize,
        try environmentEncodedLengthU64(
            constructor,
            activation_entry,
            activation_slots,
            slots,
        ),
    ) orelse error.OutputCapacity;
}

pub fn environmentEncodedLengthU64(
    constructor: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *const [1024]Slot,
) Error!u64 {
    const flags = readInt(u16, constructor, 10);
    var length: u64 = if (flags & 1 != 0) blk: {
        _ = activation_entry orelse return error.InvalidState;
        break :blk 4;
    } else 0;
    const activation_count = readInt(u16, constructor, 16);
    const field_count = @as(u32, activation_count) +
        readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..field_count) |index| {
        const value = readInt(u16, constructor, field_cursor);
        const slot = if (index < activation_count)
            activation_slots[value]
        else
            slots[value];
        if (!slot.initialized) return error.InvalidState;
        length = std.math.add(u64, length, slot.bytes.len) catch
            return error.OutputCapacity;
        field_cursor += 8;
    }
    return length;
}

/// Encode one canonical constructor environment from its two semantic slot
/// projections. This is the inverse owner of `loadEnvironmentSlots`.
pub fn encodeEnvironmentSlots(
    constructor: []const u8,
    activation_entry: ?u32,
    activation_slots: *const [1024]Slot,
    slots: *const [1024]Slot,
    output: []u8,
) Error![]const u8 {
    const required = try environmentEncodedLength(
        constructor,
        activation_entry,
        activation_slots,
        slots,
    );
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    if (readInt(u16, constructor, 10) & 1 != 0) {
        std.mem.writeInt(u32, output[0..4], activation_entry.?, .little);
        cursor = 4;
    }
    const activation_count = readInt(u16, constructor, 16);
    const field_count = @as(u32, activation_count) +
        readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..field_count) |index| {
        const value = readInt(u16, constructor, field_cursor);
        const slot = if (index < activation_count)
            activation_slots[value]
        else
            slots[value];
        @memcpy(output[cursor..][0..slot.bytes.len], slot.bytes);
        cursor += slot.bytes.len;
        field_cursor += 8;
    }
    return output[0..required];
}

/// Decode one canonical constructor environment into the shared slot carrier.
/// ABI-specific callers remain responsible only for resolving the optional
/// activation constructor identity through their own constructor mapping.
pub fn loadEnvironmentSlots(
    image: anytype,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    activation_slots: ?*[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!LoadedEnvironment {
    return loadEnvironmentSlotsTracked(
        image,
        constructor,
        environment,
        slots,
        activation_slots,
        workspace,
        null,
    );
}

pub fn loadEnvironmentSlotsTracked(
    image: anytype,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    activation_slots: ?*[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
    capacity: ?*CapacityTracker,
) Error!LoadedEnvironment {
    const loaded = try decodeEnvironmentSlots(
        image,
        constructor,
        environment,
        slots,
        activation_slots,
        workspace,
    );
    try validatePathInvariantsTracked(
        image,
        constructor,
        slots,
        workspace,
        capacity,
    );
    return loaded;
}

/// Decode an environment that has already crossed semantic State admission.
/// This projection validates canonical value encodings but does not replay path
/// invariants or write invariant-result scratch.
pub fn decodeEnvironmentSlots(
    image: anytype,
    constructor: []const u8,
    environment: []const u8,
    slots: *[1024]Slot,
    activation_slots: ?*[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!LoadedEnvironment {
    try initializeZeroWidthSlots(image, slots);
    if (activation_slots) |activation| {
        try initializeZeroWidthSlots(image, activation);
    }
    const flags = readInt(u16, constructor, 10);
    var cursor: usize = 0;
    const activation_entry: ?u32 = if (flags & 1 != 0) blk: {
        if (environment.len < 4) return error.InvalidState;
        cursor = 4;
        break :blk readInt(u32, environment, 0);
    } else null;
    const activation_count = readInt(u16, constructor, 16);
    const field_count = @as(u32, activation_count) +
        readInt(u16, constructor, 18);
    var field_cursor: usize = 24;
    for (0..field_count) |index| {
        const value = readInt(u16, constructor, field_cursor);
        const schema = readInt(u32, constructor, field_cursor + 4);
        const consumed = dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            schema,
            environment[cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidState;
        slots[value] = .{
            .bytes = environment[cursor .. cursor + consumed],
            .initialized = true,
        };
        if (index < activation_count) {
            if (activation_slots) |activation| {
                activation[value] = slots[value];
            }
        }
        cursor += consumed;
        field_cursor += 8;
    }
    if (cursor != environment.len) return error.InvalidState;
    return .{ .activation_entry = activation_entry };
}

pub const Suspension = union(enum) {
    effect: struct {
        site_ordinal: u32,
        request_value: u16,
        continuation: []const u8,
    },
    call: struct {
        callee: []const u8,
        continuation: []const u8,
    },
    explicit_yield: struct {
        continuation: []const u8,
    },
};

pub fn suspensionView(
    segment: []const u8,
    terminator: usize,
) Error!Suspension {
    if (terminator > segment.len or segment.len - terminator < 20 or
        segment[terminator + 4] != 2)
    {
        return error.InvalidImage;
    }
    const payload = terminator + 8;
    const request_count = readInt(u16, segment, payload + 10);
    const request_end = std.math.add(
        usize,
        payload + 12,
        @as(usize, request_count) * 2,
    ) catch return error.InvalidImage;
    if (request_end > segment.len or segment.len - request_end < 4) {
        return error.InvalidImage;
    }
    if (segment[request_end] > 1) return error.InvalidImage;
    const callee_present = segment[request_end] == 1;
    var continuation_start = request_end + 4;
    const callee = if (callee_present) blk: {
        const length = edgeLength(segment[continuation_start..]);
        if (length > segment.len - continuation_start) {
            return error.InvalidImage;
        }
        const edge = segment[continuation_start..][0..length];
        continuation_start += length;
        break :blk edge;
    } else &.{};
    if (continuation_start > segment.len) return error.InvalidImage;
    const continuation = segment[continuation_start..];
    return switch (segment[payload]) {
        0 => if (request_count == 1 and !callee_present)
            .{ .effect = .{
                .site_ordinal = readInt(u32, segment, payload + 4),
                .request_value = readInt(u16, segment, payload + 12),
                .continuation = continuation,
            } }
        else
            error.InvalidImage,
        1 => if (request_count == 0 and callee_present)
            .{ .call = .{ .callee = callee, .continuation = continuation } }
        else
            error.InvalidImage,
        2 => if (request_count == 0 and !callee_present)
            .{ .explicit_yield = .{ .continuation = continuation } }
        else
            error.InvalidImage,
        else => error.InvalidImage,
    };
}

pub fn suspensionCallee(segment: []const u8, terminator: usize) []const u8 {
    return switch (suspensionView(segment, terminator) catch return &.{}) {
        .call => |call| call.callee,
        else => &.{},
    };
}

pub fn edgeLength(edge: []const u8) usize {
    return 4 + @as(usize, readInt(u16, edge, 2)) * 4;
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
    var cursor: usize = image_v1.segment_prefix_length +
        @as(usize, readInt(u16, segment, 10)) * 2;
    for (0..readInt(u32, segment, 12)) |_| {
        cursor += readInt(u32, segment, cursor);
    }
    return cursor;
}

pub fn suspensionContinuation(segment: []const u8, terminator: usize) []const u8 {
    return switch (suspensionView(segment, terminator) catch return &.{}) {
        .effect => |effect| effect.continuation,
        .call => |call| call.continuation,
        .explicit_yield => |yielded| yielded.continuation,
    };
}

pub fn isAwaitCallConstructor(image: anytype, constructor: []const u8) bool {
    if (constructor.len < 24 or constructor[8] != 4 or constructor[9] != 2) {
        return false;
    }
    const segment = segmentRecord(
        image,
        readInt(u16, constructor, 12),
    ) catch return false;
    const suspension = suspensionView(
        segment,
        segmentTerminatorOffset(segment),
    ) catch return false;
    return suspension == .call;
}

pub fn constantBytes(
    image: anytype,
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

fn ordinaryInstructionOperandCount(
    image: anytype,
    instruction: []const u8,
) Error!u16 {
    const operation = std.enums.fromInt(
        program_semantics_v1.WireOperation,
        readInt(u16, instruction, 6),
    ) orelse return error.InvalidImage;
    const actual = readInt(u16, instruction, 10);
    const base = program_semantics_v1.fixedOperandCount(operation) orelse
        return actual;
    if (actual == base) return base;
    const failure_count = program_semantics_v1.failureRolesForWire(
        operation,
    ).len;
    if (image.catalogs.envelope.header.evaluator_semantics_version ==
        image_v1.evaluator_semantics_v2 and failure_count != 0 and
        actual == base + failure_count)
    {
        return base;
    }
    return error.InvalidImage;
}

pub fn executeScalarOperation(
    image: anytype,
    instruction: []const u8,
    result: u16,
    slots: *[1024]Slot,
    scratch: []u8,
    scratch_cursor: *usize,
    capacity: ?*CapacityTracker,
) Error!?u32 {
    const operation = readInt(u16, instruction, 6);
    const operand_count = readInt(u16, instruction, 10);
    const ordinary_operand_count = try ordinaryInstructionOperandCount(
        image,
        instruction,
    );
    var operands: [3]u16 = undefined;
    if (ordinary_operand_count > operands.len) return error.InvalidImage;
    for (0..operand_count) |index| {
        const operand = readInt(u16, instruction, 16 + index * 2);
        if (!slots[operand].initialized) return error.InvalidBindings;
        if (index < ordinary_operand_count) operands[index] = operand;
    }
    if (operation == 23) {
        if (ordinary_operand_count != 3 or slots[operands[0]].bytes.len != 1) {
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
        if (ordinary_operand_count != 1 or slots[operands[0]].bytes.len != 4) {
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
            .bytes = try writeRaw(scratch, scratch_cursor, capacity, .bool, @intFromBool(value)),
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
                capacity,
                .bool,
                @intFromBool(left.raw == 0),
            ),
            .initialized = true,
        };
        return null;
    }
    if (operation == 19) {
        const converted = convertInteger(left, result_kind) orelse
            return try instructionFailureTag(image, instruction, slots, "arithmetic_overflow");
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, capacity, result_kind, converted),
            .initialized = true,
        };
        return null;
    }
    if (operation == 8) {
        const value = signedValue(left);
        const negated = std.math.sub(i128, 0, value) catch
            return try instructionFailureTag(image, instruction, slots, "arithmetic_overflow");
        const raw = encodeSigned(negated, result_kind) orelse
            return try instructionFailureTag(image, instruction, slots, "arithmetic_overflow");
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, capacity, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    if (operation == 15) {
        const raw = (~left.raw) & integerMask(left.bits);
        slots[result] = .{
            .bytes = try writeRaw(scratch, scratch_cursor, capacity, result_kind, raw),
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
                capacity,
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
            .bytes = try writeRaw(scratch, scratch_cursor, capacity, result_kind, raw),
            .initialized = true,
        };
        return null;
    }
    const raw = integerArithmetic(left, right, operation) catch |err| switch (err) {
        error.DivisionByZero => return try instructionFailureTag(image, instruction, slots, "division_by_zero"),
        error.Overflow => return try instructionFailureTag(image, instruction, slots, "arithmetic_overflow"),
    };
    slots[result] = .{
        .bytes = try writeRaw(scratch, scratch_cursor, capacity, result_kind, raw),
        .initialized = true,
    };
    return null;
}

pub fn executeCompositeOperation(
    image: anytype,
    instruction: []const u8,
    result: u16,
    slots: *[1024]Slot,
    scratch: []u8,
    scratch_cursor: *usize,
    workspace: *image_v1.ValidationWorkspace,
    capacity: ?*CapacityTracker,
) Error!?u32 {
    const operation = readInt(u16, instruction, 6);
    const operand_count = readInt(u16, instruction, 10);
    const ordinary_operand_count = try ordinaryInstructionOperandCount(
        image,
        instruction,
    );
    const immediate = readInt(u32, instruction, 12);
    if (operation == 24) {
        var length: usize = 0;
        for (0..ordinary_operand_count) |index| {
            const operand = readInt(u16, instruction, 16 + index * 2);
            if (!slots[operand].initialized) return error.InvalidBindings;
            length = std.math.add(
                usize,
                length,
                slots[operand].bytes.len,
            ) catch return error.ScratchCapacity;
        }
        const output = try allocateScratch(scratch, scratch_cursor, capacity, length);
        var cursor: usize = 0;
        for (0..ordinary_operand_count) |index| {
            const operand = readInt(u16, instruction, 16 + index * 2);
            @memcpy(
                output[cursor..][0..slots[operand].bytes.len],
                slots[operand].bytes,
            );
            cursor += slots[operand].bytes.len;
        }
        slots[result] = .{ .bytes = output, .initialized = true };
        return null;
    }
    var operands: [3]u16 = undefined;
    if (ordinary_operand_count > operands.len) return error.InvalidImage;
    for (0..operand_count) |index| {
        const operand = readInt(u16, instruction, 16 + index * 2);
        if (!slots[operand].initialized) return error.InvalidBindings;
        if (index < ordinary_operand_count) operands[index] = operand;
    }
    switch (operation) {
        24 => unreachable,
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
                capacity,
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
            const payload = if (ordinary_operand_count == 0)
                &.{}
            else
                slots[operands[0]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                capacity,
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
                        capacity,
                        .bool,
                        @intFromBool(matches),
                    ),
                    .initialized = true,
                };
            } else {
                if (!matches) return try instructionFailureTag(image, instruction, slots, "invalid_variant");
                slots[result] = .{
                    .bytes = slots[operands[0]].bytes[4..],
                    .initialized = true,
                };
            }
        },
        30 => {
            const output = try allocateScratch(scratch, scratch_cursor, capacity, 1);
            output[0] = 0;
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        31 => {
            const payload = slots[operands[0]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                capacity,
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
                    capacity,
                    .bool,
                    @intFromBool(slots[operands[0]].bytes[0] == 1),
                ),
                .initialized = true,
            };
        },
        33, 41, 49 => {
            const output = try allocateScratch(scratch, scratch_cursor, capacity, 4);
            @memset(output, 0);
            slots[result] = .{ .bytes = output, .initialized = true };
        },
        37 => {
            const vector = slots[operands[0]].bytes;
            const element = slots[operands[1]].bytes;
            const schema = try valueNode(image, operands[0]);
            const length = readInt(u32, vector, 0);
            if (length >= readInt(u32, schema.payload, 0)) {
                return try instructionFailureTag(image, instruction, slots, "capacity_exceeded");
            }
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                capacity,
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
                    capacity,
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
            ) catch return try instructionFailureTag(image, instruction, slots, "invalid_index");
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
            ) catch return try instructionFailureTag(image, instruction, slots, "invalid_index");
            const prefix_length = @intFromPtr(element.ptr) - @intFromPtr(vector.ptr);
            const replacement = slots[operands[2]].bytes;
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                capacity,
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
                capacity,
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
                    capacity,
                    prefix_length,
                );
                @memcpy(output, vector[0..prefix_length]);
                std.mem.writeInt(u32, output[0..4], requested, .little);
                slots[result] = .{ .bytes = output, .initialized = true };
            }
        },
        40 => {
            const output = try allocateScratch(scratch, scratch_cursor, capacity, 4);
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
            ) catch return try instructionFailureTag(image, instruction, slots, "capacity_exceeded");
            const schema = try valueNode(image, result);
            if (combined > readInt(u32, schema.payload, 0)) {
                return try instructionFailureTag(image, instruction, slots, "capacity_exceeded");
            }
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                capacity,
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
                return try instructionFailureTag(image, instruction, slots, "invalid_utf8");
            }
            var encoded: [4]u8 = undefined;
            const encoded_length = std.unicode.utf8Encode(
                @intCast(raw),
                &encoded,
            ) catch return try instructionFailureTag(image, instruction, slots, "invalid_utf8");
            slots[result] = .{
                .bytes = appendSequence(
                    image,
                    result,
                    slots[operands[0]].bytes,
                    &.{encoded[0..encoded_length]},
                    scratch,
                    scratch_cursor,
                    capacity,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try instructionFailureTag(image, instruction, slots, "capacity_exceeded"),
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
                ) catch return try instructionFailureTag(image, instruction, slots, "capacity_exceeded")
            else
                std.fmt.bufPrint(
                    &formatted_storage,
                    "{d}",
                    .{signedValue(integer)},
                ) catch return try instructionFailureTag(image, instruction, slots, "capacity_exceeded");
            slots[result] = .{
                .bytes = appendSequence(
                    image,
                    result,
                    slots[operands[0]].bytes,
                    &.{formatted},
                    scratch,
                    scratch_cursor,
                    capacity,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try instructionFailureTag(image, instruction, slots, "capacity_exceeded"),
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
                return try instructionFailureTag(image, instruction, slots, "capacity_exceeded");
            }
            const copied = source[4 + start .. 4 + end];
            const node = try valueNode(image, result);
            if (copied.len > readInt(u32, node.payload, 0)) {
                return try instructionFailureTag(image, instruction, slots, "capacity_exceeded");
            }
            if (operation == 46 and !std.unicode.utf8ValidateSlice(copied)) {
                return try instructionFailureTag(image, instruction, slots, "invalid_utf8");
            }
            const output = try allocateScratch(
                scratch,
                scratch_cursor,
                capacity,
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
                    capacity,
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
                    capacity,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try instructionFailureTag(image, instruction, slots, "capacity_exceeded"),
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
                    capacity,
                ) catch |err| switch (err) {
                    error.CapacityExceeded => return try instructionFailureTag(image, instruction, slots, "capacity_exceeded"),
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
    image: anytype,
    result_value: u16,
    prefix: []const u8,
    suffixes: []const []const u8,
    scratch: []u8,
    scratch_cursor: *usize,
    capacity: ?*CapacityTracker,
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
        capacity,
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

pub fn sequencePayload(value: []const u8) []const u8 {
    return value[4..][0..readInt(u32, value, 0)];
}

pub fn productField(
    image: anytype,
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
        ) catch return error.InvalidBindings;
    }
    const schema_id = readInt(u32, node.payload, 4 + @as(usize, field_index) * 4);
    const length = dynamic_value_v1.validateValuePrefix(
        image.catalogs.schemas,
        schema_id,
        product[cursor..],
        &workspace.value_tasks,
    ) catch return error.InvalidBindings;
    return product[cursor..][0..length];
}

pub fn vectorElement(
    image: anytype,
    vector_value: u16,
    vector: []const u8,
    target: u32,
    workspace: *image_v1.ValidationWorkspace,
) Error![]const u8 {
    const node = try valueNode(image, vector_value);
    if (node.kind != .vector) return error.InvalidImage;
    const length = readInt(u32, vector, 0);
    if (target >= length) return error.InvalidBindings;
    const element_schema = readInt(u32, node.payload, 4);
    var cursor: usize = 4;
    const element_node = image.catalogs.schemas.node(element_schema) catch
        return error.InvalidImage;
    if (element_node.maximum_encoded_size == 0) return vector[cursor..cursor];
    for (0..target) |_| {
        cursor += dynamic_value_v1.validateValuePrefix(
            image.catalogs.schemas,
            element_schema,
            vector[cursor..],
            &workspace.value_tasks,
        ) catch return error.InvalidBindings;
    }
    const element_length = dynamic_value_v1.validateValuePrefix(
        image.catalogs.schemas,
        element_schema,
        vector[cursor..],
        &workspace.value_tasks,
    ) catch return error.InvalidBindings;
    return vector[cursor..][0..element_length];
}

pub fn valueNode(
    image: anytype,
    value: u16,
) Error!dynamic_value_v1.Node {
    const schema_id = image.catalogs.valueSchemaId(value) catch
        return error.InvalidImage;
    return image.catalogs.schemas.node(schema_id) catch error.InvalidImage;
}

fn allocateScratch(
    scratch: []u8,
    cursor: *usize,
    capacity: ?*CapacityTracker,
    length: usize,
) Error![]u8 {
    const required_u64 = std.math.add(
        u64,
        cursor.*,
        length,
    ) catch
        return error.ScratchCapacity;
    try requireScratch(capacity, scratch.len, required_u64);
    const required = std.math.cast(usize, required_u64) orelse
        return error.ScratchCapacity;
    const result = scratch[cursor.*..][0..length];
    cursor.* = required;
    return result;
}

pub const Integer = struct {
    raw: u64,
    bits: u8,
    signed: bool,
};

pub fn valueKind(
    image: anytype,
    value: u16,
) Error!dynamic_value_v1.Kind {
    const schema_id = image.catalogs.valueSchemaId(value) catch
        return error.InvalidImage;
    return (image.catalogs.schemas.node(schema_id) catch
        return error.InvalidImage).kind;
}

pub fn decodeInteger(kind: dynamic_value_v1.Kind, bytes: []const u8) Error!Integer {
    const bits: u8 = switch (kind) {
        .i8, .u8 => 8,
        .i16, .u16 => 16,
        .i32, .u32 => 32,
        .i64, .u64 => 64,
        else => return error.InvalidImage,
    };
    if (bytes.len != bits / 8) return error.InvalidBindings;
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

pub fn signedValue(value: Integer) i128 {
    if (!value.signed) return value.raw;
    if (value.bits == 64) return @as(i64, @bitCast(value.raw));
    const sign = @as(u64, 1) << @intCast(value.bits - 1);
    return if (value.raw & sign == 0)
        value.raw
    else
        @as(i128, value.raw) - (@as(i128, 1) << @intCast(value.bits));
}

pub fn integerArithmetic(
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
        if ((operation == 6 or operation == 7) and b == -1 and
            a == -(@as(i128, 1) << @intCast(left.bits - 1)))
        {
            return error.Overflow;
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

pub fn compareIntegers(left: Integer, right: Integer, operation: u16) bool {
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

pub fn convertInteger(value: Integer, kind: dynamic_value_v1.Kind) ?u64 {
    const target = integerShape(kind) orelse return null;
    if (target.signed) return encodeSigned(signedValue(value), kind);
    const source = signedValue(value);
    if (source < 0 or @as(u128, @intCast(source)) > integerMask(target.bits)) {
        return null;
    }
    return @intCast(source);
}

pub fn encodeSigned(value: i128, kind: dynamic_value_v1.Kind) ?u64 {
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

pub fn integerShape(kind: dynamic_value_v1.Kind) ?Integer {
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

pub fn integerKind(value: Integer) dynamic_value_v1.Kind {
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

pub fn integerMask(bits: u8) u64 {
    return if (bits == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(bits)) - 1;
}

fn instructionFailureTag(
    image: anytype,
    instruction: []const u8,
    slots: *[1024]Slot,
    name: []const u8,
) Error!u32 {
    const operation = std.enums.fromInt(
        program_semantics_v1.WireOperation,
        readInt(u16, instruction, 6),
    ) orelse return error.InvalidImage;
    const base = program_semantics_v1.fixedOperandCount(operation) orelse
        return error.InvalidImage;
    const roles = program_semantics_v1.failureRolesForWire(operation);
    const operand_count = readInt(u16, instruction, 10);
    if (image.catalogs.envelope.header.evaluator_semantics_version ==
        image_v1.evaluator_semantics_v2 and roles.len != 0 and
        operand_count == base + roles.len)
    {
        for (roles, 0..) |role, index| {
            if (!std.mem.eql(
                u8,
                program_semantics_v1.failureRoleName(role),
                name,
            )) continue;
            const value = readInt(
                u16,
                instruction,
                16 + (@as(usize, base) + index) * 2,
            );
            if (!slots[value].initialized or slots[value].bytes.len != 4) {
                return error.InvalidBindings;
            }
            return readInt(u32, slots[value].bytes, 0);
        }
        return error.InvalidImage;
    }
    return failureTag(image, name);
}

fn writeRaw(
    scratch: []u8,
    cursor: *usize,
    capacity: ?*CapacityTracker,
    kind: dynamic_value_v1.Kind,
    raw: u64,
) Error![]const u8 {
    const length: usize = if (kind == .bool) 1 else (integerShape(kind) orelse return error.InvalidImage).bits / 8;
    const result = try allocateScratch(scratch, cursor, capacity, length);
    for (result, 0..) |*byte, index| byte.* = @truncate(raw >> @intCast(index * 8));
    return result;
}

pub fn failureTag(image: anytype, name: []const u8) Error!u32 {
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

pub fn validatePathInvariants(
    image: anytype,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
) Error!void {
    return validatePathInvariantsTracked(
        image,
        constructor,
        slots,
        workspace,
        null,
    );
}

pub fn validatePathInvariantsTracked(
    image: anytype,
    constructor: []const u8,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
    capacity: ?*CapacityTracker,
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
                capacity,
            ),
            2 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                20,
                0,
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
                capacity,
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
                capacity,
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
                capacity,
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
                const operand_bytes = constructor[payload + 8 ..][0 .. @as(usize, operand_count) * 2];
                const instruction = try definingInstruction(image, definition);
                break :blk try validateComputedResultEncoded(
                    image,
                    result,
                    readInt(u16, instruction, 6),
                    readInt(u32, instruction, 12),
                    operand_bytes,
                    operand_count,
                    slots,
                    workspace,
                    capacity,
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
                capacity,
            ),
            10 => try validateComputedResult(
                image,
                readInt(u16, constructor, payload),
                29,
                readInt(u16, constructor, payload + 4),
                &.{readInt(u16, constructor, payload + 2)},
                slots,
                workspace,
                capacity,
            ),
            11 => blk: {
                const bounded = readInt(u16, constructor, payload + 2);
                const operation: u16 = switch ((try valueNode(image, bounded)).kind) {
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
                    capacity,
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
                capacity,
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
                    capacity,
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
                capacity,
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
                capacity,
            ),
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
                capacity,
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
                capacity,
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
    capacity: ?*CapacityTracker,
) Error!bool {
    var operand_bytes: [6]u8 = undefined;
    if (operands.len > operand_bytes.len / 2) return false;
    for (operands, 0..) |operand, index| {
        std.mem.writeInt(
            u16,
            operand_bytes[index * 2 ..][0..2],
            operand,
            .little,
        );
    }
    return validateComputedResultEncoded(
        image,
        result,
        operation,
        immediate,
        operand_bytes[0 .. operands.len * 2],
        @intCast(operands.len),
        slots,
        workspace,
        capacity,
    );
}

fn validateComputedResultEncoded(
    image: anytype,
    result: u16,
    operation: u16,
    immediate: u32,
    operand_bytes: []const u8,
    operand_count: u16,
    slots: *[1024]Slot,
    workspace: *image_v1.ValidationWorkspace,
    capacity: ?*CapacityTracker,
) Error!bool {
    if (!slots[result].initialized or
        operand_bytes.len != @as(usize, operand_count) * 2)
    {
        return false;
    }
    if (operation == 24) {
        return productConstructMatches(
            slots[result].bytes,
            operand_bytes,
            operand_count,
            slots,
        );
    }
    const instruction_length = 16 + operand_bytes.len;
    if (instruction_length > workspace.invariant_instruction.len) {
        return error.ScratchCapacity;
    }
    const instruction = workspace.invariant_instruction[0..instruction_length];
    @memset(instruction, 0);
    std.mem.writeInt(u32, instruction[0..4], @intCast(instruction_length), .little);
    std.mem.writeInt(u16, instruction[6..8], operation, .little);
    std.mem.writeInt(u16, instruction[8..10], result, .little);
    std.mem.writeInt(u16, instruction[10..12], operand_count, .little);
    std.mem.writeInt(u32, instruction[12..16], immediate, .little);
    @memcpy(instruction[16..], operand_bytes);
    const expected = slots[result];
    defer slots[result] = expected;
    var scratch_cursor: usize = 0;
    const failure = if (operation == 0) blk: {
        slots[result] = .{
            .bytes = try constantBytes(image, immediate),
            .initialized = true,
        };
        break :blk null;
    } else if (operation == 1) blk: {
        if (operand_count != 1) return false;
        const operand = readInt(u16, operand_bytes, 0);
        if (operand >= slots.len or !slots[operand].initialized) return false;
        slots[result] = slots[operand];
        break :blk null;
    } else if (operation <= 23 or operation == 57)
        try executeScalarOperation(
            image,
            instruction,
            result,
            slots,
            workspace.invariant_result,
            &scratch_cursor,
            capacity,
        )
    else if (operation <= 56)
        try executeCompositeOperation(
            image,
            instruction,
            result,
            slots,
            workspace.invariant_result,
            &scratch_cursor,
            workspace,
            capacity,
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
            const value = try decodeInteger(
                try valueKind(image, result),
                slots[result].bytes,
            );
            break :blk value.signed and signedValue(value) == @as(i64, @bitCast(payload));
        },
        2 => blk: {
            const value = try decodeInteger(
                try valueKind(image, result),
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

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
