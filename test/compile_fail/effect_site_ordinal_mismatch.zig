const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Misnumbered = struct {
    pub const id: u32 = 3;
    pub const site_id: u32 = 3;
    pub const semantic_identity = "compile-fail.misnumbered.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

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
    pub const effect_sites = .{Misnumbered};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "effect-site-ordinal-mismatch",
        .value_types = &.{},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Machine = program_v2.program(
    "effect-site-ordinal-mismatch",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
