const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const continuation_arguments = [_]cir.EdgeArgument{.@"resume"};

const Unused = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "unused.authority.v1";
    pub const Payload = bool;
    pub const Resume = bool;
};

const LookupAtSourceOne = struct {
    pub const id: u32 = 1;
    pub const semantic_identity = "lookup.authority.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const LookupAtSourceZero = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "lookup.authority.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

fn BodyWithUnusedSite() type {
    return struct {
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 1,
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

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{ Unused, LookupAtSourceOne };
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "residual-effect-source",
            .value_types = &.{ u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

fn BodyWithCanonicalSite() type {
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

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum {
            rejected,
        };
        pub const effect_sites = .{LookupAtSourceZero};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "residual-effect-source",
            .value_types = &.{ u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const options = @import("machine").Options{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const WithUnused = program_v2.program(
    "with-unused-source-effect",
    BodyWithUnusedSite(),
).compile(options);
const Canonical = program_v2.program(
    "canonical-source-effect",
    BodyWithCanonicalSite(),
).compile(options);

test "compiler eliminates unreferenced effects and canonicalizes residual ordinals" {
    try std.testing.expect(!@hasDecl(
        WithUnused.EffectRow,
        "source_site_count",
    ));
    try std.testing.expectEqual(
        @as(usize, 1),
        WithUnused.EffectRow.operation_site_count,
    );
    const Site = WithUnused.EffectRow.site(0);
    try std.testing.expectEqual(@as(u32, 0), Site.site_ordinal);
    try std.testing.expect(!@hasDecl(Site, "source_site_ordinal"));
    try std.testing.expectEqualStrings(
        "lookup.authority.v1",
        Site.semantic_identity,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Canonical.EffectRow.site(0).semantic_contract_digest,
        &Site.semantic_contract_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Canonical.Manifest.machine_contract_digest,
        &WithUnused.Manifest.machine_contract_digest,
    );

    const state = try WithUnused.initialState(std.testing.allocator, 7);
    defer WithUnused.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try WithUnused.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u32, 0), request.identity.site_ordinal);
    switch (request.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 7), payload),
    }
    const prepared_resume = try WithUnused.prepareResume(state, request);
    defer WithUnused.deinitPreparedResume(prepared_resume);
    try WithUnused.@"resume"(prepared_resume, @as(u32, 11));
    const done = switch (try WithUnused.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 11), done.value().*);
}
