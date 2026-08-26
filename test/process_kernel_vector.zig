const boundary = @import("boundary");
const process_advance_v1 = @import("process_advance_v1");
const std = @import("std");

const Lookup = boundary.effect.site(
    0,
    "process.kernel.fixture.lookup.v1",
    u32,
    u32,
);
const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &resume_arguments },
            .resume_type = u32_type,
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
    pub const Failure = enum { rejected };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-kernel-vector",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const Image = boundary.program("process-kernel-vector", Body).image();

const Storage = struct {
    state: [64 * 1024]u8 = undefined,
    value: [64 * 1024]u8 = undefined,
    request: [64 * 1024]u8 = undefined,
    candidate: [64 * 1024]u8 = undefined,
    environment: [64 * 1024]u8 = undefined,
    auxiliary_environment: [64 * 1024]u8 = undefined,
    scratch: [512 * 1024]u8 = undefined,

    fn buffers(self: *@This()) process_advance_v1.Buffers {
        return .{
            .output_state = &self.state,
            .output_value = &self.value,
            .output_request = &self.request,
            .candidate_state = &self.candidate,
            .environment = &self.environment,
            .auxiliary_environment = &self.auxiliary_environment,
            .scratch = &self.scratch,
        };
    }
};

pub fn main(init: std.process.Init) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 17, .little);

    var first_storage: Storage = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &Image.bytes,
        .{ .initial_args = &initial },
        null,
        first_storage.buffers(),
        &first_workspace,
    );
    const pending = first.requested;

    var second_storage: Storage = .{};
    var second_workspace: boundary.image.ValidationWorkspace = .{};
    const second = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        second_storage.buffers(),
        &second_workspace,
    );

    const request = try boundary.process_v1.effect.validateRequest(
        pending.request,
        Image.program_transition_digest,
    );
    var resume_value: [4]u8 = undefined;
    std.mem.writeInt(u32, &resume_value, 29, .little);
    var result_storage: [256]u8 = undefined;
    const result = try boundary.process_v1.effect.encodeResult(.{
        .request_identity_digest = request.request_identity_digest,
        .resume_schema_digest = request.resume_schema_digest,
        .@"resume" = &resume_value,
    }, &result_storage);
    var third_storage: Storage = .{};
    var third_workspace: boundary.image.ValidationWorkspace = .{};
    const third = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        result,
        third_storage.buffers(),
        &third_workspace,
    );

    var input_one_storage: [128 * 1024]u8 = undefined;
    var input_two_storage: [128 * 1024]u8 = undefined;
    var input_three_storage: [128 * 1024]u8 = undefined;
    const inputs = [_][]const u8{
        try process_advance_v1.encodeKernelInput(
            &Image.bytes,
            .{ .initial_args = &initial },
            null,
            &input_one_storage,
        ),
        try process_advance_v1.encodeKernelInput(
            &Image.bytes,
            .{ .process_state = pending.state },
            null,
            &input_two_storage,
        ),
        try process_advance_v1.encodeKernelInput(
            &Image.bytes,
            .{ .process_state = pending.state },
            result,
            &input_three_storage,
        ),
    };
    var output_one_storage: [128 * 1024]u8 = undefined;
    var output_two_storage: [128 * 1024]u8 = undefined;
    var output_three_storage: [128 * 1024]u8 = undefined;
    const outputs = [_][]const u8{
        try process_advance_v1.encodeOutcome(first, &output_one_storage),
        try process_advance_v1.encodeOutcome(second, &output_two_storage),
        try process_advance_v1.encodeOutcome(third, &output_three_storage),
    };

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try writeInt(stdout, 3);
    for (inputs, outputs) |input, output| {
        try writeInt(stdout, @intCast(input.len));
        try writeInt(stdout, @intCast(output.len));
        try stdout.writeAll(input);
        try stdout.writeAll(output);
    }
    try stdout.flush();
}

fn writeInt(writer: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try writer.writeAll(&bytes);
}
