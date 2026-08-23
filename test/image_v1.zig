const image_v1 = @import("image_v1");
const std = @import("std");

fn canonicalEmptyEnvelope() [image_v1.header_length]u8 {
    var bytes = [_]u8{0} ** image_v1.header_length;
    @memcpy(bytes[0..image_v1.magic.len], &image_v1.magic);
    writeInt(u16, &bytes, 8, image_v1.image_format_version);
    writeInt(u16, &bytes, 10, image_v1.evaluator_semantics_version);
    writeInt(u32, &bytes, 16, image_v1.header_length);
    writeInt(u64, &bytes, 24, image_v1.header_length);
    writeInt(u32, &bytes, 20, image_v1.section_count);
    for (0..image_v1.section_count) |index| {
        const offset = image_v1.fixed_prefix_length +
            index * image_v1.section_descriptor_length;
        writeInt(u16, &bytes, offset, @intCast(index + 1));
        writeInt(u16, &bytes, offset + 2, 1);
        writeInt(u64, &bytes, offset + 8, image_v1.header_length);
    }
    return bytes;
}

fn writeInt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    value: T,
) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}

test "BPI1 envelope validates exact fixed header and section directory" {
    const bytes = canonicalEmptyEnvelope();
    const envelope = try image_v1.validateEnvelope(&bytes);
    try std.testing.expectEqual(@as(u64, 316), envelope.header.total_length);
    try std.testing.expectEqual(@as(usize, 0), envelope.section(.roots).len);
    try std.testing.expectEqual(
        image_v1.SectionKind.entry_transitions,
        envelope.sections[9].kind,
    );
}

test "BPI1 envelope rejects noncanonical structure" {
    var bytes = canonicalEmptyEnvelope();
    bytes[0] = 'X';
    try std.testing.expectError(
        error.InvalidMagic,
        image_v1.validateEnvelope(&bytes),
    );

    bytes = canonicalEmptyEnvelope();
    writeInt(u16, &bytes, image_v1.fixed_prefix_length, 2);
    try std.testing.expectError(
        error.InvalidSectionOrder,
        image_v1.validateEnvelope(&bytes),
    );

    bytes = canonicalEmptyEnvelope();
    writeInt(
        u64,
        &bytes,
        image_v1.fixed_prefix_length + 8,
        image_v1.header_length + 1,
    );
    try std.testing.expectError(
        error.InvalidSectionOffset,
        image_v1.validateEnvelope(&bytes),
    );

    bytes = canonicalEmptyEnvelope();
    bytes[12] = 1;
    try std.testing.expectError(
        error.UnknownFlags,
        image_v1.validateEnvelope(&bytes),
    );
}
