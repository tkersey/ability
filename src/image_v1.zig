const dynamic_value_v1 = @import("dynamic_value_v1");
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
    LimitExceeded,
    InvalidUtf8,
    InvalidSchema,
    InvalidRoot,
    InvalidFailureMap,
    DuplicateFailureName,
    DuplicateFailureTag,
    InvalidConstant,
    DuplicateConstant,
    InvalidEffect,
    DuplicateEffectIdentity,
    InvalidValue,
    InvalidFunction,
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

pub const ValidationWorkspace = struct {
    schema_nodes: [1024]dynamic_value_v1.NodeIndex = undefined,
    value_tasks: [2048]dynamic_value_v1.ValueTask = undefined,
};

pub const Catalogs = struct {
    envelope: ValidatedEnvelope,
    schemas: dynamic_value_v1.Table,
    initial_args_schema_id: u32,
    result_schema_id: u32,
    failure_schema_id: u32,
    value_count: u32,
    function_count: u32,
    effect_count: u32,
    constant_count: u32,
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

/// Validate the BEI1 type and static catalog frontier before executable graph
/// validation. No image instruction or effect is evaluated.
pub fn validateCatalogs(
    image: []const u8,
    workspace: *ValidationWorkspace,
) Error!Catalogs {
    const envelope = try validateEnvelope(image);
    const schemas = dynamic_value_v1.validateSchemaSection(
        envelope.section(.schemas),
        &workspace.schema_nodes,
    ) catch |err| return mapDynamicSchemaError(err);
    const roots = try validateRoots(envelope.section(.roots), schemas);
    try validateFailures(
        envelope.section(.failures),
        schemas,
        roots.failure_schema_id,
    );
    const constant_count = try validateConstants(
        envelope.section(.constants),
        schemas,
        &workspace.value_tasks,
    );
    const effect_count = try validateEffects(
        envelope.section(.effects),
        schemas,
    );
    const values = try validateValues(envelope.section(.values), schemas);
    if (roots.entry_parameter_count == 1) {
        if (roots.entry_parameter_value_id >= values.count or
            values.schemaId(roots.entry_parameter_value_id) !=
                roots.initial_args_schema_id)
        {
            return error.InvalidRoot;
        }
    }
    const function_count = try validateFunctions(
        envelope.section(.functions),
        schemas,
    );
    return .{
        .envelope = envelope,
        .schemas = schemas,
        .initial_args_schema_id = roots.initial_args_schema_id,
        .result_schema_id = roots.result_schema_id,
        .failure_schema_id = roots.failure_schema_id,
        .value_count = values.count,
        .function_count = function_count,
        .effect_count = effect_count,
        .constant_count = constant_count,
    };
}

const Roots = struct {
    initial_args_schema_id: u32,
    result_schema_id: u32,
    failure_schema_id: u32,
    entry_parameter_count: u16,
    entry_parameter_value_id: u16,
};

fn validateRoots(bytes: []const u8, schemas: dynamic_value_v1.Table) Error!Roots {
    if (bytes.len != 28) return error.InvalidRoot;
    const initial_args = readInt(u32, bytes, 0);
    const result = readInt(u32, bytes, 4);
    const failure = readInt(u32, bytes, 8);
    _ = schemas.node(initial_args) catch return error.InvalidRoot;
    _ = schemas.node(result) catch return error.InvalidRoot;
    _ = schemas.node(failure) catch return error.InvalidRoot;
    const parameter_count = readInt(u16, bytes, 14);
    if (parameter_count > 1 or readInt(u16, bytes, 20) != 0 or
        readInt(u16, bytes, 22) != 0 or readInt(u16, bytes, 26) != 0)
    {
        return error.InvalidRoot;
    }
    const parameter_value = readInt(u16, bytes, 24);
    if (parameter_count == 0) {
        if (parameter_value != std.math.maxInt(u16) or
            (schemas.node(initial_args) catch return error.InvalidRoot).kind !=
                .unit)
        {
            return error.InvalidRoot;
        }
    } else if (parameter_value == std.math.maxInt(u16)) {
        return error.InvalidRoot;
    }
    return .{
        .initial_args_schema_id = initial_args,
        .result_schema_id = result,
        .failure_schema_id = failure,
        .entry_parameter_count = parameter_count,
        .entry_parameter_value_id = parameter_value,
    };
}

fn validateFailures(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    failure_schema_id: u32,
) Error!void {
    if (bytes.len < 4) return error.InvalidFailureMap;
    const failure_schema = schemas.node(failure_schema_id) catch
        return error.InvalidFailureMap;
    if (failure_schema.kind != .@"enum") return error.InvalidFailureMap;
    const count = readInt(u32, bytes, 0);
    if (count != readInt(u32, failure_schema.payload, 0)) {
        return error.InvalidFailureMap;
    }
    var cursor: usize = 4;
    for (0..count) |index| {
        if (bytes.len - cursor < 8) return error.InvalidFailureMap;
        const tag = readInt(u32, bytes, cursor);
        if (tag != readInt(u32, failure_schema.payload, 4 + index * 4)) {
            return error.InvalidFailureMap;
        }
        cursor += 4;
        const name_length = readInt(u32, bytes, cursor);
        cursor += 4;
        const name = takeCatalogSlice(bytes, &cursor, name_length) catch
            return error.InvalidFailureMap;
        if (name.len == 0 or !std.unicode.utf8ValidateSlice(name)) {
            return error.InvalidUtf8;
        }
        var prior_cursor: usize = 4;
        for (0..index) |_| {
            const prior_tag = readInt(u32, bytes, prior_cursor);
            prior_cursor += 4;
            const prior_length = readInt(u32, bytes, prior_cursor);
            prior_cursor += 4;
            const prior_name = takeCatalogSlice(
                bytes,
                &prior_cursor,
                prior_length,
            ) catch return error.InvalidFailureMap;
            if (prior_tag == tag) return error.DuplicateFailureTag;
            if (std.mem.eql(u8, prior_name, name)) {
                return error.DuplicateFailureName;
            }
        }
    }
    if (cursor != bytes.len) return error.InvalidFailureMap;
}

fn validateConstants(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    tasks: []dynamic_value_v1.ValueTask,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidConstant;
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |index| {
        if (bytes.len - cursor < 8) return error.InvalidConstant;
        const record_start = cursor;
        const schema_id = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const value = takeCatalogSlice(bytes, &cursor, length) catch
            return error.InvalidConstant;
        dynamic_value_v1.validateValue(schemas, schema_id, value, tasks) catch
            return error.InvalidConstant;
        var prior_cursor: usize = 4;
        for (0..index) |_| {
            const prior_start = prior_cursor;
            const prior_schema = readInt(u32, bytes, prior_cursor);
            prior_cursor += 4;
            const prior_length = readInt(u32, bytes, prior_cursor);
            prior_cursor += 4;
            _ = takeCatalogSlice(bytes, &prior_cursor, prior_length) catch
                return error.InvalidConstant;
            if (prior_schema == schema_id and
                std.mem.eql(
                    u8,
                    bytes[prior_start..prior_cursor],
                    bytes[record_start..cursor],
                ))
            {
                return error.DuplicateConstant;
            }
        }
    }
    if (cursor != bytes.len) return error.InvalidConstant;
    return count;
}

fn validateEffects(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidEffect;
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |ordinal| {
        if (bytes.len - cursor < 84) return error.InvalidEffect;
        if (readInt(u32, bytes, cursor) != ordinal) return error.InvalidEffect;
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4;
        const identity = takeCatalogSlice(
            bytes,
            &cursor,
            identity_length,
        ) catch return error.InvalidEffect;
        if (identity.len == 0 or !std.unicode.utf8ValidateSlice(identity)) {
            return error.InvalidUtf8;
        }
        _ = schemas.node(readInt(u32, bytes, cursor)) catch
            return error.InvalidEffect;
        cursor += 4;
        _ = schemas.node(readInt(u32, bytes, cursor)) catch
            return error.InvalidEffect;
        cursor += 4;
        if (bytes[cursor] != 0 or !allZero(bytes[cursor + 1 .. cursor + 4])) {
            return error.InvalidEffect;
        }
        cursor += 4 + 64;
        var prior_cursor: usize = 4;
        for (0..ordinal) |_| {
            prior_cursor += 4;
            const prior_length = readInt(u32, bytes, prior_cursor);
            prior_cursor += 4;
            const prior_identity = takeCatalogSlice(
                bytes,
                &prior_cursor,
                prior_length,
            ) catch return error.InvalidEffect;
            if (std.mem.eql(u8, prior_identity, identity)) {
                return error.DuplicateEffectIdentity;
            }
            prior_cursor += 8 + 4 + 64;
        }
    }
    if (cursor != bytes.len) return error.InvalidEffect;
    return count;
}

const Values = struct {
    bytes: []const u8,
    count: u32,

    fn schemaId(self: Values, value: u16) u32 {
        return readInt(u32, self.bytes, 4 + @as(usize, value) * 4);
    }
};

fn validateValues(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
) Error!Values {
    if (bytes.len < 4) return error.InvalidValue;
    const count = readInt(u32, bytes, 0);
    if (count > 1024 or bytes.len != 4 + @as(usize, count) * 4) {
        return error.InvalidValue;
    }
    for (0..count) |index| {
        _ = schemas.node(readInt(u32, bytes, 4 + index * 4)) catch
            return error.InvalidValue;
    }
    return .{ .bytes = bytes, .count = count };
}

fn validateFunctions(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidFunction;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or bytes.len != 4 + @as(usize, count) * 8) {
        return error.InvalidFunction;
    }
    for (0..count) |index| {
        const offset = 4 + index * 8;
        if (readInt(u16, bytes, offset) != index) {
            return error.InvalidFunction;
        }
        _ = schemas.node(readInt(u32, bytes, offset + 4)) catch
            return error.InvalidFunction;
    }
    return count;
}

fn takeCatalogSlice(
    bytes: []const u8,
    cursor: *usize,
    length: usize,
) Error![]const u8 {
    const end = std.math.add(usize, cursor.*, length) catch
        return error.LengthOverflow;
    if (end > bytes.len) return error.LengthMismatch;
    defer cursor.* = end;
    return bytes[cursor.*..end];
}

fn mapDynamicSchemaError(err: dynamic_value_v1.Error) Error {
    return switch (err) {
        error.LengthOverflow => error.LengthOverflow,
        error.LimitExceeded => error.LimitExceeded,
        else => error.InvalidSchema,
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
