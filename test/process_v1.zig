const process_effect_v1 = @import("process_effect_v1");
const process_state_v1 = @import("process_state_v1");
const std = @import("std");

test "ABL_PST1 round trips an unbounded-count frame sequence canonically" {
    const digest = [_]u8{0x41} ** 32;
    const frames = [_]process_state_v1.Frame{
        .{ .constructor_id = 0, .environment = &.{} },
        .{ .constructor_id = 127, .environment = &.{ 1, 2, 3 } },
        .{ .constructor_id = 128, .environment = &.{ 4, 5 } },
    };
    var storage: [256]u8 = undefined;
    const encoded = try process_state_v1.encode(digest, &frames, &storage);
    const state = try process_state_v1.validate(encoded, digest);
    try std.testing.expectEqual(@as(u64, 3), state.frame_count);
    try std.testing.expectEqualSlices(
        u8,
        &process_state_v1.magic,
        encoded[0..process_state_v1.magic.len],
    );
    var iterator = state.iterator();
    for (frames) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqual(expected.constructor_id, actual.constructor_id);
        try std.testing.expectEqualSlices(u8, expected.environment, actual.environment);
    }
    try std.testing.expect((try iterator.next()) == null);
    try std.testing.expectEqual(
        process_state_v1.artifactDigest(encoded),
        process_state_v1.artifactDigest(state.bytes),
    );
}

test "ABL_PST1 rejects non-minimal naturals and wrong program binding" {
    const digest = [_]u8{0x22} ** 32;
    const frame = [_]process_state_v1.Frame{.{
        .constructor_id = 1,
        .environment = &.{},
    }};
    var storage: [96]u8 = undefined;
    const encoded = try process_state_v1.encode(digest, &frame, &storage);
    var overlong: [96]u8 = undefined;
    @memcpy(overlong[0..process_state_v1.fixed_header_length], encoded[0..process_state_v1.fixed_header_length]);
    overlong[process_state_v1.fixed_header_length] = 0x81;
    overlong[process_state_v1.fixed_header_length + 1] = 0;
    @memcpy(
        overlong[process_state_v1.fixed_header_length + 2 ..][0 .. encoded.len - process_state_v1.fixed_header_length - 1],
        encoded[process_state_v1.fixed_header_length + 1 ..],
    );
    try std.testing.expectError(
        error.NonCanonicalNatural,
        process_state_v1.validate(overlong[0 .. encoded.len + 1], digest),
    );
    var wrong = digest;
    wrong[0] ^= 1;
    try std.testing.expectError(
        error.InvalidState,
        process_state_v1.validate(encoded, wrong),
    );
}

test "ABL_ERQ1 and ABL_ERS1 bind the current request and resume schema" {
    const input: process_effect_v1.RequestInput = .{
        .program_transition_digest = [_]u8{1} ** 32,
        .pre_request_state_digest = [_]u8{2} ** 32,
        .effect_site_semantic_digest = [_]u8{3} ** 32,
        .payload_schema_digest = [_]u8{4} ** 32,
        .resume_schema_digest = [_]u8{5} ** 32,
        .continuation_digest = [_]u8{6} ** 32,
        .effect_semantic_identity = "fixture.effect.v1",
        .payload = &.{ 7, 8, 9 },
    };
    var request_storage: [512]u8 = undefined;
    const request_bytes = try process_effect_v1.encodeRequest(
        input,
        &request_storage,
    );
    const request = try process_effect_v1.validateRequest(
        request_bytes,
        input.program_transition_digest,
    );
    try std.testing.expectEqualStrings(
        input.effect_semantic_identity,
        request.effect_semantic_identity,
    );
    try std.testing.expectEqualSlices(u8, input.payload, request.payload);
    try std.testing.expectEqual(
        process_effect_v1.requestIdentity(input),
        request.request_identity_digest,
    );

    var forged_identity: [512]u8 = undefined;
    @memcpy(forged_identity[0..request_bytes.len], request_bytes);
    const semantic_offset = @intFromPtr(request.effect_semantic_identity.ptr) -
        @intFromPtr(request_bytes.ptr);
    forged_identity[semantic_offset] ^= 1;
    try std.testing.expectError(
        error.DigestMismatch,
        process_effect_v1.validateRequest(
            forged_identity[0..request_bytes.len],
            input.program_transition_digest,
        ),
    );

    var forged_payload_schema: [512]u8 = undefined;
    @memcpy(forged_payload_schema[0..request_bytes.len], request_bytes);
    const payload_schema_offset = process_effect_v1.request_magic.len +
        4 + 4 * 32;
    forged_payload_schema[payload_schema_offset] ^= 1;
    try std.testing.expectError(
        error.DigestMismatch,
        process_effect_v1.validateRequest(
            forged_payload_schema[0..request_bytes.len],
            input.program_transition_digest,
        ),
    );

    const result_input: process_effect_v1.ResultInput = .{
        .request_identity_digest = request.request_identity_digest,
        .resume_schema_digest = request.resume_schema_digest,
        .@"resume" = &.{ 10, 11 },
    };
    var result_storage: [128]u8 = undefined;
    const result_bytes = try process_effect_v1.encodeResult(
        result_input,
        &result_storage,
    );
    const result = try process_effect_v1.validateResult(result_bytes);
    try std.testing.expectEqual(
        request.request_identity_digest,
        result.request_identity_digest,
    );
    try std.testing.expectEqual(
        request.resume_schema_digest,
        result.resume_schema_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        result_input.@"resume",
        result.@"resume",
    );

    request_storage[request_bytes.len - 1] ^= 1;
    try std.testing.expectError(
        error.DigestMismatch,
        process_effect_v1.validateRequest(
            request_storage[0..request_bytes.len],
            input.program_transition_digest,
        ),
    );
}
