const cir = @import("control_ir");
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

fn writeInt(index: *usize, comptime T: type, value: T) void {
    const width = @divExact(@typeInfo(T).int.bits, 8);
    std.mem.writeInt(T, output_storage[index.*..][0..width], value, .little);
    index.* += width;
}

fn writeBytes(index: *usize, bytes: []const u8) void {
    @memcpy(output_storage[index.*..][0..bytes.len], bytes);
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
    writeInt(&index, u32, @intCast(encoded.len));
    writeBytes(&index, encoded);
    writeInt(&index, u64, request.sequence);
    writeInt(&index, u32, request.constructor_id);
    writeInt(&index, u32, 0);
    writeInt(&index, u32, request_payload);
    writeInt(&index, u64, insufficient_fuel);
    writeInt(&index, u64, 8);
    writeInt(&index, u32, done.value().*);
    writeInt(&index, u64, caller_fuel);
    return @intCast(index);
}

pub export fn boundaryMachineParityOutputPointer() u32 {
    return @intCast(@intFromPtr(&output_storage));
}

pub fn outputBytes(length: u32) []const u8 {
    return output_storage[0..length];
}
