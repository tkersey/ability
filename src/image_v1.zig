const dynamic_value_v1 = @import("dynamic_value_v1");
const reducer_semantics_v1 = @import("reducer_semantics_v1");
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
    ProgramSemanticDigestMismatch,
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
    invariant_instruction: [16 + 2 * 1024]u8 = undefined,
    invariant_result: []u8 = &.{},
    catalog_digests: [1024][32]u8 = undefined,
    catalog_keys: [1024]u32 = undefined,
    catalog_offsets: [1024]u32 = undefined,
    catalog_lengths: [1024]u32 = undefined,
    constant_used: [1024]bool = undefined,
    canonical_schema_seen: [1024]bool = undefined,
    canonical_schema_stack: [2048]SchemaOrderTask = undefined,
};

pub const SchemaOrderTask = struct {
    schema_id: u32,
    expanded: bool,
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
    entry_parameter_count: u16,
    entry_parameter_value_id: u16,

    pub fn valueSchemaId(self: Catalogs, value: u16) Error!u32 {
        if (value >= self.value_count) return error.InvalidValue;
        return readInt(u32, self.values_section, 4 + @as(usize, value) * 4);
    }
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
        workspace,
    );
    const constant_count = try validateConstants(
        envelope.section(.constants),
        schemas,
        &workspace.value_tasks,
        workspace,
    );
    const effect_count = try validateEffects(
        envelope.section(.effects),
        schemas,
        &workspace.schema_hash_tasks,
        workspace,
    );
    const values = try validateValues(envelope.section(.values), schemas);
    if (envelope.header.maximum_kernel_scratch_bytes !=
        try deriveKernelScratch(schemas, values))
    {
        return error.ScratchRequirementMismatch;
    }
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
        .entry_parameter_count = roots.entry_parameter_count,
        .entry_parameter_value_id = roots.entry_parameter_value_id,
    };
}

pub fn validateImage(
    image: []const u8,
    workspace: *ValidationWorkspace,
) Error!ValidatedImage {
    const catalogs = try validateCatalogs(image, workspace);
    try validateCanonicalSchemaOrder(catalogs, workspace);
    @memset(workspace.constant_used[0..catalogs.constant_count], false);
    var next_constant: u32 = 0;
    const segment_count = try validateSegments(
        catalogs,
        &workspace.constant_used,
        &next_constant,
    );
    for (workspace.constant_used[0..catalogs.constant_count]) |used| {
        if (!used) return error.InvalidConstant;
    }
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
    const program_digest = try computeProgramSemanticDigest(
        catalogs,
        &workspace.schema_hash_tasks,
    );
    if (!std.mem.eql(
        u8,
        &program_digest,
        &catalogs.envelope.header.program_semantic_digest,
    )) {
        return error.ProgramSemanticDigestMismatch;
    }
    return .{
        .catalogs = catalogs,
        .segment_count = segment_count,
        .constructor_count = constructor_count,
    };
}

fn validateCanonicalSchemaOrder(
    catalogs: Catalogs,
    workspace: *ValidationWorkspace,
) Error!void {
    @memset(
        workspace.canonical_schema_seen[0..catalogs.schemas.count()],
        false,
    );
    var next_schema: u32 = 0;
    try visitCanonicalSchema(
        catalogs.schemas,
        catalogs.initial_args_schema_id,
        workspace,
        &next_schema,
    );
    try visitCanonicalSchema(
        catalogs.schemas,
        catalogs.result_schema_id,
        workspace,
        &next_schema,
    );
    try visitCanonicalSchema(
        catalogs.schemas,
        catalogs.failure_schema_id,
        workspace,
        &next_schema,
    );

    const effects = catalogs.envelope.section(.effects);
    var effect_cursor: usize = 4;
    for (0..catalogs.effect_count) |_| {
        effect_cursor += 4;
        const identity_length = readInt(u32, effects, effect_cursor);
        effect_cursor += 4 + identity_length;
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, effects, effect_cursor),
            workspace,
            &next_schema,
        );
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, effects, effect_cursor + 4),
            workspace,
            &next_schema,
        );
        effect_cursor += 8 + 4 + 64;
    }
    for (0..catalogs.value_count) |value| {
        try visitCanonicalSchema(
            catalogs.schemas,
            try catalogs.valueSchemaId(@intCast(value)),
            workspace,
            &next_schema,
        );
    }
    const functions = catalogs.functions_section;
    for (0..catalogs.function_count) |function| {
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, functions, 4 + function * 8 + 4),
            workspace,
            &next_schema,
        );
    }
    const constants = catalogs.envelope.section(.constants);
    var constant_cursor: usize = 4;
    for (0..catalogs.constant_count) |_| {
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, constants, constant_cursor),
            workspace,
            &next_schema,
        );
        const length = readInt(u32, constants, constant_cursor + 4);
        constant_cursor += 8 + length;
    }
    if (next_schema != catalogs.schemas.count()) return error.InvalidSchema;
}

fn visitCanonicalSchema(
    schemas: dynamic_value_v1.Table,
    root: u32,
    workspace: *ValidationWorkspace,
    next_schema: *u32,
) Error!void {
    var stack_length: usize = 0;
    try pushSchemaOrderTask(workspace, &stack_length, root, false);
    while (stack_length != 0) {
        stack_length -= 1;
        const task = workspace.canonical_schema_stack[stack_length];
        if (workspace.canonical_schema_seen[task.schema_id]) continue;
        const node = schemas.node(task.schema_id) catch return error.InvalidSchema;
        if (task.expanded) {
            if (task.schema_id != next_schema.*) return error.InvalidSchema;
            workspace.canonical_schema_seen[task.schema_id] = true;
            next_schema.* += 1;
            continue;
        }
        try pushSchemaOrderTask(
            workspace,
            &stack_length,
            task.schema_id,
            true,
        );
        switch (node.kind) {
            .array, .vector => try pushSchemaOrderTask(
                workspace,
                &stack_length,
                readInt(u32, node.payload, 4),
                false,
            ),
            .optional => try pushSchemaOrderTask(
                workspace,
                &stack_length,
                readInt(u32, node.payload, 0),
                false,
            ),
            .product => {
                const count = readInt(u32, node.payload, 0);
                var index = count;
                while (index != 0) {
                    index -= 1;
                    try pushSchemaOrderTask(
                        workspace,
                        &stack_length,
                        readInt(u32, node.payload, 4 + @as(usize, index) * 4),
                        false,
                    );
                }
            },
            .sum => {
                const count = readInt(u32, node.payload, 4);
                var index = count;
                while (index != 0) {
                    index -= 1;
                    try pushSchemaOrderTask(
                        workspace,
                        &stack_length,
                        readInt(u32, node.payload, 12 + @as(usize, index) * 8),
                        false,
                    );
                }
                try pushSchemaOrderTask(
                    workspace,
                    &stack_length,
                    readInt(u32, node.payload, 0),
                    false,
                );
            },
            else => {},
        }
    }
}

fn pushSchemaOrderTask(
    workspace: *ValidationWorkspace,
    stack_length: *usize,
    schema_id: u32,
    expanded: bool,
) Error!void {
    if (schema_id >= workspace.canonical_schema_seen.len or
        stack_length.* == workspace.canonical_schema_stack.len)
    {
        return error.InvalidSchema;
    }
    workspace.canonical_schema_stack[stack_length.*] = .{
        .schema_id = schema_id,
        .expanded = expanded,
    };
    stack_length.* += 1;
}

/// Re-encode a fully validated canonical image into caller-owned storage.
/// Structural validation has already rejected alternate encodings.
pub fn reencodeValidated(
    image: ValidatedImage,
    output: []u8,
) Error!usize {
    const source = image.catalogs.envelope.image;
    if (output.len < source.len) return error.LengthMismatch;
    @memcpy(output[0..source.len], source);
    return source.len;
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
    workspace: *ValidationWorkspace,
) Error!void {
    if (bytes.len < 4) return error.InvalidFailureMap;
    const failure_schema = schemas.node(failure_schema_id) catch
        return error.InvalidFailureMap;
    if (failure_schema.kind != .@"enum") return error.InvalidFailureMap;
    const count = readInt(u32, bytes, 0);
    if (count > 1024 or count != readInt(u32, failure_schema.payload, 0)) {
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
        std.crypto.hash.sha2.Sha256.hash(
            name,
            &workspace.catalog_digests[index],
            .{},
        );
        for (0..index) |prior| {
            if (workspace.catalog_keys[prior] == tag) {
                return error.DuplicateFailureTag;
            }
            const prior_offset: usize = workspace.catalog_offsets[prior];
            const prior_length: usize = workspace.catalog_lengths[prior];
            if (std.mem.eql(
                u8,
                &workspace.catalog_digests[prior],
                &workspace.catalog_digests[index],
            ) and std.mem.eql(
                u8,
                bytes[prior_offset..][0..prior_length],
                name,
            )) {
                return error.DuplicateFailureName;
            }
        }
        workspace.catalog_keys[index] = tag;
        workspace.catalog_offsets[index] = @intCast(cursor - name.len);
        workspace.catalog_lengths[index] = @intCast(name.len);
    }
    if (cursor != bytes.len) return error.InvalidFailureMap;
}

fn validateConstants(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    tasks: []dynamic_value_v1.ValueTask,
    workspace: *ValidationWorkspace,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidConstant;
    const count = readInt(u32, bytes, 0);
    if (count > 1024) return error.InvalidConstant;
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
        std.crypto.hash.sha2.Sha256.hash(
            bytes[record_start..cursor],
            &workspace.catalog_digests[index],
            .{},
        );
        for (0..index) |prior| {
            const prior_offset: usize = workspace.catalog_offsets[prior];
            const prior_length: usize = workspace.catalog_lengths[prior];
            if (std.mem.eql(
                u8,
                &workspace.catalog_digests[prior],
                &workspace.catalog_digests[index],
            ) and std.mem.eql(
                u8,
                bytes[prior_offset..][0..prior_length],
                bytes[record_start..cursor],
            )) {
                return error.DuplicateConstant;
            }
        }
        workspace.catalog_offsets[index] = @intCast(record_start);
        workspace.catalog_lengths[index] = @intCast(cursor - record_start);
    }
    if (cursor != bytes.len) return error.InvalidConstant;
    return count;
}

fn validateEffects(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    hash_tasks: []dynamic_value_v1.SchemaHashTask,
    workspace: *ValidationWorkspace,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidEffect;
    const count = readInt(u32, bytes, 0);
    if (count > 128) return error.InvalidEffect;
    var cursor: usize = 4;
    for (0..count) |ordinal| {
        if (bytes.len - cursor < 84) return error.InvalidEffect;
        if (readInt(u32, bytes, cursor) != ordinal) return error.InvalidEffect;
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4;
        if (identity_length > bytes.len - cursor or
            bytes.len - cursor - identity_length < 76)
        {
            return error.InvalidEffect;
        }
        const identity = takeCatalogSlice(
            bytes,
            &cursor,
            identity_length,
        ) catch return error.InvalidEffect;
        if (identity.len == 0 or !std.unicode.utf8ValidateSlice(identity)) {
            return error.InvalidUtf8;
        }
        std.crypto.hash.sha2.Sha256.hash(
            identity,
            &workspace.catalog_digests[ordinal],
            .{},
        );
        for (0..ordinal) |prior| {
            const prior_offset: usize = workspace.catalog_offsets[prior];
            const prior_length: usize = workspace.catalog_lengths[prior];
            if (std.mem.eql(
                u8,
                &workspace.catalog_digests[prior],
                &workspace.catalog_digests[ordinal],
            ) and std.mem.eql(
                u8,
                bytes[prior_offset..][0..prior_length],
                identity,
            )) return error.DuplicateEffectIdentity;
        }
        workspace.catalog_offsets[ordinal] = @intCast(cursor - identity.len);
        workspace.catalog_lengths[ordinal] = @intCast(identity.len);
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

fn deriveKernelScratch(
    schemas: dynamic_value_v1.Table,
    values: Values,
) Error!u64 {
    var value_bytes: u64 = 0;
    for (0..values.count) |value| {
        const schema_id = values.schemaId(@intCast(value));
        const node = schemas.node(schema_id) catch return error.InvalidSchema;
        value_bytes = std.math.add(
            u64,
            value_bytes,
            node.maximum_encoded_size,
        ) catch return error.LengthOverflow;
    }
    const value_metadata = std.math.mul(u64, values.count, 16) catch
        return error.LengthOverflow;
    const schema_stack = std.math.mul(u64, schemas.count(), 16) catch
        return error.LengthOverflow;
    var maximum_single: u64 = 0;
    for (schemas.nodes) |node| {
        maximum_single = @max(maximum_single, node.maximum_encoded_size);
    }
    const framing = std.math.add(
        u64,
        std.math.mul(u64, maximum_single, 3) catch
            return error.LengthOverflow,
        176,
    ) catch return error.LengthOverflow;
    return std.math.add(
        u64,
        std.math.add(u64, value_bytes, value_metadata) catch
            return error.LengthOverflow,
        std.math.add(u64, schema_stack, framing) catch
            return error.LengthOverflow,
    ) catch error.LengthOverflow;
}

fn validateFunctions(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidFunction;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > 128) return error.InvalidFunction;
    const records_length = std.math.mul(usize, count, 8) catch
        return error.InvalidFunction;
    const expected_length = std.math.add(usize, 4, records_length) catch
        return error.InvalidFunction;
    if (bytes.len != expected_length) {
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

fn validateSegments(
    catalogs: Catalogs,
    constant_used: *[1024]bool,
    next_constant: *u32,
) Error!u32 {
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
        if (segment_id == catalogs.entry_segment_id and bytes[cursor + 8] != 0) {
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
            cursor = try validateInstruction(
                catalogs,
                bytes,
                cursor,
                end,
                constant_used,
                next_constant,
            );
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
    constant_used: *[1024]bool,
    next_constant: *u32,
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
    const wire_operation = std.enums.fromInt(
        reducer_semantics_v1.WireOperation,
        operation,
    ) orelse return error.InvalidInstruction;
    const expected_kind: u8 = if (operation <= 2) @intCast(operation) else 3;
    if (bytes[start + 5] != 0 or operation > 57 or kind != expected_kind or
        result >= catalogs.value_count or
        end != start + 16 + @as(usize, operand_count) * 2)
    {
        return error.InvalidInstruction;
    }
    if (operation == 0) {
        if (immediate >= catalogs.constant_count) return error.InvalidInstruction;
        if (!constant_used[immediate]) {
            if (immediate != next_constant.*) return error.InvalidConstant;
            next_constant.* += 1;
        }
        constant_used[immediate] = true;
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
    try validateInstructionSchemas(
        catalogs,
        wire_operation,
        result,
        bytes[start + 16 .. end],
        operand_count,
        immediate,
    );
    return end;
}

fn validateInstructionSchemas(
    catalogs: Catalogs,
    operation: reducer_semantics_v1.WireOperation,
    result: u16,
    operand_bytes: []const u8,
    operand_count: u16,
    immediate: u32,
) Error!void {
    if (reducer_semantics_v1.fixedOperandCount(operation)) |expected| {
        if (operand_count != expected) return error.InvalidInstruction;
    }
    const result_schema = valueSchema(catalogs, result);
    const result_node = catalogs.schemas.node(result_schema) catch
        return error.InvalidInstruction;
    const Operand = struct {
        fn id(bytes: []const u8, index: usize) u16 {
            return readInt(u16, bytes, index * 2);
        }
        fn schema(c: Catalogs, bytes: []const u8, index: usize) u32 {
            return valueSchema(c, id(bytes, index));
        }
        fn node(
            c: Catalogs,
            bytes: []const u8,
            index: usize,
        ) Error!dynamic_value_v1.Node {
            return c.schemas.node(schema(c, bytes, index)) catch
                error.InvalidInstruction;
        }
    };
    const bool_schema = result_node.kind == .bool;
    const u32_result = result_node.kind == .u32;
    switch (operation) {
        .constant => if (result_schema != try constantSchema(
            catalogs,
            immediate,
        )) return error.InvalidInstruction,
        .copy => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        )) return error.InvalidInstruction,
        .compare_eq_zero => {
            if (!isIntegerKind((try Operand.node(
                catalogs,
                operand_bytes,
                0,
            )).kind) or !bool_schema) return error.InvalidInstruction;
        },
        .integer_add,
        .integer_subtract,
        .integer_multiply,
        .integer_divide,
        .integer_remainder,
        .integer_bit_and,
        .integer_bit_or,
        .integer_bit_xor,
        => {
            if (!isIntegerKind(result_node.kind) or
                result_schema != Operand.schema(catalogs, operand_bytes, 0) or
                result_schema != Operand.schema(catalogs, operand_bytes, 1))
            {
                return error.InvalidInstruction;
            }
        },
        .integer_negate => {
            if (!isSignedIntegerKind(result_node.kind) or
                result_schema != Operand.schema(catalogs, operand_bytes, 0))
            {
                return error.InvalidInstruction;
            }
        },
        .integer_equal,
        .integer_not_equal,
        .integer_less_than,
        .integer_less_equal,
        .integer_greater_than,
        .integer_greater_equal,
        => {
            const left = Operand.schema(catalogs, operand_bytes, 0);
            if (!bool_schema or left != Operand.schema(
                catalogs,
                operand_bytes,
                1,
            ) or !isIntegerKind((try catalogs.schemas.node(left)).kind)) {
                return error.InvalidInstruction;
            }
        },
        .integer_bit_not => {
            if (!isIntegerKind(result_node.kind) or
                result_schema != Operand.schema(catalogs, operand_bytes, 0))
            {
                return error.InvalidInstruction;
            }
        },
        .integer_convert => if (!isIntegerKind(result_node.kind) or
            !isIntegerKind((try Operand.node(
                catalogs,
                operand_bytes,
                0,
            )).kind)) return error.InvalidInstruction,
        .boolean_not => if (!bool_schema or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bool)
            return error.InvalidInstruction,
        .boolean_and, .boolean_or => if (!bool_schema or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bool or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bool)
            return error.InvalidInstruction,
        .select => if ((try Operand.node(
            catalogs,
            operand_bytes,
            0,
        )).kind != .bool or
            result_schema != Operand.schema(catalogs, operand_bytes, 1) or
            result_schema != Operand.schema(catalogs, operand_bytes, 2))
            return error.InvalidInstruction,
        .product_construct => {
            if (result_node.kind != .product or
                readInt(u32, result_node.payload, 0) != operand_count)
            {
                return error.InvalidInstruction;
            }
            for (0..operand_count) |index| {
                if (readInt(u32, result_node.payload, 4 + index * 4) !=
                    Operand.schema(catalogs, operand_bytes, index))
                {
                    return error.InvalidInstruction;
                }
            }
        },
        .product_extract, .product_replace => {
            const product_schema = Operand.schema(catalogs, operand_bytes, 0);
            const product = catalogs.schemas.node(product_schema) catch
                return error.InvalidInstruction;
            if (product.kind != .product or
                immediate >= readInt(u32, product.payload, 0))
            {
                return error.InvalidInstruction;
            }
            const field_schema = readInt(
                u32,
                product.payload,
                4 + @as(usize, immediate) * 4,
            );
            if (operation == .product_extract) {
                if (result_schema != field_schema) return error.InvalidInstruction;
            } else if (result_schema != product_schema or
                Operand.schema(catalogs, operand_bytes, 1) != field_schema)
            {
                return error.InvalidInstruction;
            }
        },
        .sum_construct => {
            if (result_node.kind != .sum or
                immediate >= readInt(u32, result_node.payload, 4))
            {
                return error.InvalidInstruction;
            }
            const payload_schema = readInt(
                u32,
                result_node.payload,
                12 + @as(usize, immediate) * 8,
            );
            const payload_node = catalogs.schemas.node(payload_schema) catch
                return error.InvalidInstruction;
            const expected: u16 = if (payload_node.kind == .unit) 0 else 1;
            if (operand_count != expected or (expected == 1 and
                Operand.schema(catalogs, operand_bytes, 0) != payload_schema))
            {
                return error.InvalidInstruction;
            }
        },
        .sum_tag_is, .sum_extract => {
            const sum = try Operand.node(catalogs, operand_bytes, 0);
            if (sum.kind != .sum or immediate >= readInt(u32, sum.payload, 4)) {
                return error.InvalidInstruction;
            }
            if (operation == .sum_tag_is) {
                if (!bool_schema) return error.InvalidInstruction;
            } else if (result_schema != readInt(
                u32,
                sum.payload,
                12 + @as(usize, immediate) * 8,
            ) or result_node.kind == .unit) return error.InvalidInstruction;
        },
        .optional_none => if (result_node.kind != .optional)
            return error.InvalidInstruction,
        .optional_some => if (result_node.kind != .optional or
            readInt(u32, result_node.payload, 0) != Operand.schema(
                catalogs,
                operand_bytes,
                0,
            )) return error.InvalidInstruction,
        .optional_is_some => if (!bool_schema or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .optional)
            return error.InvalidInstruction,
        .vector_empty => if (result_node.kind != .vector)
            return error.InvalidInstruction,
        .vector_length => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .vector)
            return error.InvalidInstruction,
        .vector_get, .vector_set, .vector_push, .vector_truncate, .vector_clear => {
            const vector_schema = Operand.schema(catalogs, operand_bytes, 0);
            const vector = catalogs.schemas.node(vector_schema) catch
                return error.InvalidInstruction;
            if (vector.kind != .vector) return error.InvalidInstruction;
            const element_schema = readInt(u32, vector.payload, 4);
            switch (operation) {
                .vector_get => if (result_schema != element_schema or
                    (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
                    return error.InvalidInstruction,
                .vector_set => if (result_schema != vector_schema or
                    (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32 or
                    Operand.schema(catalogs, operand_bytes, 2) != element_schema)
                    return error.InvalidInstruction,
                .vector_push => if (result_schema != vector_schema or
                    Operand.schema(catalogs, operand_bytes, 1) != element_schema)
                    return error.InvalidInstruction,
                .vector_truncate => if (result_schema != vector_schema or
                    (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
                    return error.InvalidInstruction,
                .vector_clear => if (result_schema != vector_schema)
                    return error.InvalidInstruction,
                else => unreachable,
            }
        },
        .vector_pop => {
            const vector_schema = Operand.schema(catalogs, operand_bytes, 0);
            const vector = catalogs.schemas.node(vector_schema) catch
                return error.InvalidInstruction;
            if (vector.kind != .vector or result_node.kind != .product or
                readInt(u32, result_node.payload, 0) != 2 or
                readInt(u32, result_node.payload, 4) != vector_schema)
            {
                return error.InvalidInstruction;
            }
            const optional_schema = readInt(u32, result_node.payload, 8);
            const optional = catalogs.schemas.node(optional_schema) catch
                return error.InvalidInstruction;
            if (optional.kind != .optional or
                readInt(u32, optional.payload, 0) !=
                    readInt(u32, vector.payload, 4))
            {
                return error.InvalidInstruction;
            }
        },
        .text_empty => if (result_node.kind != .text)
            return error.InvalidInstruction,
        .text_append => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .text)
            return error.InvalidInstruction,
        .text_append_scalar => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
            return error.InvalidInstruction,
        .text_append_unsigned, .text_append_signed => {
            const integer = (try Operand.node(catalogs, operand_bytes, 1)).kind;
            if (result_schema != Operand.schema(catalogs, operand_bytes, 0) or
                (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
                !isIntegerKind(integer) or
                (operation == .text_append_unsigned and
                    isSignedIntegerKind(integer)) or
                (operation == .text_append_signed and
                    !isSignedIntegerKind(integer)))
            {
                return error.InvalidInstruction;
            }
        },
        .text_copy => if (result_node.kind != .text or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32 or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .u32)
            return error.InvalidInstruction,
        .text_compare => if (result_node.kind != .i8 or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .text)
            return error.InvalidInstruction,
        .text_join => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .text)
            return error.InvalidInstruction,
        .bytes_empty => if (result_node.kind != .bytes)
            return error.InvalidInstruction,
        .bytes_append => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bytes)
            return error.InvalidInstruction,
        .bytes_append_scalar => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u8)
            return error.InvalidInstruction,
        .bytes_copy => if (result_node.kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32 or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .u32)
            return error.InvalidInstruction,
        .bytes_compare => if (result_node.kind != .i8 or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bytes)
            return error.InvalidInstruction,
        .bytes_join => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .bytes)
            return error.InvalidInstruction,
        .text_length => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text)
            return error.InvalidInstruction,
        .bytes_length => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes)
            return error.InvalidInstruction,
        .enum_to_u32 => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .@"enum")
            return error.InvalidInstruction,
    }
}

fn constantSchema(catalogs: Catalogs, target: u32) Error!u32 {
    const bytes = catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..catalogs.constant_count) |constant| {
        const schema = readInt(u32, bytes, cursor);
        const length = readInt(u32, bytes, cursor + 4);
        cursor += 8;
        if (constant == target) return schema;
        cursor += length;
    }
    return error.InvalidInstruction;
}

fn isIntegerKind(kind: dynamic_value_v1.Kind) bool {
    return @intFromEnum(kind) >= @intFromEnum(dynamic_value_v1.Kind.i8) and
        @intFromEnum(kind) <= @intFromEnum(dynamic_value_v1.Kind.u64);
}

fn isSignedIntegerKind(kind: dynamic_value_v1.Kind) bool {
    return kind == .i8 or kind == .i16 or kind == .i32 or kind == .i64;
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
        0 => try validateEdge(catalogs, bytes, &cursor, end, null),
        1 => {
            if (end - cursor < 4 or
                readInt(u16, bytes, cursor) >= catalogs.value_count or
                readInt(u16, bytes, cursor + 2) != 0)
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
            try validateEdge(catalogs, bytes, &cursor, end, null);
            try validateEdge(catalogs, bytes, &cursor, end, null);
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
    if (kind == 0 and request_count != 1) return error.InvalidTerminator;
    const request_values_start = cursor.*;
    for (0..request_count) |_| {
        if (end - cursor.* < 2 or
            readInt(u16, bytes, cursor.*) >= catalogs.value_count)
        {
            return error.InvalidTerminator;
        }
        cursor.* += 2;
    }
    const declared_resume_schema = readInt(u32, bytes, end - 4);
    if (kind == 0) {
        const schemas = try effectSchemas(catalogs, site);
        const request_value = readInt(u16, bytes, request_values_start);
        if (valueSchema(catalogs, request_value) != schemas.payload or
            declared_resume_schema != schemas.resume_schema)
        {
            return error.InvalidTerminator;
        }
    }
    if (end - cursor.* < 4) return error.InvalidTerminator;
    const callee_present = bytes[cursor.*];
    if (callee_present > 1 or !allZero(bytes[cursor.* + 1 .. cursor.* + 4]) or
        (callee_present == 1) != (kind == 1))
    {
        return error.InvalidTerminator;
    }
    cursor.* += 4;
    if (callee_present == 1) {
        try validateEdge(catalogs, bytes, cursor, end, null);
    }
    try validateEdge(
        catalogs,
        bytes,
        cursor,
        end,
        if (declared_resume_schema == std.math.maxInt(u32))
            null
        else
            declared_resume_schema,
    );
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
    resume_schema: ?u32,
) Error!void {
    if (end - cursor.* < 4) return error.InvalidTerminator;
    const target = readInt(u16, bytes, cursor.*);
    const count = readInt(u16, bytes, cursor.* + 2);
    if (target >= readInt(u32, catalogs.envelope.section(.segments), 0)) {
        return error.InvalidTerminator;
    }
    const target_segment = imageSegmentRecord(catalogs, target) catch
        return error.InvalidTerminator;
    if (count != readInt(u16, target_segment, 10)) {
        return error.InvalidTerminator;
    }
    cursor.* += 4;
    for (0..count) |index| {
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
        const target_value = readInt(
            u16,
            target_segment,
            24 + index * 2,
        );
        if (bytes[cursor.*] == 0) {
            if (valueSchema(catalogs, value) !=
                valueSchema(catalogs, target_value))
            {
                return error.InvalidTerminator;
            }
        } else if (resume_schema == null or
            resume_schema.? != valueSchema(catalogs, target_value))
        {
            return error.InvalidTerminator;
        }
        cursor.* += 4;
    }
}

fn effectSchemas(
    catalogs: Catalogs,
    target: u32,
) Error!struct { payload: u32, resume_schema: u32 } {
    const bytes = catalogs.envelope.section(.effects);
    var cursor: usize = 4;
    for (0..catalogs.effect_count) |ordinal| {
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4 + identity_length;
        const payload = readInt(u32, bytes, cursor);
        const resume_schema = readInt(u32, bytes, cursor + 4);
        if (ordinal == target) return .{
            .payload = payload,
            .resume_schema = resume_schema,
        };
        cursor += 8 + 4 + 64;
    }
    return error.InvalidTerminator;
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
        if (bytes[cursor + 8] != try expectedConstructorKind(
            catalogs,
            @intCast(constructor_id),
            bytes[cursor + 9],
            readInt(u16, bytes, cursor + 12),
        )) {
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

fn expectedConstructorKind(
    catalogs: Catalogs,
    constructor_id: u32,
    origin: u8,
    source_segment: u16,
) Error!u8 {
    if (constructor_id == catalogs.initial_constructor_id) return 0;
    if (origin == 0 or origin == 1) {
        const segment = try imageSegmentRecord(catalogs, source_segment);
        return switch (segment[8]) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 5,
            4 => 7,
            else => error.InvalidConstructor,
        };
    }
    if (origin != 2) return error.InvalidConstructor;
    var suspension_source = source_segment;
    const transitions = catalogs.envelope.section(.entry_transitions);
    for (0..readInt(u32, transitions, 0)) |index| {
        const offset = 4 + index * 12;
        if (transitions[offset + 2] == 4 and
            readInt(u32, transitions, offset + 8) == constructor_id)
        {
            suspension_source = readInt(u16, transitions, offset);
            break;
        }
    }
    const segment = try imageSegmentRecord(catalogs, suspension_source);
    const terminator = imageSegmentTerminator(segment);
    if (segment[terminator + 4] != 2) return error.InvalidConstructor;
    return switch (segment[terminator + 8]) {
        0 => 3,
        1 => 4,
        2, 3 => 6,
        else => error.InvalidConstructor,
    };
}

fn imageSegmentRecord(catalogs: Catalogs, target: u16) Error![]const u8 {
    const bytes = catalogs.envelope.section(.segments);
    var cursor: usize = 4;
    for (0..readInt(u32, bytes, 0)) |id| {
        const end = try recordEnd(bytes, cursor, 24);
        if (id == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidConstructor;
}

fn imageSegmentTerminator(segment: []const u8) usize {
    var cursor: usize = 24 + @as(usize, readInt(u16, segment, 10)) * 2;
    for (0..readInt(u32, segment, 12)) |_| {
        cursor += readInt(u32, segment, cursor);
    }
    return cursor;
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
    if (count > 1024) return error.InvalidTransition;
    const records_length = std.math.mul(usize, count, 12) catch
        return error.InvalidTransition;
    const expected_length = std.math.add(usize, 4, records_length) catch
        return error.InvalidTransition;
    if (bytes.len != expected_length) {
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

const SemanticHasher = std.crypto.hash.sha2.Sha256;

fn computeProgramSemanticDigest(
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) Error![32]u8 {
    var hasher = SemanticHasher.init(.{});
    semanticHashBytes(&hasher, "boundary-rnf-compiler-semantics-v4");
    semanticHashBytes(
        &hasher,
        reducer_semantics_v1.segment_fuel_semantic_domain,
    );
    semanticHashU64(
        &hasher,
        reducer_semantics_v1.dynamic_fuel_quantum_bytes,
    );
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.initial_args_schema_id,
        schema_tasks,
    );
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.result_schema_id,
        schema_tasks,
    );
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.failure_schema_id,
        schema_tasks,
    );
    try hashFailures(&hasher, catalogs.envelope.section(.failures));
    semanticHashU32(&hasher, catalogs.effect_count);
    try hashEffectContracts(&hasher, catalogs.envelope.section(.effects));
    semanticHashU32(&hasher, catalogs.value_count);
    for (0..catalogs.value_count) |value| {
        try semanticHashSchema(
            &hasher,
            catalogs,
            valueSchema(catalogs, @intCast(value)),
            schema_tasks,
        );
    }
    semanticHashU16(&hasher, catalogs.entry_segment_id);
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.result_schema_id,
        schema_tasks,
    );
    semanticHashU32(&hasher, catalogs.function_count);
    for (0..catalogs.function_count) |function| {
        const offset = 4 + function * 8;
        semanticHashU16(
            &hasher,
            readInt(u16, catalogs.functions_section, offset),
        );
        semanticHashU16(
            &hasher,
            readInt(u16, catalogs.functions_section, offset + 2),
        );
        try semanticHashSchema(
            &hasher,
            catalogs,
            readInt(u32, catalogs.functions_section, offset + 4),
            schema_tasks,
        );
    }
    try hashSegments(&hasher, catalogs, schema_tasks);
    semanticHashBytes(&hasher, "await-effect-cost");
    semanticHashU64(&hasher, reducer_semantics_v1.await_effect_cost);
    try hashConstructors(&hasher, catalogs, schema_tasks);
    hashTransitions(&hasher, catalogs.envelope.section(.entry_transitions));
    semanticHashU32(&hasher, 0);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn semanticHashSchema(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_id: u32,
    tasks: []dynamic_value_v1.SchemaHashTask,
) Error!void {
    const digest = dynamic_value_v1.schemaDigest(
        catalogs.schemas,
        schema_id,
        tasks,
    ) catch return error.InvalidSchema;
    hasher.update(&digest);
}

fn hashFailures(hasher: *SemanticHasher, bytes: []const u8) Error!void {
    semanticHashBytes(hasher, "failure-name-tag-map-v1");
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    var cursor: usize = 4;
    for (0..count) |_| {
        const tag = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const name = try takeCatalogSlice(bytes, &cursor, length);
        semanticHashBytes(hasher, name);
        semanticHashU32(hasher, tag);
    }
}

fn hashEffectContracts(hasher: *SemanticHasher, bytes: []const u8) Error!void {
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |_| {
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4 + length + 8 + 4 + 32;
        hasher.update(bytes[cursor..][0..32]);
        cursor += 32;
    }
}

fn hashSegments(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) Error!void {
    const bytes = catalogs.envelope.section(.segments);
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    var cursor: usize = 4;
    for (0..count) |_| {
        const segment_start = cursor;
        const end = try recordEnd(bytes, cursor, 24);
        semanticHashU16(hasher, readInt(u16, bytes, cursor + 4));
        semanticHashU16(hasher, readInt(u16, bytes, cursor + 6));
        const parameter_count = readInt(u16, bytes, cursor + 10);
        const instruction_count = readInt(u32, bytes, cursor + 12);
        semanticHashU32(hasher, parameter_count);
        cursor += 24;
        for (0..parameter_count) |_| {
            semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 2;
        }
        semanticHashU32(hasher, instruction_count);
        for (0..instruction_count) |_| {
            cursor = try hashInstruction(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                cursor,
            );
        }
        cursor = try hashTerminator(
            hasher,
            catalogs,
            schema_tasks,
            bytes,
            cursor,
        );
        semanticHashU64(hasher, readInt(u64, bytes, segment_start + 16));
        if (cursor != end) return error.InvalidSegment;
    }
}

fn hashInstruction(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    start: usize,
) Error!usize {
    const end = try recordEnd(bytes, start, 16);
    semanticHashU8(hasher, bytes[start + 4]);
    semanticHashU16(hasher, readInt(u16, bytes, start + 8));
    const operand_count = readInt(u16, bytes, start + 10);
    semanticHashU32(hasher, operand_count);
    var cursor = start + 16;
    for (0..operand_count) |_| {
        semanticHashU16(hasher, readInt(u16, bytes, cursor));
        cursor += 2;
    }
    const wire: reducer_semantics_v1.WireOperation = @enumFromInt(
        readInt(u16, bytes, start + 6),
    );
    semanticHashU8(
        hasher,
        reducer_semantics_v1.currentSemanticTagForWire(wire),
    );
    const immediate = readInt(u32, bytes, start + 12);
    switch (wire) {
        .constant => try hashConstant(
            hasher,
            catalogs,
            schema_tasks,
            immediate,
        ),
        .product_extract,
        .product_replace,
        .sum_construct,
        .sum_tag_is,
        .sum_extract,
        => semanticHashU16(hasher, @intCast(immediate)),
        else => {},
    }
    return end;
}

fn hashConstant(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    target: u32,
) Error!void {
    const bytes = catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..catalogs.constant_count) |index| {
        const schema_id = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const value = try takeCatalogSlice(bytes, &cursor, length);
        if (index != target) continue;
        try semanticHashSchema(hasher, catalogs, schema_id, schema_tasks);
        semanticHashBytes(hasher, value);
        return;
    }
    return error.InvalidConstant;
}

fn hashTerminator(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    start: usize,
) Error!usize {
    const end = try recordEnd(bytes, start, 8);
    const kind = bytes[start + 4];
    semanticHashU8(hasher, kind);
    var cursor = start + 8;
    switch (kind) {
        0 => try hashEdge(hasher, bytes, &cursor),
        1 => {
            semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 4;
            try hashEdge(hasher, bytes, &cursor);
            try hashEdge(hasher, bytes, &cursor);
        },
        2 => try hashSuspension(
            hasher,
            catalogs,
            schema_tasks,
            bytes,
            &cursor,
        ),
        3 => {
            const present = bytes[cursor] == 1;
            semanticHashBool(hasher, present);
            if (present) {
                semanticHashU16(hasher, readInt(u16, bytes, cursor + 2));
            }
            cursor += 4;
        },
        4, 6 => {
            semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 4;
        },
        5 => {
            semanticHashU16(
                hasher,
                @intCast(readInt(u32, bytes, cursor)),
            );
            cursor += 4;
        },
        else => return error.InvalidTerminator,
    }
    if (cursor != end) return error.InvalidTerminator;
    return end;
}

fn hashSuspension(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    cursor: *usize,
) Error!void {
    const kind = bytes[cursor.*];
    const site = readInt(u32, bytes, cursor.* + 4);
    const callee_function = readInt(u16, bytes, cursor.* + 8);
    const request_count = readInt(u16, bytes, cursor.* + 10);
    const requests_start = cursor.* + 12;
    var edge_cursor = requests_start + @as(usize, request_count) * 2;
    const callee_present = bytes[edge_cursor] == 1;
    edge_cursor += 4;

    semanticHashU8(hasher, kind);
    semanticHashBool(hasher, site != std.math.maxInt(u32));
    if (site != std.math.maxInt(u32)) semanticHashU32(hasher, site);
    semanticHashBool(hasher, callee_function != std.math.maxInt(u16));
    if (callee_function != std.math.maxInt(u16)) {
        semanticHashU16(hasher, callee_function);
    }
    semanticHashBool(hasher, callee_present);
    if (callee_present) try hashEdge(hasher, bytes, &edge_cursor);
    semanticHashU32(hasher, request_count);
    var request_cursor = requests_start;
    for (0..request_count) |_| {
        semanticHashU16(hasher, readInt(u16, bytes, request_cursor));
        request_cursor += 2;
    }
    try hashEdge(hasher, bytes, &edge_cursor);
    const resume_schema = readInt(u32, bytes, edge_cursor);
    semanticHashBool(hasher, resume_schema != std.math.maxInt(u32));
    if (resume_schema != std.math.maxInt(u32)) {
        try semanticHashSchema(
            hasher,
            catalogs,
            resume_schema,
            schema_tasks,
        );
    }
    cursor.* = edge_cursor + 4;
}

fn hashEdge(
    hasher: *SemanticHasher,
    bytes: []const u8,
    cursor: *usize,
) Error!void {
    semanticHashU16(hasher, readInt(u16, bytes, cursor.*));
    const count = readInt(u16, bytes, cursor.* + 2);
    semanticHashU32(hasher, count);
    cursor.* += 4;
    for (0..count) |_| {
        const kind = bytes[cursor.*];
        semanticHashU8(hasher, kind);
        if (kind == 0) {
            semanticHashU16(hasher, readInt(u16, bytes, cursor.* + 2));
        } else if (kind != 1) {
            return error.InvalidTerminator;
        }
        cursor.* += 4;
    }
}

fn hashConstructors(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) Error!void {
    const bytes = catalogs.envelope.section(.constructors);
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    var cursor: usize = 4;
    for (0..count) |_| {
        const end = try recordEnd(bytes, cursor, 24);
        semanticHashU32(hasher, readInt(u32, bytes, cursor + 4));
        semanticHashU8(hasher, bytes[cursor + 9]);
        semanticHashU16(hasher, readInt(u16, bytes, cursor + 12));
        const resume_target = readInt(u16, bytes, cursor + 14);
        semanticHashBool(hasher, resume_target != std.math.maxInt(u16));
        if (resume_target != std.math.maxInt(u16)) {
            semanticHashU16(hasher, resume_target);
        }
        semanticHashBool(
            hasher,
            readInt(u16, bytes, cursor + 10) & 1 == 1,
        );
        const activation_count = readInt(u16, bytes, cursor + 16);
        const environment_count = readInt(u16, bytes, cursor + 18);
        const invariant_count = readInt(u16, bytes, cursor + 20);
        semanticHashU32(hasher, activation_count);
        cursor += 24;
        for (0..activation_count) |_| {
            try hashEnvironmentField(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                &cursor,
            );
        }
        semanticHashU32(hasher, environment_count);
        for (0..environment_count) |_| {
            try hashEnvironmentField(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                &cursor,
            );
        }
        semanticHashU32(hasher, invariant_count);
        for (0..invariant_count) |_| {
            cursor = try hashInvariant(hasher, bytes, cursor);
        }
        if (cursor != end) return error.InvalidConstructor;
    }
}

fn hashEnvironmentField(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    cursor: *usize,
) Error!void {
    semanticHashU16(hasher, readInt(u16, bytes, cursor.*));
    try semanticHashSchema(
        hasher,
        catalogs,
        readInt(u32, bytes, cursor.* + 4),
        schema_tasks,
    );
    cursor.* += 8;
}

fn hashInvariant(
    hasher: *SemanticHasher,
    bytes: []const u8,
    start: usize,
) Error!usize {
    const end = try recordEnd(bytes, start, 8);
    const tag = bytes[start + 4];
    const payload = start + 8;
    semanticHashU8(hasher, tag);
    switch (tag) {
        0 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashBool(hasher, bytes[payload + 2] == 1);
        },
        1, 2, 5, 11, 16 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
        },
        3 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
            semanticHashU8(hasher, bytes[payload + 6]);
        },
        4, 7 => {
            for (0..4) |index| {
                semanticHashU16(
                    hasher,
                    readInt(u16, bytes, payload + index * 2),
                );
            }
        },
        6 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            const value_kind = bytes[payload + 4];
            semanticHashU8(hasher, value_kind);
            const value = readInt(u64, bytes, payload + 12);
            switch (value_kind) {
                0 => semanticHashBool(hasher, value == 1),
                1, 2 => semanticHashU64(hasher, value),
                3 => semanticHashU16(hasher, @truncate(value)),
                else => return error.InvalidInvariant,
            }
        },
        8 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            const operand_count = readInt(u16, bytes, payload + 4);
            semanticHashU16(hasher, operand_count);
            for (0..operand_count) |index| {
                semanticHashU16(
                    hasher,
                    readInt(u16, bytes, payload + 8 + index * 2),
                );
            }
        },
        9, 10 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
        },
        12 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU8(hasher, bytes[payload + 4]);
            semanticHashU8(hasher, bytes[payload + 5]);
        },
        13 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
            semanticHashU8(hasher, bytes[payload + 6]);
            semanticHashU8(hasher, bytes[payload + 7]);
        },
        14 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU8(hasher, bytes[payload + 4]);
        },
        15 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashBool(hasher, bytes[payload + 2] == 1);
        },
        17 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU8(hasher, bytes[payload + 4]);
            semanticHashBool(hasher, bytes[payload + 5] == 1);
        },
        18 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
            semanticHashU8(hasher, bytes[payload + 6]);
        },
        19 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashBool(hasher, bytes[payload + 4] == 1);
        },
        20 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
        },
        else => return error.InvalidInvariant,
    }
    return end;
}

fn hashTransitions(hasher: *SemanticHasher, bytes: []const u8) void {
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    for (0..count) |index| {
        const offset = 4 + index * 12;
        semanticHashU16(hasher, readInt(u16, bytes, offset));
        semanticHashU8(hasher, bytes[offset + 2]);
        semanticHashU16(hasher, readInt(u16, bytes, offset + 4));
        semanticHashU32(hasher, readInt(u32, bytes, offset + 8));
    }
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

fn semanticHashU8(hasher: anytype, value: u8) void {
    hasher.update(&.{value});
}

fn semanticHashU16(hasher: anytype, value: u16) void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    hasher.update(&bytes);
}

fn semanticHashBool(hasher: anytype, value: bool) void {
    semanticHashU8(hasher, @intFromBool(value));
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
