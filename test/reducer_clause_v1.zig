const clause = @import("reducer_clause_v1");
const std = @import("std");

test "pure clause error surface excludes Machine policy" {
    const errors = @typeInfo(clause.Error).error_set.?;
    inline for (errors) |item| {
        try std.testing.expect(!std.mem.eql(
            u8,
            item.name,
            "ExecutionBudgetExceeded",
        ));
        try std.testing.expect(!std.mem.eql(
            u8,
            item.name,
            "FrameDepthExceeded",
        ));
    }
}

test "pure clause preserves source-width signed remainder overflow" {
    try std.testing.expectError(
        error.Overflow,
        clause.integerArithmetic(
            .{ .raw = 0x80, .bits = 8, .signed = true },
            .{ .raw = 0xff, .bits = 8, .signed = true },
            7,
        ),
    );
}
