const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const state_header_length: usize = 8 + 2 + 2 + 32 + 8 + 8 + 4 + 4;
const frame_header_length: usize = 4 + 4;
const first_environment_offset = state_header_length + frame_header_length;

const Choice = union(enum) {
    left: u32,
    right: u32,
};

const Left = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.constructor-invariant.left.v1";
    pub const Payload = Choice;
    pub const Resume = u32;
};

const Right = struct {
    pub const id: u32 = 1;
    pub const semantic_identity = "test.constructor-invariant.right.v1";
    pub const Payload = Choice;
    pub const Resume = u32;
};

const choice_type: cir.ValueType = .{ .schema = 0 };
const bool_type: cir.ValueType = .{ .scalar = .boolean };
const u32_type: cir.ValueType = .{ .scalar = .u32 };
const sum_value_types = [_]cir.ValueType{
    choice_type,
    bool_type,
    u32_type,
};
const sum_entry_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .sum_tag_is = 0 },
    },
};
const sum_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const sum_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &sum_entry_instructions,
        .terminator = .{ .branch = .{
            .condition = 1,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &sum_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &sum_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const SumBody = struct {
    pub const InitialArgs = Choice;
    pub const Result = u32;
    pub const Failure = enum {
        rejected,
    };
    pub const effect_sites = .{ Left, Right };
    pub const schema_types = .{Choice};
    pub const control_ir: cir.Program = .{
        .label = "sum-case-constructor-invariant",
        .value_types = &sum_value_types,
        .blocks = &sum_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const SumProgram = program_v2.program(
    "sum-case-constructor-invariant",
    SumBody,
);
const SumMachine = SumProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const Maybe = ?void;

const Some = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "test.constructor-invariant.some.v1";
    pub const Payload = Maybe;
    pub const Resume = u32;
};

const None = struct {
    pub const id: u32 = 1;
    pub const semantic_identity = "test.constructor-invariant.none.v1";
    pub const Payload = Maybe;
    pub const Resume = u32;
};

const maybe_type: cir.ValueType = .{ .schema = 0 };
const optional_value_types = [_]cir.ValueType{
    maybe_type,
    bool_type,
    u32_type,
};
const optional_entry_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .optional_is_some,
    },
};
const optional_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const optional_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &optional_entry_instructions,
        .terminator = .{ .branch = .{
            .condition = 1,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &optional_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &optional_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const OptionalBody = struct {
    pub const InitialArgs = Maybe;
    pub const Result = u32;
    pub const Failure = enum {
        rejected,
    };
    pub const effect_sites = .{ Some, None };
    pub const schema_types = .{Maybe};
    pub const control_ir: cir.Program = .{
        .label = "optional-case-constructor-invariant",
        .value_types = &optional_value_types,
        .blocks = &optional_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const OptionalProgram = program_v2.program(
    "optional-case-constructor-invariant",
    OptionalBody,
);
const OptionalMachine = OptionalProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const DerivedLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.derived-lookup.v1";
    pub const Payload = bool;
    pub const Resume = u32;
};

const derived_entry_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .copy,
        .result = 1,
        .operands = &.{0},
        .operation = .copy,
    },
    .{
        .kind = .compare_eq_zero,
        .result = 2,
        .operands = &.{1},
        .operation = .compare_eq_zero,
    },
};
const derived_else_arguments = [_]cir.EdgeArgument{.{ .value = 2 }};
const derived_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const derived_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &derived_entry_instructions,
        .terminator = .{ .branch = .{
            .condition = 2,
            .then_edge = .{ .target = 1 },
            .else_edge = .{
                .target = 2,
                .arguments = &derived_else_arguments,
            },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .return_value = 0 },
    },
    .{
        .id = 2,
        .parameters = &.{3},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{3},
            .continuation = .{
                .target = 3,
                .arguments = &derived_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{4},
        .terminator = .{ .return_value = 4 },
    },
};

const DerivedBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum {
        rejected,
    };
    pub const constants = .{@as(u32, 1)};
    pub const effect_sites = .{DerivedLookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "derived-predicate-constructor-invariant",
        .value_types = &.{
            u32_type,
            u32_type,
            bool_type,
            bool_type,
            u32_type,
        },
        .blocks = &derived_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const DerivedProgram = program_v2.program(
    "derived-predicate-constructor-invariant",
    DerivedBody,
);
const DerivedMachine = DerivedProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const ClosedExpressionLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.closed-expression.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const closed_expression_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .integer_add,
    },
    .{
        .kind = .compare_eq_zero,
        .result = 3,
        .operands = &.{2},
        .operation = .compare_eq_zero,
    },
};
const closed_expression_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const closed_expression_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &closed_expression_instructions,
        .terminator = .{ .branch = .{
            .condition = 3,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .return_value = 2 },
    },
    .{
        .id = 2,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{2},
            .continuation = .{
                .target = 3,
                .arguments = &closed_expression_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{4},
        .terminator = .{ .return_value = 4 },
    },
};

const ClosedExpressionBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected, arithmetic_overflow };
    pub const constants = .{@as(u32, 1)};
    pub const effect_sites = .{ClosedExpressionLookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "closed-expression-constructor-invariant",
        .value_types = &.{
            u32_type,
            u32_type,
            u32_type,
            bool_type,
            u32_type,
        },
        .blocks = &closed_expression_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const ClosedExpressionProgram = program_v2.program(
    "closed-expression-constructor-invariant",
    ClosedExpressionBody,
);
const ClosedExpressionMachine = ClosedExpressionProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const ConstantAlgebraicLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.algebraic-constant.v1";
    pub const Payload = Choice;
    pub const Resume = u32;
};

const algebraic_constant_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .sum_tag_is = 0 },
    },
};
const algebraic_constant_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const algebraic_constant_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &algebraic_constant_instructions,
        .terminator = .{ .branch = .{
            .condition = 1,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &algebraic_constant_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .terminator = .{ .fail = 0 },
    },
    .{
        .id = 3,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const ConstantAlgebraicBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{Choice{ .left = 7 }};
    pub const effect_sites = .{ConstantAlgebraicLookup};
    pub const schema_types = .{Choice};
    pub const control_ir: cir.Program = .{
        .label = "algebraic-constant-constructor-invariant",
        .value_types = &.{ choice_type, bool_type, u32_type },
        .blocks = &algebraic_constant_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const ConstantAlgebraicProgram = program_v2.program(
    "algebraic-constant-constructor-invariant",
    ConstantAlgebraicBody,
);
const ConstantAlgebraicMachine = ConstantAlgebraicProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const optional_constant_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .optional_is_some,
    },
};
const optional_constant_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const optional_constant_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &optional_constant_instructions,
        .terminator = .{ .branch = .{
            .condition = 1,
            .then_edge = .{ .target = 2 },
            .else_edge = .{ .target = 1 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &optional_constant_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .terminator = .{ .fail = 0 },
    },
    .{
        .id = 3,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const ConstantOptionalBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{@as(Maybe, null)};
    pub const effect_sites = .{Some};
    pub const schema_types = .{Maybe};
    pub const control_ir: cir.Program = .{
        .label = "optional-constant-constructor-invariant",
        .value_types = &.{ maybe_type, bool_type, u32_type },
        .blocks = &optional_constant_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const ConstantOptionalProgram = program_v2.program(
    "optional-constant-constructor-invariant",
    ConstantOptionalBody,
);
const ConstantOptionalMachine = ConstantOptionalProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

test "sum branches persist the source case and reject a forged local path" {
    const awaiting_left = &SumProgram.rnf.constructors[2];
    try std.testing.expectEqual(@as(usize, 1), awaiting_left.environment_len);
    try std.testing.expectEqual(
        @as(cir.ValueId, 0),
        awaiting_left.environment[0].value,
    );
    try std.testing.expectEqual(@as(usize, 1), awaiting_left.invariant_len);
    switch (awaiting_left.invariants[0]) {
        .sum_case => |term| {
            try std.testing.expectEqual(@as(cir.ValueId, 0), term.value);
            try std.testing.expectEqual(@as(u16, 0), term.case_index);
            try std.testing.expect(term.equal);
        },
        else => return error.TestUnexpectedResult,
    }

    const state = try SumMachine.initialState(
        std.testing.allocator,
        .{ .left = 7 },
    );
    defer SumMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try SumMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try SumMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    std.mem.writeInt(
        u32,
        forged[first_environment_offset..][0..4],
        1,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        SumMachine.decodeState(std.testing.allocator, forged),
    );
}

test "optional branches use the same canonical sum-case invariant" {
    const awaiting_some = &OptionalProgram.rnf.constructors[2];
    try std.testing.expectEqual(@as(usize, 1), awaiting_some.environment_len);
    try std.testing.expectEqual(
        @as(cir.ValueId, 0),
        awaiting_some.environment[0].value,
    );
    switch (awaiting_some.invariants[0]) {
        .sum_case => |term| {
            try std.testing.expectEqual(@as(u16, 1), term.case_index);
            try std.testing.expect(term.equal);
        },
        else => return error.TestUnexpectedResult,
    }

    const state = try OptionalMachine.initialState(
        std.testing.allocator,
        @as(Maybe, {}),
    );
    defer OptionalMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try OptionalMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try OptionalMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    forged[first_environment_offset] = 0;
    try std.testing.expectError(
        error.ProgramContractViolation,
        OptionalMachine.decodeState(std.testing.allocator, forged),
    );
}

test "derived live predicates retain their local defining equation" {
    const awaiting = blk: {
        for (DerivedProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 2 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    try std.testing.expectEqual(@as(usize, 3), awaiting.environment_len);
    try std.testing.expectEqual(
        @as(cir.ValueId, 0),
        awaiting.environmentFields()[0].value,
    );
    try std.testing.expectEqual(
        @as(cir.ValueId, 1),
        awaiting.environmentFields()[1].value,
    );
    try std.testing.expectEqual(
        @as(cir.ValueId, 3),
        awaiting.environmentFields()[2].value,
    );
    var saw_operand_fact = false;
    var saw_definition = false;
    var saw_copy = false;
    var saw_constant = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .integer_zero => |fact| {
            saw_operand_fact = fact.value == 1 and !fact.equal;
        },
        .integer_zero_result => |definition| {
            saw_definition =
                definition.result == 3 and definition.value == 1;
        },
        .value_copy => |definition| {
            saw_copy = definition.result == 1 and definition.source == 0;
        },
        .value_constant => |definition| {
            saw_constant = definition.result == 0 and
                switch (definition.contents) {
                    .unsigned => |value| value == 1,
                    else => false,
                };
        },
        else => {},
    };
    try std.testing.expect(saw_operand_fact);
    try std.testing.expect(saw_definition);
    try std.testing.expect(saw_copy);
    try std.testing.expect(saw_constant);

    const state = try DerivedMachine.initialState(std.testing.allocator, {});
    defer DerivedMachine.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try DerivedMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (request.value) {
        .s0 => |predicate| try std.testing.expect(!predicate),
    }
    const encoded = try DerivedMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged_copy = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged_copy);
    std.mem.writeInt(
        u32,
        forged_copy[first_environment_offset + @sizeOf(u32) ..][0..4],
        2,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        DerivedMachine.decodeState(std.testing.allocator, forged_copy),
    );

    const forged_constant = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged_constant);
    std.mem.writeInt(
        u32,
        forged_constant[first_environment_offset..][0..4],
        2,
        .little,
    );
    std.mem.writeInt(
        u32,
        forged_constant[first_environment_offset + @sizeOf(u32) ..][0..4],
        2,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        DerivedMachine.decodeState(std.testing.allocator, forged_constant),
    );
}

test "closed arithmetic definitions bind retained branch operands" {
    const awaiting = blk: {
        for (ClosedExpressionProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 2 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_add = false;
    var constant_count: usize = 0;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .integer_binary_result => |definition| {
            saw_add = definition.result == 2 and
                definition.left == 0 and
                definition.right == 1 and
                definition.operation == .add and
                definition.scalar_type == .u32;
        },
        .value_constant => |definition| {
            if ((definition.result == 0 or definition.result == 1) and
                switch (definition.contents) {
                    .unsigned => |value| value == 1,
                    else => false,
                }) constant_count += 1;
        },
        else => {},
    };
    try std.testing.expect(saw_add);
    try std.testing.expectEqual(@as(usize, 2), constant_count);

    const state = try ClosedExpressionMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer ClosedExpressionMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try ClosedExpressionMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try ClosedExpressionMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);

    var environment_offset = first_environment_offset;
    for (awaiting.environmentFields()) |field| {
        if (field.value == 2) {
            std.mem.writeInt(
                u32,
                forged[environment_offset..][0..4],
                3,
                .little,
            );
            break;
        }
        environment_offset += switch (field.value_type) {
            .scalar => |scalar| switch (scalar) {
                .boolean, .i8, .u8 => 1,
                .i16, .u16 => 2,
                .i32, .u32 => 4,
                .i64, .u64 => 8,
                .unit => 0,
            },
            .schema => return error.TestUnexpectedResult,
        };
    }
    try std.testing.expectError(
        error.ProgramContractViolation,
        ClosedExpressionMachine.decodeState(std.testing.allocator, forged),
    );
}

test "algebraic constants have canonical sum-case witnesses" {
    inline for (.{
        .{
            .Program = ConstantAlgebraicProgram,
            .Machine = ConstantAlgebraicMachine,
            .expected_case = @as(u16, 0),
        },
        .{
            .Program = ConstantOptionalProgram,
            .Machine = ConstantOptionalMachine,
            .expected_case = @as(u16, 0),
        },
    }) |witness| {
        var saw_constant = false;
        for (witness.Program.rnf.constructorSlice()) |constructor| {
            if (constructor.kind != .await_effect) continue;
            for (constructor.invariantTerms()) |term| switch (term) {
                .value_constant => |definition| {
                    saw_constant = switch (definition.contents) {
                        .sum_case => |case_index| case_index ==
                            witness.expected_case,
                        else => false,
                    };
                },
                else => {},
            };
        }
        try std.testing.expect(saw_constant);

        const state = try witness.Machine.initialState(
            std.testing.allocator,
            {},
        );
        defer witness.Machine.deinitState(state);
        var fuel: u64 = 8;
        _ = switch (try witness.Machine.step(state, &fuel)) {
            .request => |request| request,
            else => return error.TestUnexpectedResult,
        };
    }
}
