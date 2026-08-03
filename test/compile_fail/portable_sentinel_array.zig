const portable_value = @import("portable_value");

comptime {
    portable_value.assertPortable([3:0]u8);
}
