const boundary = @import("boundary");
const fixture = @import("process_kernel_fixture");
const process_advance_v1 = @import("process_advance_v1");
const std = @import("std");

const Storage = struct {
    state: [64 * 1024]u8 = undefined,
    value: [64 * 1024]u8 = undefined,
    request: [64 * 1024]u8 = undefined,
    candidate: [64 * 1024]u8 = undefined,
    environment: [64 * 1024]u8 = undefined,
    auxiliary_environment: [64 * 1024]u8 = undefined,
    scratch: [1024 * 1024]u8 = undefined,

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
    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const outcome = try process_advance_v1.advance(
        &fixture.CapacityImage.bytes,
        .{ .initial_args = &initial },
        null,
        storage.buffers(),
        &workspace,
    );
    _ = outcome.requested;

    var input_storage: [128 * 1024]u8 = undefined;
    const input = try process_advance_v1.encodeKernelInput(
        &fixture.CapacityImage.bytes,
        .{ .initial_args = &initial },
        null,
        &input_storage,
    );
    const declared_base_memory = (process_advance_v1.KernelArenaLayout{
        .state_bytes = @sizeOf(@TypeOf(storage.state)),
        .candidate_state_bytes = @sizeOf(@TypeOf(storage.candidate)),
        .value_bytes = @sizeOf(@TypeOf(storage.value)),
        .request_bytes = @sizeOf(@TypeOf(storage.request)),
        .environment_bytes = @sizeOf(@TypeOf(storage.environment)),
        .auxiliary_environment_bytes = @sizeOf(@TypeOf(storage.auxiliary_environment)),
        .scratch_bytes = @sizeOf(@TypeOf(storage.scratch)),
        .error_bytes = 4 * 1024,
        .validation_workspace_bytes = @sizeOf(@TypeOf(workspace)),
    }).baseMemoryWithoutOutput(input.len);
    var output_storage: [56]u8 = undefined;
    const output = try process_advance_v1.encodeOutcomeForCapacity(
        outcome,
        input.len,
        1024 * 1024,
        declared_base_memory,
        64,
        &output_storage,
    );
    if ((try process_advance_v1.outcomeEncodedLength(outcome)) <=
        output_storage.len or output[10] != 5)
    {
        return error.ExpectedSerializationCapacity;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try writeInt(stdout, 1);
    try writeInt(stdout, @intCast(input.len));
    try writeInt(stdout, @intCast(output.len));
    try stdout.writeAll(input);
    try stdout.writeAll(output);
    try stdout.flush();
}

fn writeInt(writer: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try writer.writeAll(&bytes);
}
