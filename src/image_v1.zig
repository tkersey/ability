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
    InvalidSegment,
    InvalidInstruction,
    InvalidTerminator,
    InvalidConstructor,
    InvalidInvariant,
    InvalidTransition,
    UnreachableEntry,
    MachineContractDigestMismatch,
    ScratchRequirementMismatch,
    DigestMismatch,
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
    schema_hash_tasks: [8192]dynamic_value_v1.SchemaHashTask = undefined,
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
    entry_segment_id: u16,
    initial_constructor_id: u32,
    values_section: []const u8,
    functions_section: []const u8,
};

pub const ValidatedImage = struct {
    catalogs: Catalogs,
    segment_count: u32,
    constructor_count: u32,
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
    if (envelope.header.maximum_single_value_bytes !=
        maximumSingleValueBytes(schemas))
    {
        return error.ScratchRequirementMismatch;
    }
    const machine_digest = computeMachineContractDigest(envelope.header) catch
        return error.MachineContractDigestMismatch;
    if (!std.mem.eql(
        u8,
        &machine_digest,
        &envelope.header.machine_contract_digest,
    )) {
        return error.MachineContractDigestMismatch;
    }
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
        &workspace.schema_hash_tasks,
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
        .entry_segment_id = roots.entry_segment_id,
        .initial_constructor_id = roots.initial_constructor_id,
        .values_section = envelope.section(.values),
        .functions_section = envelope.section(.functions),
    };
}

pub fn validateImage(
    image: []const u8,
    workspace: *ValidationWorkspace,
) Error!ValidatedImage {
    const catalogs = try validateCatalogs(image, workspace);
    const segment_count = try validateSegments(catalogs);
    try validateFunctionEntries(catalogs, segment_count);
    const constructor_count = try validateConstructors(
        catalogs,
        segment_count,
    );
    try validateTransitions(catalogs, segment_count, constructor_count);
    if (catalogs.entry_segment_id >= segment_count or
        catalogs.initial_constructor_id >= constructor_count)
    {
        return error.UnreachableEntry;
    }
    return .{
        .catalogs = catalogs,
        .segment_count = segment_count,
        .constructor_count = constructor_count,
    };
}

const Roots = struct {
    initial_args_schema_id: u32,
    result_schema_id: u32,
    failure_schema_id: u32,
    entry_parameter_count: u16,
    entry_parameter_value_id: u16,
    entry_segment_id: u16,
    initial_constructor_id: u32,
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
        .entry_segment_id = readInt(u16, bytes, 12),
        .initial_constructor_id = readInt(u32, bytes, 16),
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
    hash_tasks: []dynamic_value_v1.SchemaHashTask,
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
        const payload_schema = readInt(u32, bytes, cursor);
        _ = schemas.node(payload_schema) catch
            return error.InvalidEffect;
        cursor += 4;
        const resume_schema = readInt(u32, bytes, cursor);
        _ = schemas.node(resume_schema) catch
            return error.InvalidEffect;
        cursor += 4;
        if (bytes[cursor] != 0 or !allZero(bytes[cursor + 1 .. cursor + 4])) {
            return error.InvalidEffect;
        }
        cursor += 4;
        const semantic_digest = try effectDigest(
            schemas,
            hash_tasks,
            null,
            identity,
            payload_schema,
            resume_schema,
        );
        if (!std.mem.eql(u8, &semantic_digest, bytes[cursor..][0..32])) {
            return error.DigestMismatch;
        }
        cursor += 32;
        const ordinal_digest = try effectDigest(
            schemas,
            hash_tasks,
            @intCast(ordinal),
            identity,
            payload_schema,
            resume_schema,
        );
        if (!std.mem.eql(u8, &ordinal_digest, bytes[cursor..][0..32])) {
            return error.DigestMismatch;
        }
        cursor += 32;
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

fn effectDigest(
    schemas: dynamic_value_v1.Table,
    hash_tasks: []dynamic_value_v1.SchemaHashTask,
    ordinal: ?u32,
    identity: []const u8,
    payload_schema: u32,
    resume_schema: u32,
) Error![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    semanticHashBytes(
        &hasher,
        if (ordinal == null)
            "boundary-effect-site-semantic-contract-v1"
        else
            "boundary-effect-site-contract-v1",
    );
    if (ordinal) |value| semanticHashU32(&hasher, value);
    semanticHashBytes(&hasher, identity);
    const payload_digest = dynamic_value_v1.schemaDigest(
        schemas,
        payload_schema,
        hash_tasks,
    ) catch return error.InvalidSchema;
    hasher.update(&payload_digest);
    const resume_digest = dynamic_value_v1.schemaDigest(
        schemas,
        resume_schema,
        hash_tasks,
    ) catch return error.InvalidSchema;
    hasher.update(&resume_digest);
    semanticHashBytes(&hasher, "single-resume");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
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

fn validateSegments(catalogs: Catalogs) Error!u32 {
    const bytes = catalogs.envelope.section(.segments);
    if (bytes.len < 4) return error.InvalidSegment;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > 128) return error.InvalidSegment;
    var cursor: usize = 4;
    for (0..count) |segment_id| {
        if (bytes.len - cursor < 24) return error.InvalidSegment;
        const end = recordEnd(bytes, cursor, 24) catch
            return error.InvalidSegment;
        if (readInt(u16, bytes, cursor + 4) != segment_id or
            readInt(u16, bytes, cursor + 6) >= catalogs.function_count or
            bytes[cursor + 8] > 4 or bytes[cursor + 9] != 0 or
            readInt(u64, bytes, cursor + 16) == 0)
        {
            return error.InvalidSegment;
        }
        const parameter_count = readInt(u16, bytes, cursor + 10);
        const instruction_count = readInt(u32, bytes, cursor + 12);
        cursor += 24;
        for (0..parameter_count) |index| {
            if (end - cursor < 2) return error.InvalidSegment;
            const value = readInt(u16, bytes, cursor);
            if (value >= catalogs.value_count) return error.InvalidSegment;
            var prior = cursor - index * 2;
            while (prior < cursor) : (prior += 2) {
                if (readInt(u16, bytes, prior) == value) {
                    return error.InvalidSegment;
                }
            }
            cursor += 2;
        }
        for (0..instruction_count) |_| {
            cursor = try validateInstruction(catalogs, bytes, cursor, end);
        }
        cursor = try validateTerminator(catalogs, bytes, cursor, end);
        if (cursor != end) return error.InvalidSegment;
    }
    if (cursor != bytes.len) return error.InvalidSegment;
    return count;
}

fn validateInstruction(
    catalogs: Catalogs,
    bytes: []const u8,
    start: usize,
    segment_end: usize,
) Error!usize {
    if (segment_end - start < 16) return error.InvalidInstruction;
    const end = recordEnd(bytes, start, 16) catch
        return error.InvalidInstruction;
    if (end > segment_end) return error.InvalidInstruction;
    const kind = bytes[start + 4];
    const operation = readInt(u16, bytes, start + 6);
    const result = readInt(u16, bytes, start + 8);
    const operand_count = readInt(u16, bytes, start + 10);
    const immediate = readInt(u32, bytes, start + 12);
    const expected_kind: u8 = if (operation <= 2) @intCast(operation) else 3;
    if (bytes[start + 5] != 0 or operation > 57 or kind != expected_kind or
        result >= catalogs.value_count or
        end != start + 16 + @as(usize, operand_count) * 2)
    {
        return error.InvalidInstruction;
    }
    if (operation == 0) {
        if (immediate >= catalogs.constant_count) return error.InvalidInstruction;
    } else if (operation < 25 or operation > 29) {
        if (immediate != 0) return error.InvalidInstruction;
    }
    var cursor = start + 16;
    for (0..operand_count) |_| {
        if (readInt(u16, bytes, cursor) >= catalogs.value_count) {
            return error.InvalidInstruction;
        }
        cursor += 2;
    }
    return end;
}

fn validateTerminator(
    catalogs: Catalogs,
    bytes: []const u8,
    start: usize,
    segment_end: usize,
) Error!usize {
    if (segment_end - start < 8) return error.InvalidTerminator;
    const end = recordEnd(bytes, start, 8) catch
        return error.InvalidTerminator;
    if (end > segment_end or bytes[start + 4] > 6 or
        bytes[start + 5] != 0 or readInt(u16, bytes, start + 6) != 0)
    {
        return error.InvalidTerminator;
    }
    var cursor = start + 8;
    switch (bytes[start + 4]) {
        0 => try validateEdge(catalogs, bytes, &cursor, end),
        1 => {
            if (end - cursor < 4 or
                readInt(u16, bytes, cursor) >= catalogs.value_count or
                readInt(u16, bytes, cursor + 2) != 0)
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
            try validateEdge(catalogs, bytes, &cursor, end);
            try validateEdge(catalogs, bytes, &cursor, end);
        },
        2 => try validateSuspension(catalogs, bytes, &cursor, end),
        3 => {
            if (end - cursor != 4 or bytes[cursor] > 1 or
                bytes[cursor + 1] != 0)
            {
                return error.InvalidTerminator;
            }
            const value = readInt(u16, bytes, cursor + 2);
            if ((bytes[cursor] == 0 and value != std.math.maxInt(u16)) or
                (bytes[cursor] == 1 and value >= catalogs.value_count))
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
        },
        4, 6 => {
            if (end - cursor != 4 or
                readInt(u16, bytes, cursor) >= catalogs.value_count or
                readInt(u16, bytes, cursor + 2) != 0)
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
        },
        5 => {
            if (end - cursor != 4) return error.InvalidTerminator;
            cursor += 4;
        },
        else => unreachable,
    }
    if (cursor != end) return error.InvalidTerminator;
    return end;
}

fn validateSuspension(
    catalogs: Catalogs,
    bytes: []const u8,
    cursor: *usize,
    end: usize,
) Error!void {
    if (end - cursor.* < 20) return error.InvalidTerminator;
    const kind = bytes[cursor.*];
    if (kind > 3 or bytes[cursor.* + 1] != 0 or
        readInt(u16, bytes, cursor.* + 2) != 0)
    {
        return error.InvalidTerminator;
    }
    const site = readInt(u32, bytes, cursor.* + 4);
    const callee = readInt(u16, bytes, cursor.* + 8);
    const request_count = readInt(u16, bytes, cursor.* + 10);
    cursor.* += 12;
    if ((kind == 0 and site >= catalogs.effect_count) or
        (kind != 0 and site != std.math.maxInt(u32)) or
        (kind == 1 and callee >= catalogs.function_count) or
        (kind != 1 and callee != std.math.maxInt(u16)))
    {
        return error.InvalidTerminator;
    }
    for (0..request_count) |_| {
        if (end - cursor.* < 2 or
            readInt(u16, bytes, cursor.*) >= catalogs.value_count)
        {
            return error.InvalidTerminator;
        }
        cursor.* += 2;
    }
    if (end - cursor.* < 4) return error.InvalidTerminator;
    const callee_present = bytes[cursor.*];
    if (callee_present > 1 or !allZero(bytes[cursor.* + 1 .. cursor.* + 4]) or
        (callee_present == 1) != (kind == 1))
    {
        return error.InvalidTerminator;
    }
    cursor.* += 4;
    if (callee_present == 1) try validateEdge(catalogs, bytes, cursor, end);
    try validateEdge(catalogs, bytes, cursor, end);
    if (end - cursor.* != 4) return error.InvalidTerminator;
    const resume_schema = readInt(u32, bytes, cursor.*);
    if (resume_schema != std.math.maxInt(u32)) {
        _ = catalogs.schemas.node(resume_schema) catch
            return error.InvalidTerminator;
    }
    cursor.* += 4;
}

fn validateEdge(
    catalogs: Catalogs,
    bytes: []const u8,
    cursor: *usize,
    end: usize,
) Error!void {
    if (end - cursor.* < 4) return error.InvalidTerminator;
    const target = readInt(u16, bytes, cursor.*);
    const count = readInt(u16, bytes, cursor.* + 2);
    if (target >= readInt(u32, catalogs.envelope.section(.segments), 0)) {
        return error.InvalidTerminator;
    }
    cursor.* += 4;
    for (0..count) |_| {
        if (end - cursor.* < 4 or bytes[cursor.*] > 1 or
            bytes[cursor.* + 1] != 0)
        {
            return error.InvalidTerminator;
        }
        const value = readInt(u16, bytes, cursor.* + 2);
        if ((bytes[cursor.*] == 0 and value >= catalogs.value_count) or
            (bytes[cursor.*] == 1 and value != std.math.maxInt(u16)))
        {
            return error.InvalidTerminator;
        }
        cursor.* += 4;
    }
}

fn validateFunctionEntries(catalogs: Catalogs, segment_count: u32) Error!void {
    for (0..catalogs.function_count) |index| {
        const offset = 4 + index * 8;
        if (readInt(u16, catalogs.functions_section, offset + 2) >= segment_count) {
            return error.InvalidFunction;
        }
    }
}

fn validateConstructors(catalogs: Catalogs, segment_count: u32) Error!u32 {
    const bytes = catalogs.envelope.section(.constructors);
    if (bytes.len < 4) return error.InvalidConstructor;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > 256) return error.InvalidConstructor;
    var cursor: usize = 4;
    for (0..count) |constructor_id| {
        if (bytes.len - cursor < 24) return error.InvalidConstructor;
        const end = recordEnd(bytes, cursor, 24) catch
            return error.InvalidConstructor;
        if (readInt(u32, bytes, cursor + 4) != constructor_id or
            bytes[cursor + 8] > 7 or bytes[cursor + 9] > 2 or
            readInt(u16, bytes, cursor + 10) & ~@as(u16, 1) != 0 or
            readInt(u16, bytes, cursor + 12) >= segment_count or
            readInt(u16, bytes, cursor + 22) != 0)
        {
            return error.InvalidConstructor;
        }
        const resume_target = readInt(u16, bytes, cursor + 14);
        if (resume_target != std.math.maxInt(u16) and
            resume_target >= segment_count)
        {
            return error.InvalidConstructor;
        }
        const activation_count = readInt(u16, bytes, cursor + 16);
        const environment_count = readInt(u16, bytes, cursor + 18);
        const invariant_count = readInt(u16, bytes, cursor + 20);
        cursor += 24;
        const field_count = @as(u32, activation_count) + environment_count;
        for (0..field_count) |_| {
            if (end - cursor < 8) return error.InvalidConstructor;
            const value = readInt(u16, bytes, cursor);
            if (value >= catalogs.value_count or
                readInt(u16, bytes, cursor + 2) != 0 or
                readInt(u32, bytes, cursor + 4) != valueSchema(catalogs, value))
            {
                return error.InvalidConstructor;
            }
            cursor += 8;
        }
        for (0..invariant_count) |_| {
            cursor = try validateInvariant(catalogs, bytes, cursor, end);
        }
        if (cursor != end) return error.InvalidConstructor;
    }
    if (cursor != bytes.len) return error.InvalidConstructor;
    return count;
}

fn validateInvariant(
    catalogs: Catalogs,
    bytes: []const u8,
    start: usize,
    constructor_end: usize,
) Error!usize {
    if (constructor_end - start < 8) return error.InvalidInvariant;
    const end = recordEnd(bytes, start, 8) catch return error.InvalidInvariant;
    if (end > constructor_end or bytes[start + 4] > 20 or
        bytes[start + 5] != 0 or readInt(u16, bytes, start + 6) != 0)
    {
        return error.InvalidInvariant;
    }
    const payload_length = end - start - 8;
    const expected: usize = switch (bytes[start + 4]) {
        0, 1, 2, 5, 11, 15, 16 => 4,
        3, 4, 7, 9, 10, 12, 13, 14, 17, 18, 19, 20 => 8,
        6 => 20,
        8 => blk: {
            if (payload_length < 8) return error.InvalidInvariant;
            break :blk 8 + @as(usize, readInt(u16, bytes, start + 12)) * 2;
        },
        else => unreachable,
    };
    if (payload_length != expected) return error.InvalidInvariant;
    const value_slots: usize = switch (bytes[start + 4]) {
        0, 15, 19 => 1,
        1, 2, 5, 6, 9, 10, 11, 12, 14, 16, 20 => 2,
        3, 13, 18 => 3,
        4, 7 => 4,
        8 => 2,
        17 => 2,
        else => 0,
    };
    for (0..value_slots) |index| {
        if (readInt(u16, bytes, start + 8 + index * 2) >= catalogs.value_count) {
            return error.InvalidInvariant;
        }
    }
    if (bytes[start + 4] == 8) {
        const operand_count = readInt(u16, bytes, start + 12);
        for (0..operand_count) |index| {
            if (readInt(u16, bytes, start + 16 + index * 2) >=
                catalogs.value_count)
            {
                return error.InvalidInvariant;
            }
        }
    }
    return end;
}

fn validateTransitions(
    catalogs: Catalogs,
    segment_count: u32,
    constructor_count: u32,
) Error!void {
    const bytes = catalogs.envelope.section(.entry_transitions);
    if (bytes.len < 4) return error.InvalidTransition;
    const count = readInt(u32, bytes, 0);
    if (bytes.len != 4 + @as(usize, count) * 12) {
        return error.InvalidTransition;
    }
    var previous: ?[3]u32 = null;
    for (0..count) |index| {
        const offset = 4 + index * 12;
        const source = readInt(u16, bytes, offset);
        const edge = bytes[offset + 2];
        const target = readInt(u16, bytes, offset + 4);
        const constructor = readInt(u32, bytes, offset + 8);
        if (edge > 4 or bytes[offset + 3] != 0 or
            readInt(u16, bytes, offset + 6) != 0 or
            source >= segment_count or target >= segment_count or
            constructor >= constructor_count)
        {
            return error.InvalidTransition;
        }
        const key = [3]u32{ source, edge, target };
        if (previous) |prior| {
            if (!lexicographicallyLess(prior, key)) {
                return error.InvalidTransition;
            }
        }
        previous = key;
    }
}

fn valueSchema(catalogs: Catalogs, value: u16) u32 {
    return readInt(u32, catalogs.values_section, 4 + @as(usize, value) * 4);
}

fn lexicographicallyLess(left: [3]u32, right: [3]u32) bool {
    for (left, right) |left_item, right_item| {
        if (left_item != right_item) return left_item < right_item;
    }
    return false;
}

fn recordEnd(bytes: []const u8, start: usize, minimum: usize) Error!usize {
    if (bytes.len - start < 4) return error.LengthMismatch;
    const length = readInt(u32, bytes, start);
    if (length < minimum) return error.LengthMismatch;
    const end = std.math.add(usize, start, length) catch
        return error.LengthOverflow;
    if (end > bytes.len) return error.LengthMismatch;
    return end;
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

fn maximumSingleValueBytes(schemas: dynamic_value_v1.Table) u32 {
    var maximum: u64 = 0;
    for (schemas.nodes) |node| {
        maximum = @max(maximum, node.maximum_encoded_size);
    }
    return std.math.cast(u32, maximum) orelse std.math.maxInt(u32);
}

fn computeMachineContractDigest(header: Header) Error![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&header.program_semantic_digest);
    hasher.update("\x00boundary-machine-abi=2");
    hasher.update("\x00state=rnf-v1");
    var buffer: [32]u8 = undefined;
    hasher.update("\x00frames=");
    hasher.update(std.fmt.bufPrint(
        &buffer,
        "{d}",
        .{header.maximum_frames},
    ) catch return error.MachineContractDigestMismatch);
    hasher.update("\x00state-bytes=");
    hasher.update(std.fmt.bufPrint(
        &buffer,
        "{d}",
        .{header.maximum_state_bytes},
    ) catch return error.MachineContractDigestMismatch);
    hasher.update("\x00fuel=");
    hasher.update(std.fmt.bufPrint(
        &buffer,
        "{d}",
        .{header.maximum_machine_fuel},
    ) catch return error.MachineContractDigestMismatch);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn semanticHashU32(hasher: anytype, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn semanticHashU64(hasher: anytype, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn semanticHashBytes(hasher: anytype, value: []const u8) void {
    semanticHashU64(hasher, value.len);
    hasher.update(value);
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
