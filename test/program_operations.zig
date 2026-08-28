const cir = @import("control_ir");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Title = portable_value.Text(16);
const Digest = portable_value.Text(32);
const Item = struct {
    title: Title,
    score: u32,
};
const Items = portable_value.Vector(Item, 2);
const PureResult = struct {
    items: Items,
    digest: Digest,
    total: u32,
};

const title = Title.fromSlice("alpha") catch unreachable;
const value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .scalar = .u32 },
    .{ .schema = 1 },
    .{ .schema = 2 },
    .{ .schema = 2 },
    .{ .schema = 3 },
    .{ .schema = 3 },
    .{ .scalar = .u32 },
    .{ .scalar = .u32 },
    .{ .schema = 4 },
};
const instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .product_construct,
    },
    .{
        .kind = .pure,
        .result = 3,
        .operation = .vector_empty,
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 3, 2 },
        .operation = .vector_push,
    },
    .{
        .kind = .pure,
        .result = 5,
        .operation = .text_empty,
    },
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{ 5, 0 },
        .operation = .text_append,
    },
    .{
        .kind = .constant,
        .result = 7,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{ 1, 7 },
        .operation = .integer_add,
    },
    .{
        .kind = .pure,
        .result = 9,
        .operands = &.{ 4, 6, 8 },
        .operation = .product_construct,
    },
};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &instructions,
        .terminator = .{ .return_value = 9 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = PureResult;
    pub const Failure = enum {
        arithmetic_overflow,
        capacity_exceeded,
        invalid_index,
    };
    pub const contract_bytes = "pure-operation-algebra\x00v1";
    pub const constants = .{
        title,
        @as(u32, 7),
        @as(u32, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ Title, Item, Items, Digest, PureResult };
    pub const control_ir: cir.Program = .{
        .label = "pure-operation-algebra",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 4 },
    };
};

const Program = program_v2.program("pure-operation-algebra", Body);
const pure_options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 128,
};
const PureMachine = Program.compile(pure_options);
const PureImage = Program.image();
const PureProfile = Program.machineV2Profile(pure_options);

const MappedFailure = enum { mapped };
const mapped_failure_value_types = [_]cir.ValueType{
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
    .{ .schema = 0 },
    .{ .scalar = .u8 },
};
const mapped_failure_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{ 0, 1, 2 },
        .operation = .integer_add,
    },
};
const mapped_failure_blocks = [_]cir.Block{.{
    .id = 0,
    .instructions = &mapped_failure_instructions,
    .terminator = .{ .return_value = 3 },
}};
const MappedFailureBody = struct {
    pub const InitialArgs = void;
    pub const Result = u8;
    pub const Failure = MappedFailure;
    pub const constants = .{
        @as(u8, std.math.maxInt(u8)),
        @as(u8, 1),
        MappedFailure.mapped,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{MappedFailure};
    pub const control_ir: cir.Program = .{
        .label = "mapped-instruction-failure",
        .value_types = &mapped_failure_value_types,
        .blocks = &mapped_failure_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};
const MappedFailureProgram = program_v2.program(
    "mapped-instruction-failure",
    MappedFailureBody,
);
const MappedFailureImage = MappedFailureProgram.image();
const MappedFailureMachine = MappedFailureProgram.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 32,
});
const MappedFailureProfile = MappedFailureProgram.machineV2Profile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 32,
});

pub const ReificationBaselineBody = Body;
pub const ReificationBaselineProgram = Program;
pub const ReificationBaselineMachine = PureMachine;

test "compiled pure operations construct products vectors and text" {
    const state = try PureMachine.initialState(std.testing.allocator, {});
    defer PureMachine.deinitState(state);

    const before = try PureMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var insufficient_fuel: u64 = 10;
    try std.testing.expectEqual(
        PureMachine.Outcome.yielded,
        try PureMachine.step(state, &insufficient_fuel),
    );
    try std.testing.expectEqual(@as(u64, 10), insufficient_fuel);
    const after_yield = try PureMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(after_yield);
    try std.testing.expectEqualSlices(u8, before, after_yield);

    var fuel: u64 = 64;
    const done = switch (try PureMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();

    const result = done.value();
    try std.testing.expectEqual(@as(u32, 1), try result.items.len());
    const item = (try result.items.get(0)).?;
    try std.testing.expectEqualStrings("alpha", try item.title.slice());
    try std.testing.expectEqual(@as(u32, 7), item.score);
    try std.testing.expectEqualStrings("alpha", try result.digest.slice());
    try std.testing.expectEqual(@as(u32, 8), result.total);

    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&PureImage.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(program_image, &PureProfile.bytes, &workspace);
    var kernel_state: [4096]u8 = undefined;
    var invariant_scratch: [4096]u8 = undefined;
    const kernel_state_length = try kernel_v1.initial(
        image,
        &.{},
        &kernel_state,
        &invariant_scratch,
        &workspace,
    );
    var scratch: [8192]u8 = undefined;
    var kernel_output: [4096]u8 = undefined;
    var kernel_next_state: [4096]u8 = undefined;
    var kernel_insufficient_fuel: u64 = 10;
    const kernel_yielded = switch (try kernel_v1.step(
        image,
        kernel_state[0..kernel_state_length],
        &kernel_insufficient_fuel,
        &kernel_next_state,
        &kernel_output,
        &scratch,
        &workspace,
    )) {
        .yielded => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualSlices(
        u8,
        kernel_state[0..kernel_state_length],
        kernel_yielded,
    );
    try std.testing.expectEqual(@as(u64, 10), kernel_insufficient_fuel);

    var kernel_fuel: u64 = 64;
    const kernel_done = switch (try kernel_v1.step(
        image,
        kernel_state[0..kernel_state_length],
        &kernel_fuel,
        &kernel_next_state,
        &kernel_output,
        &scratch,
        &workspace,
    )) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const maximum_result_size = comptime portable_value.maximumEncodedSize(
        PureResult,
    );
    var direct_bytes: [maximum_result_size]u8 = undefined;
    const direct_length = try portable_value.encode(
        PureResult,
        result.*,
        &direct_bytes,
    );
    try std.testing.expectEqual(fuel, kernel_fuel);
    try std.testing.expectEqualSlices(
        u8,
        direct_bytes[0..direct_length],
        kernel_done,
    );
}

test "evaluator semantics v2 maps an instruction failure through explicit operands" {
    const projection = MappedFailureProgram.componentAdmission()
        .instructionFailureProjection(mapped_failure_instructions[3]);
    try std.testing.expectEqual(@as(usize, 2), projection.ordinary_operand_count);
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(MappedFailure.mapped)),
        projection.failure_tags[0],
    );
    try std.testing.expectEqual(
        image_v1.evaluator_semantics_v2,
        MappedFailureImage.evaluator_semantics_version,
    );
    try std.testing.expectEqual(
        image_v1.evaluator_semantics_v2,
        std.mem.readInt(u16, MappedFailureImage.bytes[10..12], .little),
    );

    const state = try MappedFailureMachine.initialState(std.testing.allocator, {});
    defer MappedFailureMachine.deinitState(state);
    var fuel: u64 = 32;
    switch (try MappedFailureMachine.step(state, &fuel)) {
        .failed => |failure| switch (failure) {
            .authored => |authored| try std.testing.expectEqual(
                MappedFailure.mapped,
                authored,
            ),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var workspace: image_v1.ValidationWorkspace = .{};
    const image = try image_v1.validateImage(
        &MappedFailureImage.bytes,
        &workspace,
    );
    const bound = try kernel_v1.bindMachineV2(
        image,
        &MappedFailureProfile.bytes,
        &workspace,
    );
    var kernel_state: [1024]u8 = undefined;
    var invariant_scratch: [1024]u8 = undefined;
    const state_length = try kernel_v1.initial(
        bound,
        &.{},
        &kernel_state,
        &invariant_scratch,
        &workspace,
    );
    var next_state: [1024]u8 = undefined;
    var output: [4]u8 = undefined;
    var scratch: [4096]u8 = undefined;
    var kernel_fuel: u64 = 32;
    const outcome = try kernel_v1.step(
        bound,
        kernel_state[0..state_length],
        &kernel_fuel,
        &next_state,
        &output,
        &scratch,
        &workspace,
    );
    const failure_bytes = switch (outcome) {
        .failed => |bytes| bytes,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(MappedFailure.mapped)),
        std.mem.readInt(u32, failure_bytes[0..4], .little),
    );
}

test "evaluator semantics v1 rejects explicit instruction failure operands" {
    var downgraded = MappedFailureImage.bytes;
    std.mem.writeInt(
        u16,
        downgraded[10..12],
        image_v1.evaluator_semantics_v1,
        .little,
    );
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidInstruction,
        image_v1.validateImage(&downgraded, &workspace),
    );
}

test "BPI1 rejects schema-invalid operation substitutions before execution" {
    var malformed = PureImage.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segment_offset: usize = @intCast(envelope.sections[7].offset);
    var cursor = segment_offset + 4;
    cursor += image_v1.segment_prefix_length + @as(usize, std.mem.readInt(
        u16,
        malformed[cursor + 10 ..][0..2],
        .little,
    )) * 2;
    const instruction_count = std.mem.readInt(
        u32,
        malformed[segment_offset + 4 + 12 ..][0..4],
        .little,
    );
    var replaced = false;
    for (0..instruction_count) |_| {
        const operation = std.mem.readInt(
            u16,
            malformed[cursor + 6 ..][0..2],
            .little,
        );
        if (operation == 3) {
            std.mem.writeInt(
                u16,
                malformed[cursor + 6 ..][0..2],
                21,
                .little,
            );
            replaced = true;
            break;
        }
        cursor += std.mem.readInt(
            u32,
            malformed[cursor..][0..4],
            .little,
        );
    }
    try std.testing.expect(replaced);
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidInstruction,
        image_v1.validateImage(&malformed, &workspace),
    );
}

test "BPI1 rejects constants made unreachable by instruction mutation" {
    var malformed = PureImage.bytes;
    const envelope = try image_v1.validateEnvelope(&malformed);
    const segment_offset: usize = @intCast(envelope.sections[7].offset);
    var cursor = segment_offset + 4;
    cursor += image_v1.segment_prefix_length + @as(usize, std.mem.readInt(
        u16,
        malformed[cursor + 10 ..][0..2],
        .little,
    )) * 2;
    const instruction_count = std.mem.readInt(
        u32,
        malformed[segment_offset + 4 + 12 ..][0..4],
        .little,
    );
    var replaced = false;
    for (0..instruction_count) |_| {
        const operation = std.mem.readInt(
            u16,
            malformed[cursor + 6 ..][0..2],
            .little,
        );
        const immediate = std.mem.readInt(
            u32,
            malformed[cursor + 12 ..][0..4],
            .little,
        );
        if (operation == 0 and immediate == 2) {
            std.mem.writeInt(
                u32,
                malformed[cursor + 12 ..][0..4],
                1,
                .little,
            );
            replaced = true;
            break;
        }
        cursor += std.mem.readInt(
            u32,
            malformed[cursor..][0..4],
            .little,
        );
    }
    try std.testing.expect(replaced);
    var workspace: image_v1.ValidationWorkspace = .{};
    try std.testing.expectError(
        error.InvalidConstant,
        image_v1.validateImage(&malformed, &workspace),
    );
}

const ConstantTitles = portable_value.Vector(Title, 2);
const ConstantResult = struct {
    title: Title,
    titles: ConstantTitles,
};

const dirty_constant = blk: {
    var result = ConstantResult{
        .title = Title.fromSlice("root") catch unreachable,
        .titles = ConstantTitles.empty(),
    };
    result.title.storage[15] = 0xa1;

    var item = Title.fromSlice("item") catch unreachable;
    item.storage[15] = 0xb2;
    result.titles.push(item) catch unreachable;

    var spare = Title.fromSlice("spare") catch unreachable;
    spare.storage[15] = 0xc3;
    result.titles.storage[1] = spare;
    break :blk result;
};

const constant_value_types = [_]cir.ValueType{
    .{ .schema = 0 },
};
const constant_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
};
const constant_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &constant_instructions,
        .terminator = .{ .return_value = 0 },
    },
};

const ConstantBody = struct {
    pub const InitialArgs = void;
    pub const Result = ConstantResult;
    pub const Failure = enum { unreachable_failure };
    pub const contract_bytes = "canonical-compiler-constant\x00v1";
    pub const constants = .{dirty_constant};
    pub const effect_sites = .{};
    pub const schema_types = .{ConstantResult};
    pub const control_ir: cir.Program = .{
        .label = "canonical-compiler-constant",
        .value_types = &constant_value_types,
        .blocks = &constant_blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};

const ConstantMachine = program_v2.program(
    "canonical-compiler-constant",
    ConstantBody,
).compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 8,
});

test "compiler constants materialize canonical portable representations" {
    const state = try ConstantMachine.initialState(std.testing.allocator, {});
    defer ConstantMachine.deinitState(state);

    var fuel: u64 = 8;
    const done = switch (try ConstantMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();

    const result = done.value();
    try std.testing.expectEqualStrings("root", try result.title.slice());
    try std.testing.expectEqual(@as(u8, 0), result.title.storage[15]);
    try std.testing.expectEqual(@as(u32, 1), try result.titles.len());
    try std.testing.expectEqualStrings(
        "item",
        try result.titles.storage[0].slice(),
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        result.titles.storage[0].storage[15],
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        try result.titles.storage[1].len(),
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        result.titles.storage[1].storage[15],
    );
}

const array_constant_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 1 },
    },
};
const array_constant_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &array_constant_instructions,
        .terminator = .{ .return_value = 0 },
    },
};

const ArrayConstantBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { unreachable_failure };
    pub const constants = [_]u32{ 13, 29 };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "homogeneous-array-constants",
        .value_types = &.{.{ .scalar = .u32 }},
        .blocks = &array_constant_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

const ArrayConstantMachine = program_v2.program(
    "homogeneous-array-constants",
    ArrayConstantBody,
).compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 8,
});

test "homogeneous array constants compile and retain indexed semantics" {
    const state = try ArrayConstantMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer ArrayConstantMachine.deinitState(state);

    var fuel: u64 = 8;
    const done = switch (try ArrayConstantMachine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 29), done.value().*);
}

const failure_blocks = [_]cir.Block{
    .{
        .id = 0,
        .terminator = .{ .fail = 7 },
    },
};

fn FailureBody(comptime FailureType: type) type {
    return struct {
        pub const InitialArgs = void;
        pub const Result = void;
        pub const Failure = FailureType;
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: cir.Program = .{
            .label = "non-dense-failure-tags",
            .value_types = &.{},
            .blocks = &failure_blocks,
            .entry = 0,
            .result_type = .{ .scalar = .unit },
        };
    };
}

const FailureA = enum(u16) {
    rejected = 7,
    other = 11,
};
const FailureB = enum(u16) {
    other = 7,
    rejected = 11,
};
const FailureMachineA =
    program_v2.program("non-dense-failure-tags", FailureBody(FailureA))
        .compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 8,
    });
const FailureMachineB =
    program_v2.program("non-dense-failure-tags", FailureBody(FailureB))
        .compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 1024,
        .maximum_machine_fuel = 8,
    });

test "non-dense failure tags retain name-bound runtime and identity semantics" {
    const state = try FailureMachineA.initialState(std.testing.allocator, {});
    defer FailureMachineA.deinitState(state);
    var fuel: u64 = 1;
    switch (try FailureMachineA.step(state, &fuel)) {
        .failed => |failure| switch (failure) {
            .authored => |authored| {
                try std.testing.expectEqual(
                    @as(u16, 7),
                    @intFromEnum(authored),
                );
                try std.testing.expectEqualStrings(
                    "rejected",
                    @tagName(authored),
                );
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(!std.mem.eql(
        u8,
        &FailureMachineA.Manifest.machine_contract_digest,
        &FailureMachineB.Manifest.machine_contract_digest,
    ));
}

const DynamicFailure = enum {
    rejected,
    cancelled,
};
const DynamicFailureArgs = struct {
    first: DynamicFailure,
    second: DynamicFailure,
};
const dynamic_failure_value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .schema = 1 },
    .{ .schema = 1 },
};
const dynamic_failure_instructions = [_]cir.Instruction{
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
};

fn DynamicFailureBody(comptime selected_value: cir.ValueId) type {
    return struct {
        const dynamic_failure_blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .instructions = &dynamic_failure_instructions,
                .terminator = .{ .fail_value = selected_value },
            },
        };

        pub const InitialArgs = DynamicFailureArgs;
        pub const Result = void;
        pub const Failure = DynamicFailure;
        pub const effect_sites = .{};
        pub const schema_types = .{ DynamicFailureArgs, DynamicFailure };
        pub const control_ir: cir.Program = .{
            .label = "value-driven-failure",
            .value_types = &dynamic_failure_value_types,
            .blocks = &dynamic_failure_blocks,
            .entry = 0,
            .result_type = .{ .scalar = .unit },
        };
    };
}

const FirstFailureMachine = program_v2.program(
    "value-driven-failure",
    DynamicFailureBody(1),
).compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 16,
});
const SecondFailureMachine = program_v2.program(
    "value-driven-failure",
    DynamicFailureBody(2),
).compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 16,
});

test "value-driven failure preserves runtime value and semantic identity" {
    const args: DynamicFailureArgs = .{
        .first = .rejected,
        .second = .cancelled,
    };

    const first_state = try FirstFailureMachine.initialState(
        std.testing.allocator,
        args,
    );
    defer FirstFailureMachine.deinitState(first_state);
    var first_fuel: u64 = 16;
    switch (try FirstFailureMachine.step(first_state, &first_fuel)) {
        .failed => |failure| switch (failure) {
            .authored => |authored| try std.testing.expectEqual(
                DynamicFailure.rejected,
                authored,
            ),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    const second_state = try SecondFailureMachine.initialState(
        std.testing.allocator,
        args,
    );
    defer SecondFailureMachine.deinitState(second_state);
    var second_fuel: u64 = 16;
    switch (try SecondFailureMachine.step(second_state, &second_fuel)) {
        .failed => |failure| switch (failure) {
            .authored => |authored| try std.testing.expectEqual(
                DynamicFailure.cancelled,
                authored,
            ),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    try std.testing.expect(!std.mem.eql(
        u8,
        &FirstFailureMachine.Manifest.machine_contract_digest,
        &SecondFailureMachine.Manifest.machine_contract_digest,
    ));
    try std.testing.expectEqual(@as(u32, 2), FirstFailureMachine.abi_version);
    try std.testing.expectEqual(@as(u32, 2), SecondFailureMachine.abi_version);
}

const NonDenseMethod = enum(u16) {
    get = 2,
    m_search = 47,
};

const enum_to_u32_value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .scalar = .u32 },
};
const enum_to_u32_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 1,
    .operands = &.{0},
    .operation = .enum_to_u32,
}};
const enum_to_u32_blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &enum_to_u32_instructions,
    .terminator = .{ .return_value = 1 },
}};

const EnumToU32Body = struct {
    pub const InitialArgs = NonDenseMethod;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{NonDenseMethod};
    pub const control_ir: cir.Program = .{
        .label = "enum-to-u32",
        .value_types = &enum_to_u32_value_types,
        .blocks = &enum_to_u32_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

const EnumToU32Machine = program_v2.program(
    "enum-to-u32",
    EnumToU32Body,
).compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 16,
});

test "enum_to_u32 projects the canonical portable enum tag" {
    inline for (.{ NonDenseMethod.get, NonDenseMethod.m_search }) |input| {
        const state = try EnumToU32Machine.initialState(
            std.testing.allocator,
            input,
        );
        defer EnumToU32Machine.deinitState(state);
        var fuel: u64 = 16;
        const done = switch (try EnumToU32Machine.step(state, &fuel)) {
            .done => |result| result,
            else => return error.TestUnexpectedResult,
        };
        defer done.deinit();
        try std.testing.expectEqual(
            @as(u32, @intCast(@intFromEnum(input))),
            done.value().*,
        );
    }
    try std.testing.expectEqual(@as(u32, 2), EnumToU32Machine.abi_version);
}
