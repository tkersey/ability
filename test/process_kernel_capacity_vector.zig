const boundary = @import("boundary");
const fixture = @import("process_kernel_fixture");
const process_advance_v1 = @import("process_advance_v1");
const std = @import("std");

const Arena = process_advance_v1.CapacityArena;
const Storage = struct {
    input: Arena(.input, 128 * 1024) = .{},
    output: Arena(.output, 64) = .{},
    state: Arena(.output, 64 * 1024) = .{},
    value: Arena(.output, 64 * 1024) = .{},
    request: Arena(.output, 64 * 1024) = .{},
    candidate: Arena(.output, 64 * 1024) = .{},
    environment: Arena(.output, 64 * 1024) = .{},
    auxiliary_environment: Arena(.output, 64 * 1024) = .{},
    scratch: Arena(.scratch, 1024 * 1024) = .{},

    fn buffers(self: *@This()) process_advance_v1.Buffers {
        return .{
            .output_state = &self.state.bytes,
            .output_value = &self.value.bytes,
            .output_request = &self.request.bytes,
            .candidate_state = &self.candidate.bytes,
            .environment = &self.environment.bytes,
            .auxiliary_environment = &self.auxiliary_environment.bytes,
            .scratch = &self.scratch.bytes,
        };
    }
};

pub fn main(init: std.process.Init) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 17, .little);
    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const attempt = try process_advance_v1.advanceAttempt(
        &fixture.CapacityImage.bytes,
        .{ .initial_args = &initial },
        null,
        storage.buffers(),
        &workspace,
    );
    const outcome = attempt.outcome;
    _ = outcome.requested;

    const input = try process_advance_v1.encodeKernelInput(
        &fixture.CapacityImage.bytes,
        .{ .initial_args = &initial },
        null,
        &storage.input.bytes,
    );
    const output = try process_advance_v1.encodeOutcomeForCapacity(
        outcome,
        attempt.capacity,
        input.len,
        &storage,
        64,
        &storage.output.bytes,
    );
    if ((try process_advance_v1.outcomeEncodedLength(outcome)) <=
        storage.output.bytes.len or output[10] != 5)
    {
        return error.ExpectedSerializationCapacity;
    }
    if (std.mem.readInt(u64, output[48..56], .little) !=
        attempt.capacity.scratch_bytes)
    {
        return error.SerializationLostScratchEvidence;
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
