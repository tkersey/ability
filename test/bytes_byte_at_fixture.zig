const boundary = @import("boundary");
const machine = @import("machine");

pub const Bytes = boundary.Bytes(8);
pub const Input = struct {
    bytes: Bytes,
    index: u32,
};
pub const Failure = enum { bad_index };
const FixtureFailure = Failure;

const value_types = [_]boundary.ir.ValueType{
    .{ .schema = 0 },
    .{ .schema = 1 },
    .{ .scalar = .u32 },
    .{ .schema = 2 },
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
        .kind = .pure,
        .result = 4,
        .operands = &.{ 1, 2, 3 },
        .operation = .bytes_byte_at,
    },
};

const byte_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 4 }};
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
        .parameters = &.{5},
        .terminator = .{ .return_value = 5 },
    },
};

const Body = struct {
    pub const InitialArgs = Input;
    pub const Result = u8;
    pub const Failure = FixtureFailure;
    pub const constants = .{FixtureFailure.bad_index};
    pub const effect_sites = .{};
    pub const schema_types = .{ Input, Bytes, FixtureFailure };
    pub const control_ir: boundary.ir.Program = .{
        .label = "bytes-byte-at-v1",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};

pub const Program = boundary.program("bytes-byte-at-v1", Body);
pub const Image = Program.image();
const options: machine.Options = .{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 32,
};
pub const Machine = Program.compile(options);
pub const Profile = Program.machineV2Profile(options);

pub fn input(index: u32) Input {
    return .{
        .bytes = Bytes.fromSlice(&.{ 0xff, 0x00, 0x80 }) catch unreachable,
        .index = index,
    };
}
