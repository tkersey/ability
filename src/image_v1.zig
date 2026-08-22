const std = @import("std");

pub const magic = "ABL_BEI1".*;
pub const image_format_version: u16 = 1;
pub const machine_abi_version: u16 = 2;
pub const state_format_version: u16 = 1;
pub const kernel_semantics_version: u16 = 1;
pub const fixed_prefix_length: u32 = 144;
pub const section_count: u32 = 10;
pub const section_descriptor_length: u32 = 24;
pub const header_length: u32 = fixed_prefix_length +
    section_count * section_descriptor_length;

pub const Error = error{
    InvalidMagic,
    UnsupportedImageVersion,
    UnsupportedMachineAbi,
    UnsupportedStateFormat,
    UnsupportedKernelSemantics,
    UnknownFlags,
    InvalidHeaderLength,
    LengthOverflow,
    LengthMismatch,
    InvalidSectionCount,
    InvalidSectionOrder,
    InvalidSectionOffset,
    InvalidSectionLength,
    TrailingBytes,
};

pub const SectionKind = enum(u16) {
    roots = 1,
    schemas = 2,
    failures = 3,
    constants = 4,
    effects = 5,
    values = 6,
    functions = 7,
    segments = 8,
    constructors = 9,
    entry_transitions = 10,
};

pub const Section = struct {
    kind: SectionKind,
    offset: u64,
    length: u64,

    pub fn bytes(self: Section, image: []const u8) []const u8 {
        const start: usize = @intCast(self.offset);
        const end: usize = @intCast(self.offset + self.length);
        return image[start..end];
    }
};

pub const Header = struct {
    total_length: u64,
    program_semantic_digest: [32]u8,
    machine_contract_digest: [32]u8,
    maximum_frames: u32,
    maximum_state_bytes: u32,
    maximum_machine_fuel: u64,
    maximum_kernel_scratch_bytes: u64,
    maximum_single_value_bytes: u32,
};

pub const ValidatedEnvelope = struct {
    image: []const u8,
    header: Header,
    sections: [section_count]Section,

    pub fn section(self: *const ValidatedEnvelope, kind: SectionKind) []const u8 {
        return self.sections[@intFromEnum(kind) - 1].bytes(self.image);
    }
};

pub fn validateEnvelope(image: []const u8) Error!ValidatedEnvelope {
    if (image.len < header_length) return error.InvalidHeaderLength;
    if (!std.mem.eql(u8, image[0..magic.len], &magic)) {
        return error.InvalidMagic;
    }
    if (readInt(u16, image, 8) != image_format_version) {
        return error.UnsupportedImageVersion;
    }
    if (readInt(u16, image, 10) != machine_abi_version) {
        return error.UnsupportedMachineAbi;
    }
    if (readInt(u16, image, 12) != state_format_version) {
        return error.UnsupportedStateFormat;
    }
    if (readInt(u16, image, 14) != kernel_semantics_version) {
        return error.UnsupportedKernelSemantics;
    }
    if (readInt(u32, image, 16) != 0) return error.UnknownFlags;
    if (readInt(u32, image, 20) != header_length) {
        return error.InvalidHeaderLength;
    }
    const declared_total = readInt(u64, image, 24);
    const actual_total = std.math.cast(u64, image.len) orelse
        return error.LengthOverflow;
    if (declared_total < header_length) return error.LengthMismatch;
    if (declared_total < actual_total) return error.TrailingBytes;
    if (declared_total > actual_total) return error.LengthMismatch;
    if (readInt(u32, image, 32) != section_count) {
        return error.InvalidSectionCount;
    }
    if (!allZero(image[36..40]) or !allZero(image[132..144])) {
        return error.UnknownFlags;
    }

    var sections: [section_count]Section = undefined;
    var expected_offset: u64 = header_length;
    for (0..section_count) |index| {
        const descriptor_offset = fixed_prefix_length +
            index * section_descriptor_length;
        const raw_kind = readInt(u16, image, descriptor_offset);
        const expected_kind: u16 = @intCast(index + 1);
        if (raw_kind != expected_kind) return error.InvalidSectionOrder;
        if (readInt(u16, image, descriptor_offset + 2) != 1 or
            readInt(u32, image, descriptor_offset + 4) != 0)
        {
            return error.UnknownFlags;
        }
        const offset = readInt(u64, image, descriptor_offset + 8);
        const length = readInt(u64, image, descriptor_offset + 16);
        if (offset != expected_offset) return error.InvalidSectionOffset;
        expected_offset = std.math.add(u64, offset, length) catch
            return error.InvalidSectionLength;
        if (expected_offset > declared_total) {
            return error.InvalidSectionLength;
        }
        sections[index] = .{
            .kind = @enumFromInt(raw_kind),
            .offset = offset,
            .length = length,
        };
    }
    if (expected_offset != declared_total) return error.InvalidSectionLength;

    return .{
        .image = image,
        .header = .{
            .total_length = declared_total,
            .program_semantic_digest = image[40..72].*,
            .machine_contract_digest = image[72..104].*,
            .maximum_frames = readInt(u32, image, 104),
            .maximum_state_bytes = readInt(u32, image, 108),
            .maximum_machine_fuel = readInt(u64, image, 112),
            .maximum_kernel_scratch_bytes = readInt(u64, image, 120),
            .maximum_single_value_bytes = readInt(u32, image, 128),
        },
        .sections = sections,
    };
}

fn readInt(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
}
