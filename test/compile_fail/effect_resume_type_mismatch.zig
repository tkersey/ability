const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Lookup = struct {
    pub const semantic_identity = "compile-fail.lookup.v1";
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
            .resume_type = .{ .scalar = .boolean },
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
    pub const Result = bool;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{Lookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "effect-resume-type-mismatch",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .boolean },
    };
};

const Machine = program_v2.program(
    "effect-resume-type-mismatch",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
