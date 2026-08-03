const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .terminator = .{ .return_value = null },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "undersized-machine-state",
        .value_types = &.{},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Machine = program_v2.program(
    "undersized-machine-state",
    Body,
).compile(.{
    .maximum_state_bytes = 75,
});

comptime {
    _ = Machine.abi_version;
}
