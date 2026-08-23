const cir = @import("control_ir");
const driver = @import("driver");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Text4 = portable_value.Text(4);

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

const CanonicalTextLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.canonical-text.v1";
    pub const Payload = Text4;
    pub const Resume = Text4;
};
const canonical_text_arguments = [_]cir.EdgeArgument{.@"resume"};
const canonical_text_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &canonical_text_arguments,
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
const CanonicalTextBody = struct {
    pub const InitialArgs = Text4;
    pub const Result = Text4;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{CanonicalTextLookup};
    pub const schema_types = .{Text4};
    pub const control_ir: cir.Program = .{
        .label = "canonical-text-ingress",
        .value_types = &.{ .{ .schema = 0 }, .{ .schema = 0 } },
        .blocks = &canonical_text_blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};
const CanonicalTextMachine = program_v2.program(
    "canonical-text-ingress",
    CanonicalTextBody,
).compile(.{});

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
const LargeResponseKernelMachine = program_v2.program(
    "large-response-state-preflight",
    LargeResponseBody,
).kernelMachine(.{
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

fn largeValueBody(comptime value_count: usize) type {
    comptime if (value_count < 65) {
        @compileError("large Control IR fixture must cross the former 64-value ceiling");
    };
    return struct {
        const value_types = [_]cir.ValueType{u32_type} ** value_count;
        const instructions = blk: {
            var result: [value_count - 1]cir.Instruction = undefined;
            for (1..value_count) |index| {
                result[index - 1] = .{
                    .kind = .copy,
                    .result = @intCast(index),
                    .operands = &.{@as(cir.ValueId, @intCast(index - 1))},
                    .operation = .copy,
                };
            }
            break :blk result;
        };
        const large_blocks = [_]cir.Block{.{
            .id = 0,
            .parameters = &.{0},
            .instructions = &instructions,
            .terminator = .{ .return_value = value_count - 1 },
        }};

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const compiler_limits: cir.CompilerLimits = .{
            .maximum_values = value_count,
            .maximum_blocks = 1,
            .maximum_constructors = 4,
            .maximum_environment_fields = 1,
            .maximum_invariant_terms = 1,
            .maximum_generated_operations = 512,
        };
        pub const control_ir: cir.Program = .{
            .label = "large-value-control-ir",
            .value_types = &value_types,
            .blocks = &large_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const LargeValueProgram = program_v2.program(
    "large-value-control-ir",
    largeValueBody(384),
);
const LargeValueMachine = LargeValueProgram.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 512,
});

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
    try std.testing.expect(!std.mem.eql(
        u8,
        &Site.semantic_contract_digest,
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
        CompiledMachine.prepareResume(state, forged),
    );
    const unchanged = (try CompiledMachine.current(state)).?;
    try std.testing.expectEqualSlices(
        u8,
        &request.identity.digest,
        &unchanged.identity.digest,
    );
    {
        const prepared_resume = try CompiledMachine.prepareResume(state, request);
        defer CompiledMachine.deinitPreparedResume(prepared_resume);
        try CompiledMachine.@"resume"(prepared_resume, @as(u32, 42));
    }
    const done = switch (try CompiledMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 42), done.value().*);
}

test "Program.compile admits a bounded Control IR above 64 values" {
    try std.testing.expectEqual(@as(usize, 384), LargeValueProgram.compiler_limits.maximum_values);
    try std.testing.expectEqual(@as(usize, 384), LargeValueProgram.control_ir.value_types.len);

    const state = try LargeValueMachine.initialState(std.testing.allocator, @as(u32, 37));
    defer LargeValueMachine.deinitState(state);
    var fuel: u64 = 512;
    const done = switch (try LargeValueMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 37), done.value().*);
}

test "Machine canonicalizes typed initial and response ingress" {
    var initial = try Text4.fromSlice("in");
    initial.storage[3] = 0xa1;
    const state = try CanonicalTextMachine.initialState(
        std.testing.allocator,
        initial,
    );
    defer CanonicalTextMachine.deinitState(state);

    var fuel: u64 = 8;
    const request = switch (try CanonicalTextMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (request.value) {
        .s0 => |payload| {
            try std.testing.expectEqualStrings("in", try payload.slice());
            try std.testing.expectEqual(@as(u8, 0), payload.storage[3]);
        },
    }

    {
        const prepared_resume = try CanonicalTextMachine.prepareResume(
            state,
            request,
        );
        defer CanonicalTextMachine.deinitPreparedResume(prepared_resume);
        var response = try Text4.fromSlice("ok");
        response.storage[3] = 0xb2;
        try CanonicalTextMachine.@"resume"(prepared_resume, response);
    }

    const done = switch (try CanonicalTextMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqualStrings("ok", try done.value().slice());
    try std.testing.expectEqual(@as(u8, 0), done.value().storage[3]);
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
        pub const semantic_site_contract_digests = .{
            CompiledMachine.EffectRow.site(0).semantic_contract_digest,
        };

        pub fn handle(
            _: *@This(),
            comptime Site: type,
            payload: Site.Payload,
            _: CompiledMachine.RequestIdentity,
        ) !Site.Resume {
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
        identities: [2][32]u8 = undefined,

        pub const semantic_site_contract_digests = .{
            CompiledMachine.EffectRow.site(0).semantic_contract_digest,
        };

        pub fn handle(
            self: *@This(),
            comptime Site: type,
            payload: Site.Payload,
            identity: CompiledMachine.RequestIdentity,
        ) error{Transient}!Site.Resume {
            self.identities[self.attempts] = identity.digest;
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
    const parked = (try CompiledMachine.current(local.state)).?;
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
    try std.testing.expectEqualSlices(
        u8,
        &handler.identities[0],
        &handler.identities[1],
    );
    try std.testing.expectEqualSlices(
        u8,
        &handler_error.request.identity.digest,
        &handler.identities[0],
    );
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

        pub const semantic_site_contract_digests = .{
            HelperEffectMachine.EffectRow.site(0).semantic_contract_digest,
        };

        pub fn handle(
            self: *@This(),
            comptime Site: type,
            payload: Site.Payload,
            _: HelperEffectMachine.RequestIdentity,
        ) !Site.Resume {
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
    const parked = (try HelperEffectMachine.current(local.state)).?;
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

        pub const semantic_site_contract_digests = .{
            LargeResponseMachine.EffectRow.site(0).semantic_contract_digest,
        };

        pub fn handle(
            self: *@This(),
            comptime Site: type,
            _: Site.Payload,
            _: LargeResponseMachine.RequestIdentity,
        ) !Site.Resume {
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
    try std.testing.expectEqual(
        @as(?LargeResponseMachine.Request, null),
        try LargeResponseMachine.current(local.state),
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

test "KernelMachine preflights the complete response state before request authority" {
    const state = try LargeResponseKernelMachine.initialState(
        std.testing.allocator,
        9,
    );
    defer LargeResponseKernelMachine.deinitState(state);
    const before = try LargeResponseKernelMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(before);
    var fuel: u64 = 8;
    try std.testing.expectError(
        error.ProgramContractViolation,
        LargeResponseKernelMachine.step(state, &fuel),
    );
    try std.testing.expectEqual(@as(u64, 8), fuel);
    try std.testing.expectEqual(
        @as(?LargeResponseKernelMachine.Request, null),
        try LargeResponseKernelMachine.current(state),
    );
    const after = try LargeResponseKernelMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

const ignored_argument_blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .return_value = null },
}};
const IgnoredArgumentBody = struct {
    pub const InitialArgs = Text4;
    pub const Result = void;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{Text4};
    pub const control_ir: cir.Program = .{
        .label = "ignored-entry-argument",
        .value_types = &.{.{ .schema = 0 }},
        .blocks = &ignored_argument_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};
const IgnoredArgumentMachine = program_v2.program(
    "ignored-entry-argument",
    IgnoredArgumentBody,
).compile(.{});

const IgnoredResponseLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.ignored-response-lookup.v1";
    pub const Payload = u32;
    pub const Resume = Text4;
};
const ignored_response_arguments = [_]cir.EdgeArgument{.@"resume"};
const ignored_response_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &ignored_response_arguments,
            },
            .resume_type = .{ .schema = 0 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = null },
    },
};
const IgnoredResponseBody = struct {
    pub const InitialArgs = u32;
    pub const Result = void;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{IgnoredResponseLookup};
    pub const schema_types = .{Text4};
    pub const control_ir: cir.Program = .{
        .label = "ignored-effect-response",
        .value_types = &.{ u32_type, .{ .schema = 0 } },
        .blocks = &ignored_response_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};
const IgnoredResponseMachine = program_v2.program(
    "ignored-effect-response",
    IgnoredResponseBody,
).compile(.{});

const dead_response_jump_arguments = [_]cir.EdgeArgument{.{ .value = 1 }};
const dead_response_jump_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &ignored_response_arguments,
            },
            .resume_type = .{ .schema = 0 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .jump = .{
            .target = 2,
            .arguments = &dead_response_jump_arguments,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .return_value = null },
    },
};
const DeadResponseJumpBody = struct {
    pub const InitialArgs = u32;
    pub const Result = void;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{IgnoredResponseLookup};
    pub const schema_types = .{Text4};
    pub const control_ir: cir.Program = .{
        .label = "future-dead-response-jump",
        .value_types = &.{ u32_type, .{ .schema = 0 }, .{ .schema = 0 } },
        .blocks = &dead_response_jump_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};
const DeadResponseJumpProgram = program_v2.program(
    "future-dead-response-jump",
    DeadResponseJumpBody,
);
const DeadResponseJumpDirect = DeadResponseJumpProgram.compile(.{});
const DeadResponseJumpKernel = DeadResponseJumpProgram.kernelMachine(.{});

test "entry initialization stores only live arguments but validates every input" {
    const valid = try Text4.fromSlice("ok");
    const state = try IgnoredArgumentMachine.initialState(
        std.testing.allocator,
        valid,
    );
    defer IgnoredArgumentMachine.deinitState(state);
    var fuel: u64 = 4;
    const done = switch (try IgnoredArgumentMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();

    var malformed = Text4.empty();
    malformed.logical_length = 5;
    try std.testing.expectError(
        error.ProgramContractViolation,
        IgnoredArgumentMachine.initialState(std.testing.allocator, malformed),
    );
}

test "resume validates a future-dead response before consuming the request" {
    const state = try IgnoredResponseMachine.initialState(
        std.testing.allocator,
        7,
    );
    defer IgnoredResponseMachine.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try IgnoredResponseMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    {
        const prepared_resume = try IgnoredResponseMachine.prepareResume(
            state,
            request,
        );
        defer IgnoredResponseMachine.deinitPreparedResume(prepared_resume);
        var malformed = Text4.empty();
        malformed.logical_length = 5;
        try std.testing.expectError(
            error.ProgramContractViolation,
            IgnoredResponseMachine.@"resume"(prepared_resume, malformed),
        );
        const unchanged = (try IgnoredResponseMachine.current(state)).?;
        try std.testing.expectEqualSlices(
            u8,
            &request.identity.digest,
            &unchanged.identity.digest,
        );

        try IgnoredResponseMachine.@"resume"(
            prepared_resume,
            try Text4.fromSlice("ok"),
        );
    }
    const done = switch (try IgnoredResponseMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
}

test "kernel omits future-dead edge arguments exactly like direct specialization" {
    const direct = try DeadResponseJumpDirect.initialState(
        std.testing.allocator,
        7,
    );
    defer DeadResponseJumpDirect.deinitState(direct);
    const kernel = try DeadResponseJumpKernel.initialState(
        std.testing.allocator,
        7,
    );
    defer DeadResponseJumpKernel.deinitState(kernel);
    var direct_fuel: u64 = 8;
    var kernel_fuel: u64 = 8;
    const direct_request = switch (try DeadResponseJumpDirect.step(
        direct,
        &direct_fuel,
    )) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const kernel_request = switch (try DeadResponseJumpKernel.step(
        kernel,
        &kernel_fuel,
    )) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualSlices(
        u8,
        &direct_request.identity.digest,
        &kernel_request.identity.digest,
    );
    const response = try Text4.fromSlice("ok");
    {
        const prepared = try DeadResponseJumpDirect.prepareResume(
            direct,
            direct_request,
        );
        defer DeadResponseJumpDirect.deinitPreparedResume(prepared);
        try DeadResponseJumpDirect.@"resume"(prepared, response);
    }
    {
        const prepared = try DeadResponseJumpKernel.prepareResume(
            kernel,
            kernel_request,
        );
        defer DeadResponseJumpKernel.deinitPreparedResume(prepared);
        try DeadResponseJumpKernel.@"resume"(prepared, response);
    }
    const direct_state = try DeadResponseJumpDirect.encodeState(
        std.testing.allocator,
        direct,
    );
    defer std.testing.allocator.free(direct_state);
    const kernel_state = try DeadResponseJumpKernel.encodeState(
        std.testing.allocator,
        kernel,
    );
    defer std.testing.allocator.free(kernel_state);
    try std.testing.expectEqualSlices(u8, direct_state, kernel_state);

    const direct_done = switch (try DeadResponseJumpDirect.step(
        direct,
        &direct_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer direct_done.deinit();
    const kernel_done = switch (try DeadResponseJumpKernel.step(
        kernel,
        &kernel_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer kernel_done.deinit();
    try std.testing.expectEqual(direct_fuel, kernel_fuel);
}
