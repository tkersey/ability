const cir = @import("control_ir");
const driver = @import("driver");
const program_v2 = @import("program_v2");
const std = @import("std");

const Lookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.lookup.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const continuation_arguments = [_]cir.EdgeArgument{
    .@"resume",
};
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
    pub const Failure = enum {
        rejected,
    };
    pub const contract_bytes = "typed-lookup-source\x00v1";
    pub const effect_sites = .{Lookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "typed-lookup-source",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Program = program_v2.program("typed-lookup", Body);
const CompiledMachine = Program.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const helper_call_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
const helper_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const helper_effect_arguments = [_]cir.EdgeArgument{.@"resume"};
const helper_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &helper_call_arguments,
            },
            .continuation = .{
                .target = 3,
                .arguments = &helper_return_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{1},
            .continuation = .{
                .target = 2,
                .arguments = &helper_effect_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{2},
        .terminator = .{ .return_to_caller = 2 },
    },
    .{
        .id = 3,
        .role = .terminal_handoff,
        .parameters = &.{3},
        .terminator = .{ .return_value = 3 },
    },
};

const HelperEffectBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        rejected,
    };
    pub const constants = .{};
    pub const effect_sites = .{Lookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "helper-effect-resume-transaction",
        .value_types = &.{ u32_type, u32_type, u32_type, u32_type },
        .blocks = &helper_blocks,
        .entry = 0,
        .result_type = u32_type,
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = u32_type,
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = u32_type,
            },
        },
    };
};

const HelperEffectMachine = program_v2.program(
    "helper-effect-resume-transaction",
    HelperEffectBody,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const LargeResponse = ?[512]u8;

const LargeLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.large-lookup.v1";
    pub const Payload = u32;
    pub const Resume = LargeResponse;
};

const large_response_arguments = [_]cir.EdgeArgument{.@"resume"};
const large_response_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &large_response_arguments,
            },
            .resume_type = .{ .schema = 0 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const LargeResponseBody = struct {
    pub const InitialArgs = u32;
    pub const Result = LargeResponse;
    pub const Failure = enum {
        rejected,
    };
    pub const effect_sites = .{LargeLookup};
    pub const schema_types = .{LargeResponse};
    pub const control_ir: cir.Program = .{
        .label = "large-response-state-preflight",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .schema = 0 },
        },
        .blocks = &large_response_blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};

const LargeResponseMachine = program_v2.program(
    "large-response-state-preflight",
    LargeResponseBody,
).compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 128,
    .maximum_machine_fuel = 32,
});

fn identityBody(
    comptime constant_value: u32,
    comptime ignored_contract_bytes: []const u8,
) type {
    return struct {
        const identity_instructions = [_]cir.Instruction{
            .{
                .kind = .constant,
                .result = 0,
                .operation = .{ .constant = 0 },
            },
        };
        const identity_blocks = [_]cir.Block{
            .{
                .id = 0,
                .instructions = &identity_instructions,
                .terminator = .{ .return_value = 0 },
            },
        };

        pub const InitialArgs = void;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const contract_bytes = ignored_contract_bytes;
        pub const constants = .{constant_value};
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "identity-body-debug-label",
            .value_types = &.{.{ .scalar = .u32 }},
            .blocks = &identity_blocks,
            .entry = 0,
            .result_type = .{ .scalar = .u32 },
        };
    };
}

fn limitedIdentityBody(comptime constant_value: u32) type {
    const Base = identityBody(constant_value, "limited-compiler-policy");
    return struct {
        pub const InitialArgs = Base.InitialArgs;
        pub const Result = Base.Result;
        pub const Failure = Base.Failure;
        pub const constants = Base.constants;
        pub const effect_sites = Base.effect_sites;
        pub const schema_types = Base.schema_types;
        pub const control_ir = Base.control_ir;
        pub const compiler_limits: cir.CompilerLimits = .{
            .maximum_values = 8,
            .maximum_blocks = 8,
            .maximum_constructors = 8,
            .maximum_environment_fields = 8,
            .maximum_invariant_terms = 4,
            .maximum_generated_operations = 4,
        };
    };
}

test "Program.compile generates direct exact-live RNF Machine" {
    try std.testing.expectEqual(@as(usize, 3), Program.rnf.constructor_count);
    try std.testing.expect(
        Program.generated_reducer_operation_count <=
            Program.compiler_limits.maximum_generated_operations,
    );
    try std.testing.expectEqual(@as(u32, 2), CompiledMachine.abi_version);
    try std.testing.expectEqual(
        @as(usize, 0),
        CompiledMachine.EffectRow.after_site_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        CompiledMachine.Manifest.effect_site_count,
    );
    const Site = CompiledMachine.EffectRow.site(0);
    try std.testing.expectEqual(@as(u32, 0), Site.site_ordinal);
    try std.testing.expect(Site.Payload == u32);
    try std.testing.expect(Site.Resume == u32);
    try std.testing.expect(Site.Result == u32);
    try std.testing.expectEqual(.single_resume, Site.response_mode);
    try std.testing.expectEqualStrings(
        "test.lookup.v1",
        Site.semantic_identity,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &Site.contract_digest,
        &([_]u8{0} ** 32),
    ));

    const state = try CompiledMachine.initialState(std.testing.allocator, 21);
    defer CompiledMachine.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try CompiledMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(
        @as(u32, 0),
        request.identity.site_ordinal,
    );
    try std.testing.expectEqual(
        request.sequence,
        request.identity.sequence,
    );
    try std.testing.expectEqual(
        request.constructor_id,
        request.identity.constructor_id,
    );
    try std.testing.expectEqualSlices(
        u8,
        &CompiledMachine.Manifest.machine_contract_digest,
        &request.identity.machine_contract_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Site.contract_digest,
        &request.identity.effect_site_digest,
    );
    switch (request.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 21), payload),
    }
    var forged = request;
    forged.identity.digest[0] ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        CompiledMachine.@"resume"(state, forged, @as(u32, 42)),
    );
    const unchanged = try CompiledMachine.current(state);
    try std.testing.expectEqualSlices(
        u8,
        &request.identity.digest,
        &unchanged.identity.digest,
    );
    try CompiledMachine.@"resume"(state, request, @as(u32, 42));
    const done = switch (try CompiledMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 42), done.value().*);
}

test "Program.compile identity derives from semantics and excludes labels" {
    const First = program_v2.program(
        "first-debug-label",
        identityBody(7, "caller-material-one"),
    ).compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const Renamed = program_v2.program(
        "second-debug-label",
        identityBody(7, "caller-material-two"),
    ).compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const Different = program_v2.program(
        "first-debug-label",
        identityBody(8, "caller-material-one"),
    ).compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const Limited = program_v2.program(
        "third-debug-label",
        limitedIdentityBody(7),
    ).compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });

    try std.testing.expectEqualSlices(
        u8,
        &First.Manifest.machine_contract_digest,
        &Renamed.Manifest.machine_contract_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &First.Manifest.machine_contract_digest,
        &Limited.Manifest.machine_contract_digest,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &First.Manifest.machine_contract_digest,
        &Different.Manifest.machine_contract_digest,
    ));

    const state = try First.initialState(std.testing.allocator, {});
    defer First.deinitState(state);
    const bytes = try First.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(
        error.ProgramContractViolation,
        Different.decodeState(std.testing.allocator, bytes),
    );
}

test "debug metadata exposes a diagnostic constructor source map" {
    const DebugMachine = Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
        .debug_metadata = true,
    });

    try std.testing.expect(DebugMachine.Manifest.includes_debug_metadata);
    try std.testing.expectEqualSlices(
        u8,
        &CompiledMachine.Manifest.machine_contract_digest,
        &DebugMachine.Manifest.machine_contract_digest,
    );
    try std.testing.expectEqualStrings(
        "typed-lookup",
        DebugMachine.debug_metadata.program_label,
    );
    try std.testing.expectEqual(
        Program.rnf.constructor_count,
        DebugMachine.debug_metadata.constructors.len,
    );
    for (
        DebugMachine.debug_metadata.constructors,
        0..,
    ) |constructor, index| {
        try std.testing.expectEqual(
            @as(u32, @intCast(index)),
            constructor.constructor_id,
        );
        try std.testing.expect(constructor.name.len != 0);
        try std.testing.expect(constructor.kind.len != 0);
    }
}

test "Driver handles effects without owning another reducer" {
    const LocalDriver = driver.Driver(CompiledMachine);
    var local = try LocalDriver.init(std.testing.allocator, 9);
    defer local.deinit();
    var handler = struct {
        pub fn handle(
            _: *@This(),
            comptime tag: anytype,
            payload: anytype,
        ) !switch (tag) {
            .s0 => u32,
        } {
            return payload * 2;
        }
    }{};
    var fuel: u64 = 8;
    const done = switch (try local.run(&handler, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 18), done.value().*);
}

test "Driver returns the exact pending request and retries handler errors" {
    const LocalDriver = driver.Driver(CompiledMachine);
    var local = try LocalDriver.init(std.testing.allocator, 9);
    defer local.deinit();
    var handler = struct {
        attempts: u8 = 0,

        pub fn handle(
            self: *@This(),
            comptime tag: anytype,
            payload: anytype,
        ) error{Transient}!switch (tag) {
            .s0 => u32,
        } {
            self.attempts += 1;
            if (self.attempts == 1) return error.Transient;
            return payload * 2;
        }
    }{};

    var fuel: u64 = 8;
    const handler_error = switch (try local.run(&handler, &fuel)) {
        .handler_error => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(error.Transient, handler_error.err);
    switch (handler_error.request.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 9), payload),
    }
    const parked = try CompiledMachine.current(local.state);
    try std.testing.expectEqual(
        parked.sequence,
        handler_error.request.sequence,
    );
    try std.testing.expectEqualSlices(
        u8,
        &parked.identity.digest,
        &handler_error.request.identity.digest,
    );

    const done = switch (try local.run(&handler, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u8, 2), handler.attempts);
    try std.testing.expectEqual(@as(u32, 18), done.value().*);
}

test "Driver allocates a multi-frame resume before invoking its handler" {
    const LocalDriver = driver.Driver(HelperEffectMachine);
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{},
    );
    var local = try LocalDriver.init(failing.allocator(), 9);
    defer local.deinit();

    var fuel: u64 = 8;
    const request = switch (try HelperEffectMachine.step(
        local.state,
        &fuel,
    )) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    var handler = struct {
        attempts: u8 = 0,

        pub fn handle(
            self: *@This(),
            comptime tag: anytype,
            payload: anytype,
        ) !switch (tag) {
            .s0 => u32,
        } {
            self.attempts += 1;
            return payload * 2;
        }
    }{};

    // prepareResume first allocates its owner, then clones the multi-frame
    // stack. Fail that clone so no handler authority has been invoked.
    failing.fail_index = failing.allocations + 1;
    try std.testing.expectError(
        error.OutOfMemory,
        local.run(&handler, &fuel),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u8, 0), handler.attempts);
    failing.fail_index = std.math.maxInt(usize);
    const parked = try HelperEffectMachine.current(local.state);
    try std.testing.expectEqualSlices(
        u8,
        &request.identity.digest,
        &parked.identity.digest,
    );

    const done = switch (try local.run(&handler, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u8, 1), handler.attempts);
    try std.testing.expectEqual(@as(u32, 18), done.value().*);
}

test "Machine preflights the complete response state before request authority" {
    const LocalDriver = driver.Driver(LargeResponseMachine);
    var local = try LocalDriver.init(std.testing.allocator, 9);
    defer local.deinit();
    var handler = struct {
        attempts: u8 = 0,

        pub fn handle(
            self: *@This(),
            comptime tag: anytype,
            _: anytype,
        ) !switch (tag) {
            .s0 => LargeResponse,
        } {
            self.attempts += 1;
            return null;
        }
    }{};

    const before = try LargeResponseMachine.encodeState(
        std.testing.allocator,
        local.state,
    );
    defer std.testing.allocator.free(before);
    var fuel: u64 = 8;
    try std.testing.expectError(
        error.ProgramContractViolation,
        local.run(&handler, &fuel),
    );
    try std.testing.expectEqual(@as(u8, 0), handler.attempts);
    try std.testing.expectEqual(@as(u64, 8), fuel);
    try std.testing.expectError(
        error.ProgramContractViolation,
        LargeResponseMachine.current(local.state),
    );
    const after = try LargeResponseMachine.encodeState(
        std.testing.allocator,
        local.state,
    );
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(
        u8,
        before,
        after,
    );
}
