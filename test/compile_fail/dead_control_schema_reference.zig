const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .fail = 0 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{u32};
    pub const control_ir: cir.Program = .{
        .label = "dead-control-schema-reference",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .schema = 1 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

const Machine = program_v2.program(
    "dead-control-schema-reference",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
