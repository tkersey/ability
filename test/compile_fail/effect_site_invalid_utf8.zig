const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Invalid = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "\xff";
    pub const Payload = void;
    pub const Resume = void;
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
    pub const effect_sites = .{Invalid};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "effect-site-invalid-utf8",
        .value_types = &.{},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Machine = program_v2.program("effect-site-invalid-utf8", Body).compile(.{});

comptime {
    _ = Machine.abi_version;
}
