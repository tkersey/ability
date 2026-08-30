const boundary = @import("boundary");
const fixture = @import("process_kernel_fixture");
const process_advance_v1 = @import("process_advance_v1");
const std = @import("std");

const storage_capacities: process_advance_v1.StorageCapacities = .{
    .input = 128 * 1024,
    .output = 64,
    .state = 64 * 1024,
    .value = 64 * 1024,
    .request = 64 * 1024,
    .environment = 64 * 1024,
    .scratch = 1024 * 1024,
};
const Storage = process_advance_v1.CapacityStorage(storage_capacities);

const default_storage_capacities: process_advance_v1.StorageCapacities = .{
    .input = 32 * 1024 * 1024,
    .output = 16 * 1024 * 1024,
    .state = 8 * 1024 * 1024,
    .value = 4 * 1024 * 1024,
    .request = 4 * 1024 * 1024,
    .environment = 8 * 1024 * 1024,
    .scratch = 64 * 1024 * 1024,
};
const DefaultStorage = process_advance_v1.CapacityStorage(
    default_storage_capacities,
);
var default_storage: DefaultStorage = .{};

const expected_live_pages: u64 = 2_457;
const expected_occupied_bytes: u64 = 160_977_264;
const expected_input_capacity: u64 = 33_554_432;
const required_input_length: usize = 33_554_433;
const required_instance_length: usize = 33_553_647;

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    defer arguments.deinit();
    _ = arguments.skip();
    const first = arguments.next() orelse return error.MissingLivePages;
    if (std.mem.eql(u8, first, "--conformance-corpus-v1")) {
        const live_pages = try parseArgument(&arguments, error.MissingLivePages);
        const occupied_bytes = try parseArgument(
            &arguments,
            error.MissingOccupiedBytes,
        );
        const input_capacity = try parseArgument(
            &arguments,
            error.MissingInputCapacity,
        );
        if (arguments.next() != null) return error.UnexpectedArgument;
        return writeConformance(
            init,
            live_pages,
            occupied_bytes,
            input_capacity,
        );
    }
    const live_pages = try std.fmt.parseInt(u64, first, 10);
    const occupied_bytes = try std.fmt.parseInt(
        u64,
        arguments.next() orelse return error.MissingOccupiedBytes,
        10,
    );
    if (arguments.next() != null) return error.UnexpectedArgument;
    return writeLegacy(init, live_pages, occupied_bytes);
}

fn writeLegacy(
    init: std.process.Init,
    live_pages: u64,
    occupied_bytes: u64,
) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 17, .little);
    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const attempt = try process_advance_v1.advanceAttemptForPhysicalStorage(
        storage_capacities,
        &fixture.CapacityImage.bytes,
        .{ .initial_args = &initial },
        null,
        &storage,
        live_pages,
        occupied_bytes,
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
        live_pages,
        occupied_bytes,
        &storage.output.bytes,
    );
    if ((try process_advance_v1.outcomeEncodedLength(outcome)) <=
        storage.output.bytes.len or output[10] != 5)
    {
        return error.ExpectedSerializationCapacity;
    }
    if (std.mem.readInt(u64, output[48..56], .little) !=
        attempt.capacity.requiredFor(.scratch))
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

fn writeConformance(
    init: std.process.Init,
    live_pages: u64,
    occupied_bytes: u64,
    input_capacity: u64,
) !void {
    if (live_pages != expected_live_pages or
        occupied_bytes != expected_occupied_bytes or
        input_capacity != expected_input_capacity or
        input_capacity != @as(u64, default_storage_capacities.input) or
        fixture.CapacityImage.bytes.len != 746)
    {
        return error.ReleasedKernelProbeMismatch;
    }
    if (@as(u64, required_input_length) != input_capacity + 1 or
        required_instance_length + process_advance_v1.kernel_input_header_length +
            fixture.CapacityImage.bytes.len != required_input_length)
    {
        return error.InvalidRequiredInputConstruction;
    }

    const initial_args = try init.gpa.alloc(u8, required_instance_length);
    defer init.gpa.free(initial_args);
    @memset(initial_args, 0);
    var workspace: boundary.image.ValidationWorkspace = .{};
    const attempt = try process_advance_v1.advanceAttemptForPhysicalStorage(
        default_storage_capacities,
        &fixture.CapacityImage.bytes,
        .{ .initial_args = initial_args },
        null,
        &default_storage,
        live_pages,
        occupied_bytes,
        &workspace,
    );
    try expectRequirement(attempt.outcome.needs_capacity);
    if (attempt.capacity.requiredFor(.input) !=
        @as(u64, required_input_length) or
        attempt.capacity.requiredFor(.output) !=
            process_advance_v1.needs_capacity_encoded_length or
        attempt.capacity.requiredFor(.scratch) != 0)
    {
        return error.UnexpectedCapacityEvidence;
    }

    const output = try process_advance_v1.encodeOutcomeForCapacity(
        attempt.outcome,
        attempt.capacity,
        required_input_length,
        &default_storage,
        live_pages,
        occupied_bytes,
        &default_storage.output.bytes,
    );
    try expectEncodedRequirement(output);
    var input_header: [process_advance_v1.kernel_input_header_length]u8 =
        undefined;
    const header = try process_advance_v1.encodeKernelInputHeader(
        0,
        false,
        @intCast(fixture.CapacityImage.bytes.len),
        @intCast(initial_args.len),
        0,
        &input_header,
    );

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("BPCGEN1\x00");
    try writeUnsigned(stdout, u32, 1);
    try writeUnsigned(stdout, u32, 1);
    try writeUnsigned(stdout, u16, @intCast("needs-capacity".len));
    try stdout.writeAll(&.{ 1, 0 });
    try writeUnsigned(stdout, u64, @intCast(required_input_length));
    try writeUnsigned(stdout, u64, @intCast(output.len));
    try stdout.writeAll("needs-capacity");
    try stdout.writeAll(header);
    try stdout.writeAll(&fixture.CapacityImage.bytes);
    try stdout.writeAll(initial_args);
    try stdout.writeAll(output);
    try stdout.flush();
}

fn expectRequirement(requirement: process_advance_v1.CapacityRequirement) !void {
    if (requirement.minimum_input_bytes != @as(u64, required_input_length) or
        requirement.minimum_output_bytes !=
            process_advance_v1.needs_capacity_encoded_length or
        requirement.minimum_scratch_bytes != 0 or
        requirement.minimum_memory_pages != expected_live_pages)
    {
        return error.UnexpectedCapacityRequirement;
    }
}

fn expectEncodedRequirement(output: []const u8) !void {
    if (output.len != process_advance_v1.needs_capacity_encoded_length or
        !std.mem.eql(u8, output[0..8], &process_advance_v1.outcome_magic) or
        std.mem.readInt(u16, output[8..10], .little) !=
            process_advance_v1.outcome_format_version or
        output[10] != 5 or output[11] != 0 or
        std.mem.readInt(u64, output[12..20], .little) != 32 or
        std.mem.readInt(u64, output[20..28], .little) != 0 or
        !allZero(output[28..32]) or
        std.mem.readInt(u64, output[32..40], .little) !=
            @as(u64, required_input_length) or
        std.mem.readInt(u64, output[40..48], .little) !=
            process_advance_v1.needs_capacity_encoded_length or
        std.mem.readInt(u64, output[48..56], .little) != 0 or
        std.mem.readInt(u64, output[56..64], .little) != expected_live_pages)
    {
        return error.UnexpectedEncodedCapacityRequirement;
    }
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}

fn parseArgument(
    arguments: *std.process.Args.Iterator,
    missing: anyerror,
) !u64 {
    return std.fmt.parseInt(
        u64,
        arguments.next() orelse return missing,
        10,
    );
}

fn writeInt(writer: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try writer.writeAll(&bytes);
}

fn writeUnsigned(writer: *std.Io.Writer, comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try writer.writeAll(&bytes);
}
