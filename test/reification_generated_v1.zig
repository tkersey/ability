const cir = @import("control_ir");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const GeneratedEffect = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "boundary.generated.effect.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

fn GeneratedBody(comptime bias: u32) type {
    return struct {
        const label = std.fmt.comptimePrint(
            "generated-reification-{d}",
            .{bias},
        );
        const u32_type: cir.ValueType = .{ .scalar = .u32 };
        const call_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
        const call_return_arguments = [_]cir.EdgeArgument{.@"resume"};
        const effect_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
        const helper_instructions = [_]cir.Instruction{
            .{
                .kind = .constant,
                .result = 3,
                .operation = .{ .constant = 0 },
            },
            .{
                .kind = .pure,
                .result = 4,
                .operands = &.{ 2, 3 },
                .operation = .integer_add,
            },
        };
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .call,
                    .callee_function = 1,
                    .callee = .{
                        .target = 1,
                        .arguments = &call_arguments,
                    },
                    .continuation = .{
                        .target = 2,
                        .arguments = &call_return_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .function_id = 1,
                .parameters = &.{2},
                .instructions = &helper_instructions,
                .terminator = .{ .return_to_caller = 4 },
            },
            .{
                .id = 2,
                .role = .call_return,
                .parameters = &.{1},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{1},
                    .continuation = .{
                        .target = 3,
                        .arguments = &effect_resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 3,
                .role = .after_handler,
                .parameters = &.{5},
                .terminator = .{ .return_value = 5 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { arithmetic_overflow };
        pub const constants = .{bias};
        pub const effect_sites = .{GeneratedEffect};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = label,
            .value_types = &.{
                u32_type,
                u32_type,
                u32_type,
                u32_type,
                u32_type,
                u32_type,
            },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
            .functions = &.{
                .{ .id = 0, .entry = 0, .result_type = u32_type },
                .{ .id = 1, .entry = 1, .result_type = u32_type },
            },
        };
    };
}

fn GeneratedProgram(comptime bias: u32) type {
    const Body = GeneratedBody(bias);
    return program_v2.program(Body.label, Body);
}

const ProgramOne = GeneratedProgram(1);
const ProgramThree = GeneratedProgram(3);
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
};

const FiniteStates = struct {
    digests: [64][32]u8 = undefined,
    count: usize = 0,

    fn insert(self: *@This(), bytes: []const u8) void {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        for (self.digests[0..self.count]) |existing| {
            if (std.mem.eql(u8, &existing, &digest)) return;
        }
        self.digests[self.count] = digest;
        self.count += 1;
    }
};

fn expectStateBytesEqual(
    comptime Direct: type,
    comptime Kernel: type,
    direct: Direct.State,
    kernel: Kernel.State,
) ![]u8 {
    const direct_bytes = try Direct.encodeState(std.testing.allocator, direct);
    errdefer std.testing.allocator.free(direct_bytes);
    const kernel_bytes = try Kernel.encodeState(std.testing.allocator, kernel);
    defer std.testing.allocator.free(kernel_bytes);
    try std.testing.expectEqualSlices(u8, direct_bytes, kernel_bytes);
    return direct_bytes;
}

fn resumeRequest(
    comptime Machine: type,
    state: Machine.State,
    request: Machine.Request,
    response: u32,
) !void {
    const prepared = try Machine.prepareResume(state, request);
    defer Machine.deinitPreparedResume(prepared);
    try Machine.@"resume"(prepared, response);
}

fn runGeneratedTrace(
    comptime Program: type,
    comptime bias: u32,
    input: u32,
    response: u32,
    require_yield: bool,
    require_switch: bool,
    finite_states: ?*FiniteStates,
    hasher: *std.crypto.hash.sha2.Sha256,
) !void {
    const Direct = Program.compile(options);
    const Kernel = Program.kernelMachine(options);
    const direct = try Direct.initialState(std.testing.allocator, input);
    defer Direct.deinitState(direct);
    const kernel = try Kernel.initialState(std.testing.allocator, input);
    defer Kernel.deinitState(kernel);
    if (finite_states) |states| {
        const initial = try Direct.encodeState(std.testing.allocator, direct);
        defer std.testing.allocator.free(initial);
        states.insert(initial);
    }
    if (require_yield) {
        var direct_zero: u64 = 0;
        var kernel_zero: u64 = 0;
        try std.testing.expectEqual(Direct.Outcome.yielded, try Direct.step(direct, &direct_zero));
        try std.testing.expectEqual(Kernel.Outcome.yielded, try Kernel.step(kernel, &kernel_zero));
        try std.testing.expectEqual(@as(u64, 0), direct_zero);
        try std.testing.expectEqual(direct_zero, kernel_zero);
        const yielded = try expectStateBytesEqual(Direct, Kernel, direct, kernel);
        std.testing.allocator.free(yielded);
    }

    var direct_fuel: u64 = 64;
    var kernel_fuel: u64 = 64;
    const direct_request = switch (try Direct.step(direct, &direct_fuel)) {
        .request => |request| request,
        else => return error.ExpectedRequest,
    };
    const kernel_request = switch (try Kernel.step(kernel, &kernel_fuel)) {
        .request => |request| request,
        else => return error.ExpectedRequest,
    };
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
    try std.testing.expectEqualSlices(
        u8,
        &direct_request.identity.digest,
        &kernel_request.identity.digest,
    );
    switch (direct_request.value) {
        .s0 => |payload| try std.testing.expect(payload == input + bias),
    }
    const parked = try expectStateBytesEqual(Direct, Kernel, direct, kernel);
    defer std.testing.allocator.free(parked);
    if (finite_states) |states| states.insert(parked);
    hasher.update(parked);
    hasher.update(&direct_request.identity.digest);

    if (require_switch) {
        const switched = try Kernel.decodeState(std.testing.allocator, parked);
        defer Kernel.deinitState(switched);
        const switched_request = (try Kernel.current(switched)) orelse
            return error.ExpectedRequest;
        try resumeRequest(Kernel, switched, switched_request, response);
        var switched_fuel: u64 = 64;
        const switched_done = switch (try Kernel.step(switched, &switched_fuel)) {
            .done => |result| result,
            else => return error.ExpectedDone,
        };
        defer switched_done.deinit();
        try std.testing.expectEqual(response, switched_done.value().*);
    }

    try resumeRequest(Direct, direct, direct_request, response);
    try resumeRequest(Kernel, kernel, kernel_request, response);
    const resumed = try expectStateBytesEqual(Direct, Kernel, direct, kernel);
    defer std.testing.allocator.free(resumed);
    if (finite_states) |states| states.insert(resumed);
    hasher.update(resumed);
    const direct_done = switch (try Direct.step(direct, &direct_fuel)) {
        .done => |result| result,
        else => return error.ExpectedDone,
    };
    defer direct_done.deinit();
    const kernel_done = switch (try Kernel.step(kernel, &kernel_fuel)) {
        .done => |result| result,
        else => return error.ExpectedDone,
    };
    defer kernel_done.deinit();
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
    try std.testing.expectEqual(response, direct_done.value().*);
    try std.testing.expectEqual(direct_done.value().*, kernel_done.value().*);
    var scalar_bytes: [16]u8 = undefined;
    std.mem.writeInt(u32, scalar_bytes[0..4], input, .little);
    std.mem.writeInt(u32, scalar_bytes[4..8], response, .little);
    std.mem.writeInt(u64, scalar_bytes[8..16], direct_fuel, .little);
    hasher.update(&scalar_bytes);
}

test "two finite Programs exhaust their bounded input response and fuel frontier" {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var states: FiniteStates = .{};
    inline for (.{ .{ ProgramOne, 1 }, .{ ProgramThree, 3 } }) |entry| {
        const Program = entry[0];
        for ([_]u32{ 0, 1 }) |input| {
            for ([_]u32{ 0, 1 }) |response| {
                for ([_]u64{ 0, 1, 2, 8, 64 }) |fuel| {
                    try runGeneratedTrace(
                        Program,
                        entry[1],
                        input,
                        response,
                        fuel == 0,
                        true,
                        &states,
                        &hasher,
                    );
                }
            }
        }
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    try std.testing.expect(!std.mem.eql(u8, &digest, &([_]u8{0} ** 32)));
    try std.testing.expectEqual(@as(usize, 12), states.count);
}

test "seeded source generator executes ten thousand differential traces" {
    var random = std.Random.DefaultPrng.init(0x42454931_00010000);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (0..10_000) |trace| {
        const input = random.random().intRangeLessThan(u32, 0, 1024);
        const response = random.random().intRangeLessThan(u32, 0, 1024);
        if (trace & 1 == 0) {
            try runGeneratedTrace(
                ProgramOne,
                1,
                input,
                response,
                trace % 5 == 0,
                trace % 10 == 0,
                null,
                &hasher,
            );
        } else {
            try runGeneratedTrace(
                ProgramThree,
                3,
                input,
                response,
                trace % 5 == 0,
                trace % 10 == 0,
                null,
                &hasher,
            );
        }
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const expected = [_]u8{
        0x35, 0x56, 0xaf, 0x59, 0xd3, 0x7a, 0xbe, 0x12,
        0xf4, 0xd3, 0x3d, 0x46, 0x98, 0x76, 0x6e, 0xfc,
        0x3e, 0x4b, 0x2a, 0xe4, 0xbf, 0x50, 0x2f, 0x26,
        0x11, 0x0b, 0xd9, 0xad, 0x22, 0x23, 0x9f, 0x16,
    };
    try std.testing.expectEqualSlices(u8, &expected, &digest);
}
