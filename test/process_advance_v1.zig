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

const LargeBytes = boundary.Bytes(256);
const large_type: boundary.ir.ValueType = .{ .schema = 0 };
const large_call_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{ .target = 1, .arguments = &call_arguments },
            .continuation = .{ .target = 2, .arguments = &return_arguments },
            .resume_type = large_type,
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
const LargeCallBody = struct {
    pub const InitialArgs = LargeBytes;
    pub const Result = LargeBytes;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{LargeBytes};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-large-call-return",
        .value_types = &.{ large_type, large_type, large_type },
        .blocks = &large_call_blocks,
        .entry = 0,
        .result_type = large_type,
        .functions = &.{
            .{ .id = 0, .entry = 0, .result_type = large_type },
            .{ .id = 1, .entry = 1, .result_type = large_type },
        },
    };
};
const LargeCallImage = boundary.program(
    "process-large-call-return",
    LargeCallBody,
).image();

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

const SwapPair = struct { left: u32, right: u32 };
const swap_entry_arguments = [_]boundary.ir.EdgeArgument{
    .{ .value = 1 },
    .{ .value = 2 },
    .{ .value = 10 },
};
const swap_backedge_arguments = [_]boundary.ir.EdgeArgument{
    .{ .value = 4 },
    .{ .value = 3 },
    .{ .value = 9 },
};
const swap_done_arguments = [_]boundary.ir.EdgeArgument{
    .{ .value = 3 },
    .{ .value = 4 },
};
const swap_entry_instructions = [_]boundary.ir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{0},
        .operation = .{ .product_extract = 1 },
    },
    .{
        .kind = .constant,
        .result = 10,
        .operation = .{ .constant = 0 },
    },
};
const swap_loop_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 9,
    .operation = .{ .constant = 1 },
}};
const swap_result_instructions = [_]boundary.ir.Instruction{.{
    .kind = .pure,
    .result = 8,
    .operands = &.{ 6, 7 },
    .operation = .product_construct,
}};
const swap_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &swap_entry_instructions,
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &swap_entry_arguments,
        } },
    },
    .{
        .id = 1,
        .role = .loop_header,
        .parameters = &.{ 3, 4, 5 },
        .instructions = &swap_loop_instructions,
        .terminator = .{ .branch = .{
            .condition = 5,
            .then_edge = .{
                .target = 2,
                .arguments = &swap_done_arguments,
            },
            .else_edge = .{
                .target = 1,
                .arguments = &swap_backedge_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .role = .terminal_handoff,
        .parameters = &.{ 6, 7 },
        .instructions = &swap_result_instructions,
        .terminator = .{ .return_value = 8 },
    },
};
const SwapBody = struct {
    pub const InitialArgs = SwapPair;
    pub const Result = SwapPair;
    pub const Failure = enum { rejected };
    pub const constants = .{ false, true };
    pub const effect_sites = .{};
    pub const schema_types = .{SwapPair};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-parallel-swap",
        .value_types = &.{
            .{ .schema = 0 },
            u32_type,
            u32_type,
            u32_type,
            u32_type,
            .{ .scalar = .boolean },
            u32_type,
            u32_type,
            .{ .schema = 0 },
            .{ .scalar = .boolean },
            .{ .scalar = .boolean },
        },
        .blocks = &swap_blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};
const SwapImage = boundary.program("process-parallel-swap", SwapBody).image();

const Storage = struct {
    state: [4096]u8 = undefined,
    value: [4096]u8 = undefined,
    request: [4096]u8 = undefined,
    candidate: [4096]u8 = undefined,
    environment: [4096]u8 = undefined,
    auxiliary_environment: [4096]u8 = undefined,
    scratch: [64 * 1024]u8 = undefined,

    fn buffers(self: *@This()) process_advance_v1.Buffers {
        return .{
            .output_state = &self.state,
            .output_value = &self.value,
            .output_request = &self.request,
            .candidate_state = &self.candidate,
            .environment = &self.environment,
            .auxiliary_environment = &self.auxiliary_environment,
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
    auxiliary_environment: [128 * 1024]u8 = undefined,
    scratch: [1024 * 1024]u8 = undefined,

    fn buffers(self: *@This()) process_advance_v1.Buffers {
        return .{
            .output_state = &self.state,
            .output_value = &self.value,
            .output_request = &self.request,
            .candidate_state = &self.candidate,
            .environment = &self.environment,
            .auxiliary_environment = &self.auxiliary_environment,
            .scratch = &self.scratch,
        };
    }
};

test "Process advance requests, recovers, resumes, and completes one segment at a time" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 41, .little);
    var first_storage: Storage = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try boundary.process_v1.advance(
        &Image.bytes,
        .{ .initial_args = &initial_args },
        null,
        first_storage.buffers(),
        &first_workspace,
    );
    const requested = first.requested;
    try std.testing.expect(requested.state.len != 0);
    try std.testing.expect(requested.request.len != 0);

    var admitted_scratch: [4096]u8 = undefined;
    var admitted_workspace: boundary.image.ValidationWorkspace = .{};
    const admitted = try boundary.process_v1.validateState(
        &Image.bytes,
        requested.state,
        &admitted_scratch,
        &admitted_workspace,
    );
    var frames: [8]boundary.process_v1.state.Frame = undefined;
    var frame_count: usize = 0;
    var frame_iterator = admitted.iterator();
    while (try frame_iterator.next()) |frame| {
        frames[frame_count] = frame;
        frame_count += 1;
    }
    var encoded_state: [4096]u8 = undefined;
    var encode_scratch: [4096]u8 = undefined;
    var encode_workspace: boundary.image.ValidationWorkspace = .{};
    const encoded = try boundary.process_v1.state.encode(
        &Image.bytes,
        frames[0..frame_count],
        &encoded_state,
        &encode_scratch,
        &encode_workspace,
    );
    try std.testing.expectEqualSlices(u8, requested.state, encoded.bytes);
    var alias_workspace: boundary.image.ValidationWorkspace = .{};
    const aliased_frames = @as(
        [*]boundary.process_v1.state.Frame,
        @ptrCast(&alias_workspace),
    )[0..frame_count];
    @memcpy(aliased_frames, frames[0..frame_count]);
    var alias_state: [4096]u8 = undefined;
    var alias_scratch: [4096]u8 = undefined;
    try std.testing.expectError(
        error.InvalidBuffers,
        boundary.process_v1.state.encode(
            &Image.bytes,
            aliased_frames,
            &alias_state,
            &alias_scratch,
            &alias_workspace,
        ),
    );
    var output_alias_frames = frames;
    output_alias_frames[frame_count - 1].environment =
        alias_state[0..frames[frame_count - 1].environment.len];
    var output_alias_scratch: [4096]u8 = undefined;
    var output_alias_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidBuffers,
        boundary.process_v1.state.encode(
            &Image.bytes,
            output_alias_frames[0..frame_count],
            &alias_state,
            &output_alias_scratch,
            &output_alias_workspace,
        ),
    );
    frames[frame_count - 1].constructor_id = std.math.maxInt(u32);
    var forged_state: [4096]u8 = undefined;
    var forged_scratch: [4096]u8 = undefined;
    var forged_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidProcessState,
        boundary.process_v1.state.encode(
            &Image.bytes,
            frames[0..frame_count],
            &forged_state,
            &forged_scratch,
            &forged_workspace,
        ),
    );

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
    try std.testing.expectEqual(
        @intFromPtr(&second_storage.state),
        @intFromPtr(second.requested.state.ptr),
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
    var image_workspace: boundary.image.ValidationWorkspace = .{};
    const validated_image = try boundary.image.validateImageView(
        &Image.bytes,
        &image_workspace,
    );
    const effects = validated_image.catalogs.envelope.section(.effects);
    const identity_length = std.mem.readInt(u32, effects[8..12], .little);
    const semantic_digest_offset: usize = 12 + identity_length + 12;
    try std.testing.expectEqualSlices(
        u8,
        effects[semantic_digest_offset..][0..32],
        &request.effect_site_semantic_digest,
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
    var no_resume_request_output: [0]u8 = .{};
    var final_workspace: boundary.image.ValidationWorkspace = .{};
    const resumed = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = requested.state },
        result,
        .{
            .output_state = &final_storage.state,
            .output_value = &final_storage.value,
            .output_request = &no_resume_request_output,
            .candidate_state = &final_storage.candidate,
            .environment = &final_storage.environment,
            .auxiliary_environment = &final_storage.auxiliary_environment,
            .scratch = &final_storage.scratch,
        },
        &final_workspace,
    );
    const resumed_state = resumed.progressed;

    var empty_result_storage: Storage = .{};
    var empty_result_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidResult,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = requested.state },
            &.{},
            empty_result_storage.buffers(),
            &empty_result_workspace,
        ),
    );

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

test "Process preserves activation across helper-entry backedges" {
    const BackedgeImage = recursion_fixture.HelperBackedgeProgram.image();
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 2, .little);

    var call_storage: Storage = .{};
    var call_workspace: boundary.image.ValidationWorkspace = .{};
    const call = try boundary.process_v1.advance(
        &BackedgeImage.bytes,
        .{ .initial_args = &initial_args },
        null,
        call_storage.buffers(),
        &call_workspace,
    );

    var branch_storage: Storage = .{};
    var branch_workspace: boundary.image.ValidationWorkspace = .{};
    const branch = try boundary.process_v1.advance(
        &BackedgeImage.bytes,
        .{ .process_state = call.progressed },
        null,
        branch_storage.buffers(),
        &branch_workspace,
    );

    var yield_storage: Storage = .{};
    var yield_workspace: boundary.image.ValidationWorkspace = .{};
    const yielded = try boundary.process_v1.advance(
        &BackedgeImage.bytes,
        .{ .process_state = branch.progressed },
        null,
        yield_storage.buffers(),
        &yield_workspace,
    );
    try std.testing.expect(yielded.explicitly_yielded.len != 0);
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

test "Process keeps large child environments separate from predecessor state" {
    var payload = [_]u8{0x5a} ** 192;
    const input = try LargeBytes.fromSlice(&payload);
    var initial_args: [512]u8 = undefined;
    const initial_length = try boundary.schema.encode(
        LargeBytes,
        input,
        &initial_args,
    );
    var storage: DeepStorage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const called = try process_advance_v1.advance(
        &LargeCallImage.bytes,
        .{ .initial_args = initial_args[0..initial_length] },
        null,
        storage.buffers(),
        &workspace,
    );
    const state = try process_state_v1.validate(
        called.progressed,
        LargeCallImage.program_transition_digest,
    );
    try std.testing.expectEqual(@as(u64, 2), state.frame_count);
}

test "Process applies overlapping edge arguments in parallel" {
    var initial: [8]u8 = undefined;
    std.mem.writeInt(u32, initial[0..4], 7, .little);
    std.mem.writeInt(u32, initial[4..8], 11, .little);
    var first_storage: Storage = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &SwapImage.bytes,
        .{ .initial_args = &initial },
        null,
        first_storage.buffers(),
        &first_workspace,
    );
    var second_storage: Storage = .{};
    var second_workspace: boundary.image.ValidationWorkspace = .{};
    const second = try process_advance_v1.advance(
        &SwapImage.bytes,
        .{ .process_state = first.progressed },
        null,
        second_storage.buffers(),
        &second_workspace,
    );
    var third_storage: Storage = .{};
    var third_workspace: boundary.image.ValidationWorkspace = .{};
    const third = try process_advance_v1.advance(
        &SwapImage.bytes,
        .{ .process_state = second.progressed },
        null,
        third_storage.buffers(),
        &third_workspace,
    );
    var fourth_storage: Storage = .{};
    var fourth_workspace: boundary.image.ValidationWorkspace = .{};
    const fourth = try process_advance_v1.advance(
        &SwapImage.bytes,
        .{ .process_state = third.progressed },
        null,
        fourth_storage.buffers(),
        &fourth_workspace,
    );
    try std.testing.expectEqual(
        @as(u32, 11),
        std.mem.readInt(u32, fourth.completed[0..4], .little),
    );
    try std.testing.expectEqual(
        @as(u32, 7),
        std.mem.readInt(u32, fourth.completed[4..8], .little),
    );
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
            .auxiliary_environment = &constrained_storage.auxiliary_environment,
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

    const requirement = constrained.needs_capacity;
    try std.testing.expectEqual(
        @as(u64, process_advance_v1.kernel_input_header_length +
            Image.bytes.len + pending.state.len),
        requirement.minimum_input_bytes,
    );
    try std.testing.expect(
        requirement.minimum_output_bytes >= pending.state.len +
            4096 * 4 + 256,
    );
    const output_capacity: usize = @intCast(requirement.minimum_output_bytes);
    const scratch_capacity: usize = @intCast(requirement.minimum_scratch_bytes);
    const retry_state = try std.testing.allocator.alloc(u8, output_capacity);
    defer std.testing.allocator.free(retry_state);
    const retry_value = try std.testing.allocator.alloc(u8, output_capacity);
    defer std.testing.allocator.free(retry_value);
    const retry_request = try std.testing.allocator.alloc(u8, output_capacity);
    defer std.testing.allocator.free(retry_request);
    const retry_candidate = try std.testing.allocator.alloc(u8, output_capacity);
    defer std.testing.allocator.free(retry_candidate);
    const retry_environment = try std.testing.allocator.alloc(u8, output_capacity);
    defer std.testing.allocator.free(retry_environment);
    const retry_auxiliary = try std.testing.allocator.alloc(u8, output_capacity);
    defer std.testing.allocator.free(retry_auxiliary);
    const retry_scratch = try std.testing.allocator.alloc(u8, scratch_capacity);
    defer std.testing.allocator.free(retry_scratch);
    var retry_workspace: boundary.image.ValidationWorkspace = .{};
    const retry = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        .{
            .output_state = retry_state,
            .output_value = retry_value,
            .output_request = retry_request,
            .candidate_state = retry_candidate,
            .environment = retry_environment,
            .auxiliary_environment = retry_auxiliary,
            .scratch = retry_scratch,
        },
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

    var no_capacity: [0]u8 = .{};
    var hidden_workspace: boundary.image.ValidationWorkspace = .{};
    const hidden = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        .{
            .output_state = &no_capacity,
            .output_value = &no_capacity,
            .output_request = &no_capacity,
            .candidate_state = &no_capacity,
            .environment = &no_capacity,
            .auxiliary_environment = &no_capacity,
            .scratch = &no_capacity,
        },
        &hidden_workspace,
    );
    const image_envelope = try boundary.image.validateEnvelope(&Image.bytes);
    try std.testing.expectEqual(
        image_envelope.header.maximum_kernel_scratch_bytes,
        hidden.needs_capacity.minimum_scratch_bytes,
    );
}

test "Process rejects aliased input and output arenas transactionally" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 19, .little);
    var initial_storage: Storage = .{};
    var initial_workspace: boundary.image.ValidationWorkspace = .{};
    const initial = try process_advance_v1.advance(
        &Image.bytes,
        .{ .initial_args = &initial_args },
        null,
        initial_storage.buffers(),
        &initial_workspace,
    );
    const pending = initial.requested;
    const before = process_state_v1.artifactDigest(pending.state);
    var other: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidBuffers,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = pending.state },
            null,
            .{
                .output_state = initial_storage.state[0..pending.state.len],
                .output_value = &other.value,
                .output_request = &other.request,
                .candidate_state = &other.candidate,
                .environment = &other.environment,
                .auxiliary_environment = &other.auxiliary_environment,
                .scratch = &other.scratch,
            },
            &workspace,
        ),
    );
    try std.testing.expectEqual(
        before,
        process_state_v1.artifactDigest(pending.state),
    );

    var workspace_alias: boundary.image.ValidationWorkspace = .{};
    const workspace_bytes = std.mem.asBytes(&workspace_alias);
    try std.testing.expect(workspace_bytes.len >= 4096);
    try std.testing.expectError(
        error.InvalidBuffers,
        process_advance_v1.advance(
            &Image.bytes,
            .{ .process_state = pending.state },
            null,
            .{
                .output_state = workspace_bytes[0..4096],
                .output_value = &other.value,
                .output_request = &other.request,
                .candidate_state = &other.candidate,
                .environment = &other.environment,
                .auxiliary_environment = &other.auxiliary_environment,
                .scratch = &other.scratch,
            },
            &workspace_alias,
        ),
    );
    try std.testing.expectError(
        error.InvalidBuffers,
        process_advance_v1.validateState(
            &Image.bytes,
            pending.state,
            workspace_bytes[0..4096],
            &workspace_alias,
        ),
    );
}

test "Process rejects aliased kernel-input encoding" {
    var storage: [128 * 1024]u8 = undefined;
    @memcpy(storage[0..Image.bytes.len], &Image.bytes);
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 23, .little);
    try std.testing.expectError(
        error.InvalidBuffers,
        process_advance_v1.encodeKernelInput(
            storage[0..Image.bytes.len],
            .{ .initial_args = &initial_args },
            null,
            &storage,
        ),
    );
}

test "Process kernel-input codec has one canonical round trip" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 23, .little);
    var storage: [128 * 1024]u8 = undefined;
    const encoded = try process_advance_v1.encodeKernelInput(
        &Image.bytes,
        .{ .initial_args = &initial_args },
        null,
        &storage,
    );
    const decoded = try process_advance_v1.validateKernelInput(encoded);
    try std.testing.expectEqualSlices(u8, &Image.bytes, decoded.image);
    try std.testing.expectEqualSlices(
        u8,
        &initial_args,
        decoded.instance.initial_args,
    );
    try std.testing.expect(decoded.effect_result == null);
    storage[36] = 1;
    try std.testing.expectError(
        error.InvalidKernelInput,
        process_advance_v1.validateKernelInput(storage[0..encoded.len]),
    );
    var wide_header: [process_advance_v1.kernel_input_header_length]u8 = undefined;
    _ = try process_advance_v1.encodeKernelInputHeader(
        1,
        false,
        0,
        @as(u64, std.math.maxInt(u32)) + 1,
        0,
        &wide_header,
    );
    try std.testing.expectEqual(
        @as(u64, std.math.maxInt(u32)) + 1,
        std.mem.readInt(u64, wide_header[20..28], .little),
    );
}

test "Process rejects aliased kernel-outcome encoding" {
    var storage: [128]u8 = undefined;
    @memset(storage[96..100], 0x77);
    try std.testing.expectError(
        error.InvalidBuffers,
        process_advance_v1.encodeOutcome(
            .{ .progressed = storage[96..100] },
            &storage,
        ),
    );
}

test "Process Capsule admits only a compatible image and bound instance" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 31, .little);
    const input: boundary.process_v1.capsule.Input = .{
        .required_kernel_semantic_version = 1,
        .image = &Image.bytes,
        .instance_kind = .initial_args,
        .instance = &initial_args,
    };
    var storage: [128 * 1024]u8 = undefined;
    var scratch: [1024 * 1024]u8 = undefined;
    var workspace: boundary.image.ValidationWorkspace = .{};
    const encoded = try boundary.process_v1.capsule.encode(
        input,
        &storage,
        &scratch,
        &workspace,
    );
    workspace = .{};
    const capsule = try boundary.process_v1.capsule.validate(
        encoded,
        &scratch,
        &workspace,
    );
    try std.testing.expectEqualSlices(u8, &Image.bytes, capsule.image);
    try std.testing.expectEqualSlices(u8, &initial_args, capsule.instance);
    try std.testing.expect(std.mem.find(u8, encoded, "profile") == null);

    var wrong_version_storage: [128 * 1024]u8 = undefined;
    var wrong_version_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.UnsupportedKernelSemanticVersion,
        boundary.process_v1.capsule.encode(
            .{
                .required_kernel_semantic_version = 2,
                .image = &Image.bytes,
                .instance_kind = .initial_args,
                .instance = &initial_args,
            },
            &wrong_version_storage,
            &scratch,
            &wrong_version_workspace,
        ),
    );

    var wrong_state_storage: [128 * 1024]u8 = undefined;
    var wrong_state_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidProcessState,
        boundary.process_v1.capsule.encode(
            .{
                .required_kernel_semantic_version = 1,
                .image = &Image.bytes,
                .instance_kind = .process_state,
                .instance = &initial_args,
            },
            &wrong_state_storage,
            &scratch,
            &wrong_state_workspace,
        ),
    );

    var corrupted_image = Image.bytes;
    corrupted_image[0] ^= 1;
    var corrupted_storage: [128 * 1024]u8 = undefined;
    var corrupted_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidMagic,
        boundary.process_v1.capsule.encode(
            .{
                .required_kernel_semantic_version = 1,
                .image = &corrupted_image,
                .instance_kind = .initial_args,
                .instance = &initial_args,
            },
            &corrupted_storage,
            &scratch,
            &corrupted_workspace,
        ),
    );

    var alias_workspace: boundary.image.ValidationWorkspace = .{};
    const alias_bytes = std.mem.asBytes(&alias_workspace);
    try std.testing.expectError(
        error.InvalidCapsule,
        boundary.process_v1.capsule.encode(
            input,
            alias_bytes,
            &scratch,
            &alias_workspace,
        ),
    );

    var scratch_alias_image = Image.bytes;
    var scratch_alias_storage: [128 * 1024]u8 = undefined;
    var scratch_alias_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidCapsule,
        boundary.process_v1.capsule.encode(
            .{
                .required_kernel_semantic_version = 1,
                .image = &scratch_alias_image,
                .instance_kind = .initial_args,
                .instance = &initial_args,
            },
            &scratch_alias_storage,
            &scratch_alias_image,
            &scratch_alias_workspace,
        ),
    );

    var direct_alias_workspace: boundary.image.ValidationWorkspace = .{};
    const direct_alias_bytes = std.mem.asBytes(&direct_alias_workspace);
    @memcpy(direct_alias_bytes[0..encoded.len], encoded);
    try std.testing.expectError(
        error.InvalidCapsule,
        boundary.process_v1.capsule.validate(
            direct_alias_bytes[0..encoded.len],
            &scratch,
            &direct_alias_workspace,
        ),
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

test "Process call production admits every changed frame" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 3, .little);
    var initial_storage: DeepStorage = .{};
    var initial_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &RecursiveImage.bytes,
        .{ .initial_args = &initial_args },
        null,
        initial_storage.buffers(),
        &initial_workspace,
    );
    const authentic = first.progressed;
    const state = try process_state_v1.validate(
        authentic,
        RecursiveImage.program_transition_digest,
    );
    try std.testing.expect(state.frame_count >= 2);
    var iterator = state.iterator();
    var parent: ?process_state_v1.FrameSpan = null;
    var child: ?process_state_v1.FrameSpan = null;
    while (try iterator.nextSpan()) |frame| {
        parent = child;
        child = frame;
    }
    const changed_parent = parent orelse return error.TestUnexpectedResult;
    const changed_child = child orelse return error.TestUnexpectedResult;
    try std.testing.expect(changed_parent.frame.environment.len >= 4);
    var forged: [128 * 1024]u8 = undefined;
    var found_omission_witness = false;
    var field_offset: usize = 0;
    while (field_offset + 4 <= changed_parent.frame.environment.len) : (field_offset += 4) {
        @memcpy(forged[0..authentic.len], authentic);
        const environment_offset = @intFromPtr(changed_parent.frame.environment.ptr) -
            @intFromPtr(authentic.ptr);
        const value_offset = environment_offset + field_offset;
        const original = std.mem.readInt(
            u32,
            forged[value_offset..][0..4],
            .little,
        );
        std.mem.writeInt(
            u32,
            forged[value_offset..][0..4],
            original +% 1,
            .little,
        );
        var child_only_scratch: [1024 * 1024]u8 = undefined;
        var child_only_workspace: boundary.image.ValidationWorkspace = .{};
        process_advance_v1.testing.validateProducedSuffix(
            &RecursiveImage.bytes,
            forged[0..authentic.len],
            &.{changed_child.frame.constructor_id},
            &child_only_scratch,
            &child_only_workspace,
        ) catch continue;
        var complete_scratch: [1024 * 1024]u8 = undefined;
        var complete_workspace: boundary.image.ValidationWorkspace = .{};
        try std.testing.expectError(
            error.InvalidProcessState,
            process_advance_v1.testing.validateProducedSuffix(
                &RecursiveImage.bytes,
                forged[0..authentic.len],
                &.{
                    changed_parent.frame.constructor_id,
                    changed_child.frame.constructor_id,
                },
                &complete_scratch,
                &complete_workspace,
            ),
        );
        var public_scratch: [1024 * 1024]u8 = undefined;
        var public_workspace: boundary.image.ValidationWorkspace = .{};
        try std.testing.expectError(
            error.InvalidProcessState,
            boundary.process_v1.validateState(
                &RecursiveImage.bytes,
                forged[0..authentic.len],
                &public_scratch,
                &public_workspace,
            ),
        );
        found_omission_witness = true;
        break;
    }
    try std.testing.expect(found_omission_witness);
}

test "Process rejects schema-valid forged constructor invariants" {
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 3, .little);
    var initial_storage: DeepStorage = .{};
    var initial_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try process_advance_v1.advance(
        &RecursiveImage.bytes,
        .{ .initial_args = &initial_args },
        null,
        initial_storage.buffers(),
        &initial_workspace,
    );
    const authentic = first.progressed;
    const authentic_view = try process_state_v1.validate(
        authentic,
        RecursiveImage.program_transition_digest,
    );
    const top = try process_state_v1.topFrame(authentic_view);
    const environment_offset = @intFromPtr(top.frame.environment.ptr) -
        @intFromPtr(authentic.ptr);
    try std.testing.expect(top.frame.environment.len >= 8);
    var forged: [128 * 1024]u8 = undefined;
    @memcpy(forged[0..authentic.len], authentic);
    std.mem.writeInt(
        u32,
        forged[environment_offset + 4 ..][0..4],
        4,
        .little,
    );
    var output: DeepStorage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidProcessState,
        process_advance_v1.advance(
            &RecursiveImage.bytes,
            .{ .process_state = forged[0..authentic.len] },
            null,
            output.buffers(),
            &workspace,
        ),
    );

    var capsule_storage: [256 * 1024]u8 = undefined;
    var capsule_scratch: [1024 * 1024]u8 = undefined;
    var capsule_workspace: boundary.image.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidProcessState,
        boundary.process_v1.capsule.encode(
            .{
                .required_kernel_semantic_version = 1,
                .image = &RecursiveImage.bytes,
                .instance_kind = .process_state,
                .instance = forged[0..authentic.len],
            },
            &capsule_storage,
            &capsule_scratch,
            &capsule_workspace,
        ),
    );
}

test "NeedsCapacity page ceiling preserves saturated u64 totals" {
    var output: [64]u8 = undefined;
    const layout: process_advance_v1.KernelArenaLayout = .{
        .input_bytes = 0,
        .output_bytes = 0,
        .state_bytes = 0,
        .candidate_state_bytes = 0,
        .value_bytes = 0,
        .request_bytes = 0,
        .environment_bytes = 0,
        .auxiliary_environment_bytes = 0,
        .scratch_bytes = 0,
    };
    const encoded = try process_advance_v1.encodeOutcomeForCapacity(
        .{ .needs_capacity = .{
            .minimum_input_bytes = 1,
            .minimum_output_bytes = std.math.maxInt(u64),
            .minimum_scratch_bytes = std.math.maxInt(u64),
            .minimum_memory_pages = 0,
        } },
        1,
        layout,
        0,
        &output,
    );
    try std.testing.expectEqual(
        @as(u64, 281474976710656),
        std.mem.readInt(u64, encoded[56..64], .little),
    );
}

test "NeedsCapacity adds every arena growth delta to live pages" {
    const layout: process_advance_v1.KernelArenaLayout = .{
        .input_bytes = 0,
        .output_bytes = 0,
        .state_bytes = 0,
        .candidate_state_bytes = 0,
        .value_bytes = 0,
        .request_bytes = 0,
        .environment_bytes = 0,
        .auxiliary_environment_bytes = 0,
        .scratch_bytes = 0,
    };
    try std.testing.expectEqual(
        @as(u64, 10),
        layout.minimumMemoryPages(
            .{
                .minimum_input_bytes = 65536,
                .minimum_output_bytes = 65536,
                .minimum_scratch_bytes = 65536,
                .minimum_memory_pages = 0,
            },
            1,
        ),
    );
}
