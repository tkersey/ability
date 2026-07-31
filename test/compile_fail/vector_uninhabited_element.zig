const portable_value = @import("portable_value");

comptime {
    _ = portable_value.Vector(enum {}, 1);
}

pub fn main() void {}
