const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    },
};

const FailurePayload = union(enum) {
    rejected: void,
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = FailurePayload;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "non-enum-failure-tagged-union",
        .value_types = &.{.{ .scalar = .unit }},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Machine = program_v2.program(
    "non-enum-failure-tagged-union",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
