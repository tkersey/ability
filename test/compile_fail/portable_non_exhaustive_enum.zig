const portable_value = @import("portable_value");

const Open = enum(u32) {
    known,
    _,
};

comptime {
    portable_value.assertPortable(Open);
}
