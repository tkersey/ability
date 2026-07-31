const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{u32};
    pub const control_ir: cir.Program = .{
        .label = "machine-state-below-entry-environment",
        .value_types = &.{.{ .schema = 0 }},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};

const Machine = program_v2.program(
    "machine-state-below-entry-environment",
    Body,
).compile(.{
    .maximum_state_bytes = 76,
});

comptime {
    _ = Machine.abi_version;
}
