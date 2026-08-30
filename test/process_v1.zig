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
    const state = try process_state_v1.encode(digest, &frames, &storage);
    try std.testing.expectEqual(@as(u64, 3), state.frame_count);
    try std.testing.expectEqualSlices(
        u8,
        &process_state_v1.magic,
        state.bytes[0..process_state_v1.magic.len],
    );
    var iterator = state.iterator();
    for (frames) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqual(expected.constructor_id, actual.constructor_id);
        try std.testing.expectEqualSlices(u8, expected.environment, actual.environment);
    }
    try std.testing.expect((try iterator.next()) == null);
    try std.testing.expectEqual(
        process_state_v1.artifactDigest(state.bytes),
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
    const encoded = (try process_state_v1.encode(digest, &frame, &storage)).bytes;
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

test "Process codecs reject output overlap with source bytes" {
    const digest = [_]u8{0x33} ** 32;
    var state_storage: [128]u8 = undefined;
    @memset(state_storage[0..4], 0x44);
    const frames = [_]process_state_v1.Frame{.{
        .constructor_id = 1,
        .environment = state_storage[0..4],
    }};
    try std.testing.expectError(
        error.InvalidEncoding,
        process_state_v1.encode(digest, &frames, &state_storage),
    );

    var request_storage: [512]u8 = undefined;
    @memset(request_storage[400..404], 0x55);
    const alias_payload_schema = [_]u8{4} ** 32;
    const alias_resume_schema = [_]u8{5} ** 32;
    try std.testing.expectError(
        error.InvalidRequest,
        process_effect_v1.encodeRequest(.{
            .program_transition_digest = [_]u8{1} ** 32,
            .pre_request_state_digest = [_]u8{2} ** 32,
            .effect_site_semantic_digest = process_effect_v1.effectSemanticDigest(
                "fixture.effect.v1",
                alias_payload_schema,
                alias_resume_schema,
            ),
            .payload_schema_digest = alias_payload_schema,
            .resume_schema_digest = alias_resume_schema,
            .continuation_digest = [_]u8{6} ** 32,
            .effect_semantic_identity = "fixture.effect.v1",
            .payload = request_storage[400..404],
        }, &request_storage),
    );

    var result_storage: [128]u8 = undefined;
    @memset(result_storage[120..124], 0x66);
    try std.testing.expectError(
        error.InvalidResult,
        process_effect_v1.encodeResult(.{
            .request_identity_digest = [_]u8{7} ** 32,
            .resume_schema_digest = [_]u8{8} ** 32,
            .@"resume" = result_storage[120..124],
        }, &result_storage),
    );
}

test "Process State mutation codecs reject every source alias before writing" {
    const digest = [_]u8{0x71} ** 32;
    const frames = [_]process_state_v1.Frame{
        .{ .constructor_id = 1, .environment = &.{1} },
        .{ .constructor_id = 2, .environment = &.{ 2, 3 } },
    };
    var state_storage: [192]u8 = undefined;
    const state = try process_state_v1.encode(
        digest,
        &frames,
        &state_storage,
    );
    var before: [192]u8 = undefined;
    @memcpy(before[0..state.bytes.len], state.bytes);
    const replacement: process_state_v1.Frame = .{
        .constructor_id = 3,
        .environment = &.{ 4, 5, 6 },
    };
    try std.testing.expectError(
        error.InvalidEncoding,
        process_state_v1.replaceTop(
            state,
            replacement,
            state_storage[1..],
        ),
    );
    try std.testing.expectError(
        error.InvalidEncoding,
        process_state_v1.replaceTopAndAppend(
            state,
            replacement,
            replacement,
            state_storage[1..],
        ),
    );
    try std.testing.expectError(
        error.InvalidEncoding,
        process_state_v1.replaceParentAndDropTop(
            state,
            replacement,
            state_storage[1..],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        before[0..state.bytes.len],
        state.bytes,
    );

    var output: [192]u8 = undefined;
    @memset(output[160..164], 0x99);
    try std.testing.expectError(
        error.InvalidEncoding,
        process_state_v1.replaceTop(
            state,
            .{ .constructor_id = 3, .environment = output[160..164] },
            &output,
        ),
    );
}

test "Process State mutation carrier owns its changed suffix cut" {
    const digest = [_]u8{0x72} ** 32;
    const frames = [_]process_state_v1.Frame{
        .{ .constructor_id = 1, .environment = &.{1} },
        .{ .constructor_id = 2, .environment = &.{2} },
    };
    var state_storage: [192]u8 = undefined;
    const state = try process_state_v1.encode(
        digest,
        &frames,
        &state_storage,
    );
    var successor_storage: [192]u8 = undefined;
    var required: u64 = 0;
    const mutation = try process_state_v1.replaceTopAndAppendTracked(
        state,
        .{ .constructor_id = 3, .environment = &.{3} },
        .{ .constructor_id = 4, .environment = &.{4} },
        &successor_storage,
        &required,
    );
    try std.testing.expectEqual(
        state.frame_count - 1,
        mutation.first_changed_frame,
    );
    try std.testing.expectEqual(
        state.frame_count + 1,
        mutation.state.frame_count,
    );
    try std.testing.expectEqual(
        @as(u64, mutation.state.bytes.len),
        required,
    );
}

test "ABL_ERQ1 and ABL_ERS1 bind the current request and resume schema" {
    const payload_schema = [_]u8{4} ** 32;
    const resume_schema = [_]u8{5} ** 32;
    const input: process_effect_v1.RequestInput = .{
        .program_transition_digest = [_]u8{1} ** 32,
        .pre_request_state_digest = [_]u8{2} ** 32,
        .effect_site_semantic_digest = process_effect_v1.effectSemanticDigest(
            "fixture.effect.v1",
            payload_schema,
            resume_schema,
        ),
        .payload_schema_digest = payload_schema,
        .resume_schema_digest = resume_schema,
        .continuation_digest = [_]u8{6} ** 32,
        .effect_semantic_identity = "fixture.effect.v1",
        .payload = &.{ 7, 8, 9 },
    };
    var contradictory_input = input;
    contradictory_input.effect_site_semantic_digest[0] ^= 1;
    var contradictory_storage: [512]u8 = undefined;
    try std.testing.expectError(
        error.DigestMismatch,
        process_effect_v1.encodeRequest(
            contradictory_input,
            &contradictory_storage,
        ),
    );
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
