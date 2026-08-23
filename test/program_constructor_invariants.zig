const cir = @import("control_ir");
const compiler = @import("compiler");
const image_emit_v1 = @import("image_emit_v1");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const state_header_length: usize = 8 + 2 + 2 + 32 + 8 + 8 + 4 + 4;
const frame_header_length: usize = 4 + 4;
const first_environment_offset = state_header_length + frame_header_length;

test "BPI1 emits the admitted constructor invariant families" {
    inline for (.{
        SumBody,
        OptionalBody,
        DerivedBody,
        ClosedExpressionBody,
        ConstantAlgebraicBody,
        ConstantOptionalBody,
        WideProductBody,
        AggregateBranchBody,
        LiveThroughBody,
        ProductExtractBody,
        SumExtractBody,
        VectorLengthBody,
        BooleanConstantBody,
        LocalTextBody,
    }) |Body| {
        const Reified = compiler.ReifiedFor(Body.control_ir.label, Body);
        const Schemas = image_emit_v1.ProgramSchemaSet(Reified);
        const Constructors = image_emit_v1.ProgramConstructors(
            Reified,
            Schemas,
        );
        try std.testing.expect(Constructors.bytes.len > 4);
        const Program = program_v2.program(Body.control_ir.label, Body);
        const Image = Program.image();
        var workspace: image_v1.ValidationWorkspace = .{};
        _ = try image_v1.validateImage(&Image.bytes, &workspace);
    }
}

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
const SumImage = SumProgram.image();
const SumProfile = SumProgram.machineV2Profile(.{
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
const ClosedExpressionKernelMachine = ClosedExpressionProgram.kernelMachineV2(.{
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

const WideProduct = struct {
    first: u32,
    second: u32,
    third: u32,
    fourth: u32,
};

const WideProductLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.wide-product.v1";
    pub const Payload = WideProduct;
    pub const Resume = u32;
};

const wide_product_instructions = [_]cir.Instruction{
    .{ .kind = .constant, .result = 0, .operation = .{ .constant = 0 } },
    .{ .kind = .constant, .result = 1, .operation = .{ .constant = 1 } },
    .{ .kind = .constant, .result = 2, .operation = .{ .constant = 2 } },
    .{ .kind = .constant, .result = 3, .operation = .{ .constant = 3 } },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 0, 1, 2, 3 },
        .operation = .product_construct,
    },
};
const wide_product_edge_arguments = [_]cir.EdgeArgument{.{ .value = 4 }};
const wide_product_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const wide_product_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &wide_product_instructions,
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &wide_product_edge_arguments,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{5},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{5},
            .continuation = .{
                .target = 2,
                .arguments = &wide_product_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{6},
        .terminator = .{ .return_value = 6 },
    },
};

const WideProductBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{
        @as(u32, 1),
        @as(u32, 2),
        @as(u32, 3),
        @as(u32, 4),
    };
    pub const effect_sites = .{WideProductLookup};
    pub const schema_types = .{WideProduct};
    pub const control_ir: cir.Program = .{
        .label = "wide-product-constructor-invariant",
        .value_types = &.{
            u32_type,
            u32_type,
            u32_type,
            u32_type,
            cir.ValueType{ .schema = 0 },
            cir.ValueType{ .schema = 0 },
            u32_type,
        },
        .blocks = &wide_product_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const WideProductProgram = program_v2.program(
    "wide-product-constructor-invariant",
    WideProductBody,
);
const WideProductMachine = WideProductProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});
const WideProductKernelMachine = WideProductProgram.kernelMachineV2(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});

const AggregateBranchInput = struct {
    selected: bool,
    retained: u32,
};

const AggregateBranchLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.aggregate-branch.v1";
    pub const Payload = AggregateBranchInput;
    pub const Resume = u32;
};

const aggregate_branch_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 1,
    .operands = &.{0},
    .operation = .{ .product_extract = 0 },
}};
const aggregate_branch_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const aggregate_branch_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &aggregate_branch_instructions,
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
                .arguments = &aggregate_branch_resume_arguments,
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

const AggregateBranchBody = struct {
    pub const InitialArgs = AggregateBranchInput;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{AggregateBranchLookup};
    pub const schema_types = .{AggregateBranchInput};
    pub const control_ir: cir.Program = .{
        .label = "aggregate-branch-constructor-invariant",
        .value_types = &.{
            cir.ValueType{ .schema = 0 },
            bool_type,
            u32_type,
        },
        .blocks = &aggregate_branch_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const AggregateBranchProgram = program_v2.program(
    "aggregate-branch-constructor-invariant",
    AggregateBranchBody,
);
const AggregateBranchMachine = AggregateBranchProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const LiveThroughLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.live-through.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const live_through_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const live_through_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const live_through_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &live_through_instructions,
        .terminator = .{ .jump = .{ .target = 1 } },
    },
    .{
        .id = 1,
        .role = .loop_header,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 2,
                .arguments = &live_through_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const LiveThroughBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{@as(u32, 7)};
    pub const effect_sites = .{LiveThroughLookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "live-through-constructor-invariant",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &live_through_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const LiveThroughProgram = program_v2.program(
    "live-through-constructor-invariant",
    LiveThroughBody,
);
const LiveThroughMachine = LiveThroughProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const yield_live_through_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const yield_live_through_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &yield_live_through_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{ .target = 1 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .return_value = 0 },
    },
};

const YieldLiveThroughBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{@as(u32, 7)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "yield-live-through-constructor-invariant",
        .value_types = &.{u32_type},
        .blocks = &yield_live_through_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const YieldLiveThroughProgram = program_v2.program(
    "yield-live-through-constructor-invariant",
    YieldLiveThroughBody,
);
const YieldLiveThroughMachine = YieldLiveThroughProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const RetainedProduct = struct {
    selected: u32,
    retained: u32,
};

const ProductLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.product-extract.v1";
    pub const Payload = RetainedProduct;
    pub const Resume = u32;
};

const product_type: cir.ValueType = .{ .schema = 0 };
const product_extract_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .compare_eq_zero,
        .result = 2,
        .operands = &.{1},
        .operation = .compare_eq_zero,
    },
};
const product_extract_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const product_extract_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &product_extract_instructions,
        .terminator = .{ .branch = .{
            .condition = 2,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .fail = 0 },
    },
    .{
        .id = 2,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &product_extract_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{3},
        .terminator = .{ .return_value = 3 },
    },
};

const ProductExtractBody = struct {
    pub const InitialArgs = RetainedProduct;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ProductLookup};
    pub const schema_types = .{RetainedProduct};
    pub const control_ir: cir.Program = .{
        .label = "product-extract-constructor-invariant",
        .value_types = &.{ product_type, u32_type, bool_type, u32_type },
        .blocks = &product_extract_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const ProductExtractProgram = program_v2.program(
    "product-extract-constructor-invariant",
    ProductExtractBody,
);
const ProductExtractMachine = ProductExtractProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const SumExtractLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.sum-extract.v1";
    pub const Payload = Choice;
    pub const Resume = u32;
};

const sum_extract_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .sum_extract = 0 },
    },
    .{
        .kind = .compare_eq_zero,
        .result = 2,
        .operands = &.{1},
        .operation = .compare_eq_zero,
    },
};
const sum_extract_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const sum_extract_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &sum_extract_instructions,
        .terminator = .{ .branch = .{
            .condition = 2,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .fail = 0 },
    },
    .{
        .id = 2,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &sum_extract_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{3},
        .terminator = .{ .return_value = 3 },
    },
};

const SumExtractBody = struct {
    pub const InitialArgs = Choice;
    pub const Result = u32;
    pub const Failure = enum { rejected, invalid_variant };
    pub const effect_sites = .{SumExtractLookup};
    pub const schema_types = .{Choice};
    pub const control_ir: cir.Program = .{
        .label = "sum-extract-constructor-invariant",
        .value_types = &.{ choice_type, u32_type, bool_type, u32_type },
        .blocks = &sum_extract_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const SumExtractProgram = program_v2.program(
    "sum-extract-constructor-invariant",
    SumExtractBody,
);
const SumExtractMachine = SumExtractProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const LengthVector = portable_value.Vector(u32, 4);

const VectorLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.vector-length.v1";
    pub const Payload = LengthVector;
    pub const Resume = u32;
};

const vector_type: cir.ValueType = .{ .schema = 0 };
const vector_length_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .vector_length,
    },
    .{
        .kind = .compare_eq_zero,
        .result = 2,
        .operands = &.{1},
        .operation = .compare_eq_zero,
    },
};
const vector_length_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const vector_length_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &vector_length_instructions,
        .terminator = .{ .branch = .{
            .condition = 2,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .terminator = .{ .fail = 0 },
    },
    .{
        .id = 2,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 3,
                .arguments = &vector_length_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{3},
        .terminator = .{ .return_value = 3 },
    },
};

const VectorLengthBody = struct {
    pub const InitialArgs = LengthVector;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{VectorLookup};
    pub const schema_types = .{LengthVector};
    pub const control_ir: cir.Program = .{
        .label = "vector-length-constructor-invariant",
        .value_types = &.{ vector_type, u32_type, bool_type, u32_type },
        .blocks = &vector_length_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const VectorLengthProgram = program_v2.program(
    "vector-length-constructor-invariant",
    VectorLengthBody,
);
const VectorLengthMachine = VectorLengthProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

fn BoundedLengthWitness(
    comptime Bounded: type,
    comptime operation: cir.InstructionOperation,
    comptime label: []const u8,
    comptime site_identity: []const u8,
) type {
    return struct {
        const Lookup = struct {
            pub const id: u32 = 0;
            pub const semantic_identity = site_identity;
            pub const Payload = Bounded;
            pub const Resume = u32;
        };
        const instructions = [_]cir.Instruction{
            .{
                .kind = .pure,
                .result = 1,
                .operands = &.{0},
                .operation = operation,
            },
            .{
                .kind = .compare_eq_zero,
                .result = 2,
                .operands = &.{1},
                .operation = .compare_eq_zero,
            },
        };
        const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .instructions = &instructions,
                .terminator = .{ .branch = .{
                    .condition = 2,
                    .then_edge = .{ .target = 1 },
                    .else_edge = .{ .target = 2 },
                } },
            },
            .{ .id = 1, .terminator = .{ .fail = 0 } },
            .{
                .id = 2,
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{0},
                    .continuation = .{
                        .target = 3,
                        .arguments = &resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 3,
                .parameters = &.{3},
                .terminator = .{ .return_value = 3 },
            },
        };
        pub const Body = struct {
            pub const InitialArgs = Bounded;
            pub const Result = u32;
            pub const Failure = enum { rejected };
            pub const effect_sites = .{Lookup};
            pub const schema_types = .{Bounded};
            pub const control_ir: cir.Program = .{
                .label = label,
                .value_types = &.{ vector_type, u32_type, bool_type, u32_type },
                .blocks = &blocks,
                .entry = 0,
                .result_type = u32_type,
            };
        };
        pub const Program = program_v2.program(label, Body);
        pub const Machine = Program.compile(.{
            .maximum_frames = 4,
            .maximum_state_bytes = 4096,
            .maximum_machine_fuel = 32,
        });
    };
}

const TextLengthWitness = BoundedLengthWitness(
    portable_value.Text(8),
    .text_length,
    "text-length-constructor-invariant",
    "test.constructor-invariant.text-length.v1",
);
const BytesLengthWitness = BoundedLengthWitness(
    portable_value.Bytes(8),
    .bytes_length,
    "bytes-length-constructor-invariant",
    "test.constructor-invariant.bytes-length.v1",
);

const BooleanConstantLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.boolean-constant.v1";
    pub const Payload = bool;
    pub const Resume = u32;
};

const boolean_constant_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 0,
        .operation = .{ .constant = 0 },
    },
};
const boolean_constant_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const boolean_constant_blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &boolean_constant_instructions,
        .terminator = .{ .branch = .{
            .condition = 0,
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
                .arguments = &boolean_constant_resume_arguments,
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
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const BooleanConstantBody = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{true};
    pub const effect_sites = .{BooleanConstantLookup};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "boolean-constant-constructor-invariant",
        .value_types = &.{ bool_type, u32_type },
        .blocks = &boolean_constant_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const BooleanConstantProgram = program_v2.program(
    "boolean-constant-constructor-invariant",
    BooleanConstantBody,
);
const BooleanConstantMachine = BooleanConstantProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const LocalText = portable_value.Text(8);

const LocalTextLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity =
        "test.constructor-invariant.target-edge-text.v1";
    pub const Payload = LocalText;
    pub const Resume = u32;
};

const local_text_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .text_append_scalar,
    },
};
const local_text_edge_arguments = [_]cir.EdgeArgument{.{ .value = 2 }};
const local_text_resume_arguments = [_]cir.EdgeArgument{.@"resume"};
const local_text_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &local_text_instructions,
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &local_text_edge_arguments,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{3},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{3},
            .continuation = .{
                .target = 2,
                .arguments = &local_text_resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{4},
        .terminator = .{ .return_value = 4 },
    },
};

const LocalTextBody = struct {
    pub const InitialArgs = LocalText;
    pub const Result = u32;
    pub const Failure = enum { rejected, capacity_exceeded, invalid_utf8 };
    pub const constants = .{@as(u32, 'b')};
    pub const effect_sites = .{LocalTextLookup};
    pub const schema_types = .{LocalText};
    pub const control_ir: cir.Program = .{
        .label = "local-text-constructor-invariant",
        .value_types = &.{
            cir.ValueType{ .schema = 0 },
            u32_type,
            cir.ValueType{ .schema = 0 },
            cir.ValueType{ .schema = 0 },
            u32_type,
        },
        .blocks = &local_text_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const LocalTextProgram = program_v2.program(
    "local-text-constructor-invariant",
    LocalTextBody,
);
const LocalTextMachine = LocalTextProgram.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

const TargetEdgeAlgebraicKind = enum { sum, optional };

fn TargetEdgeAlgebraicProgram(
    comptime kind: TargetEdgeAlgebraicKind,
) type {
    return struct {
        const Constructed = if (kind == .sum) Choice else ?u32;

        const Lookup = struct {
            pub const id: u32 = 0;
            pub const semantic_identity = if (kind == .sum)
                "test.constructor-invariant.target-edge-sum.v1"
            else
                "test.constructor-invariant.target-edge-optional.v1";
            pub const Payload = Constructed;
            pub const Resume = u32;
        };

        const instructions = [_]cir.Instruction{.{
            .kind = .pure,
            .result = 1,
            .operands = &.{0},
            .operation = if (kind == .sum)
                .{ .sum_construct = 0 }
            else
                .optional_some,
        }};
        const edge_arguments = [_]cir.EdgeArgument{.{ .value = 1 }};
        const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .instructions = &instructions,
                .terminator = .{ .jump = .{
                    .target = 1,
                    .arguments = &edge_arguments,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{2},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{2},
                    .continuation = .{
                        .target = 2,
                        .arguments = &resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 2,
                .parameters = &.{3},
                .terminator = .{ .return_value = 3 },
            },
        };

        const Body = struct {
            pub const InitialArgs = u32;
            pub const Result = u32;
            pub const Failure = enum { rejected };
            pub const effect_sites = .{Lookup};
            pub const schema_types = .{Constructed};
            pub const control_ir: cir.Program = .{
                .label = if (kind == .sum)
                    "target-edge-sum-construction"
                else
                    "target-edge-optional-construction",
                .value_types = &.{
                    u32_type,
                    cir.ValueType{ .schema = 0 },
                    cir.ValueType{ .schema = 0 },
                    u32_type,
                },
                .blocks = &blocks,
                .entry = 0,
                .result_type = u32_type,
            };
        };

        pub const Program = program_v2.program(Body.control_ir.label, Body);
        pub const Machine = Program.compile(.{
            .maximum_frames = 4,
            .maximum_state_bytes = 4096,
            .maximum_machine_fuel = 32,
        });
    };
}

const TargetEdgeSum = TargetEdgeAlgebraicProgram(.sum);
const TargetEdgeOptional = TargetEdgeAlgebraicProgram(.optional);

fn ClassificationOnlyProgram(comptime role: cir.BlockRole) type {
    return struct {
        const entry_instructions = [_]cir.Instruction{
            .{
                .kind = .constant,
                .result = 0,
                .operation = .{ .constant = 0 },
            },
        };
        const edge_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
        const blocks = [_]cir.Block{
            .{
                .id = 0,
                .instructions = &entry_instructions,
                .terminator = .{ .jump = .{
                    .target = 1,
                    .arguments = &edge_arguments,
                } },
            },
            .{
                .id = 1,
                .role = role,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };
        const Body = struct {
            pub const InitialArgs = void;
            pub const Result = u32;
            pub const Failure = enum { rejected };
            pub const constants = .{@as(u32, 7)};
            pub const effect_sites = .{};
            pub const schema_types = .{};
            pub const control_ir: cir.Program = .{
                .label = "classification-only-identity",
                .value_types = &.{ u32_type, u32_type },
                .blocks = &blocks,
                .entry = 0,
                .result_type = u32_type,
            };
        };
        pub const Program = program_v2.program(
            "classification-only-identity",
            Body,
        );
        pub const Machine = Program.compile(.{
            .maximum_frames = 4,
            .maximum_state_bytes = 4096,
            .maximum_machine_fuel = 32,
        });
    };
}

const SegmentClassification = ClassificationOnlyProgram(.segment);
const LoopClassification = ClassificationOnlyProgram(.loop_header);

test "parked block entry validates in target coordinates" {
    const transition = blk: {
        for (SegmentClassification.Program.rnf.entryTransitionSlice()) |candidate| {
            if (candidate.source_block == 0 and
                candidate.edge_kind == .jump and
                candidate.target_block == 1)
            {
                break :blk candidate;
            }
        }
        return error.TestUnexpectedResult;
    };
    const parked = &SegmentClassification.Program.rnf.constructors[
        transition.constructor_id
    ];
    try std.testing.expectEqual(@as(usize, 1), parked.environment_len);
    try std.testing.expectEqual(@as(cir.ValueId, 1), parked.environment[0].value);

    var saw_edge_definition = false;
    var saw_historical_edge_copy = false;
    for (parked.invariantTerms()) |term| switch (term) {
        .value_constant => |definition| {
            saw_edge_definition = definition.result == 1 and switch (definition.contents) {
                .unsigned => |value| value == 7,
                else => false,
            };
        },
        .value_copy => saw_historical_edge_copy = true,
        else => {},
    };
    try std.testing.expect(saw_edge_definition);
    try std.testing.expect(!saw_historical_edge_copy);

    const state = try SegmentClassification.Machine.initialState(
        std.testing.allocator,
        {},
    );
    defer SegmentClassification.Machine.deinitState(state);
    var caller_fuel: u64 = 2;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try SegmentClassification.Machine.step(
            state,
            &caller_fuel,
        )),
    );
    const encoded = try SegmentClassification.Machine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset..][0..4],
        8,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        SegmentClassification.Machine.decodeState(
            std.testing.allocator,
            forged,
        ),
    );
}

test "sum branches persist the source case and reject a forged local path" {
    const awaiting_left = blk: {
        for (SumProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.kind == .await_effect and
                constructor.source_block == 1)
            {
                break :blk constructor;
            }
        }
        return error.TestUnexpectedResult;
    };
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
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&SumImage.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(program_image, &SumProfile.bytes);
    try std.testing.expectError(
        error.InvalidState,
        kernel_v1.validateState(image, forged, &workspace),
    );
}

test "unfunded kernel step defers deep environment validation" {
    const state = try SumMachine.initialState(
        std.testing.allocator,
        .{ .left = 7 },
    );
    defer SumMachine.deinitState(state);
    const encoded = try SumMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const malformed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed);
    std.mem.writeInt(
        u32,
        malformed[first_environment_offset..][0..4],
        2,
        .little,
    );
    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&SumImage.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(program_image, &SumProfile.bytes);
    var fuel: u64 = 0;
    var output_state: [4096]u8 = undefined;
    var output_value: [4096]u8 = undefined;
    var scratch: [8192]u8 = undefined;
    const yielded = switch (try kernel_v1.step(
        image,
        malformed,
        &fuel,
        &output_state,
        &output_value,
        &scratch,
        &workspace,
    )) {
        .yielded => |bytes| bytes,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualSlices(u8, malformed, yielded);
    try std.testing.expectEqual(@as(u64, 0), fuel);
}

test "public resume consumes only preallocated response authority" {
    try std.testing.expect(!@hasDecl(SumMachine, "commitPreparedResume"));
    const resume_info = @typeInfo(@TypeOf(SumMachine.@"resume")).@"fn";
    try std.testing.expectEqual(@as(usize, 2), resume_info.params.len);
    try std.testing.expect(resume_info.params[0].type.? ==
        SumMachine.PreparedResume);

    const state = try SumMachine.initialState(
        std.testing.allocator,
        .{ .left = 7 },
    );
    defer SumMachine.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try SumMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const prepared_resume = try SumMachine.prepareResume(state, request);
    defer SumMachine.deinitPreparedResume(prepared_resume);
    try SumMachine.@"resume"(prepared_resume, @as(u32, 11));
    try std.testing.expectError(
        error.ProgramContractViolation,
        SumMachine.@"resume"(prepared_resume, @as(u32, 11)),
    );
}

test "optional branches use the same canonical sum-case invariant" {
    const awaiting_some = blk: {
        for (OptionalProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.kind == .await_effect and
                constructor.source_block == 1)
            {
                break :blk constructor;
            }
        }
        return error.TestUnexpectedResult;
    };
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
    var saw_constant = false;
    var saw_historical_edge_copy = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .integer_zero => |fact| {
            saw_operand_fact = fact.value == 1 and !fact.equal;
        },
        .integer_zero_result => |definition| {
            saw_definition =
                definition.result == 3 and definition.value == 1;
        },
        .value_constant => |definition| {
            saw_constant = definition.result == 0 and
                switch (definition.contents) {
                    .unsigned => |value| value == 1,
                    else => false,
                };
        },
        .value_copy => |definition| {
            saw_historical_edge_copy = definition.result == 3 and
                definition.source == 2;
        },
        else => {},
    };
    try std.testing.expect(saw_operand_fact);
    try std.testing.expect(saw_definition);
    try std.testing.expect(saw_constant);
    try std.testing.expect(!saw_historical_edge_copy);

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
    try std.testing.expectError(
        error.ProgramContractViolation,
        ClosedExpressionKernelMachine.decodeState(
            std.testing.allocator,
            forged,
        ),
    );
}

test "payload-bearing algebraic constants retain executable definitions" {
    const awaiting = blk: {
        for (ConstantAlgebraicProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.kind == .await_effect) break :blk constructor;
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .instruction_result => |definition| {
            saw_definition = definition.result == 0 and
                definition.definition == 0 and
                definition.operand_count == 0;
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const state = try ConstantAlgebraicMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer ConstantAlgebraicMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try ConstantAlgebraicMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try ConstantAlgebraicMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset + 4 ..][0..4],
        8,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        ConstantAlgebraicMachine.decodeState(std.testing.allocator, forged),
    );
}

test "payload-free algebraic constants retain canonical case witnesses" {
    var saw_constant = false;
    for (ConstantOptionalProgram.rnf.constructorSlice()) |constructor| {
        if (constructor.kind != .await_effect) continue;
        for (constructor.invariantTerms()) |term| switch (term) {
            .value_constant => |definition| {
                saw_constant = switch (definition.contents) {
                    .sum_case => |case_index| case_index == 0,
                    else => false,
                };
            },
            else => {},
        };
    }
    try std.testing.expect(saw_constant);
}

test "wide product definitions survive target-edge projection" {
    const target_entry = blk: {
        for (WideProductProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 1 and
                constructor.origin == .block_entry)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (target_entry.invariantTerms()) |term| switch (term) {
        .instruction_result => |definition| {
            saw_definition = definition.result == 5 and
                definition.definition == 4 and
                definition.operand_count == 4 and
                std.mem.eql(
                    cir.ValueId,
                    definition.operands[0..4],
                    &.{ 0, 1, 2, 3 },
                );
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const state = try WideProductMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer WideProductMachine.deinitState(state);
    var fuel: u64 = 6;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try WideProductMachine.step(state, &fuel)),
    );
    const encoded = try WideProductMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset + 16 ..][0..4],
        9,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        WideProductMachine.decodeState(std.testing.allocator, forged),
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        WideProductKernelMachine.decodeState(std.testing.allocator, forged),
    );
}

test "predecessor-defined live-through values retain local definitions" {
    const target_entry = blk: {
        for (LiveThroughProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 1 and
                constructor.origin == .block_entry)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (target_entry.invariantTerms()) |term| switch (term) {
        .value_constant => |definition| {
            saw_definition = definition.result == 0 and
                switch (definition.contents) {
                    .unsigned => |value| value == 7,
                    else => false,
                };
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const state = try LiveThroughMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer LiveThroughMachine.deinitState(state);
    var fuel: u64 = 2;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try LiveThroughMachine.step(state, &fuel)),
    );
    const encoded = try LiveThroughMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset..][0..4],
        8,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        LiveThroughMachine.decodeState(std.testing.allocator, forged),
    );
}

test "explicit yields finalize live-through definitions locally" {
    const yielded = blk: {
        for (YieldLiveThroughProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.kind == .caller_fuel_yield and
                constructor.origin == .suspension)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (yielded.invariantTerms()) |term| switch (term) {
        .value_constant => |definition| {
            saw_definition = definition.result == 0 and
                switch (definition.contents) {
                    .unsigned => |value| value == 7,
                    else => false,
                };
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const state = try YieldLiveThroughMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer YieldLiveThroughMachine.deinitState(state);
    var fuel: u64 = 8;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try YieldLiveThroughMachine.step(state, &fuel)),
    );
    const encoded = try YieldLiveThroughMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset..][0..4],
        8,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        YieldLiveThroughMachine.decodeState(std.testing.allocator, forged),
    );
}

test "aggregate-derived branch booleans retain executable definitions" {
    const awaiting = blk: {
        for (AggregateBranchProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.kind == .await_effect) break :blk constructor;
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .instruction_result => |definition| {
            saw_definition = definition.result == 1 and
                definition.definition == 1 and
                definition.operand_count == 1 and
                definition.operands[0] == 0;
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const state = try AggregateBranchMachine.initialState(
        std.testing.allocator,
        .{ .selected = true, .retained = 9 },
    );
    defer AggregateBranchMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try AggregateBranchMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try AggregateBranchMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    forged[first_environment_offset] = 0;
    try std.testing.expectError(
        error.ProgramContractViolation,
        AggregateBranchMachine.decodeState(std.testing.allocator, forged),
    );
}

test "retained product extracts are authenticated locally" {
    const awaiting = blk: {
        for (ProductExtractProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 2 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_extract = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .product_extract_result => |definition| {
            saw_extract = definition.result == 1 and
                definition.product == 0 and
                definition.field_index == 0;
        },
        else => {},
    };
    try std.testing.expect(saw_extract);

    const state = try ProductExtractMachine.initialState(
        std.testing.allocator,
        .{ .selected = 1, .retained = 9 },
    );
    defer ProductExtractMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try ProductExtractMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try ProductExtractMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset + 8 ..][0..4],
        2,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        ProductExtractMachine.decodeState(std.testing.allocator, forged),
    );
}

test "retained sum extracts are authenticated locally" {
    const awaiting = blk: {
        for (SumExtractProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 2 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_extract = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .sum_extract_result => |definition| {
            saw_extract = definition.result == 1 and
                definition.sum == 0 and
                definition.case_index == 0;
        },
        else => {},
    };
    try std.testing.expect(saw_extract);

    const state = try SumExtractMachine.initialState(
        std.testing.allocator,
        .{ .left = 1 },
    );
    defer SumExtractMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try SumExtractMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try SumExtractMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset + 8 ..][0..4],
        2,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        SumExtractMachine.decodeState(std.testing.allocator, forged),
    );
}

test "Boolean constants retain canonical definition witnesses" {
    const awaiting = blk: {
        for (BooleanConstantProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 1 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_constant = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .value_constant => |definition| {
            saw_constant = definition.result == 0 and
                switch (definition.contents) {
                    .boolean => |contents| contents,
                    else => false,
                };
        },
        else => {},
    };
    try std.testing.expect(saw_constant);

    const state = try BooleanConstantMachine.initialState(
        std.testing.allocator,
        {},
    );
    defer BooleanConstantMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try BooleanConstantMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try BooleanConstantMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    forged[first_environment_offset] = 0;
    try std.testing.expectError(
        error.ProgramContractViolation,
        BooleanConstantMachine.decodeState(std.testing.allocator, forged),
    );
}

test "target-edge Text values retain executable source definitions" {
    const awaiting = blk: {
        for (LocalTextProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 1 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .instruction_result => |definition| {
            saw_definition = definition.result == 3 and
                definition.definition == 2 and
                definition.operand_count == 2 and
                definition.operands[0] == 0 and
                definition.operands[1] == 1;
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const initial = try LocalText.fromSlice("a");
    const state = try LocalTextMachine.initialState(
        std.testing.allocator,
        initial,
    );
    defer LocalTextMachine.deinitState(state);
    var fuel: u64 = 32;
    _ = switch (try LocalTextMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try LocalTextMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    const source_size = try portable_value.encodedSize(LocalText, initial);
    const target_offset = first_environment_offset + source_size + 4;
    forged[target_offset + 4] = 'c';
    try std.testing.expectError(
        error.ProgramContractViolation,
        LocalTextMachine.decodeState(std.testing.allocator, forged),
    );
}

fn expectTargetEdgeAlgebraicDefinition(
    comptime Witness: type,
    comptime payload_offset: usize,
) !void {
    const awaiting = blk: {
        for (Witness.Program.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 1 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_definition = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .instruction_result => |definition| {
            saw_definition = definition.result == 2 and
                definition.definition == 1 and
                definition.operand_count == 1 and
                definition.operands[0] == 0;
        },
        else => {},
    };
    try std.testing.expect(saw_definition);

    const state = try Witness.Machine.initialState(
        std.testing.allocator,
        7,
    );
    defer Witness.Machine.deinitState(state);
    var fuel: u64 = 16;
    _ = switch (try Witness.Machine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try Witness.Machine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    const target_offset = first_environment_offset + @sizeOf(u32);
    std.mem.writeInt(
        u32,
        forged[target_offset + payload_offset ..][0..4],
        8,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        Witness.Machine.decodeState(std.testing.allocator, forged),
    );
}

test "target-edge sum payloads retain executable source definitions" {
    try expectTargetEdgeAlgebraicDefinition(TargetEdgeSum, 4);
}

test "target-edge optional payloads retain executable source definitions" {
    try expectTargetEdgeAlgebraicDefinition(TargetEdgeOptional, 1);
}

test "bounded collection lengths are authenticated locally" {
    const awaiting = blk: {
        for (VectorLengthProgram.rnf.constructorSlice()) |*constructor| {
            if (constructor.source_block == 2 and
                constructor.kind == .await_effect)
            {
                break :blk constructor;
            }
        }
        return error.TestExpectedEqual;
    };
    var saw_length = false;
    for (awaiting.invariantTerms()) |term| switch (term) {
        .bounded_length_result => |definition| {
            saw_length = definition.result == 1 and definition.bounded == 0;
        },
        else => {},
    };
    try std.testing.expect(saw_length);

    var initial = LengthVector.empty();
    try initial.push(7);
    const state = try VectorLengthMachine.initialState(
        std.testing.allocator,
        initial,
    );
    defer VectorLengthMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = switch (try VectorLengthMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const encoded = try VectorLengthMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    const vector_bytes = try portable_value.encodedSize(LengthVector, initial);
    std.mem.writeInt(
        u32,
        forged[first_environment_offset + vector_bytes ..][0..4],
        2,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        VectorLengthMachine.decodeState(std.testing.allocator, forged),
    );

    inline for (.{ TextLengthWitness, BytesLengthWitness }) |Witness| {
        const bounded_awaiting = blk: {
            for (Witness.Program.rnf.constructorSlice()) |*constructor| {
                if (constructor.source_block == 2 and
                    constructor.kind == .await_effect)
                {
                    break :blk constructor;
                }
            }
            return error.TestExpectedEqual;
        };
        var bounded_saw_length = false;
        for (bounded_awaiting.invariantTerms()) |term| switch (term) {
            .bounded_length_result => |definition| {
                bounded_saw_length = definition.result == 1 and
                    definition.bounded == 0;
            },
            else => {},
        };
        try std.testing.expect(bounded_saw_length);

        const bounded_initial = try Witness.Body.InitialArgs.fromSlice("x");
        const bounded_state = try Witness.Machine.initialState(
            std.testing.allocator,
            bounded_initial,
        );
        defer Witness.Machine.deinitState(bounded_state);
        var bounded_fuel: u64 = 8;
        _ = switch (try Witness.Machine.step(
            bounded_state,
            &bounded_fuel,
        )) {
            .request => |request| request,
            else => return error.TestUnexpectedResult,
        };
        const bounded_encoded = try Witness.Machine.encodeState(
            std.testing.allocator,
            bounded_state,
        );
        defer std.testing.allocator.free(bounded_encoded);
        const bounded_forged = try std.testing.allocator.dupe(
            u8,
            bounded_encoded,
        );
        defer std.testing.allocator.free(bounded_forged);
        const bounded_bytes = try portable_value.encodedSize(
            Witness.Body.InitialArgs,
            bounded_initial,
        );
        std.mem.writeInt(
            u32,
            bounded_forged[first_environment_offset + bounded_bytes ..][0..4],
            2,
            .little,
        );
        try std.testing.expectError(
            error.ProgramContractViolation,
            Witness.Machine.decodeState(
                std.testing.allocator,
                bounded_forged,
            ),
        );
    }
}

test "diagnostic constructor classifications do not alter Machine identity" {
    try std.testing.expectEqualSlices(
        u8,
        &SegmentClassification.Machine.Manifest.machine_contract_digest,
        &LoopClassification.Machine.Manifest.machine_contract_digest,
    );

    const segment_state = try SegmentClassification.Machine.initialState(
        std.testing.allocator,
        {},
    );
    defer SegmentClassification.Machine.deinitState(segment_state);
    const loop_state = try LoopClassification.Machine.initialState(
        std.testing.allocator,
        {},
    );
    defer LoopClassification.Machine.deinitState(loop_state);
    var segment_fuel: u64 = 2;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try SegmentClassification.Machine.step(
            segment_state,
            &segment_fuel,
        )),
    );
    var loop_fuel: u64 = 2;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try LoopClassification.Machine.step(
            loop_state,
            &loop_fuel,
        )),
    );
    const segment_bytes = try SegmentClassification.Machine.encodeState(
        std.testing.allocator,
        segment_state,
    );
    defer std.testing.allocator.free(segment_bytes);
    const loop_bytes = try LoopClassification.Machine.encodeState(
        std.testing.allocator,
        loop_state,
    );
    defer std.testing.allocator.free(loop_bytes);
    try std.testing.expectEqualSlices(u8, segment_bytes, loop_bytes);

    inline for (.{ SegmentClassification, LoopClassification }) |Witness| {
        const state = try Witness.Machine.initialState(
            std.testing.allocator,
            {},
        );
        defer Witness.Machine.deinitState(state);
        var fuel: u64 = 8;
        const result = switch (try Witness.Machine.step(state, &fuel)) {
            .done => |value| value,
            else => return error.TestUnexpectedResult,
        };
        defer result.deinit();
        try std.testing.expectEqual(@as(u32, 7), result.value().*);
    }
}

test "zero caller fuel preserves the exact constructor state" {
    const state = try SegmentClassification.Machine.initialState(
        std.testing.allocator,
        {},
    );
    defer SegmentClassification.Machine.deinitState(state);
    const before = try SegmentClassification.Machine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(before);
    var caller_fuel: u64 = 0;
    try std.testing.expectEqual(
        .yielded,
        std.meta.activeTag(try SegmentClassification.Machine.step(
            state,
            &caller_fuel,
        )),
    );
    const after = try SegmentClassification.Machine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    try std.testing.expectEqual(@as(u64, 0), caller_fuel);
}
