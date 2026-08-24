const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const machine_v2_metering_v1 = @import("machine_v2_metering_v1");
const std = @import("std");

pub const magic = "ABL_MV2P1".*;
pub const format_version: u16 = 1;
pub const machine_abi_version: u16 = 2;
pub const state_format_version: u16 = 1;
pub const header_length: usize = 192;

pub const Error = error{
    InvalidProfile,
    ProgramTransitionMismatch,
    MachineV2ContractMismatch,
};

pub const Validated = struct {
    bytes: []const u8,
    program_transition_digest: [32]u8,
    machine_v2_semantic_digest: [32]u8,
    machine_v2_contract_digest: [32]u8,
    maximum_frames: u32,
    maximum_state_bytes: u32,
    maximum_machine_fuel: u64,
    segment_count: u32,
    constructor_count: u32,
    transition_count: u32,
    initial_constructor_id: u32,
    bpi_constructor_count: u32,

    pub fn segmentCost(self: Validated, segment_id: u16) Error!u64 {
        if (segment_id >= self.segment_count) return error.InvalidProfile;
        return std.mem.readInt(
            u64,
            self.bytes[header_length + @as(usize, segment_id) * 8 ..][0..8],
            .little,
        );
    }

    pub fn segmentTerminatorOverride(self: Validated, segment_id: u16) Error!u8 {
        if (segment_id >= self.segment_count) return error.InvalidProfile;
        return self.bytes[header_length + self.segment_count * 8 + segment_id];
    }

    pub fn constructorOrigin(self: Validated, constructor_id: u32) Error!u8 {
        if (constructor_id >= self.constructor_count) return error.InvalidProfile;
        return self.bytes[header_length + self.segment_count * 9 + constructor_id];
    }

    pub fn mappedConstructor(self: Validated, constructor_id: u32) Error!u32 {
        if (constructor_id >= self.constructor_count) return error.InvalidProfile;
        const offset = header_length + self.segment_count * 9 +
            self.constructor_count + constructor_id * 4;
        return std.mem.readInt(u32, self.bytes[offset..][0..4], .little);
    }

    pub fn transitionKind(self: Validated, transition_id: u32) Error!u8 {
        if (transition_id >= self.transition_count) return error.InvalidProfile;
        return self.bytes[
            header_length + self.segment_count * 9 +
                self.constructor_count * 5 + transition_id
        ];
    }

    pub fn transitionConstructor(
        self: Validated,
        transition_id: u32,
    ) Error!u32 {
        if (transition_id >= self.transition_count) return error.InvalidProfile;
        const offset = header_length + self.segment_count * 9 +
            self.constructor_count * 5 + self.transition_count +
            transition_id * 4;
        return std.mem.readInt(u32, self.bytes[offset..][0..4], .little);
    }
};

pub fn validate(
    bytes: []const u8,
    expected_program_transition_digest: [32]u8,
) Error!Validated {
    if (bytes.len < header_length or !std.mem.eql(u8, bytes[0..9], &magic) or
        std.mem.readInt(u16, bytes[9..11], .little) != format_version or
        std.mem.readInt(u16, bytes[11..13], .little) != machine_abi_version or
        std.mem.readInt(u16, bytes[13..15], .little) != state_format_version or
        bytes[15] != 0 or
        std.mem.readInt(u32, bytes[16..20], .little) != header_length or
        !allZero(bytes[20..24]) or
        std.mem.readInt(u64, bytes[24..32], .little) != bytes.len or
        !allZero(bytes[164..168]) or !allZero(bytes[188..192]))
    {
        return error.InvalidProfile;
    }
    const program_transition_digest = bytes[32..64].*;
    if (!std.mem.eql(
        u8,
        &program_transition_digest,
        &expected_program_transition_digest,
    )) return error.ProgramTransitionMismatch;
    const segment_count = std.mem.readInt(u32, bytes[168..172], .little);
    const constructor_count = std.mem.readInt(u32, bytes[172..176], .little);
    const transition_count = std.mem.readInt(u32, bytes[176..180], .little);
    const initial_constructor_id = std.mem.readInt(u32, bytes[180..184], .little);
    const bpi_constructor_count = std.mem.readInt(u32, bytes[184..188], .little);
    var expected_length = std.math.add(
        usize,
        header_length,
        std.math.mul(usize, segment_count, 9) catch return error.InvalidProfile,
    ) catch return error.InvalidProfile;
    expected_length = std.math.add(
        usize,
        expected_length,
        std.math.mul(usize, constructor_count, 5) catch
            return error.InvalidProfile,
    ) catch return error.InvalidProfile;
    expected_length = std.math.add(
        usize,
        expected_length,
        std.math.mul(usize, transition_count, 5) catch
            return error.InvalidProfile,
    ) catch return error.InvalidProfile;
    if (bytes.len != expected_length or segment_count == 0 or
        segment_count > 128 or constructor_count > 256 or
        transition_count > 1024 or bpi_constructor_count > 256 or
        std.mem.readInt(u32, bytes[128..132], .little) == 0 or
        std.mem.readInt(u32, bytes[132..136], .little) < 76 or
        std.mem.readInt(u64, bytes[144..152], .little) != 16 or
        std.mem.readInt(u64, bytes[152..160], .little) != 1 or
        std.mem.readInt(u32, bytes[160..164], .little) != 1 or
        constructor_count == 0 or bpi_constructor_count == 0 or
        initial_constructor_id >= constructor_count)
    {
        return error.InvalidProfile;
    }
    for (0..segment_count) |segment| {
        if (std.mem.readInt(
            u64,
            bytes[header_length + segment * 8 ..][0..8],
            .little,
        ) == 0) return error.InvalidProfile;
        if (bytes[header_length + segment_count * 8 + segment] > 1) {
            return error.InvalidProfile;
        }
    }
    for (0..constructor_count) |constructor| {
        if (bytes[header_length + segment_count * 9 + constructor] > 2) {
            return error.InvalidProfile;
        }
        const mapping_offset = header_length + segment_count * 9 +
            constructor_count + constructor * 4;
        if (std.mem.readInt(u32, bytes[mapping_offset..][0..4], .little) >=
            bpi_constructor_count)
        {
            return error.InvalidProfile;
        }
    }
    for (0..transition_count) |transition| {
        if (bytes[
            header_length + segment_count * 9 + constructor_count * 5 +
                transition
        ] > 4) {
            return error.InvalidProfile;
        }
        const constructor_offset = header_length + segment_count * 9 +
            constructor_count * 5 + transition_count + transition * 4;
        if (std.mem.readInt(u32, bytes[constructor_offset..][0..4], .little) >=
            constructor_count)
        {
            return error.InvalidProfile;
        }
    }
    const machine_v2_semantic_digest = bytes[64..96].*;
    const maximum_frames = std.mem.readInt(u32, bytes[128..132], .little);
    const maximum_state_bytes = std.mem.readInt(u32, bytes[132..136], .little);
    const maximum_machine_fuel = std.mem.readInt(u64, bytes[136..144], .little);
    const expected_contract = machineV2ContractDigest(
        machine_v2_semantic_digest,
        maximum_frames,
        maximum_state_bytes,
        maximum_machine_fuel,
    );
    if (!std.mem.eql(u8, &expected_contract, bytes[96..128])) {
        return error.MachineV2ContractMismatch;
    }
    return .{
        .bytes = bytes,
        .program_transition_digest = program_transition_digest,
        .machine_v2_semantic_digest = machine_v2_semantic_digest,
        .machine_v2_contract_digest = bytes[96..128].*,
        .maximum_frames = maximum_frames,
        .maximum_state_bytes = maximum_state_bytes,
        .maximum_machine_fuel = maximum_machine_fuel,
        .segment_count = segment_count,
        .constructor_count = constructor_count,
        .transition_count = transition_count,
        .initial_constructor_id = initial_constructor_id,
        .bpi_constructor_count = bpi_constructor_count,
    };
}

pub fn validateProjection(
    image: image_v1.ValidatedImage,
    profile: Validated,
) (Error || image_v1.Error)!void {
    const catalogs = image.catalogs;
    const transitions = catalogs.envelope.section(.entry_transitions);
    const bpi_transition_count = readInt(u32, transitions, 0);
    if (profile.segment_count != image.segment_count or
        profile.bpi_constructor_count != image.constructor_count or
        profile.transition_count != bpi_transition_count)
    {
        return error.InvalidProfile;
    }

    var synthetic_constructor = [_]bool{false} ** 256;
    for (0..bpi_transition_count) |transition| {
        const offset = 4 + transition * 12;
        const source = readInt(u16, transitions, offset);
        const bpi_kind = transitions[offset + 2];
        const bpi_constructor = readInt(u32, transitions, offset + 8);
        const v2_constructor = try profile.transitionConstructor(
            @intCast(transition),
        );
        if (try profile.mappedConstructor(v2_constructor) != bpi_constructor) {
            return error.InvalidProfile;
        }
        const override = try profile.segmentTerminatorOverride(source);
        const expected_kind: u8 = if (override == 1) blk: {
            if (bpi_kind != 0) return error.InvalidProfile;
            synthetic_constructor[v2_constructor] = true;
            break :blk 4;
        } else bpi_kind;
        if (try profile.transitionKind(@intCast(transition)) != expected_kind) {
            return error.InvalidProfile;
        }
    }

    const constructors = catalogs.envelope.section(.constructors);
    var ordinary_count = [_]u8{0} ** 256;
    var mapping_count = [_]u8{0} ** 256;
    for (0..profile.constructor_count) |constructor| {
        const mapped = try profile.mappedConstructor(@intCast(constructor));
        const record = try bpiConstructorRecord(constructors, mapped);
        mapping_count[mapped] = std.math.add(
            u8,
            mapping_count[mapped],
            1,
        ) catch return error.InvalidProfile;
        const origin = try profile.constructorOrigin(@intCast(constructor));
        if (origin == record[9]) {
            ordinary_count[mapped] = std.math.add(
                u8,
                ordinary_count[mapped],
                1,
            ) catch return error.InvalidProfile;
            if (ordinary_count[mapped] != 1) return error.InvalidProfile;
        } else if (origin != 2 or record[9] != 0 or
            !synthetic_constructor[constructor])
        {
            return error.InvalidProfile;
        }
    }
    for (mapping_count[0..image.constructor_count]) |count| {
        if (count == 0) return error.InvalidProfile;
    }

    if (profile.initial_constructor_id != catalogs.initial_constructor_id) {
        return error.InvalidProfile;
    }
    const mapped_initial = try profile.mappedConstructor(
        profile.initial_constructor_id,
    );
    if (mapped_initial != catalogs.initial_constructor_id) {
        return error.InvalidProfile;
    }
}

/// Reconstruct the frozen current-v4 Machine semantic digest from BPI1 plus
/// the profile-owned metering and synthetic-checkpoint annotations.
pub fn semanticDigestForImage(
    image: image_v1.ValidatedImage,
    profile: Validated,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) (Error || image_v1.Error)![32]u8 {
    const catalogs = image.catalogs;
    if (profile.segment_count != image.segment_count or
        profile.bpi_constructor_count != image.constructor_count or
        profile.transition_count != transitionCount(catalogs))
    {
        return error.InvalidProfile;
    }
    const mapped_initial = profile.mappedConstructor(
        profile.initial_constructor_id,
    ) catch return error.InvalidProfile;
    if (mapped_initial != catalogs.initial_constructor_id) {
        return error.InvalidProfile;
    }
    var hasher = image_v1.SemanticHasher.init(.{});
    image_v1.semanticHashBytes(&hasher, "boundary-rnf-compiler-semantics-v4");
    image_v1.semanticHashBytes(
        &hasher,
        machine_v2_metering_v1.segment_fuel_semantic_domain,
    );
    image_v1.semanticHashU64(
        &hasher,
        machine_v2_metering_v1.dynamic_fuel_quantum_bytes,
    );
    try hashCommonPrefix(&hasher, catalogs, schema_tasks);
    try hashSegments(&hasher, catalogs, profile, schema_tasks);
    image_v1.semanticHashBytes(&hasher, "await-effect-cost");
    image_v1.semanticHashU64(
        &hasher,
        machine_v2_metering_v1.await_effect_cost,
    );
    try hashConstructors(&hasher, catalogs, profile, schema_tasks);
    try hashTransitions(&hasher, catalogs, profile);
    image_v1.semanticHashU32(&hasher, 0);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn hashCommonPrefix(
    hasher: *image_v1.SemanticHasher,
    catalogs: image_v1.Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) image_v1.Error!void {
    try image_v1.semanticHashSchema(
        hasher,
        catalogs,
        catalogs.initial_args_schema_id,
        schema_tasks,
    );
    try image_v1.semanticHashSchema(
        hasher,
        catalogs,
        catalogs.result_schema_id,
        schema_tasks,
    );
    try image_v1.semanticHashSchema(
        hasher,
        catalogs,
        catalogs.failure_schema_id,
        schema_tasks,
    );
    try image_v1.hashFailures(hasher, catalogs.envelope.section(.failures));
    image_v1.semanticHashU32(hasher, catalogs.effect_count);
    try image_v1.hashEffectContracts(
        hasher,
        catalogs.envelope.section(.effects),
    );
    image_v1.semanticHashU32(hasher, catalogs.value_count);
    for (0..catalogs.value_count) |value| {
        try image_v1.semanticHashSchema(
            hasher,
            catalogs,
            try catalogs.valueSchemaId(@intCast(value)),
            schema_tasks,
        );
    }
    image_v1.semanticHashU16(hasher, catalogs.entry_segment_id);
    try image_v1.semanticHashSchema(
        hasher,
        catalogs,
        catalogs.result_schema_id,
        schema_tasks,
    );
    image_v1.semanticHashU32(hasher, catalogs.function_count);
    for (0..catalogs.function_count) |function| {
        const offset = 4 + function * 8;
        image_v1.semanticHashU16(
            hasher,
            readInt(u16, catalogs.functions_section, offset),
        );
        image_v1.semanticHashU16(
            hasher,
            readInt(u16, catalogs.functions_section, offset + 2),
        );
        try image_v1.semanticHashSchema(
            hasher,
            catalogs,
            readInt(u32, catalogs.functions_section, offset + 4),
            schema_tasks,
        );
    }
}

fn hashSegments(
    hasher: *image_v1.SemanticHasher,
    catalogs: image_v1.Catalogs,
    profile: Validated,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) (Error || image_v1.Error)!void {
    const bytes = catalogs.envelope.section(.segments);
    image_v1.semanticHashU32(hasher, profile.segment_count);
    var cursor: usize = 4;
    for (0..profile.segment_count) |segment| {
        const end = try recordEnd(
            bytes,
            cursor,
            image_v1.segment_prefix_length,
        );
        image_v1.semanticHashU16(hasher, readInt(u16, bytes, cursor + 4));
        image_v1.semanticHashU16(hasher, readInt(u16, bytes, cursor + 6));
        const parameter_count = readInt(u16, bytes, cursor + 10);
        const instruction_count = readInt(u32, bytes, cursor + 12);
        image_v1.semanticHashU32(hasher, parameter_count);
        cursor += image_v1.segment_prefix_length;
        for (0..parameter_count) |_| {
            image_v1.semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 2;
        }
        image_v1.semanticHashU32(hasher, instruction_count);
        for (0..instruction_count) |_| {
            cursor = try image_v1.hashInstruction(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                cursor,
            );
        }
        if (try profile.segmentTerminatorOverride(@intCast(segment)) == 0) {
            cursor = try image_v1.hashTerminator(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                cursor,
            );
        } else {
            cursor = try hashCallerCheckpoint(hasher, bytes, cursor);
        }
        image_v1.semanticHashU64(
            hasher,
            try profile.segmentCost(@intCast(segment)),
        );
        if (cursor != end) return error.InvalidProfile;
    }
}

fn hashCallerCheckpoint(
    hasher: *image_v1.SemanticHasher,
    bytes: []const u8,
    start: usize,
) (Error || image_v1.Error)!usize {
    const end = try recordEnd(bytes, start, 8);
    if (bytes[start + 4] != 0) return error.InvalidProfile;
    image_v1.semanticHashU8(hasher, 2);
    image_v1.semanticHashU8(hasher, 3);
    image_v1.semanticHashBool(hasher, false);
    image_v1.semanticHashBool(hasher, false);
    image_v1.semanticHashBool(hasher, false);
    image_v1.semanticHashU32(hasher, 0);
    var cursor = start + 8;
    try image_v1.hashEdge(hasher, bytes, &cursor);
    image_v1.semanticHashBool(hasher, false);
    if (cursor != end) return error.InvalidProfile;
    return end;
}

fn hashConstructors(
    hasher: *image_v1.SemanticHasher,
    catalogs: image_v1.Catalogs,
    profile: Validated,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) (Error || image_v1.Error)!void {
    const bytes = catalogs.envelope.section(.constructors);
    image_v1.semanticHashU32(hasher, profile.constructor_count);
    for (0..profile.constructor_count) |constructor| {
        const mapped = try profile.mappedConstructor(@intCast(constructor));
        const record = try bpiConstructorRecord(bytes, mapped);
        var cursor: usize = 0;
        const end = record.len;
        image_v1.semanticHashU32(hasher, @intCast(constructor));
        image_v1.semanticHashU8(
            hasher,
            try profile.constructorOrigin(@intCast(constructor)),
        );
        image_v1.semanticHashU16(hasher, readInt(u16, record, cursor + 12));
        const resume_target = readInt(u16, record, cursor + 14);
        image_v1.semanticHashBool(
            hasher,
            resume_target != std.math.maxInt(u16),
        );
        if (resume_target != std.math.maxInt(u16)) {
            image_v1.semanticHashU16(hasher, resume_target);
        }
        image_v1.semanticHashBool(
            hasher,
            readInt(u16, record, cursor + 10) & 1 == 1,
        );
        const activation_count = readInt(u16, record, cursor + 16);
        const environment_count = readInt(u16, record, cursor + 18);
        const invariant_count = readInt(u16, record, cursor + 20);
        image_v1.semanticHashU32(hasher, activation_count);
        cursor += 24;
        for (0..activation_count) |_| {
            try image_v1.hashEnvironmentField(
                hasher,
                catalogs,
                schema_tasks,
                record,
                &cursor,
            );
        }
        image_v1.semanticHashU32(hasher, environment_count);
        for (0..environment_count) |_| {
            try image_v1.hashEnvironmentField(
                hasher,
                catalogs,
                schema_tasks,
                record,
                &cursor,
            );
        }
        image_v1.semanticHashU32(hasher, invariant_count);
        for (0..invariant_count) |_| {
            cursor = try image_v1.hashInvariant(hasher, record, cursor);
        }
        if (cursor != end) return error.InvalidProfile;
    }
}

fn bpiConstructorRecord(
    bytes: []const u8,
    target: u32,
) image_v1.Error![]const u8 {
    var cursor: usize = 4;
    for (0..readInt(u32, bytes, 0)) |constructor| {
        const end = try recordEnd(bytes, cursor, 24);
        if (constructor == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidConstructor;
}

fn hashTransitions(
    hasher: *image_v1.SemanticHasher,
    catalogs: image_v1.Catalogs,
    profile: Validated,
) Error!void {
    const bytes = catalogs.envelope.section(.entry_transitions);
    image_v1.semanticHashU32(hasher, profile.transition_count);
    for (0..profile.transition_count) |transition| {
        const offset = 4 + transition * 12;
        image_v1.semanticHashU16(hasher, readInt(u16, bytes, offset));
        image_v1.semanticHashU8(
            hasher,
            try profile.transitionKind(@intCast(transition)),
        );
        image_v1.semanticHashU16(hasher, readInt(u16, bytes, offset + 4));
        image_v1.semanticHashU32(
            hasher,
            try profile.transitionConstructor(@intCast(transition)),
        );
    }
}

fn transitionCount(catalogs: image_v1.Catalogs) u32 {
    return readInt(
        u32,
        catalogs.envelope.section(.entry_transitions),
        0,
    );
}

fn recordEnd(
    bytes: []const u8,
    start: usize,
    minimum: usize,
) image_v1.Error!usize {
    if (bytes.len - start < 4) return error.LengthMismatch;
    const length = readInt(u32, bytes, start);
    if (length < minimum) return error.LengthMismatch;
    const end = std.math.add(usize, start, length) catch
        return error.LengthOverflow;
    if (end > bytes.len) return error.LengthMismatch;
    return end;
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

pub fn machineV2ContractDigest(
    semantic_digest: [32]u8,
    maximum_frames: u32,
    maximum_state_bytes: u32,
    maximum_machine_fuel: u64,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&semantic_digest);
    hasher.update("\x00boundary-machine-abi=2");
    hasher.update("\x00state=rnf-v1");
    var buffer: [32]u8 = undefined;
    hasher.update("\x00frames=");
    hasher.update(std.fmt.bufPrint(&buffer, "{d}", .{maximum_frames}) catch
        unreachable);
    hasher.update("\x00state-bytes=");
    hasher.update(std.fmt.bufPrint(&buffer, "{d}", .{maximum_state_bytes}) catch
        unreachable);
    hasher.update("\x00fuel=");
    hasher.update(std.fmt.bufPrint(&buffer, "{d}", .{maximum_machine_fuel}) catch
        unreachable);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}

/// Compiler-owned compatibility projection for the bounded Machine ABI v2.
///
/// This is deliberately distinct from the canonical Reified Program: it owns
/// the checkpointed RNF, metering annotations, and the legacy semantic digest
/// needed to preserve existing Machine v2 State and Request identities.
pub fn Lowering(
    comptime Reified: type,
    comptime control_value: anytype,
    comptime reachability_value: anytype,
    comptime semantic_canonicalization_value: anytype,
    comptime residual_effects_value: anytype,
    comptime invariant_constants_value: anytype,
    comptime normal_form_value: anytype,
    comptime initial_constructor_id_value: u32,
    comptime effective_block_costs_value: anytype,
    comptime generated_operation_count_value: usize,
    comptime machine_v2_semantic_digest_value: [32]u8,
) type {
    return struct {
        pub const reified_program = Reified;
        pub const program_label = Reified.program_label;
        pub const Body = Reified.Body;
        pub const compiler_limits = Reified.compiler_limits;
        pub const control = control_value;
        pub const reachability = reachability_value;
        pub const semantic_canonicalization =
            semantic_canonicalization_value;
        pub const residual_effects = residual_effects_value;
        pub const invariant_constants = invariant_constants_value;
        pub const rnf_value = normal_form_value;
        pub const initial_constructor_id = initial_constructor_id_value;
        pub const effective_block_costs = effective_block_costs_value;
        pub const generated_reducer_operation_count =
            generated_operation_count_value;
        pub const machine_v2_semantic_digest =
            machine_v2_semantic_digest_value;

        // Machine ABI v2's existing Definition contract consumes this exact
        // byte sequence. The compatibility alias is intentionally private to
        // the v2 lowering rather than exposed as Program meaning.
        pub const semantic_digest = machine_v2_semantic_digest;
        pub const contract_bytes = semantic_digest[0..];

        pub fn portableType(comptime value_type: anytype) type {
            return Reified.portableType(value_type);
        }
    };
}

pub fn requireLowering(comptime V2: type) void {
    inline for (.{
        "reified_program",
        "control",
        "reachability",
        "semantic_canonicalization",
        "residual_effects",
        "invariant_constants",
        "rnf_value",
        "initial_constructor_id",
        "effective_block_costs",
        "generated_reducer_operation_count",
        "machine_v2_semantic_digest",
        "contract_bytes",
        "portableType",
    }) |name| {
        if (!@hasDecl(V2, name)) {
            @compileError("Boundary Machine v2 lowering is missing " ++ name);
        }
    }
}

/// Canonical Machine ABI v2 profile bytes for one Program and option set.
/// Program clauses and schemas remain solely in BPI1.
pub fn Profile(
    comptime program_transition_digest_value: [32]u8,
    comptime machine_v2_semantic_digest_value: [32]u8,
    comptime machine_v2_contract_digest_value: [32]u8,
    comptime options: anytype,
    comptime segment_costs: []const u64,
    comptime segment_terminator_overrides: []const u8,
    comptime constructor_origins: []const u8,
    comptime constructor_mappings: []const u32,
    comptime transition_kinds: []const u8,
    comptime transition_constructors: []const u32,
    comptime initial_constructor_id: u32,
    comptime bpi_constructor_count: u32,
) type {
    if (segment_terminator_overrides.len != segment_costs.len or
        constructor_mappings.len != constructor_origins.len or
        transition_constructors.len != transition_kinds.len)
    {
        @compileError("Machine v2 profile projection lengths differ");
    }
    const byte_length = header_length + segment_costs.len * 9 +
        constructor_origins.len * 5 + transition_kinds.len * 5;
    const encoded = comptime blk: {
        var bytes: [byte_length]u8 = [_]u8{0} ** byte_length;
        @memcpy(bytes[0..9], &magic);
        std.mem.writeInt(u16, bytes[9..11], format_version, .little);
        std.mem.writeInt(u16, bytes[11..13], machine_abi_version, .little);
        std.mem.writeInt(u16, bytes[13..15], state_format_version, .little);
        std.mem.writeInt(u32, bytes[16..20], @intCast(header_length), .little);
        std.mem.writeInt(u64, bytes[24..32], @intCast(byte_length), .little);
        @memcpy(bytes[32..64], &program_transition_digest_value);
        @memcpy(bytes[64..96], &machine_v2_semantic_digest_value);
        @memcpy(bytes[96..128], &machine_v2_contract_digest_value);
        std.mem.writeInt(u32, bytes[128..132], @intCast(options.maximum_frames), .little);
        std.mem.writeInt(u32, bytes[132..136], @intCast(options.maximum_state_bytes), .little);
        std.mem.writeInt(u64, bytes[136..144], options.maximum_machine_fuel, .little);
        std.mem.writeInt(u64, bytes[144..152], 16, .little);
        std.mem.writeInt(u64, bytes[152..160], 1, .little);
        // v1 means preflight resource-shape metering plus caller-fuel
        // checkpoint behavior as implemented by Machine ABI v2.
        std.mem.writeInt(u32, bytes[160..164], 1, .little);
        std.mem.writeInt(u32, bytes[168..172], @intCast(segment_costs.len), .little);
        std.mem.writeInt(u32, bytes[172..176], @intCast(constructor_origins.len), .little);
        std.mem.writeInt(u32, bytes[176..180], @intCast(transition_kinds.len), .little);
        std.mem.writeInt(u32, bytes[180..184], initial_constructor_id, .little);
        std.mem.writeInt(u32, bytes[184..188], bpi_constructor_count, .little);
        var cursor: usize = header_length;
        for (segment_costs) |cost| {
            std.mem.writeInt(u64, bytes[cursor..][0..8], cost, .little);
            cursor += 8;
        }
        @memcpy(
            bytes[cursor..][0..segment_terminator_overrides.len],
            segment_terminator_overrides,
        );
        cursor += segment_terminator_overrides.len;
        @memcpy(
            bytes[cursor..][0..constructor_origins.len],
            constructor_origins,
        );
        cursor += constructor_origins.len;
        for (constructor_mappings) |mapping| {
            std.mem.writeInt(u32, bytes[cursor..][0..4], mapping, .little);
            cursor += 4;
        }
        @memcpy(
            bytes[cursor..][0..transition_kinds.len],
            transition_kinds,
        );
        cursor += transition_kinds.len;
        for (transition_constructors) |constructor| {
            std.mem.writeInt(u32, bytes[cursor..][0..4], constructor, .little);
            cursor += 4;
        }
        break :blk bytes;
    };
    const sha256 = comptime blk: {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&encoded, &digest, .{});
        break :blk digest;
    };
    return struct {
        pub const bytes = encoded;
        pub const artifact_sha256 = sha256;
        pub const program_transition_digest =
            program_transition_digest_value;
        pub const machine_v2_semantic_digest =
            machine_v2_semantic_digest_value;
        pub const machine_v2_contract_digest =
            machine_v2_contract_digest_value;
        pub const machine_options = options;
    };
}
