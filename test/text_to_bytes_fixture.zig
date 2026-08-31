const boundary = @import("boundary");

pub const Text = boundary.Text(8);
pub const Bytes = boundary.Bytes(8);
pub const Failure = enum { rejected };
const FixtureFailure = Failure;

const Body = struct {
    pub const InitialArgs = Text;
    pub const Result = Bytes;
    pub const Failure = FixtureFailure;
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{ Text, Bytes, FixtureFailure };
    pub const control_ir: boundary.ir.Program = .{
        .label = "text-to-bytes-v1",
        .value_types = &.{ .{ .schema = 0 }, .{ .schema = 1 } },
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .instructions = &.{.{
                .kind = .pure,
                .result = 1,
                .operands = &.{0},
                .operation = .text_to_bytes,
            }},
            .terminator = .{ .return_value = 1 },
        }},
        .entry = 0,
        .result_type = .{ .schema = 1 },
    };
};

pub const Program = boundary.program("text-to-bytes-v1", Body);
pub const Image = Program.image();
pub const Machine = Program.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 8,
});

pub const input = Text.fromSlice("é\x00") catch unreachable;
