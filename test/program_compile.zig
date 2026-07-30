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
