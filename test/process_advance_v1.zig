const boundary = @import("boundary");
const process_advance_v1 = @import("process_advance_v1");
const process_state_v1 = @import("process_state_v1");
const recursion_fixture = @import("recursion_fixture");
const std = @import("std");

const Lookup = boundary.effect.site(
    0,
    "process.fixture.lookup.v1",
    u32,
    u32,
);

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const forward_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 1 }};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .jump = .{
            .target = 2,
            .arguments = &forward_arguments,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-one-effect",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Program = boundary.program("process-one-effect", Body);
const Image = Program.image();

const call_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 0 }};
const return_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const call_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{ .target = 1, .arguments = &call_arguments },
            .continuation = .{ .target = 2, .arguments = &return_arguments },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_to_caller = 1 },
    },
    .{
        .id = 2,
        .role = .terminal_handoff,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const CallBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-call-return",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &call_blocks,
        .entry = 0,
        .result_type = u32_type,
        .functions = &.{
            .{ .id = 0, .entry = 0, .result_type = u32_type },
            .{ .id = 1, .entry = 1, .result_type = u32_type },
        },
    };
};

const CallImage = boundary.program("process-call-return", CallBody).image();

const forever_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 0 }};
const forever_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .role = .loop_header,
    .parameters = &.{0},
    .terminator = .{ .@"suspend" = .{
        .kind = .explicit_yield,
        .continuation = .{ .target = 0, .arguments = &forever_arguments },
    } },
}};
const ForeverBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-forever",
        .value_types = &.{u32_type},
        .blocks = &forever_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const ForeverImage = boundary.program("process-forever", ForeverBody).image();
const RecursiveImage = recursion_fixture.ProcessRecursionProgram.image();

const Storage = struct {
    state: [4096]u8 = undefined,
    value: [4096]u8 = undefined,
    request: [4096]u8 = undefined,
    candidate: [4096]u8 = undefined,
    environment: [4096]u8 = undefined,
    scratch: [64 * 1024]u8 = undefined,

    fn buffers(self: *@This()) process_advance_v1.Buffers {
        return .{
            .output_state = &self.state,
            .output_value = &self.value,
            .output_request = &self.request,
            .candidate_state = &self.candidate,
            .environment = &self.environment,
            .scratch = &self.scratch,
        };
    }
};

const DeepStorage = struct {
    state: [128 * 1024]u8 = undefined,
    value: [64 * 1024]u8 = undefined,
    request: [64 * 1024]u8 = undefined,
    candidate: [128 * 1024]u8 = undefined,
    environment: [128 * 1024]u8 = undefined,
    scratch: [1024 * 1024]u8 = undefined,

    fn buffers(self: *@This()) process_advance_v1.Buffers {
        return .{
            .output_state = &self.state,
            .output_value = &self.value,
            .output_request = &self.request,
            .candidate_state = &self.candidate,
            .environment = &self.environment,
            .scratch = &self.scratch,
        };
    }
};

test "Process advance requests, recovers, resumes, and completes one segment at a time" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 41, .little);
    var first_storage: Storage = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &Image.bytes,
        .{ .initial_args = &initial_args },
        null,
        first_storage.buffers(),
        &first_workspace,
    );
    const requested = first.requested;
    try std.testing.expect(requested.state.len != 0);
    try std.testing.expect(requested.request.len != 0);

    var second_storage: Storage = .{};
    var second_workspace: boundary.image.ValidationWorkspace = .{};
    const second = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = requested.state },
        null,
        second_storage.buffers(),
        &second_workspace,
    );
    try std.testing.expectEqualSlices(
        u8,
        requested.state,
        second.requested.state,
    );
    try std.testing.expectEqualSlices(
        u8,
        requested.request,
        second.requested.request,
    );

    const request = try boundary.process_v1.effect.validateRequest(
        requested.request,
        Image.program_transition_digest,
    );
    var resume_value: [4]u8 = undefined;
    std.mem.writeInt(u32, &resume_value, 99, .little);
    var result_storage: [128]u8 = undefined;
    const result = try boundary.process_v1.effect.encodeResult(.{
        .request_identity_digest = request.request_identity_digest,
        .resume_schema_digest = request.resume_schema_digest,
        .@"resume" = &resume_value,
    }, &result_storage);
    var final_storage: Storage = .{};
    var final_workspace: boundary.image.ValidationWorkspace = .{};
    const resumed = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = requested.state },
        result,
        final_storage.buffers(),
        &final_workspace,
    );
    const resumed_state = resumed.progressed;

    var duplicate_storage: Storage = .{};
    var duplicate_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.UnexpectedEffectResult,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = resumed_state },
            result,
            duplicate_storage.buffers(),
            &duplicate_workspace,
        ),
    );

    var final_step_storage: Storage = .{};
    var final_step_workspace: boundary.image.ValidationWorkspace = .{};
    const final = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = resumed_state },
        null,
        final_step_storage.buffers(),
        &final_step_workspace,
    );
    try std.testing.expectEqualSlices(u8, &resume_value, final.completed);

    var wrong_request_identity = request.request_identity_digest;
    wrong_request_identity[0] ^= 1;
    var wrong_request_storage: [128]u8 = undefined;
    const wrong_request_result = try boundary.process_v1.effect.encodeResult(.{
        .request_identity_digest = wrong_request_identity,
        .resume_schema_digest = request.resume_schema_digest,
        .@"resume" = &resume_value,
    }, &wrong_request_storage);
    var wrong_request_buffers: Storage = .{};
    var wrong_request_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.ResultRequestMismatch,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = requested.state },
            wrong_request_result,
            wrong_request_buffers.buffers(),
            &wrong_request_workspace,
        ),
    );

    var wrong_schema = request.resume_schema_digest;
    wrong_schema[0] ^= 1;
    var wrong_schema_storage: [128]u8 = undefined;
    const wrong_schema_result = try boundary.process_v1.effect.encodeResult(.{
        .request_identity_digest = request.request_identity_digest,
        .resume_schema_digest = wrong_schema,
        .@"resume" = &resume_value,
    }, &wrong_schema_storage);
    var wrong_schema_buffers: Storage = .{};
    var wrong_schema_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.ResultSchemaMismatch,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = requested.state },
            wrong_schema_result,
            wrong_schema_buffers.buffers(),
            &wrong_schema_workspace,
        ),
    );

    var malformed_result_storage: [128]u8 = undefined;
    const malformed_result = try boundary.process_v1.effect.encodeResult(.{
        .request_identity_digest = request.request_identity_digest,
        .resume_schema_digest = request.resume_schema_digest,
        .@"resume" = &.{0xff},
    }, &malformed_result_storage);
    var malformed_result_buffers: Storage = .{};
    var malformed_result_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidResult,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = requested.state },
            malformed_result,
            malformed_result_buffers.buffers(),
            &malformed_result_workspace,
        ),
    );

    var malformed_state: [4096]u8 = undefined;
    @memcpy(malformed_state[0..requested.state.len], requested.state);
    malformed_state[process_state_v1.fixed_header_length + 1] = 0xff;
    var malformed_buffers: Storage = .{};
    var malformed_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidProcessState,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = malformed_state[0..requested.state.len] },
            null,
            malformed_buffers.buffers(),
            &malformed_workspace,
        ),
    );
}

test "Process advance preserves a call stack and returns one segment at a time" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 73, .little);

    var call_storage: Storage = .{};
    var call_workspace: boundary.image.ValidationWorkspace = .{};
    const called = try process_advance_v1.advance(
        &CallImage.bytes,
        .{ .initial_args = &initial_args },
        null,
        call_storage.buffers(),
        &call_workspace,
    );
    const called_state = called.progressed;
    const called_view = try process_state_v1.validate(
        called_state,
        CallImage.program_transition_digest,
    );
    try std.testing.expectEqual(@as(u64, 2), called_view.frame_count);

    var return_storage: Storage = .{};
    var return_workspace: boundary.image.ValidationWorkspace = .{};
    const returned = try process_advance_v1.advance(
        &CallImage.bytes,
        .{ .process_state = called_state },
        null,
        return_storage.buffers(),
        &return_workspace,
    );
    const returned_state = returned.progressed;
    const returned_view = try process_state_v1.validate(
        returned_state,
        CallImage.program_transition_digest,
    );
    try std.testing.expectEqual(@as(u64, 1), returned_view.frame_count);

    var done_storage: Storage = .{};
    var done_workspace: boundary.image.ValidationWorkspace = .{};
    const done = try process_advance_v1.advance(
        &CallImage.bytes,
        .{ .process_state = returned_state },
        null,
        done_storage.buffers(),
        &done_workspace,
    );
    try std.testing.expectEqualSlices(u8, &initial_args, done.completed);
}

test "Process NeedsCapacity is transactional and retryable" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 11, .little);
    var baseline_storage: Storage = .{};
    var baseline_workspace: boundary.image.ValidationWorkspace = .{};
    const baseline = try process_advance_v1.advance(
        &Image.bytes,
        .{ .initial_args = &initial_args },
        null,
        baseline_storage.buffers(),
        &baseline_workspace,
    );
    const pending = baseline.requested;
    const before_digest = process_state_v1.artifactDigest(pending.state);

    var constrained_storage: Storage = .{};
    var no_request_capacity: [0]u8 = .{};
    var constrained_workspace: boundary.image.ValidationWorkspace = .{};
    const constrained = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        .{
            .output_state = &constrained_storage.state,
            .output_value = &constrained_storage.value,
            .output_request = &no_request_capacity,
            .candidate_state = &constrained_storage.candidate,
            .environment = &constrained_storage.environment,
            .scratch = &constrained_storage.scratch,
        },
        &constrained_workspace,
    );
    try std.testing.expect(
        constrained.needs_capacity.minimum_output_bytes > 0,
    );
    try std.testing.expectEqual(
        before_digest,
        process_state_v1.artifactDigest(pending.state),
    );

    var retry_storage: Storage = .{};
    var retry_workspace: boundary.image.ValidationWorkspace = .{};
    const retry = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        retry_storage.buffers(),
        &retry_workspace,
    );
    try std.testing.expectEqualSlices(
        u8,
        pending.state,
        retry.requested.state,
    );
    try std.testing.expectEqualSlices(
        u8,
        pending.request,
        retry.requested.request,
    );
}

test "Process has no semantic reduction lifetime cap" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 5, .little);
    var left: Storage = .{};
    var right: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &ForeverImage.bytes,
        .{ .initial_args = &initial_args },
        null,
        left.buffers(),
        &workspace,
    );
    var state = first.explicitly_yielded;
    var use_right = true;
    for (0..4096) |_| {
        workspace = .{};
        const next = try process_advance_v1.advance(
            &ForeverImage.bytes,
            .{ .process_state = state },
            null,
            if (use_right) right.buffers() else left.buffers(),
            &workspace,
        );
        state = next.explicitly_yielded;
        use_right = !use_right;
    }
    _ = try process_state_v1.validate(
        state,
        ForeverImage.program_transition_digest,
    );
}

test "Process recursive state exceeds the former frame ceiling and resumes" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 300, .little);
    var left: DeepStorage = .{};
    var right: DeepStorage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &RecursiveImage.bytes,
        .{ .initial_args = &initial_args },
        null,
        left.buffers(),
        &workspace,
    );
    var state = first.progressed;
    var use_right = true;
    var maximum_frames: u64 = 0;
    var reductions: usize = 1;
    while (reductions < 4096) : (reductions += 1) {
        const view = try process_state_v1.validate(
            state,
            RecursiveImage.program_transition_digest,
        );
        maximum_frames = @max(maximum_frames, view.frame_count);
        workspace = .{};
        const next = try process_advance_v1.advance(
            &RecursiveImage.bytes,
            .{ .process_state = state },
            null,
            if (use_right) right.buffers() else left.buffers(),
            &workspace,
        );
        use_right = !use_right;
        switch (next) {
            .progressed => |next_state| state = next_state,
            .completed => |result| {
                try std.testing.expectEqual(
                    @as(u32, 45_150),
                    std.mem.readInt(u32, result[0..4], .little),
                );
                try std.testing.expect(maximum_frames > 256);
                return;
            },
            else => return error.UnexpectedProcessOutcome,
        }
    }
    return error.RecursiveProcessDidNotComplete;
}
