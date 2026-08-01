const cir = @import("control_ir");
const driver = @import("driver");
const program_v2 = @import("program_v2");
const std = @import("std");

const Lookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "compile-fail.driver-semantic-site.actual.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

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
            .resume_type = .{ .scalar = .u32 },
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
    pub const effect_sites = .{Lookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "driver-semantic-site-mismatch",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

const Machine = program_v2.program(
    "driver-semantic-site-mismatch",
    Body,
).compile(.{});

test "Driver rejects an unadmitted same-shaped semantic site" {
    const LocalDriver = driver.Driver(Machine);
    var local = try LocalDriver.init(std.testing.allocator, 7);
    defer local.deinit();
    var handler = struct {
        pub const semantic_site_identities = .{
            "compile-fail.driver-semantic-site.expected.v1",
        };

        pub fn handle(
            _: *@This(),
            comptime Site: type,
            payload: Site.Payload,
            _: Machine.RequestIdentity,
        ) !Site.Resume {
            return payload;
        }
    }{};
    var fuel: u64 = 8;
    _ = try local.run(&handler, &fuel);
}
