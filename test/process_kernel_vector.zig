const authored_failure = @import("authored_failure_v2_fixture");
const boundary = @import("boundary");
const morphism_fixture = @import("morphism_fixture");
const process_advance_v1 = @import("process_advance_v1");
const recursion_fixture = @import("recursion_fixture");
const std = @import("std");

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

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try writeInt(stdout, 15);

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
    try writeVector(stdout, &Image.bytes, .{ .initial_args = &initial }, null, first);
    const pending = first.requested;

    workspace = .{};
    const second = try process_advance_v1.advance(
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        right.buffers(),
        &workspace,
    );
    try writeVector(
        stdout,
        &Image.bytes,
        .{ .process_state = pending.state },
        null,
        second,
    );

    const request = try boundary.process_v1.effect.validateRequest(
        pending.request,
        Image.program_transition_digest,
    );
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
    try writeVector(
        stdout,
        &Image.bytes,
        .{ .process_state = pending.state },
        result,
        third,
    );

    right = .{};
    workspace = .{};
    const fourth = try process_advance_v1.advance(
        &ProgressedImage.bytes,
        .{ .initial_args = &initial },
        null,
        right.buffers(),
        &workspace,
    );
    try writeVector(
        stdout,
        &ProgressedImage.bytes,
        .{ .initial_args = &initial },
        null,
        fourth,
    );

    right = .{};
    workspace = .{};
    const fifth = try process_advance_v1.advance(
        &YieldedImage.bytes,
        .{ .initial_args = &initial },
        null,
        right.buffers(),
        &workspace,
    );
    try writeVector(
        stdout,
        &YieldedImage.bytes,
        .{ .initial_args = &initial },
        null,
        fifth,
    );

    right = .{};
    workspace = .{};
    const sixth = try process_advance_v1.advance(
        &FailedImage.bytes,
        .{ .initial_args = &.{} },
        null,
        right.buffers(),
        &workspace,
    );
    try writeVector(
        stdout,
        &FailedImage.bytes,
        .{ .initial_args = &.{} },
        null,
        sixth,
    );

    try writeAuthoredFailureVectors(stdout);
    try writeMorphismVector(stdout);
    try writeRecursionVectors(stdout);

    try stdout.flush();
}

fn writeAuthoredFailureVectors(writer: *std.Io.Writer) !void {
    if (authored_failure.Image.evaluator_semantics_version !=
        boundary.image.evaluator_semantics_v2 or
        authored_failure.DivisionImage.evaluator_semantics_version !=
            boundary.image.evaluator_semantics_v2)
    {
        return error.ExpectedAuthoredFailureV2Image;
    }
    try writeAuthoredFailureCase(
        writer,
        &authored_failure.bad_math_initial_args,
        authored_failure.bad_math_failure_tag,
    );
    try writeAuthoredFailureCase(
        writer,
        &authored_failure.bad_position_initial_args,
        authored_failure.bad_position_failure_tag,
    );

    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const success = try advanceAndWrite(
        writer,
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
    writer: *std.Io.Writer,
    initial_args: []const u8,
    expected_tag: u32,
) !void {
    var left: Storage = .{};
    var right: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const started = try advanceAndWrite(
        writer,
        &authored_failure.Image.bytes,
        .{ .initial_args = initial_args },
        null,
        &left,
        &workspace,
    );
    const state = started.progressed;
    workspace = .{};
    const failed = try advanceAndWrite(
        writer,
        &authored_failure.Image.bytes,
        .{ .process_state = state },
        null,
        &right,
        &workspace,
    );
    try expectFailureTag(failed, expected_tag);
}

fn writeMorphismVector(writer: *std.Io.Writer) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 7, .little);
    var storage: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const outcome = try advanceAndWrite(
        writer,
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

fn writeRecursionVectors(writer: *std.Io.Writer) !void {
    var initial: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial, 1, .little);
    var left: Storage = .{};
    var right: Storage = .{};
    var workspace: boundary.image.ValidationWorkspace = .{};
    const called = try advanceAndWrite(
        writer,
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
        writer,
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
        writer,
        &RecursionImage.bytes,
        .{ .process_state = branch_state },
        null,
        &left,
        &workspace,
    );
    try expectFrameCount(recurred.progressed, 3);
}

fn advanceAndWrite(
    writer: *std.Io.Writer,
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
    try writeVector(writer, image, instance, effect_result, outcome);
    return outcome;
}

fn writeVector(
    writer: *std.Io.Writer,
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
    try writeInt(writer, @intCast(input.len));
    try writeInt(writer, @intCast(output.len));
    try writer.writeAll(input);
    try writer.writeAll(output);
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
