const cir = @import("control_ir");
const effect = @import("effect_v2");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const SourceLookup = effect.site(
    0,
    "source.lookup.v1",
    u32,
    u32,
);
const ResidualLookup = effect.site(
    0,
    "residual.lookup.v2",
    u32,
    u32,
);

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
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

fn MorphismBody() type {
    return struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{SourceLookup};
        pub const effect_morphisms = .{
            effect.morphism(0, ResidualLookup),
        };
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "effect-morphism",
            .value_types = &.{ u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

fn DirectBody() type {
    return struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{ResidualLookup};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "effect-morphism",
            .value_types = &.{ u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const Morphed = program_v2.program(
    "morphed-effect",
    MorphismBody(),
).compile(options);
const Direct = program_v2.program(
    "direct-effect",
    DirectBody(),
).compile(options);

test "declarative effect morphism lowers to the canonical residual contract" {
    try std.testing.expectEqualSlices(
        u8,
        &Direct.Manifest.machine_contract_digest,
        &Morphed.Manifest.machine_contract_digest,
    );
    const Site = Morphed.EffectRow.site(0);
    try std.testing.expectEqualStrings(
        "residual.lookup.v2",
        Site.semantic_identity,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Direct.EffectRow.site(0).contract_digest,
        &Site.contract_digest,
    );

    const state = try Morphed.initialState(std.testing.allocator, 7);
    defer Morphed.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try Morphed.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (request.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 7), payload),
    }
    {
        const prepared_resume = try Morphed.prepareResume(state, request);
        defer Morphed.deinitPreparedResume(prepared_resume);
        try Morphed.@"resume"(prepared_resume, @as(u32, 11));
    }
    const done = switch (try Morphed.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 11), done.value().*);
}
