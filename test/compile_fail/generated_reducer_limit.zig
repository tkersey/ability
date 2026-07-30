const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const instructions = [_]cir.Instruction{
    .{
        .kind = .copy,
        .result = 1,
        .operands = &.{0},
        .operation = .copy,
    },
};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &instructions,
        .terminator = .{ .return_value = 1 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const compiler_limits: cir.CompilerLimits = .{
        .maximum_generated_operations = 1,
    };
    pub const control_ir: cir.Program = .{
        .label = "generated-reducer-limit",
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
    "generated-reducer-limit",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
