const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");

const Text1 = portable_value.Text(1);
const dead_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .terminator = .{ .return_value = null },
    },
    .{
        .id = 1,
        .instructions = &dead_instructions,
        .terminator = .{ .fail = 0 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = enum { rejected };
    pub const constants = .{Text1{
        .storage = .{0},
        .logical_length = 2,
    }};
    pub const effect_sites = .{};
    pub const schema_types = .{Text1};
    pub const control_ir: cir.Program = .{
        .label = "dead-control-malformed-constant",
        .value_types = &.{.{ .schema = 0 }},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Machine = program_v2.program(
    "dead-control-malformed-constant",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
