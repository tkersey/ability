const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

fn LargeFailure() type {
    @setEvalBranchQuota(1_000_000);
    var names: [2049][:0]const u8 = undefined;
    var values: [2049]u16 = undefined;
    inline for (0..2049) |index| {
        names[index] = std.fmt.comptimePrint("failure_{d}", .{index});
        values[index] = @intCast(index);
    }
    return @Enum(u16, .exhaustive, &names, &values);
}

const blocks = [_]cir.Block{.{
    .id = 0,
    .terminator = .{ .return_value = null },
}};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = LargeFailure();
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "image-failure-variant-limit",
        .value_types = &.{},
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};

const Image = program_v2.program("image-failure-variant-limit", Body).image();

comptime {
    _ = Image.bytes;
}
