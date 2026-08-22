const boundary = @import("boundary");
const std = @import("std");

const Lookup = boundary.effect.site(
    0,
    "proof.single-reducer.lookup.v1",
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
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
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
        .label = "single-reducer-proof",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Program = boundary.program("single-reducer-proof", Body);
const options: boundary.MachineOptions = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const Machine = Program.compile(options);
const Image = Program.image(options);
const Reducer = fn (Machine.State, *u64) Machine.Error!Machine.Outcome;

fn reducerDeclarationCount(comptime Owner: type) comptime_int {
    var result = 0;
    inline for (@typeInfo(Owner).@"struct".decls) |declaration| {
        if (@TypeOf(@field(Owner, declaration.name)) == Reducer) result += 1;
    }
    return result;
}

fn functionDeclarationCount(comptime Owner: type) comptime_int {
    var result = 0;
    inline for (@typeInfo(Owner).@"struct".decls) |declaration| {
        switch (@typeInfo(@TypeOf(@field(Owner, declaration.name)))) {
            .@"fn" => result += 1,
            else => {},
        }
    }
    return result;
}

fn freeBytes(allocator: std.mem.Allocator, bytes: []u8) void {
    allocator.free(bytes);
}

comptime {
    if (!@hasDecl(Machine, "step")) {
        @compileError("compiled Boundary Machine has no public step reducer");
    }
    if (@TypeOf(Machine.step) != Reducer) {
        @compileError("compiled Boundary Machine step does not own the Machine ABI reducer signature");
    }
    if (reducerDeclarationCount(Machine) != 1) {
        @compileError("compiled Boundary Machine exposes more than one ABI-shaped reducer");
    }
    if (!@hasDecl(Program, "compile") or
        !@hasDecl(Program, "image") or
        functionDeclarationCount(Program) != 2)
    {
        @compileError("Boundary Program exposes a competing compilation route");
    }
    if (@hasDecl(Image, "step") or @hasDecl(Image, "resume")) {
        @compileError("Boundary image product exposes reducer authority");
    }
    if (@hasDecl(boundary, "Runtime") or
        @hasDecl(boundary, "staticMachine") or
        @hasDecl(boundary, "StaticMachineOptions"))
    {
        @compileError("Boundary public root exposes a competing runtime");
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var image_workspace: boundary.image.ValidationWorkspace = .{};
    const image = try boundary.image.validateImage(
        &Image.bytes,
        &image_workspace,
    );
    var malformed_image = Image.bytes;
    const envelope = try boundary.image.validateEnvelope(&malformed_image);
    const effects_offset: usize = envelope.sections[4].offset;
    const identity_length = std.mem.readInt(
        u32,
        malformed_image[effects_offset + 8 ..][0..4],
        .little,
    );
    const semantic_digest_offset = effects_offset + 4 + 8 +
        identity_length + 12;
    malformed_image[semantic_digest_offset] ^= 0xff;
    var malformed_workspace: boundary.image.ValidationWorkspace = .{};
    if (boundary.image.validateImage(
        &malformed_image,
        &malformed_workspace,
    )) |_| {
        return error.ForgedEffectDigestAccepted;
    } else |err| if (err != error.DigestMismatch) {
        return err;
    }
    var kernel_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &kernel_args, 21, .little);
    var kernel_initial: [4096]u8 = undefined;
    const kernel_initial_length = try boundary.kernel.initial(
        image,
        &kernel_args,
        &kernel_initial,
        &image_workspace,
    );
    var kernel_fuel: u64 = 8;
    var kernel_state: [4096]u8 = undefined;
    var kernel_payload: [4]u8 = undefined;
    var kernel_scratch: [12 * 1024]u8 = undefined;
    const kernel_request = switch (try boundary.kernel.step(
        image,
        kernel_initial[0..kernel_initial_length],
        &kernel_fuel,
        &kernel_state,
        &kernel_payload,
        &kernel_scratch,
        &image_workspace,
    )) {
        .requested => |request| request,
        else => return error.ExpectedEffectRequest,
    };
    const state = try Machine.initialState(allocator, 21);
    defer Machine.deinitState(state);
    var caller_fuel: u64 = 8;
    switch (try Machine.step(state, &caller_fuel)) {
        .request => |request| {
            const direct_state = try Machine.encodeState(
                allocator,
                state,
            );
            defer freeBytes(allocator, direct_state);
            try std.testing.expectEqualSlices(
                u8,
                direct_state,
                kernel_request.state,
            );
            try std.testing.expectEqual(
                request.identity.digest,
                kernel_request.identity.digest,
            );
            try std.testing.expectEqual(
                request.identity.continuation_digest,
                kernel_request.identity.continuation_digest,
            );
            try std.testing.expectEqual(
                @as(u32, 21),
                std.mem.readInt(u32, kernel_request.payload[0..4], .little),
            );
            try std.testing.expectEqual(caller_fuel, kernel_fuel);
            const prepared = try Machine.prepareResume(state, request);
            try Machine.@"resume"(prepared, @as(u32, 42));
            Machine.deinitPreparedResume(prepared);
            const direct_resumed = try Machine.encodeState(
                allocator,
                state,
            );
            defer freeBytes(allocator, direct_resumed);
            var response: [4]u8 = undefined;
            std.mem.writeInt(u32, &response, 42, .little);
            var kernel_resumed: [4096]u8 = undefined;
            @memset(&kernel_resumed, 0xa5);
            var stale_identity = kernel_request.identity;
            stale_identity.sequence += 1;
            try std.testing.expectError(
                error.InvalidState,
                boundary.kernel.@"resume"(
                    image,
                    kernel_request.state,
                    stale_identity,
                    &response,
                    &kernel_resumed,
                    &image_workspace,
                ),
            );
            try std.testing.expectEqual(@as(u8, 0xa5), kernel_resumed[0]);
            const kernel_resumed_length = try boundary.kernel.@"resume"(
                image,
                kernel_request.state,
                kernel_request.identity,
                &response,
                &kernel_resumed,
                &image_workspace,
            );
            try std.testing.expectEqualSlices(
                u8,
                direct_resumed,
                kernel_resumed[0..kernel_resumed_length],
            );
            const direct_done = switch (try Machine.step(
                state,
                &caller_fuel,
            )) {
                .done => |value| value,
                else => return error.ExpectedEffectRequest,
            };
            defer direct_done.deinit();
            var kernel_terminal_state: [4096]u8 = undefined;
            const kernel_done = switch (try boundary.kernel.step(
                image,
                kernel_resumed[0..kernel_resumed_length],
                &kernel_fuel,
                &kernel_terminal_state,
                &kernel_payload,
                &kernel_scratch,
                &image_workspace,
            )) {
                .done => |value| value,
                else => return error.ExpectedEffectRequest,
            };
            try std.testing.expectEqual(caller_fuel, kernel_fuel);
            try std.testing.expectEqual(
                direct_done.value().*,
                std.mem.readInt(u32, kernel_done[0..4], .little),
            );
        },
        else => return error.ExpectedEffectRequest,
    }

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "single_boundary_reducer={}\n" ++
            "reducer_public_entry=Program.compile(...).step\n" ++
            "program_compile_surface_count={d}\n",
        .{
            reducerDeclarationCount(Machine) == 1,
            @intFromBool(@hasDecl(Program, "compile")),
        },
    );
    try stdout.flush();
}
