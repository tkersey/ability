const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const FailureType = enum { custom };
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
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .copy,
        .result = 3,
        .operands = &.{2},
        .operation = .copy,
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 0, 1, 3 },
        .operation = .integer_add,
    },
};
const blocks = [_]cir.Block{.{
    .id = 0,
    .instructions = &instructions,
    .terminator = .{ .return_value = 4 },
}};
const Body = struct {
    pub const InitialArgs = void;
    pub const Result = u8;
    pub const Failure = FailureType;
    pub const constants = .{
        @as(u8, 1),
        @as(u8, 2),
        FailureType.custom,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{FailureType};
    pub const control_ir: cir.Program = .{
        .label = "authored-instruction-failure-operand",
        .value_types = &.{
            .{ .scalar = .u8 },
            .{ .scalar = .u8 },
            .{ .schema = 0 },
            .{ .schema = 0 },
            .{ .scalar = .u8 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};

comptime {
    _ = program_v2.program("authored-instruction-failure-operand", Body);
}
