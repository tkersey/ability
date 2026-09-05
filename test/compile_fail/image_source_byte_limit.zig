const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const maximum_image_bytes = 1;
    pub const control_ir: cir.Program = .{
        .label = "image-source-byte-limit",
        .value_types = &.{.{ .scalar = .u32 }},
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .return_value = 0 },
        }},
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

comptime {
    _ = program_v2.program("image-source-byte-limit", Body).image();
}
