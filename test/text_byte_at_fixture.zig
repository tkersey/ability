const boundary = @import("boundary");

pub const Text = boundary.Text(8);

pub const Input = struct {
    text: Text,
    index: u32,
};

pub const Failure = enum {
    bad_index,
};
const FixtureFailure = Failure;

const value_types = [_]boundary.ir.ValueType{
    .{ .schema = 0 },
    .{ .schema = 1 },
    .{ .scalar = .u32 },
    .{ .schema = 2 },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
};

const instructions = [_]boundary.ir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{0},
        .operation = .{ .product_extract = 1 },
    },
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 4,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .constant,
        .result = 5,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{ 4, 5, 3 },
        .operation = .integer_add,
    },
    .{
        .kind = .pure,
        .result = 7,
        .operands = &.{ 1, 2, 3 },
        .operation = .text_byte_at,
    },
};

const byte_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 7 }};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &instructions,
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &byte_arguments,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{8},
        .terminator = .{ .return_value = 8 },
    },
};

const Body = struct {
    pub const InitialArgs = Input;
    pub const Result = u8;
    pub const Failure = FixtureFailure;
    pub const constants = .{
        FixtureFailure.bad_index,
        @as(u8, 1),
        @as(u8, 2),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ Input, Text, FixtureFailure };
    pub const control_ir: boundary.ir.Program = .{
        .label = "text-byte-at-v1",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};

pub const Program = boundary.program("text-byte-at-v1", Body);
pub const Image = Program.image();
pub const Machine = Program.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 32,
});

pub fn input(index: u32) Input {
    return .{
        .text = Text.fromSlice("é\"") catch unreachable,
        .index = index,
    };
}
