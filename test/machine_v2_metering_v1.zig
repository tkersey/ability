const control_ir = @import("control_ir");
const metering = @import("machine_v2_metering_v1");
const std = @import("std");

test "Machine v2 dynamic fuel and result-shape metering have one owner" {
    try std.testing.expectEqual(@as(u64, 0), metering.dynamicBytesCost(false, 33));
    try std.testing.expectEqual(@as(u64, 0), metering.dynamicBytesCost(true, 0));
    try std.testing.expectEqual(@as(u64, 1), metering.dynamicBytesCost(true, 16));
    try std.testing.expectEqual(@as(u64, 2), metering.dynamicBytesCost(true, 17));

    const Backend = struct {
        pub fn maximumResultBytes(comptime _: control_ir.Instruction) u64 {
            return 100;
        }
        pub fn constantBytes(comptime _: control_ir.Instruction) u64 {
            return 7;
        }
        pub fn operandBytes(context: anytype, value: control_ir.ValueId) u64 {
            return context.sizes[@intCast(value)];
        }
        pub fn boundedResultBytes(
            comptime _: control_ir.Instruction,
            candidate: u64,
        ) u64 {
            return @min(100, candidate);
        }
        pub fn exactProductFieldBytes(
            _: anytype,
            comptime _: control_ir.Instruction,
            comptime _: usize,
        ) ?u64 {
            return null;
        }
        pub fn exactVectorElementBytes(
            _: anytype,
            comptime _: control_ir.Instruction,
        ) ?u64 {
            return null;
        }
    };
    const context = .{ .sizes = [_]u64{ 0, 12, 9, 7 } };
    try std.testing.expectEqual(
        @as(u64, 10),
        metering.resultEncodedBytes(.{
            .kind = .pure,
            .result = 0,
            .operands = &.{2},
            .operation = .optional_some,
        }, context, Backend),
    );
    try std.testing.expectEqual(
        @as(u64, 21),
        metering.resultEncodedBytes(.{
            .kind = .pure,
            .result = 0,
            .operands = &.{ 1, 2 },
            .operation = .vector_push,
        }, context, Backend),
    );
    try std.testing.expectEqual(
        @as(u64, 20),
        metering.resultEncodedBytes(.{
            .kind = .pure,
            .result = 0,
            .operands = &.{ 1, 2, 3 },
            .operation = .text_join,
        }, context, Backend),
    );
}
