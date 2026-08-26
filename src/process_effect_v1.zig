const process_state_v1 = @import("process_state_v1");
const std = @import("std");

pub const request_magic = "ABL_ERQ1".*;
pub const result_magic = "ABL_ERS1".*;
pub const format_version: u16 = 1;
const digest_length: usize = 32;
const request_fixed_length: usize = request_magic.len + 2 + 2 + 7 * digest_length;
const result_fixed_length: usize = result_magic.len + 2 + 2 + 2 * digest_length;

pub const Error = process_state_v1.Error || error{
    DigestMismatch,
    InvalidRequest,
    InvalidResult,
    InvalidUtf8,
};

pub const RequestInput = struct {
    program_transition_digest: [32]u8,
    pre_request_state_digest: [32]u8,
    effect_site_semantic_digest: [32]u8,
    payload_schema_digest: [32]u8,
    resume_schema_digest: [32]u8,
    continuation_digest: [32]u8,
    effect_semantic_identity: []const u8,
    payload: []const u8,
};

pub const RequestView = struct {
    bytes: []const u8,
    request_identity_digest: [32]u8,
    program_transition_digest: [32]u8,
    pre_request_state_digest: [32]u8,
    effect_site_semantic_digest: [32]u8,
    payload_schema_digest: [32]u8,
    resume_schema_digest: [32]u8,
    continuation_digest: [32]u8,
    effect_semantic_identity: []const u8,
    payload: []const u8,
};

pub const ResultInput = struct {
    request_identity_digest: [32]u8,
    resume_schema_digest: [32]u8,
    @"resume": []const u8,
};

pub const ResultView = struct {
    bytes: []const u8,
    request_identity_digest: [32]u8,
    resume_schema_digest: [32]u8,
    @"resume": []const u8,
};

pub fn requestIdentity(input: RequestInput) [32]u8 {
    var payload_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.payload, &payload_digest, .{});
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("boundary-process-request-identity-v1\x00");
    hasher.update(&input.program_transition_digest);
    hasher.update(&input.pre_request_state_digest);
    hasher.update(&input.effect_site_semantic_digest);
    var identity_length: [8]u8 = undefined;
    std.mem.writeInt(
        u64,
        &identity_length,
        @intCast(input.effect_semantic_identity.len),
        .little,
    );
    hasher.update(&identity_length);
    hasher.update(input.effect_semantic_identity);
    hasher.update(&input.payload_schema_digest);
    hasher.update(&payload_digest);
    hasher.update(&input.continuation_digest);
    hasher.update(&input.resume_schema_digest);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub fn requestEncodedLength(input: RequestInput) Error!usize {
    if (input.effect_semantic_identity.len == 0 or
        !std.unicode.utf8ValidateSlice(input.effect_semantic_identity))
    {
        return error.InvalidUtf8;
    }
    var length = try addLength(
        request_fixed_length,
        process_state_v1.naturalEncodedLength(input.effect_semantic_identity.len),
    );
    length = try addLength(length, input.effect_semantic_identity.len);
    length = try addLength(
        length,
        process_state_v1.naturalEncodedLength(input.payload.len),
    );
    return addLength(length, input.payload.len);
}

pub fn encodeRequest(input: RequestInput, output: []u8) Error![]const u8 {
    const required = try requestEncodedLength(input);
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    append(output, &cursor, &request_magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    const identity = requestIdentity(input);
    inline for (.{
        identity,
        input.program_transition_digest,
        input.pre_request_state_digest,
        input.effect_site_semantic_digest,
        input.payload_schema_digest,
        input.resume_schema_digest,
        input.continuation_digest,
    }) |digest| append(output, &cursor, &digest);
    cursor += try process_state_v1.writeNatural(
        input.effect_semantic_identity.len,
        output[cursor..],
    );
    append(output, &cursor, input.effect_semantic_identity);
    cursor += try process_state_v1.writeNatural(input.payload.len, output[cursor..]);
    append(output, &cursor, input.payload);
    if (cursor != required) return error.InvalidRequest;
    const encoded = output[0..required];
    _ = try validateRequest(encoded, input.program_transition_digest);
    return encoded;
}

pub fn validateRequest(
    bytes: []const u8,
    expected_program_transition_digest: ?[32]u8,
) Error!RequestView {
    if (bytes.len < request_fixed_length + 2 or
        !std.mem.eql(u8, bytes[0..request_magic.len], &request_magic))
    {
        return error.InvalidRequest;
    }
    if (readInt(u16, bytes, request_magic.len) != format_version) {
        return error.UnsupportedVersion;
    }
    if (readInt(u16, bytes, request_magic.len + 2) != 0) {
        return error.UnknownFlags;
    }
    var cursor = request_magic.len + 4;
    const identity = takeDigest(bytes, &cursor);
    const program = takeDigest(bytes, &cursor);
    const state = takeDigest(bytes, &cursor);
    const site = takeDigest(bytes, &cursor);
    const payload_schema = takeDigest(bytes, &cursor);
    const resume_schema = takeDigest(bytes, &cursor);
    const continuation = takeDigest(bytes, &cursor);
    if (expected_program_transition_digest) |expected| {
        if (!std.mem.eql(u8, &program, &expected)) return error.DigestMismatch;
    }
    const identity_length = try process_state_v1.readNatural(bytes[cursor..]);
    cursor = try addLength(cursor, identity_length.length);
    const semantic_length = std.math.cast(usize, identity_length.value) orelse
        return error.InvalidRequest;
    const semantic_end = try addLength(cursor, semantic_length);
    if (semantic_length == 0 or semantic_end > bytes.len) {
        return error.InvalidRequest;
    }
    const semantic_identity = bytes[cursor..semantic_end];
    if (!std.unicode.utf8ValidateSlice(semantic_identity)) {
        return error.InvalidUtf8;
    }
    cursor = semantic_end;
    const payload_length = try process_state_v1.readNatural(bytes[cursor..]);
    cursor = try addLength(cursor, payload_length.length);
    const value_length = std.math.cast(usize, payload_length.value) orelse
        return error.InvalidRequest;
    const payload_end = try addLength(cursor, value_length);
    if (payload_end != bytes.len) return error.InvalidRequest;
    const payload = bytes[cursor..payload_end];
    const expected_identity = requestIdentity(.{
        .program_transition_digest = program,
        .pre_request_state_digest = state,
        .effect_site_semantic_digest = site,
        .payload_schema_digest = payload_schema,
        .resume_schema_digest = resume_schema,
        .continuation_digest = continuation,
        .effect_semantic_identity = semantic_identity,
        .payload = payload,
    });
    if (!std.mem.eql(u8, &identity, &expected_identity)) {
        return error.DigestMismatch;
    }
    return .{
        .bytes = bytes,
        .request_identity_digest = identity,
        .program_transition_digest = program,
        .pre_request_state_digest = state,
        .effect_site_semantic_digest = site,
        .payload_schema_digest = payload_schema,
        .resume_schema_digest = resume_schema,
        .continuation_digest = continuation,
        .effect_semantic_identity = semantic_identity,
        .payload = payload,
    };
}

pub fn resultEncodedLength(input: ResultInput) Error!usize {
    var length = try addLength(
        result_fixed_length,
        process_state_v1.naturalEncodedLength(input.@"resume".len),
    );
    length = try addLength(length, input.@"resume".len);
    return length;
}

pub fn encodeResult(input: ResultInput, output: []u8) Error![]const u8 {
    const required = try resultEncodedLength(input);
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    append(output, &cursor, &result_magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    append(output, &cursor, &input.request_identity_digest);
    append(output, &cursor, &input.resume_schema_digest);
    cursor += try process_state_v1.writeNatural(input.@"resume".len, output[cursor..]);
    append(output, &cursor, input.@"resume");
    if (cursor != required) return error.InvalidResult;
    const encoded = output[0..required];
    _ = try validateResult(encoded);
    return encoded;
}

pub fn validateResult(bytes: []const u8) Error!ResultView {
    if (bytes.len < result_fixed_length + 1 or
        !std.mem.eql(u8, bytes[0..result_magic.len], &result_magic))
    {
        return error.InvalidResult;
    }
    if (readInt(u16, bytes, result_magic.len) != format_version) {
        return error.UnsupportedVersion;
    }
    if (readInt(u16, bytes, result_magic.len + 2) != 0) {
        return error.UnknownFlags;
    }
    var cursor = result_magic.len + 4;
    const request_identity = takeDigest(bytes, &cursor);
    const resume_schema = takeDigest(bytes, &cursor);
    const resume_length = try process_state_v1.readNatural(bytes[cursor..]);
    cursor = try addLength(cursor, resume_length.length);
    const value_length = std.math.cast(usize, resume_length.value) orelse
        return error.InvalidResult;
    const end = try addLength(cursor, value_length);
    if (end != bytes.len) return error.InvalidResult;
    return .{
        .bytes = bytes,
        .request_identity_digest = request_identity,
        .resume_schema_digest = resume_schema,
        .@"resume" = bytes[cursor..end],
    };
}

fn takeDigest(bytes: []const u8, cursor: *usize) [32]u8 {
    const digest = bytes[cursor.*..][0..32].*;
    cursor.* += 32;
    return digest;
}

fn addLength(left: usize, right: usize) Error!usize {
    return std.math.add(usize, left, right) catch error.LengthOverflow;
}

fn append(output: []u8, cursor: *usize, bytes: []const u8) void {
    @memcpy(output[cursor.*..][0..bytes.len], bytes);
    cursor.* += bytes.len;
}

fn appendInt(
    comptime T: type,
    output: []u8,
    cursor: *usize,
    value: T,
) void {
    std.mem.writeInt(T, output[cursor.*..][0..@sizeOf(T)], value, .little);
    cursor.* += @sizeOf(T);
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
