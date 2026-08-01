const cir = @import("control_ir");
const driver = @import("driver");
const program_v2 = @import("program_v2");
const std = @import("std");

const shared_semantic_identity = "compile-fail.driver-contract.v1";

fn LookupSite(comptime ResumeType: type) type {
    return struct {
        pub const id: u32 = 0;
        pub const semantic_identity = shared_semantic_identity;
        pub const Payload = u32;
        pub const Resume = ResumeType;
    };
}

fn Body(comptime ResumeType: type, comptime resume_type: cir.ValueType) type {
    const Site = LookupSite(ResumeType);
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
                .resume_type = resume_type,
            } },
        },
        .{
            .id = 1,
            .parameters = &.{1},
            .terminator = .{ .return_value = 1 },
        },
    };

    return struct {
        pub const InitialArgs = u32;
        pub const Result = ResumeType;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{Site};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "driver-semantic-contract-mismatch",
            .value_types = &.{
                .{ .scalar = .u32 },
                resume_type,
            },
            .blocks = &blocks,
            .entry = 0,
            .result_type = resume_type,
        };
    };
}

const Machine = program_v2.program(
    "driver-semantic-contract-actual",
    Body(u32, .{ .scalar = .u32 }),
).compile(.{});

const IncompatibleMachine = program_v2.program(
    "driver-semantic-contract-incompatible",
    Body(u64, .{ .scalar = .u64 }),
).compile(.{});

test "Driver rejects the same semantic identity with a changed schema" {
    const LocalDriver = driver.Driver(Machine);
    var local = try LocalDriver.init(std.testing.allocator, 7);
    defer local.deinit();
    var handler = struct {
        pub const semantic_site_contract_digests = .{
            IncompatibleMachine.EffectRow.site(0).semantic_contract_digest,
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
