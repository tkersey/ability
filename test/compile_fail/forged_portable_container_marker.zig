const portable_value = @import("portable_value");

const Canonical = portable_value.Text(4);
const Forged = struct {
    pub const portable_value_kind = Canonical.portable_value_kind;
    pub const portable_value_authenticity =
        Canonical.portable_value_authenticity;
    pub const maximum_length: usize = Canonical.maximum_length;

    pointer: *u8,
};

comptime {
    portable_value.assertPortable(Forged);
}
