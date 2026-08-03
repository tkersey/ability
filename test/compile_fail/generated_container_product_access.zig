const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");

const Text4 = portable_value.Text(4);
const instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 1,
    .operands = &.{0},
    .operation = .{ .product_extract = 0 },
}};
const blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &instructions,
    .terminator = .{ .return_value = 1 },
}};

const Body = struct {
    pub const InitialArgs = Text4;
    pub const Result = [4]u8;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{ Text4, [4]u8 };
    pub const control_ir: cir.Program = .{
        .label = "generated-container-product-access",
        .value_types = &.{ .{ .schema = 0 }, .{ .schema = 1 } },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 1 },
    };
};

const Machine = program_v2.program(
    "generated-container-product-access",
    Body,
).compile(.{});

comptime {
    _ = Machine.abi_version;
}
