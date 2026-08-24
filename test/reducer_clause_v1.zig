const clause = @import("reducer_clause_v1");
const image_v1 = @import("image_v1");
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

test "product construction streams more operands than the value catalog" {
    const operand_count: u16 = 1025;
    var instruction: [16 + @as(usize, operand_count) * 2]u8 =
        [_]u8{0} ** (16 + @as(usize, operand_count) * 2);
    std.mem.writeInt(u32, instruction[0..4], instruction.len, .little);
    std.mem.writeInt(u16, instruction[6..8], 24, .little);
    std.mem.writeInt(u16, instruction[8..10], 1, .little);
    std.mem.writeInt(u16, instruction[10..12], operand_count, .little);
    var slots = [_]clause.Slot{.{}} ** 1024;
    slots[0] = .{ .bytes = &.{7}, .initialized = true };
    var scratch: [operand_count]u8 = undefined;
    var scratch_cursor: usize = 0;
    var workspace: image_v1.ValidationWorkspace = .{};
    const image: image_v1.ValidatedImage = undefined;
    try std.testing.expectEqual(
        @as(?u32, null),
        try clause.executeCompositeOperation(
            image,
            &instruction,
            1,
            &slots,
            &scratch,
            &scratch_cursor,
            &workspace,
        ),
    );
    try std.testing.expectEqual(@as(usize, operand_count), slots[1].bytes.len);
    for (slots[1].bytes) |byte| try std.testing.expectEqual(@as(u8, 7), byte);
    try std.testing.expect(clause.productConstructMatches(
        slots[1].bytes,
        instruction[16..],
        operand_count,
        &slots,
    ));
    scratch[operand_count - 1] = 8;
    try std.testing.expect(!clause.productConstructMatches(
        slots[1].bytes,
        instruction[16..],
        operand_count,
        &slots,
    ));
    try std.testing.expect(!clause.productConstructMatches(
        slots[1].bytes,
        instruction[16 .. instruction.len - 2],
        operand_count,
        &slots,
    ));
}
