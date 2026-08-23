const std = @import("std");

pub const magic = "ABL_MV2P1".*;
pub const format_version: u16 = 1;
pub const machine_abi_version: u16 = 2;
pub const state_format_version: u16 = 1;
pub const header_length: usize = 176;

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

    pub fn segmentCost(self: Validated, segment_id: u16) Error!u64 {
        if (segment_id >= self.segment_count) return error.InvalidProfile;
        return std.mem.readInt(
            u64,
            self.bytes[header_length + @as(usize, segment_id) * 8 ..][0..8],
            .little,
        );
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
        !allZero(bytes[164..168]) or !allZero(bytes[172..176]))
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
    const expected_length = std.math.add(
        usize,
        header_length,
        std.math.mul(usize, segment_count, 8) catch return error.InvalidProfile,
    ) catch return error.InvalidProfile;
    if (bytes.len != expected_length or segment_count == 0 or
        std.mem.readInt(u32, bytes[128..132], .little) == 0 or
        std.mem.readInt(u32, bytes[132..136], .little) == 0 or
        std.mem.readInt(u64, bytes[144..152], .little) != 16 or
        std.mem.readInt(u64, bytes[152..160], .little) != 1 or
        std.mem.readInt(u32, bytes[160..164], .little) != 1)
    {
        return error.InvalidProfile;
    }
    for (0..segment_count) |segment| {
        if (std.mem.readInt(
            u64,
            bytes[header_length + segment * 8 ..][0..8],
            .little,
        ) == 0) return error.InvalidProfile;
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
    };
}

fn machineV2ContractDigest(
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
) type {
    const byte_length = header_length + segment_costs.len * @sizeOf(u64);
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
        var cursor: usize = header_length;
        for (segment_costs) |cost| {
            std.mem.writeInt(u64, bytes[cursor..][0..8], cost, .little);
            cursor += 8;
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
