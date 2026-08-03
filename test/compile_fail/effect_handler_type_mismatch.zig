const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Source = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "compile-fail.local.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const Handler = struct {
    pub const source_id: u32 = 0;
    pub const function_id: u16 = 1;
};

const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const helper_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 3,
    .operation = .{ .constant = 0 },
}};
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
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{2},
        .instructions = &helper_instructions,
        .terminator = .{ .return_to_caller = 3 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{@as(u32, 1)};
    pub const effect_sites = .{Source};
    pub const effect_handlers = .{Handler};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "effect-handler-type-mismatch",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 2,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const Machine = program_v2.program(
    "effect-handler-type-mismatch",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
