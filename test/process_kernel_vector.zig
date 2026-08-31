const authored_failure = @import("authored_failure_v2_fixture");
const boundary = @import("boundary");
const morphism_fixture = @import("morphism_fixture");
const process_advance_v1 = @import("process_advance_v1");
const recursion_fixture = @import("recursion_fixture");
const std = @import("std");
const text_byte_at = @import("text_byte_at_fixture");

const Lookup = boundary.effect.site(
    0,
    "process.kernel.fixture.lookup.v1",
    u32,
    u32,
);
const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &resume_arguments },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};
const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-kernel-vector",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const Image = boundary.program("process-kernel-vector", Body).image();
pub const CapacityImage = Image;

const forward_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 0 }};
const progressed_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &forward_arguments,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};
const ProgressedBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-kernel-progressed",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &progressed_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const ProgressedImage = boundary.program(
    "process-kernel-progressed",
    ProgressedBody,
).image();

const yielded_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 1,
                .arguments = &forward_arguments,
            },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};
const YieldedBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-kernel-yielded",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &yielded_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const YieldedImage = boundary.program(
    "process-kernel-yielded",
    YieldedBody,
).image();

const failed_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .terminator = .{ .fail = 0 },
}};
const FailedBody = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "process-kernel-failed",
        .value_types = &.{},
        .blocks = &failed_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .unit },
    };
};
const FailedImage = boundary.program(
    "process-kernel-failed",
    FailedBody,
).image();

const MorphismImage = morphism_fixture.ReificationBaselineProgram.image();
const RecursionImage = recursion_fixture.ProcessRecursionProgram.image();

const Storage = struct {
    state: [64 * 1024]u8 = undefined,
    value: [64 * 1024]u8 = undefined,
    request: [64 * 1024]u8 = undefined,
    candidate: [64 * 1024]u8 = undefined,
    environment: [64 * 1024]u8 = undefined,
    auxiliary_environment: [64 * 1024]u8 = undefined,
    scratch: [512 * 1024]u8 = undefined,

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

const EmissionMode = enum { legacy, conformance };

const Emission = struct {
    writer: *std.Io.Writer,
    mode: EmissionMode,

    fn writeHeader(self: @This(), count: u32) !void {
        switch (self.mode) {
            .legacy => try writeInt(self.writer, count),
            .conformance => {
                try self.writer.writeAll("BPCGEN1\x00");
                try writeUnsigned(self.writer, u32, 1);
                try writeUnsigned(self.writer, u32, count);
            },
        }
    }

    fn writeVector(
        self: @This(),
        id: []const u8,
        image: []const u8,
        instance: process_advance_v1.Instance,
        effect_result: ?[]const u8,
        outcome: process_advance_v1.Outcome,
    ) !void {
        var input_storage: [128 * 1024]u8 = undefined;
        var output_storage: [128 * 1024]u8 = undefined;
        const input = try process_advance_v1.encodeKernelInput(
            image,
            instance,
            effect_result,
            &input_storage,
        );
        const output = try process_advance_v1.encodeOutcome(
            outcome,
            &output_storage,
        );
        switch (self.mode) {
            .legacy => {
                try writeInt(self.writer, @intCast(input.len));
                try writeInt(self.writer, @intCast(output.len));
            },
            .conformance => {
                try writeUnsigned(self.writer, u16, @intCast(id.len));
                try self.writer.writeAll(&.{ 0, 0 });
                try writeUnsigned(self.writer, u64, @intCast(input.len));
                try writeUnsigned(self.writer, u64, @intCast(output.len));
                try self.writer.writeAll(id);
            },
        }
        try self.writer.writeAll(input);
        try self.writer.writeAll(output);
    }
};

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    defer arguments.deinit();
    _ = arguments.skip();
    const mode: EmissionMode = if (arguments.next()) |argument|
        if (std.mem.eql(u8, argument, "--conformance-corpus-v1"))
            .conformance
        else
            return error.UnexpectedArgument
    else
        .legacy;
    if (arguments.next() != null) return error.UnexpectedArgument;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const emission: Emission = .{ .writer = stdout, .mode = mode };
    try emission.writeHeader(if (mode == .conformance) 19 else 17);

    var left: Storage = .{};
    var right: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 17, .little);
    const first = try process_advance_v1.advance(
        &Image.bytes,
        .{ .initial_args = &initial },
        null,
        left.buffers(),
        &workspace,
    );
    try emission.writeVector(
        "typed-effect-initial",
        &Image.bytes,
        .{ .initial_args = &initial },
        null,
        first,
    );
    const pending = first.requested;

    workspace = .{};
    const second = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        right.buffers(),
        &workspace,
    );
    try emission.writeVector(
        "pending-request-reconstruction",
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        second,
    );
    try expectEquivalentRequests(first, second);

    const request = try boundary.process_v1.effect.validateRequest(
        pending.request,
        Image.program_transition_digest,
    );
    if (!std.mem.eql(
        u8,
        request.effect_semantic_identity,
        "process.kernel.fixture.lookup.v1",
    ) or !std.mem.eql(u8, request.payload, &initial)) {
        return error.UnexpectedTypedRequest;
    }
    var resume_value: [4]u8 = undefined;
    std.mem.writeInt(u32, &resume_value, 29, .little);
    var result_storage: [256]u8 = undefined;
    const result = try boundary.process_v1.effect.encodeResult(.{
        .request_identity_digest = request.request_identity_digest,
        .resume_schema_digest = request.resume_schema_digest,
        .@"resume" = &resume_value,
    }, &result_storage);
    right = .{};
    workspace = .{};
    const third = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        result,
        right.buffers(),
        &workspace,
    );
    try emission.writeVector(
        "typed-resume",
        &Image.bytes,
        .{ .process_state = pending.state },
        result,
        third,
    );
    try expectU32Result(third, 29);

    right = .{};
    workspace = .{};
    const fourth = try process_advance_v1.advance(
        &ProgressedImage.bytes,
        .{ .initial_args = &initial },
        null,
        right.buffers(),
        &workspace,
    );
    try emission.writeVector(
        "initial-progress",
        &ProgressedImage.bytes,
        .{ .initial_args = &initial },
        null,
        fourth,
    );
    _ = fourth.progressed;

    right = .{};
    workspace = .{};
    const fifth = try process_advance_v1.advance(
        &YieldedImage.bytes,
        .{ .initial_args = &initial },
        null,
        right.buffers(),
        &workspace,
    );
    try emission.writeVector(
        "explicit-yield",
        &YieldedImage.bytes,
        .{ .initial_args = &initial },
        null,
        fifth,
    );
    _ = fifth.explicitly_yielded;

    right = .{};
    workspace = .{};
    if (FailedImage.evaluator_semantics_version !=
        boundary.image.evaluator_semantics_v1)
    {
        return error.ExpectedAuthoredFailureV1Image;
    }
    const sixth = try process_advance_v1.advance(
        &FailedImage.bytes,
        .{ .initial_args = &.{} },
        null,
        right.buffers(),
        &workspace,
    );
    try emission.writeVector(
        "authored-failure-v1",
        &FailedImage.bytes,
        .{ .initial_args = &.{} },
        null,
        sixth,
    );
    try expectFailureTag(sixth, 0);

    try writeAuthoredFailureVectors(emission);
    if (mode == .legacy) try writeTextByteAtVectors(emission);
    try writeMorphismVector(emission);
    try writeRecursionVectors(emission);

    try stdout.flush();
}

fn writeTextByteAtVectors(emission: Emission) !void {
    if (text_byte_at.Image.evaluator_semantics_version !=
        boundary.image.evaluator_semantics_v3)
    {
        return error.ExpectedTextByteAtV3Image;
    }
    const maximum_input = comptime boundary.schema.maximumEncodedSize(
        text_byte_at.Input,
    );
    var initial: [maximum_input]u8 = undefined;
    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};

    const success_length = try boundary.schema.encode(
        text_byte_at.Input,
        text_byte_at.input(2),
        &initial,
    );
    const completed = try advanceAndWrite(
        emission,
        "text-byte-at-v3-success",
        &text_byte_at.Image.bytes,
        .{ .initial_args = initial[0..success_length] },
        null,
        &storage,
        &workspace,
    );
    const value = completed.completed;
    if (value.len != 1 or value[0] != '"') {
        return error.UnexpectedTextByteAtValue;
    }

    storage = .{};
    workspace = .{};
    const failure_length = try boundary.schema.encode(
        text_byte_at.Input,
        text_byte_at.input(3),
        &initial,
    );
    const failed = try advanceAndWrite(
        emission,
        "text-byte-at-v3-invalid-index",
        &text_byte_at.Image.bytes,
        .{ .initial_args = initial[0..failure_length] },
        null,
        &storage,
        &workspace,
    );
    try expectFailureTag(failed, @intFromEnum(text_byte_at.Failure.bad_index));
}

fn writeAuthoredFailureVectors(emission: Emission) !void {
    if (authored_failure.Image.evaluator_semantics_version !=
        boundary.image.evaluator_semantics_v2 or
        authored_failure.DivisionImage.evaluator_semantics_version !=
            boundary.image.evaluator_semantics_v2)
    {
        return error.ExpectedAuthoredFailureV2Image;
    }
    try writeAuthoredFailureCase(
        emission,
        "authored-failure-v2-bad-math-progress",
        "authored-failure-v2-bad-math",
        &authored_failure.bad_math_initial_args,
        authored_failure.bad_math_failure_tag,
    );
    try writeAuthoredFailureCase(
        emission,
        "authored-failure-v2-bad-position-progress",
        "authored-failure-v2-bad-position",
        &authored_failure.bad_position_initial_args,
        authored_failure.bad_position_failure_tag,
    );

    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const success = try advanceAndWrite(
        emission,
        "authored-failure-v2-success",
        &authored_failure.DivisionImage.bytes,
        .{ .initial_args = &authored_failure.division_success_initial_args },
        null,
        &storage,
        &workspace,
    );
    const quotient = success.completed;
    if (quotient.len != 1 or quotient[0] != 4) {
        return error.UnexpectedAuthoredFailureSuccess;
    }
}

fn writeAuthoredFailureCase(
    emission: Emission,
    started_id: []const u8,
    failed_id: []const u8,
    initial_args: []const u8,
    expected_tag: u32,
) !void {
    var left: Storage = .{};
    var right: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const started = try advanceAndWrite(
        emission,
        started_id,
        &authored_failure.Image.bytes,
        .{ .initial_args = initial_args },
        null,
        &left,
        &workspace,
    );
    const state = started.progressed;
    workspace = .{};
    const failed = try advanceAndWrite(
        emission,
        failed_id,
        &authored_failure.Image.bytes,
        .{ .process_state = state },
        null,
        &right,
        &workspace,
    );
    try expectFailureTag(failed, expected_tag);
}

fn writeMorphismVector(emission: Emission) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 7, .little);
    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const outcome = try advanceAndWrite(
        emission,
        "effect-morphism",
        &MorphismImage.bytes,
        .{ .initial_args = &initial },
        null,
        &storage,
        &workspace,
    );
    const request = try boundary.process_v1.effect.validateRequest(
        outcome.requested.request,
        MorphismImage.program_transition_digest,
    );
    if (!std.mem.eql(
        u8,
        request.effect_semantic_identity,
        "residual.lookup.v2",
    ) or !std.mem.eql(u8, request.payload, &initial)) {
        return error.UnexpectedMorphedRequest;
    }
}

fn writeRecursionVectors(emission: Emission) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 1, .little);
    var left: Storage = .{};
    var right: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const called = try advanceAndWrite(
        emission,
        "recursion-call",
        &RecursionImage.bytes,
        .{ .initial_args = &initial },
        null,
        &left,
        &workspace,
    );
    const call_state = called.progressed;
    try expectFrameCount(call_state, 2);

    workspace = .{};
    const branched = try advanceAndWrite(
        emission,
        "recursion-branch",
        &RecursionImage.bytes,
        .{ .process_state = call_state },
        null,
        &right,
        &workspace,
    );
    const branch_state = branched.progressed;
    try expectFrameCount(branch_state, 2);

    left = .{};
    workspace = .{};
    const recurred = try advanceAndWrite(
        emission,
        "recursion-recur",
        &RecursionImage.bytes,
        .{ .process_state = branch_state },
        null,
        &left,
        &workspace,
    );
    const recur_state = recurred.progressed;
    try expectFrameCount(recur_state, 3);
    if (emission.mode == .legacy) return;

    right = .{};
    workspace = .{};
    const base = try advanceAndWrite(
        emission,
        "recursion-base-branch",
        &RecursionImage.bytes,
        .{ .process_state = recur_state },
        null,
        &right,
        &workspace,
    );
    const base_state = base.progressed;
    try expectFrameCount(base_state, 3);

    left = .{};
    workspace = .{};
    const inner = try advanceAndWrite(
        emission,
        "recursion-return-inner",
        &RecursionImage.bytes,
        .{ .process_state = base_state },
        null,
        &left,
        &workspace,
    );
    const inner_state = inner.progressed;
    try expectFrameCount(inner_state, 2);

    right = .{};
    workspace = .{};
    const root = try advanceAndWrite(
        emission,
        "recursion-return-root",
        &RecursionImage.bytes,
        .{ .process_state = inner_state },
        null,
        &right,
        &workspace,
    );
    const root_state = root.progressed;
    try expectFrameCount(root_state, 1);

    left = .{};
    workspace = .{};
    const completed = try advanceAndWrite(
        emission,
        "recursion-complete",
        &RecursionImage.bytes,
        .{ .process_state = root_state },
        null,
        &left,
        &workspace,
    );
    try expectU32Result(completed, 1);
}

fn advanceAndWrite(
    emission: Emission,
    id: []const u8,
    image: []const u8,
    instance: process_advance_v1.Instance,
    effect_result: ?[]const u8,
    storage: *Storage,
    workspace: *boundary.image.ValidationWorkspace,
) !process_advance_v1.Outcome {
    const outcome = try process_advance_v1.advance(
        image,
        instance,
        effect_result,
        storage.buffers(),
        workspace,
    );
    try emission.writeVector(id, image, instance, effect_result, outcome);
    return outcome;
}

fn expectEquivalentRequests(
    left: process_advance_v1.Outcome,
    right: process_advance_v1.Outcome,
) !void {
    const left_request = switch (left) {
        .requested => |requested| requested,
        else => return error.ExpectedRequested,
    };
    const right_request = switch (right) {
        .requested => |requested| requested,
        else => return error.ExpectedRequested,
    };
    if (!std.mem.eql(u8, left_request.state, right_request.state) or
        !std.mem.eql(u8, left_request.request, right_request.request))
    {
        return error.PendingRequestReconstructionMismatch;
    }
    var left_storage: [128 * 1024]u8 = undefined;
    var right_storage: [128 * 1024]u8 = undefined;
    const left_bytes = try process_advance_v1.encodeOutcome(left, &left_storage);
    const right_bytes = try process_advance_v1.encodeOutcome(right, &right_storage);
    if (!std.mem.eql(u8, left_bytes, right_bytes)) {
        return error.PendingOutcomeReconstructionMismatch;
    }
}

fn expectU32Result(outcome: process_advance_v1.Outcome, expected: u32) !void {
    const result = switch (outcome) {
        .completed => |bytes| bytes,
        else => return error.ExpectedCompleted,
    };
    if (result.len != @sizeOf(u32) or
        std.mem.readInt(u32, result[0..@sizeOf(u32)], .little) != expected)
    {
        return error.UnexpectedCompletedResult;
    }
}

fn expectFailureTag(outcome: process_advance_v1.Outcome, expected: u32) !void {
    const failure = switch (outcome) {
        .authored_failure => |bytes| bytes,
        else => return error.ExpectedAuthoredFailure,
    };
    if (failure.len != 4 or
        std.mem.readInt(u32, failure[0..4], .little) != expected)
    {
        return error.UnexpectedAuthoredFailureTag;
    }
}

fn expectFrameCount(state: []const u8, expected: u64) !void {
    const view = try boundary.process_v1.state.validateEncoding(
        state,
        RecursionImage.program_transition_digest,
    );
    if (view.frame_count != expected) return error.UnexpectedFrameCount;
}

fn writeInt(writer: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try writer.writeAll(&bytes);
}

fn writeUnsigned(writer: *std.Io.Writer, comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try writer.writeAll(&bytes);
}
