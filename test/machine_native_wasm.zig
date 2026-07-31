const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Double = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.double.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const continuation_arguments = [_]cir.EdgeArgument{.@"resume"};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &continuation_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        rejected,
    };
    pub const effect_sites = .{Double};
    pub const schema_types = .{};
    pub const block_costs = [_]u64{ 2, 3 };
    pub const control_ir: cir.Program = .{
        .label = "native-wasm-parity",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

const Program = program_v2.program("native-wasm-parity", Body);
const ParityMachine = Program.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

var source_storage: [4096]u8 = undefined;
var image_storage: [4096]u8 = undefined;
var restored_storage: [4096]u8 = undefined;
var output_storage: [4096]u8 = undefined;

fn writeInt(
    output: []u8,
    index: *usize,
    comptime T: type,
    value: T,
) void {
    const width = @divExact(@typeInfo(T).int.bits, 8);
    std.mem.writeInt(T, output[index.*..][0..width], value, .little);
    index.* += width;
}

fn writeBytes(output: []u8, index: *usize, bytes: []const u8) void {
    @memcpy(output[index.*..][0..bytes.len], bytes);
    index.* += bytes.len;
}

pub export fn boundaryMachineParityRun() u32 {
    var source = std.heap.FixedBufferAllocator.init(&source_storage);
    const state = ParityMachine.initialState(source.allocator(), 21) catch return 0;
    defer ParityMachine.deinitState(state);

    var insufficient_fuel: u64 = 1;
    switch (ParityMachine.step(state, &insufficient_fuel) catch return 0) {
        .yielded => {},
        else => return 0,
    }
    if (insufficient_fuel != 1) return 0;

    var caller_fuel: u64 = 10;
    const request = switch (ParityMachine.step(state, &caller_fuel) catch return 0) {
        .request => |value| value,
        else => return 0,
    };
    const request_payload = switch (request.value) {
        .s0 => |payload| payload,
    };
    if (caller_fuel != 8 or request.sequence != 1 or
        request_payload != 21)
    {
        return 0;
    }

    var image = std.heap.FixedBufferAllocator.init(&image_storage);
    const encoded = ParityMachine.encodeState(image.allocator(), state) catch
        return 0;
    var restored = std.heap.FixedBufferAllocator.init(&restored_storage);
    const restored_state = ParityMachine.decodeState(
        restored.allocator(),
        encoded,
    ) catch return 0;
    defer ParityMachine.deinitState(restored_state);
    const current = ParityMachine.current(restored_state) catch return 0;
    const current_payload = switch (current.value) {
        .s0 => |payload| payload,
    };
    if (current.sequence != request.sequence or
        current.constructor_id != request.constructor_id or
        current_payload != request_payload)
    {
        return 0;
    }
    ParityMachine.@"resume"(restored_state, current, @as(u32, 42)) catch
        return 0;

    const done = switch (ParityMachine.step(restored_state, &caller_fuel) catch
        return 0) {
        .done => |value| value,
        else => return 0,
    };
    defer done.deinit();
    if (done.value().* != 42 or caller_fuel != 5) return 0;

    var index: usize = 0;
    writeInt(&output_storage, &index, u32, @intCast(encoded.len));
    writeBytes(&output_storage, &index, encoded);
    writeInt(&output_storage, &index, u64, request.sequence);
    writeInt(&output_storage, &index, u32, request.constructor_id);
    writeInt(&output_storage, &index, u32, 0);
    writeInt(&output_storage, &index, u32, request_payload);
    writeInt(&output_storage, &index, u64, insufficient_fuel);
    writeInt(&output_storage, &index, u64, 8);
    writeInt(&output_storage, &index, u32, done.value().*);
    writeInt(&output_storage, &index, u64, caller_fuel);
    return @intCast(index);
}

pub export fn boundaryMachineParityOutputPointer() u32 {
    return @intCast(@intFromPtr(&output_storage));
}

pub fn outputBytes(length: u32) []const u8 {
    return output_storage[0..length];
}

const ParityText = portable_value.Text(8192);
const ParityBytes = portable_value.Bytes(32);
const ParityItem = struct {
    title: portable_value.Text(16),
    count: u32,
};
const ParityItems = portable_value.Vector(ParityItem, 8);
const ParityEnum = enum(u16) {
    zero = 0,
    high = 513,
};
const ParitySum = union(enum) {
    unit: void,
    signed: i16,
    text: portable_value.Text(8),
};
const PortableParityValue = struct {
    unit: void,
    boolean: bool,
    i8_value: i8,
    i16_value: i16,
    i32_value: i32,
    i64_value: i64,
    u8_value: u8,
    u16_value: u16,
    u32_value: u32,
    u64_value: u64,
    array: [3]u16,
    enumeration: ParityEnum,
    sum: ParitySum,
    optional: ?i32,
    bytes: ParityBytes,
    text: ParityText,
    items: ParityItems,
};

const value_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    },
};

const PortableParityBody = struct {
    pub const InitialArgs = PortableParityValue;
    pub const Result = PortableParityValue;
    pub const Failure = enum {
        rejected,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{PortableParityValue};
    pub const control_ir: cir.Program = .{
        .label = "portable-value-native-wasm-parity",
        .value_types = &.{.{ .schema = 0 }},
        .blocks = &value_blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};

const PortableParityMachine = program_v2.program(
    "portable-value-native-wasm-parity",
    PortableParityBody,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 32 * 1024,
    .maximum_machine_fuel = 32,
});

var value_source_storage: [64 * 1024]u8 = undefined;
var value_image_storage: [32 * 1024]u8 = undefined;
var value_output_storage: [32 * 1024]u8 = undefined;

fn portableParityValue() !PortableParityValue {
    var items = ParityItems.empty();
    try items.push(.{
        .title = try portable_value.Text(16).fromSlice("alpha"),
        .count = 3,
    });
    try items.push(.{
        .title = try portable_value.Text(16).fromSlice("beta"),
        .count = 5,
    });
    return .{
        .unit = {},
        .boolean = true,
        .i8_value = -8,
        .i16_value = -16,
        .i32_value = -32,
        .i64_value = -64,
        .u8_value = 8,
        .u16_value = 16,
        .u32_value = 32,
        .u64_value = 64,
        .array = .{ 3, 5, 8 },
        .enumeration = .high,
        .sum = .{
            .text = try portable_value.Text(8).fromSlice("sum"),
        },
        .optional = -7,
        .bytes = try ParityBytes.fromSlice(&.{ 1, 2, 3 }),
        .text = try ParityText.fromSlice("portable-parity"),
        .items = items,
    };
}

pub export fn boundaryMachineValueParityRun() u32 {
    const initial = portableParityValue() catch return 0;
    var source = std.heap.FixedBufferAllocator.init(&value_source_storage);
    const state = PortableParityMachine.initialState(
        source.allocator(),
        initial,
    ) catch return 0;
    defer PortableParityMachine.deinitState(state);

    var image = std.heap.FixedBufferAllocator.init(&value_image_storage);
    const encoded_state = PortableParityMachine.encodeState(
        image.allocator(),
        state,
    ) catch return 0;

    var caller_fuel: u64 = 8;
    const done = switch (PortableParityMachine.step(
        state,
        &caller_fuel,
    ) catch return 0) {
        .done => |value| value,
        else => return 0,
    };
    defer done.deinit();
    if (!portable_value.eqlValue(
        PortableParityValue,
        initial,
        done.value().*,
    )) return 0;

    var result_bytes: [
        portable_value.maximumEncodedSize(
            PortableParityValue,
        )
    ]u8 = undefined;
    const result_length = portable_value.encode(
        PortableParityValue,
        done.value().*,
        &result_bytes,
    ) catch return 0;

    var index: usize = 0;
    writeInt(
        &value_output_storage,
        &index,
        u32,
        @intCast(encoded_state.len),
    );
    writeBytes(&value_output_storage, &index, encoded_state);
    writeInt(
        &value_output_storage,
        &index,
        u32,
        @intCast(result_length),
    );
    writeBytes(
        &value_output_storage,
        &index,
        result_bytes[0..result_length],
    );
    writeInt(&value_output_storage, &index, u64, caller_fuel);
    return @intCast(index);
}

pub export fn boundaryMachineValueParityOutputPointer() u32 {
    return @intCast(@intFromPtr(&value_output_storage));
}

pub fn valueOutputBytes(length: u32) []const u8 {
    return value_output_storage[0..length];
}
