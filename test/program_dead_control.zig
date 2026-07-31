const cir = @import("control_ir");
const compiler = @import("compiler");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const live_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const dead_jump_arguments = [_]cir.EdgeArgument{.{ .value = 2 }};
const reindexed_dead_jump_arguments = [_]cir.EdgeArgument{.{ .value = 1 }};

const Live = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "live.lookup.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const Dead = struct {
    pub const id: u32 = 1;
    pub const semantic_identity = "dead.lookup.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

fn CanonicalBody() type {
    return struct {
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
                        .arguments = &live_resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
            .{
                .id = 2,
                .parameters = &.{2},
                .terminator = .{ .jump = .{
                    .target = 3,
                    .arguments = &dead_jump_arguments,
                } },
            },
            .{
                .id = 3,
                .parameters = &.{3},
                .terminator = .{ .return_value = 3 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{Live};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "dead-control-normalization",
            .value_types = &.{
                u32_type,
                u32_type,
                u32_type,
                u32_type,
            },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

fn BodyWithDeadEffect() type {
    return struct {
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
                        .arguments = &live_resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
            .{
                .id = 2,
                .parameters = &.{2},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 1,
                    .request_values = &.{2},
                    .continuation = .{
                        .target = 3,
                        .arguments = &live_resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 3,
                .parameters = &.{3},
                .terminator = .{ .return_value = 3 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{ Live, Dead };
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "dead-control-normalization",
            .value_types = &.{
                u32_type,
                u32_type,
                u32_type,
                u32_type,
            },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

fn ReindexedBody() type {
    return struct {
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{0},
                    .continuation = .{
                        .target = 3,
                        .arguments = &live_resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .jump = .{
                    .target = 2,
                    .arguments = &reindexed_dead_jump_arguments,
                } },
            },
            .{
                .id = 2,
                .parameters = &.{2},
                .terminator = .{ .return_value = 2 },
            },
            .{
                .id = 3,
                .parameters = &.{3},
                .terminator = .{ .return_value = 3 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{Live};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "dead-control-normalization",
            .value_types = &.{
                u32_type,
                u32_type,
                u32_type,
                u32_type,
            },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

fn BodyWithDeadHelper() type {
    return struct {
        const HugeDeadResult = [8192]u8;
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
                        .arguments = &live_resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
            .{
                .id = 2,
                .function_id = 1,
                .parameters = &.{2},
                .terminator = .{ .return_to_caller = 2 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{Live};
        pub const schema_types = .{HugeDeadResult};
        pub const control_ir: cir.Program = .{
            .label = "dead-helper-control",
            .value_types = &.{
                u32_type,
                u32_type,
                .{ .schema = 0 },
            },
            .blocks = &blocks,
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
                    .entry = 2,
                    .result_type = .{ .schema = 0 },
                },
            },
        };
    };
}

const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const CanonicalProgram = program_v2.program(
    "canonical-control",
    CanonicalBody(),
);
const WithDeadProgram = program_v2.program(
    "dead-effect-control",
    BodyWithDeadEffect(),
);
const ReindexedProgram = program_v2.program(
    "reindexed-control",
    ReindexedBody(),
);
const Canonical = CanonicalProgram.compile(options);
const WithDead = WithDeadProgram.compile(options);
const Reindexed = ReindexedProgram.compile(options);
const CanonicalDefinition = compiler.DefinitionFor(
    "canonical-control",
    CanonicalBody(),
);
const DeadHelperDefinition = compiler.DefinitionFor(
    "dead-helper-control",
    BodyWithDeadHelper(),
);

test "unreachable control creates no constructor, authority, or identity delta" {
    try std.testing.expectEqual(
        @as(usize, 3),
        WithDeadProgram.rnf.constructor_count,
    );
    for (WithDeadProgram.rnf.constructorSlice()) |constructor| {
        try std.testing.expect(constructor.source_block < 2);
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        WithDead.EffectRow.source_site_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        WithDead.EffectRow.operation_site_count,
    );
    try std.testing.expectEqualStrings(
        "live.lookup.v1",
        WithDead.EffectRow.site(0).semantic_identity,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Canonical.Manifest.machine_contract_digest,
        &WithDead.Manifest.machine_contract_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Canonical.Manifest.machine_contract_digest,
        &Reindexed.Manifest.machine_contract_digest,
    );

    const state = try WithDead.initialState(std.testing.allocator, 7);
    defer WithDead.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try WithDead.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (request.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 7), payload),
    }
    try WithDead.@"resume"(state, request, @as(u32, 11));
    const done = switch (try WithDead.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 11), done.value().*);
}

test "unreachable helper results do not enter the generated return carrier" {
    try std.testing.expectEqual(
        @as(usize, 1),
        CanonicalDefinition.reachable_function_count,
    );
    try std.testing.expectEqual(
        CanonicalDefinition.reachable_function_count,
        DeadHelperDefinition.reachable_function_count,
    );
    try std.testing.expect(DeadHelperDefinition.ReturnValue == void);
    try std.testing.expectEqual(
        @sizeOf(CanonicalDefinition.Plan),
        @sizeOf(DeadHelperDefinition.Plan),
    );
}
