const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Source = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "compile-fail.valid-source.v1";
    pub const Payload = void;
    pub const Resume = void;
};

const InvalidTarget = struct {
    pub const semantic_identity = "\xff";
    pub const Payload = void;
    pub const Resume = void;
};

const Route = struct {
    pub const source_id: u32 = 0;
    pub const Target = InvalidTarget;
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
    pub const effect_sites = .{Source};
    pub const effect_morphisms = .{Route};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "effect-morphism-invalid-utf8",
        .value_types = &.{},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Machine = program_v2.program(
    "effect-morphism-invalid-utf8",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
