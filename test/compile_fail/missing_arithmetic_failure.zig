const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .integer_add,
    },
};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &instructions,
        .terminator = .{ .return_value = 2 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{ @as(u32, 1), @as(u32, 2) };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "missing-arithmetic-failure",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

const Machine = program_v2.program(
    "missing-arithmetic-failure",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
