const cir = @import("control_ir");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const blocks = [_]cir.Block{.{
    .id = 0,
    .instructions = &instructions,
    .terminator = .{ .return_value = 0 },
}};
const Body = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{@as(u32, 42)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "kernel-wasm-vector",
        .value_types = &.{.{ .scalar = .u32 }},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};
const Program = program_v2.program("kernel-wasm-vector", Body);
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const Image = Program.image();
const Profile = Program.machineV2Profile(options);

pub fn main(init: std.process.Init) !void {
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&Image.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(program_image, &Profile.bytes, &workspace);
    var state: [4096]u8 = undefined;
    const state_length = try kernel_v1.initial(
        image,
        &.{},
        &state,
        &workspace,
    );
    var input: [48 + Image.bytes.len + Profile.bytes.len + 4096]u8 = undefined;
    @memset(input[0..48], 0);
    @memcpy(input[0..8], "ABL_KIN1");
    writeInt(u16, &input, 8, 1);
    writeInt(u16, &input, 10, 4);
    writeInt(u64, &input, 16, 8);
    writeInt(u32, &input, 24, Image.bytes.len);
    writeInt(u32, &input, 28, Profile.bytes.len);
    writeInt(u32, &input, 32, state_length);
    @memcpy(input[48..][0..Image.bytes.len], &Image.bytes);
    @memcpy(input[48 + Image.bytes.len ..][0..Profile.bytes.len], &Profile.bytes);
    @memcpy(input[48 + Image.bytes.len + Profile.bytes.len ..][0..state_length], state[0..state_length]);
    const input_length = 48 + Image.bytes.len + Profile.bytes.len + state_length;

    var fuel: u64 = 8;
    var next_state: [4096]u8 = undefined;
    var value: [4]u8 = undefined;
    var scratch: [12 * 1024]u8 = undefined;
    const done = switch (try kernel_v1.step(
        image,
        state[0..state_length],
        &fuel,
        &next_state,
        &value,
        &scratch,
        &workspace,
    )) {
        .done => |bytes| bytes,
        else => return error.UnexpectedOutcome,
    };
    var expected: [44]u8 = [_]u8{0} ** 44;
    @memcpy(expected[0..8], "ABL_KOU1");
    writeInt(u16, &expected, 8, 1);
    writeInt(u16, &expected, 10, 4);
    writeInt(u16, &expected, 12, 5);
    writeInt(u64, &expected, 16, fuel);
    writeInt(u32, &expected, 28, done.len);
    @memcpy(expected[40..44], done);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeInt(u32, @intCast(input_length), .little);
    try stdout.writeInt(u32, expected.len, .little);
    try stdout.writeAll(input[0..input_length]);
    try stdout.writeAll(&expected);
    try stdout.flush();
}

fn writeInt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    value: anytype,
) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], @intCast(value), .little);
}
