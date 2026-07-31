const portable_value = @import("portable_value");

comptime {
    portable_value.assertPortable(c_int);
}
