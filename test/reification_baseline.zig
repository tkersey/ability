const boundary = @import("boundary");
const compiler = @import("compiler");
const handler_fixture = @import("handler_fixture");
const morphism_fixture = @import("morphism_fixture");
const operations_fixture = @import("operations_fixture");
const recursion_fixture = @import("recursion_fixture");
const std = @import("std");

const OperationsDefinition = compiler.DefinitionFor(
    "pure-operation-algebra",
    operations_fixture.ReificationBaselineBody,
);
const HandlerDefinition = compiler.DefinitionFor(
    "handled-effect",
    handler_fixture.ReificationBaselineBody,
);
const MorphismDefinition = compiler.DefinitionFor(
    "morphed-effect",
    morphism_fixture.ReificationBaselineBody,
);
const RecursionDefinition = compiler.DefinitionFor(
    "bounded-recursive-helper",
    recursion_fixture.ReificationBaselineBody,
);

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const bool_type: boundary.ir.ValueType = .{ .scalar = .boolean };

const Lookup = boundary.effect.site(
    0,
    "baseline.lookup.v1",
    u32,
    u32,
);

const one_effect_resume = [_]boundary.ir.EdgeArgument{.@"resume"};
const one_effect_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &one_effect_resume,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const OneEffectBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "baseline-one-effect",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &one_effect_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const OneEffectProgram = boundary.program(
    "baseline-one-effect",
    OneEffectBody,
);
const OneEffectDefinition = compiler.DefinitionFor(
    "baseline-one-effect",
    OneEffectBody,
);
const OneEffectMachine = OneEffectProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const branch_then_arguments = [_]boundary.ir.EdgeArgument{};
const branch_else_arguments = [_]boundary.ir.EdgeArgument{};
const branch_then_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 1,
    .operation = .{ .constant = 0 },
}};
const branch_else_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 2,
    .operation = .{ .constant = 1 },
}};
const branch_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .branch = .{
            .condition = 0,
            .then_edge = .{
                .target = 1,
                .arguments = &branch_then_arguments,
            },
            .else_edge = .{
                .target = 2,
                .arguments = &branch_else_arguments,
            },
        } },
    },
    .{
        .id = 1,
        .instructions = &branch_then_instructions,
        .terminator = .{ .return_value = 1 },
    },
    .{
        .id = 2,
        .instructions = &branch_else_instructions,
        .terminator = .{ .return_value = 2 },
    },
};

const BranchBody = struct {
    pub const InitialArgs = bool;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{ @as(u32, 11), @as(u32, 22) };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "baseline-branch",
        .value_types = &.{ bool_type, u32_type, u32_type },
        .blocks = &branch_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const BranchProgram = boundary.program("baseline-branch", BranchBody);
const BranchDefinition = compiler.DefinitionFor(
    "baseline-branch",
    BranchBody,
);
const BranchMachine = BranchProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const loop_entry_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 0 }};
const loop_body_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 1 }};
const loop_done_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 1 }};
const loop_back_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 6 }};
const loop_header_instructions = [_]boundary.ir.Instruction{
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{ 1, 2 },
        .operation = .integer_less_than,
    },
};
const loop_body_instructions = [_]boundary.ir.Instruction{
    .{
        .kind = .constant,
        .result = 5,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{ 4, 5 },
        .operation = .integer_add,
    },
};
const loop_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &loop_entry_arguments,
        } },
    },
    .{
        .id = 1,
        .role = .loop_header,
        .parameters = &.{1},
        .instructions = &loop_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 3,
            .then_edge = .{
                .target = 2,
                .arguments = &loop_body_arguments,
            },
            .else_edge = .{
                .target = 3,
                .arguments = &loop_done_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .parameters = &.{4},
        .instructions = &loop_body_instructions,
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &loop_back_arguments,
        } },
    },
    .{
        .id = 3,
        .role = .terminal_handoff,
        .parameters = &.{7},
        .terminator = .{ .return_value = 7 },
    },
};

const LoopBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { arithmetic_overflow };
    pub const constants = .{ @as(u32, 3), @as(u32, 1) };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "baseline-loop",
        .value_types = &.{
            u32_type,
            u32_type,
            u32_type,
            bool_type,
            u32_type,
            u32_type,
            u32_type,
            u32_type,
        },
        .blocks = &loop_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const LoopProgram = boundary.program("baseline-loop", LoopBody);
const LoopDefinition = compiler.DefinitionFor("baseline-loop", LoopBody);
const LoopMachine = LoopProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});

const call_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 0 }};
const return_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const helper_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &call_arguments,
            },
            .continuation = .{
                .target = 2,
                .arguments = &return_arguments,
            },
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

const HelperBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "baseline-helper-call",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &helper_blocks,
        .entry = 0,
        .result_type = u32_type,
        .functions = &.{
            .{ .id = 0, .entry = 0, .result_type = u32_type },
            .{ .id = 1, .entry = 1, .result_type = u32_type },
        },
    };
};

const HelperProgram = boundary.program(
    "baseline-helper-call",
    HelperBody,
);
const HelperDefinition = compiler.DefinitionFor(
    "baseline-helper-call",
    HelperBody,
);
const HelperMachine = HelperProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

fn YieldBody(comptime kind: boundary.ir.SuspensionKind) type {
    return struct {
        const continuation_arguments = [_]boundary.ir.EdgeArgument{
            .{ .value = 0 },
        };
        const blocks = [_]boundary.ir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = kind,
                    .continuation = .{
                        .target = 1,
                        .arguments = &continuation_arguments,
                    },
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: boundary.ir.Program = .{
            .label = "baseline-yield",
            .value_types = &.{ u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const ExplicitBody = YieldBody(.explicit_yield);
const ExplicitProgram = boundary.program("baseline-explicit-yield", ExplicitBody);
const ExplicitDefinition = compiler.DefinitionFor(
    "baseline-explicit-yield",
    ExplicitBody,
);
const ExplicitMachine = ExplicitProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const CallerFuelBody = YieldBody(.caller_fuel);
const CallerFuelProgram = boundary.program(
    "baseline-caller-fuel",
    CallerFuelBody,
);
const CallerFuelDefinition = compiler.DefinitionFor(
    "baseline-caller-fuel",
    CallerFuelBody,
);
const CallerFuelMachine = CallerFuelProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

fn writeHex(writer: *std.Io.Writer, bytes: []const u8) !void {
    const alphabet = "0123456789abcdef";
    for (bytes) |byte| {
        try writer.writeByte(alphabet[byte >> 4]);
        try writer.writeByte(alphabet[byte & 0x0f]);
    }
}

fn writeDigest(writer: *std.Io.Writer, digest: [32]u8) !void {
    try writer.writeByte('"');
    try writeHex(writer, &digest);
    try writer.writeByte('"');
}

fn writeFixturePrefix(
    writer: *std.Io.Writer,
    name: []const u8,
    comptime Definition: type,
    comptime Machine: type,
) !void {
    try writer.print("{{\"name\":\"{s}\",\"program_semantic_digest\":", .{name});
    try writeDigest(writer, Definition.semantic_digest);
    try writer.writeAll(",\"machine_contract_digest\":");
    try writeDigest(writer, Machine.Manifest.machine_contract_digest);
    try writer.print(
        ",\"machine_abi\":{d},\"state_format\":\"ABL_RNF2\"," ++
            "\"state_format_version\":{d},\"options\":{{" ++
            "\"maximum_frames\":{d},\"maximum_state_bytes\":{d}," ++
            "\"maximum_machine_fuel\":{d}}}",
        .{
            Machine.abi_version,
            Machine.Manifest.state_image_format_version,
            Machine.Manifest.maximum_frames,
            Machine.Manifest.maximum_state_bytes,
            Machine.Manifest.maximum_machine_fuel,
        },
    );
}

fn writeState(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    comptime Machine: type,
    state: Machine.State,
) !void {
    const bytes = try Machine.encodeState(allocator, state);
    defer allocator.free(bytes);
    try writer.writeByte('"');
    try writeHex(writer, bytes);
    try writer.writeByte('"');
}

fn writeU32Value(writer: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try writer.writeByte('"');
    try writeHex(writer, &bytes);
    try writer.writeByte('"');
}

fn writeCanonicalValue(writer: *std.Io.Writer, value: anytype) !void {
    const Value = @TypeOf(value);
    var bytes: [boundary.schema.maximumEncodedSize(Value)]u8 = undefined;
    const length = try boundary.schema.encode(Value, value, &bytes);
    try writer.writeByte('"');
    try writeHex(writer, bytes[0..length]);
    try writer.writeByte('"');
}

fn writeRequestIdentity(
    writer: *std.Io.Writer,
    comptime Machine: type,
    request: Machine.Request,
) !void {
    var payload_bytes: [
        boundary.schema.maximumUnionPayloadSize(
            Machine.RequestValue,
        )
    ]u8 = undefined;
    const payload_length = try boundary.schema.encodeUnionPayload(
        Machine.RequestValue,
        request.value,
        &payload_bytes,
    );
    try writer.writeAll("{\"sequence\":");
    try writer.print("{d},\"constructor_id\":{d},\"site_ordinal\":{d},", .{
        request.identity.sequence,
        request.identity.constructor_id,
        request.identity.site_ordinal,
    });
    try writer.writeAll("\"machine_contract_digest\":");
    try writeDigest(writer, request.identity.machine_contract_digest);
    try writer.writeAll(",\"payload\":\"");
    try writeHex(writer, payload_bytes[0..payload_length]);
    try writer.writeByte('"');
    try writer.writeAll(",\"effect_site_digest\":");
    try writeDigest(writer, request.identity.effect_site_digest);
    try writer.writeAll(",\"payload_digest\":");
    try writeDigest(writer, request.identity.payload_digest);
    try writer.writeAll(",\"continuation_digest\":");
    try writeDigest(writer, request.identity.continuation_digest);
    try writer.writeAll(",\"identity_digest\":");
    try writeDigest(writer, request.identity.digest);
    try writer.writeByte('}');
}

fn writeU32EffectFixture(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime Definition: type,
    comptime Machine: type,
    initial_args: u32,
    response: u32,
) !void {
    try writeFixturePrefix(
        writer,
        name,
        Definition,
        Machine,
    );
    const state = try Machine.initialState(allocator, initial_args);
    defer Machine.deinitState(state);
    try writer.writeAll(",\"initial_args\":");
    try writeU32Value(writer, initial_args);
    try writer.writeAll(",\"states\":[");
    try writeState(writer, allocator, Machine, state);

    var request_fuel: u64 = 1;
    const request = switch (try Machine.step(state, &request_fuel)) {
        .request => |value| value,
        else => return error.ExpectedRequest,
    };
    try writer.writeByte(',');
    try writeState(writer, allocator, Machine, state);

    {
        const prepared = try Machine.prepareResume(state, request);
        defer Machine.deinitPreparedResume(prepared);
        try Machine.@"resume"(prepared, response);
    }
    try writer.writeByte(',');
    try writeState(writer, allocator, Machine, state);
    try writer.writeAll("],\"request\":");
    try writeRequestIdentity(writer, Machine, request);

    var result_fuel: u64 = 1;
    const result = switch (try Machine.step(state, &result_fuel)) {
        .done => |value| value,
        else => return error.ExpectedResult,
    };
    defer result.deinit();
    try writer.writeAll(",\"fuel\":[{\"before\":1,\"after\":");
    try writer.print("{d}}},{{\"before\":1,\"after\":{d}}}],", .{
        request_fuel,
        result_fuel,
    });
    try writer.writeAll("\"terminal\":{\"kind\":\"done\",\"bytes\":");
    try writeCanonicalValue(writer, result.value().*);
    try writer.writeAll("}}");
}

fn writeSimpleFixture(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime Definition: type,
    comptime Machine: type,
    initial_args: Machine.InitialArgs,
) !void {
    try writeFixturePrefix(writer, name, Definition, Machine);
    const state = try Machine.initialState(allocator, initial_args);
    defer Machine.deinitState(state);
    try writer.writeAll(",\"initial_args\":");
    try writeCanonicalValue(writer, initial_args);
    try writer.writeAll(",\"initial_state\":");
    try writeState(writer, allocator, Machine, state);
    try writer.writeAll(",\"events\":[");

    var first_event = true;
    var step_index: usize = 0;
    while (true) {
        const fuel_before: u64 = if (step_index == 0) 1 else 64;
        var fuel = fuel_before;
        const outcome = try Machine.step(state, &fuel);
        if (!first_event) try writer.writeByte(',');
        first_event = false;
        switch (outcome) {
            .yielded => {
                try writer.print(
                    "{{\"outcome\":\"yielded\",\"fuel_before\":{d}," ++
                        "\"fuel_after\":{d},\"state\":",
                    .{ fuel_before, fuel },
                );
                try writeState(writer, allocator, Machine, state);
                try writer.writeByte('}');
            },
            .done => |result| {
                defer result.deinit();
                try writer.print(
                    "{{\"outcome\":\"done\",\"fuel_before\":{d}," ++
                        "\"fuel_after\":{d},\"result\":",
                    .{ fuel_before, fuel },
                );
                try writeCanonicalValue(writer, result.value().*);
                try writer.writeAll("}]");
                try writer.writeAll(",\"terminal\":{\"kind\":\"done\",\"bytes\":");
                try writeCanonicalValue(writer, result.value().*);
                try writer.writeAll("}}");
                break;
            },
            .request => return error.UnexpectedRequest,
            .failed => return error.UnexpectedFailure,
        }
        step_index += 1;
        if (step_index > 16) return error.UnexpectedTransitionCount;
    }
}

fn decodeRejected(comptime Machine: type, bytes: []const u8) bool {
    const state = Machine.decodeState(std.heap.page_allocator, bytes) catch return true;
    Machine.deinitState(state);
    return false;
}

fn writeMalformedCases(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
) !void {
    const state = try OneEffectMachine.initialState(allocator, 5);
    defer OneEffectMachine.deinitState(state);
    const canonical = try OneEffectMachine.encodeState(
        allocator,
        state,
    );
    defer allocator.free(canonical);

    var wrong_magic = try allocator.dupe(u8, canonical);
    defer allocator.free(wrong_magic);
    wrong_magic[0] ^= 0xff;

    var wrong_digest = try allocator.dupe(u8, canonical);
    defer allocator.free(wrong_digest);
    wrong_digest[12] ^= 0xff;

    var wrong_constructor = try allocator.dupe(u8, canonical);
    defer allocator.free(wrong_constructor);
    @memset(wrong_constructor[68..72], 0xff);

    try writer.print(
        "[{{\"name\":\"wrong-magic\",\"rejected\":{}}}," ++
            "{{\"name\":\"truncated\",\"rejected\":{}}}," ++
            "{{\"name\":\"wrong-digest\",\"rejected\":{}}}," ++
            "{{\"name\":\"wrong-constructor\",\"rejected\":{}}}]",
        .{
            decodeRejected(OneEffectMachine, wrong_magic),
            decodeRejected(OneEffectMachine, canonical[0 .. canonical.len - 1]),
            decodeRejected(OneEffectMachine, wrong_digest),
            decodeRejected(OneEffectMachine, wrong_constructor),
        },
    );
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(
        "{\"format\":\"boundary-reification-baseline-v1\"," ++
            "\"boundary_version\":\"1.5.0\"," ++
            "\"boundary_commit\":\"ed4956b6229e039c72f3080dd60ddb94f58a56fc\"," ++
            "\"zig_version\":\"0.16.0\",\"fixtures\":[",
    );
    try writeU32EffectFixture(
        stdout,
        allocator,
        "one-effect",
        OneEffectDefinition,
        OneEffectMachine,
        7,
        9,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "branch",
        BranchDefinition,
        BranchMachine,
        true,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "loop",
        LoopDefinition,
        LoopMachine,
        0,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "helper-call-return",
        HelperDefinition,
        HelperMachine,
        17,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "explicit-yield",
        ExplicitDefinition,
        ExplicitMachine,
        19,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "caller-fuel-checkpoint",
        CallerFuelDefinition,
        CallerFuelMachine,
        23,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "portable-values",
        OperationsDefinition,
        operations_fixture.ReificationBaselineMachine,
        {},
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "local-effect-handler",
        HandlerDefinition,
        handler_fixture.ReificationBaselineMachine,
        41,
    );
    try stdout.writeByte(',');
    try writeU32EffectFixture(
        stdout,
        allocator,
        "effect-morphism",
        MorphismDefinition,
        morphism_fixture.ReificationBaselineMachine,
        7,
        11,
    );
    try stdout.writeByte(',');
    try writeSimpleFixture(
        stdout,
        allocator,
        "recursion",
        RecursionDefinition,
        recursion_fixture.ReificationBaselineMachine,
        3,
    );
    try stdout.writeAll("],\"malformed_state_cases\":");
    try writeMalformedCases(stdout, allocator);
    try stdout.writeAll("}\n");
    try stdout.flush();
}
