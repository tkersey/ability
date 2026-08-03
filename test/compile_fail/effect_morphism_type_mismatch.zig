const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Source = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "compile-fail.source.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const IncompatibleTarget = struct {
    pub const semantic_identity = "compile-fail.target.v1";
    pub const Payload = bool;
    pub const Resume = u32;
};

const Route = struct {
    pub const source_id: u32 = 0;
    pub const Target = IncompatibleTarget;
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
    pub const effect_sites = .{Source};
    pub const effect_morphisms = .{Route};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "effect-morphism-type-mismatch",
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
    "effect-morphism-type-mismatch",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
