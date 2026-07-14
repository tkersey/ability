// zlinter-disable declaration_naming field_naming field_ordering no_inferred_error_unions no_swallow_error require_doc_comment require_errdefer_dealloc
// The manifest decoder mirrors external JSON field names, including the schema key `id`.
const agent_loop = @import("agent_loop");
const boundary = @import("boundary");
const builtin = @import("builtin");
const std = @import("std");

const corpus_path = "conformance/world-image-v1/v0/boundary";
const generated_bundle_path = "bundle";
const tracked_publication_stage_path = "conformance/world-image-v1/v0/.boundary-oracle-stage";
const tracked_publication_backup_path = "conformance/world-image-v1/v0/.boundary-oracle-backup";
const oracle_generator_command = "zig build update-boundary-world-image-v1-oracle";
const oracle_normal_check_command = "zig build check-boundary-world-image-v1-oracle --summary all";

const semantic = boundary.ir.builder.semantic;
const EmptyHandlers = struct {};

const scalar_compiled = semantic.finish(.{
    .label = "world-image-v1-oracle-scalar-pure",
    .ir_hash = 0xB001_0001,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{},
        .locals = .{
            semantic.local("left", i32),
            semantic.local("right", i32),
            semantic.local("sum", i32),
            semantic.local("is_zero", bool),
            semantic.local("answer", i32),
        },
        .result = i32,
        .blocks = .{
            .{
                .name = "entry",
                .instructions = .{
                    semantic.constI32("left", 40),
                    semantic.constI32("right", 2),
                    semantic.addI32("sum", "left", "right"),
                    semantic.compareEqZero("is_zero", "sum"),
                },
                .terminator = semantic.branchIf("is_zero", .{ .then = "zero", .@"else" = "nonzero" }),
            },
            .{
                .name = "zero",
                .instructions = .{semantic.constI32("answer", 0)},
                .terminator = semantic.returnValue("answer"),
            },
            .{
                .name = "nonzero",
                .instructions = .{semantic.subOne("answer", "sum")},
                .terminator = semantic.returnValue("answer"),
            },
        },
    }},
}) catch |err| @compileError("invalid scalar oracle fixture: " ++ @errorName(err));

const ScalarProgram = boundary.program("world-image-v1-oracle-scalar-pure", EmptyHandlers, struct {
    pub const compiled_plan = scalar_compiled.plan;
});

fn helperPlan() boundary.ir.ProgramPlan {
    const helper = boundary.ir.builder.function(0);
    const root = boundary.ir.builder.function(1);
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 3,
            .local_count = 3,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 4,
        },
    };
    const locals = [_]boundary.ir.plan.Local{
        .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 },
        .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 },
    };
    const call_args = [_]u16{ 0, 1 };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 4, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .add_i32, .dst = 2, .operand = 0, .aux = 1 },
        boundary.ir.builder.returnValue(helper, boundary.ir.builder.local(helper, 2)) catch unreachable,
        .{ .kind = .const_i32, .dst = 0, .operand = 12 },
        .{ .kind = .const_i32, .dst = 1, .operand = 30 },
        boundary.ir.builder.callHelper(root, boundary.ir.builder.local(root, 2), helper, 0) catch unreachable,
        boundary.ir.builder.returnValue(root, boundary.ir.builder.local(root, 2)) catch unreachable,
    };
    return boundary.ir.builder.finish(.{
        .label = "world-image-v1-oracle-helper-call",
        .ir_hash = 0xB001_0002,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
        .call_args = &call_args,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const HelperProgram = boundary.program("world-image-v1-oracle-helper-call", EmptyHandlers, struct {
    pub const compiled_plan = helperPlan();
});

fn portableWordPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .usize,
        .result_codec = .usize,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 2,
        .first_instruction = 0,
        .instruction_count = 4,
    }};
    const locals = [_]boundary.ir.plan.Local{
        .{ .codec = .usize },
        .{ .codec = .usize },
        .{ .codec = .bool },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .return_value },
    };
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_usize, .dst = 0, .string_literal = "18446744073709551615" },
        .{ .kind = .compare_eq_zero, .dst = 2, .operand = 0 },
        .{ .kind = .sub_one, .dst = 1, .operand = 0 },
        boundary.ir.builder.returnValue(root, boundary.ir.builder.local(root, 1)) catch unreachable,
    };
    return boundary.ir.builder.finish(.{
        .label = "world-image-v1-oracle-portable-word",
        .ir_hash = 0xB001_0007,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const PortableWordProgram = boundary.program("world-image-v1-oracle-portable-word", EmptyHandlers, struct {
    pub const compiled_plan = portableWordPlan();
});

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(EmptyHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalOp = ApprovalRows.op("request");

const one_effect_compiled = semantic.finish(.{
    .label = "world-image-v1-oracle-one-effect",
    .ir_hash = 0xB001_0003,
    .entry = "run",
    .requirements = &.{ApprovalRows.requirement},
    .ops = &ApprovalRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{},
        .locals = .{
            semantic.local("payload", []const u8),
            semantic.local("decision", i32),
        },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.constString("payload", "deploy-prod"),
                semantic.call(ApprovalOp, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid one-effect oracle fixture: " ++ @errorName(err));

const OneEffectProgram = boundary.program("world-image-v1-oracle-one-effect", EmptyHandlers, struct {
    pub const site_metadata = one_effect_compiled.site_metadata;
    pub const compiled_plan = one_effect_compiled.plan;
});
const OneEffectSite = OneEffectProgram.protocol.operationSite("approval", "request", 0);

const DualProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval-dual",
    .ops = .{
        boundary.ir.schema.transform("first", []const u8, i32),
        boundary.ir.schema.transform("second", []const u8, i32),
    },
});
const DualRows = DualProtocol.Rows(EmptyHandlers, .{ .requirement_index = 0, .first_op = 0 });
const DualFirstOp = DualRows.op("first");
const DualSecondOp = DualRows.op("second");

const dual_compiled = semantic.finish(.{
    .label = "world-image-v1-oracle-multiple-residual",
    .ir_hash = 0xB001_0004,
    .entry = "run",
    .requirements = &.{DualRows.requirement},
    .ops = &DualRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{},
        .locals = .{
            semantic.local("payload", []const u8),
            semantic.local("first", i32),
            semantic.local("second", i32),
        },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.constString("payload", "deploy-prod"),
                semantic.call(DualFirstOp, .{ .dst = "first", .payload = "payload", .label = "approval-dual.first" }),
                semantic.call(DualSecondOp, .{ .dst = "second", .payload = "payload", .label = "approval-dual.second" }),
            },
            .terminator = semantic.returnValue("second"),
        }},
    }},
}) catch |err| @compileError("invalid multi-residual oracle fixture: " ++ @errorName(err));

const DualProgram = boundary.program("world-image-v1-oracle-multiple-residual", EmptyHandlers, struct {
    pub const site_metadata = dual_compiled.site_metadata;
    pub const compiled_plan = dual_compiled.plan;
});
const DualFirstSite = DualProgram.protocol.operationSite("approval-dual", "first", 0);
const DualSecondSite = DualProgram.protocol.operationSite("approval-dual", "second", 0);

fn nestedHelperPlan() boundary.ir.ProgramPlan {
    const inner = boundary.ir.builder.function(0);
    const outer = boundary.ir.builder.function(1);
    const root = boundary.ir.builder.function(2);
    const functions = [_]boundary.ir.plan.Function{
        .{
            .symbol_name = "inner_helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        },
        .{
            .symbol_name = "outer_helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 3,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 3,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 5,
            .instruction_count = 2,
        },
    };
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "approval", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "request",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const locals = [_]boundary.ir.plan.Local{
        .{ .codec = .string }, .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 5, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value }, .{ .kind = .return_value }, .{ .kind = .return_value },
    };
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = 0, .string_literal = "nested-helper" },
        boundary.ir.builder.callOp(inner, boundary.ir.builder.local(inner, 1), boundary.ir.builder.op(inner, 0), boundary.ir.builder.local(inner, 0)) catch unreachable,
        boundary.ir.builder.returnValue(inner, boundary.ir.builder.local(inner, 1)) catch unreachable,
        boundary.ir.builder.callHelper(outer, boundary.ir.builder.local(outer, 0), inner, null) catch unreachable,
        boundary.ir.builder.returnValue(outer, boundary.ir.builder.local(outer, 0)) catch unreachable,
        boundary.ir.builder.callHelper(root, boundary.ir.builder.local(root, 0), outer, null) catch unreachable,
        boundary.ir.builder.returnValue(root, boundary.ir.builder.local(root, 0)) catch unreachable,
    };
    return boundary.ir.builder.finish(.{
        .label = "world-image-v1-oracle-helper-park",
        .ir_hash = 0xB001_0005,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const NestedHelperProgram = boundary.program("world-image-v1-oracle-helper-park", EmptyHandlers, struct {
    pub const site_metadata = [_]boundary.ir.builder.semantic.SiteMetadata{.{
        .instruction_index = 1,
        .label = "approval.request.nested-helper",
    }};
    pub const compiled_plan = nestedHelperPlan();
});
const NestedHelperSite = NestedHelperProgram.protocol.operationSite("approval", "request", 0);

const StructuredDecision = struct {
    items: [][]const u8,
    score: i32,
};
const StructuredAction = union(enum) {
    ignore: i32,
    tool: StructuredDecision,
};
const StructuredRegistry = boundary.ir.schema.Registry(.{ StructuredDecision, StructuredAction });

fn structuredPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const decision_ref = StructuredRegistry.valueRef(StructuredDecision).?;
    const action_ref = StructuredRegistry.valueRef(StructuredAction).?;
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = 0, .string_literal = "structured" },
        boundary.ir.builder.callOp(root, boundary.ir.builder.local(root, 1), boundary.ir.builder.op(root, 0), boundary.ir.builder.local(root, 0)) catch unreachable,
        .{ .kind = .sum_variant_is, .dst = 2, .operand = 1, .aux = 1 },
        .{ .kind = .sum_extract_payload, .dst = 3, .operand = 1, .aux = 1 },
        boundary.ir.builder.returnValue(root, boundary.ir.builder.local(root, 3)) catch unreachable,
        .{ .kind = .sum_extract_payload, .dst = 3, .operand = 1, .aux = 1 },
        boundary.ir.builder.returnValue(root, boundary.ir.builder.local(root, 3)) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = decision_ref.schema_index,
        .result_codec = .product,
        .result_schema_index = decision_ref.schema_index,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "approval-structured", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "request",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .sum,
        .resume_schema_index = action_ref.schema_index,
    }};
    const locals = [_]boundary.ir.plan.Local{
        .{ .codec = .string },
        .{ .codec = .sum, .schema_index = action_ref.schema_index },
        .{ .codec = .bool },
        .{ .codec = .product, .schema_index = decision_ref.schema_index },
    };
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 5, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return boundary.ir.builder.finish(.{
        .label = "world-image-v1-oracle-typed-product-sum",
        .ir_hash = 0xB001_0006,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &StructuredRegistry.value_schemas,
        .value_fields = &StructuredRegistry.value_fields,
        .value_variants = &StructuredRegistry.value_variants,
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const StructuredProgram = boundary.program("world-image-v1-oracle-typed-product-sum", EmptyHandlers, struct {
    pub const value_schema_types = StructuredRegistry.value_schema_types;
    pub const site_metadata = [_]boundary.ir.builder.semantic.SiteMetadata{.{
        .instruction_index = 1,
        .label = "approval-structured.request",
    }};
    pub const compiled_plan = structuredPlan();
});
const StructuredSite = StructuredProgram.protocol.operationSite("approval-structured", "request", 0);

fn ClosedTarget(comptime Program: type, comptime target_label: []const u8, comptime graph_label: []const u8) type {
    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    @setEvalBranchQuota(2_000_000);
    const source_ref = Program.Evidence.refFor(
        Program.Evidence.domains.program_plan,
        Program.compiled_plan.hash(),
        .{ .label = Program.contract.label },
    );
    const graph = Closure.Graph.init(graph_label, &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .policy = Elaboration.Policy.auditOnly(),
    };
    return Elaboration.Target.compileComptime(.{
        .label = target_label,
        .input = input,
        .residual_program = Program,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
}

const SinglePortConfig = struct {
    target_label: []const u8,
    graph_label: []const u8,
    port_label: []const u8,
    protocol_label: []const u8,
    semantic_label: []const u8,
};

fn SinglePortTarget(comptime Program: type, comptime site: anytype, comptime config: SinglePortConfig) type {
    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    @setEvalBranchQuota(2_000_000);
    const source_ref = Program.Evidence.refFor(
        Program.Evidence.domains.program_plan,
        Program.compiled_plan.hash(),
        .{ .label = Program.contract.label },
    );
    const source_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = site.index,
        .protocol_label = config.protocol_label,
        .protocol_op_fingerprint = site.fingerprint,
        .semantic_label = config.semantic_label,
        .name = site.op_name,
        .mode = @tagName(site.op_mode),
        .value_ref = Program.Evidence.BoundaryValueRef.fromValueRef(site.payload_ref),
        .expected_resume_ref = Program.Evidence.BoundaryValueRef.fromValueRef(site.resume_ref),
        .result_ref = Program.Evidence.BoundaryValueRef.fromValueRef(site.result_ref),
    });
    const port = Closure.WorldPort.init(.{
        .label = config.port_label,
        .kind = .test_fixture,
        .effect_shape_ref = source_shape.evidenceRef(),
        .effect_shape_witness = source_shape,
        .supported_protocol_labels = &.{config.protocol_label},
        .supported_site_indexes = &.{site.index},
        .supported_protocol_op_fingerprints = &.{site.fingerprint},
    });
    const graph = Closure.Graph.init(config.graph_label, &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .effect_shape_count = 1,
        .world_port_refs = &.{port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .world_ports = &.{port},
        .policy = Elaboration.Policy.auditOnly(),
    };
    return Elaboration.Target.compileComptime(.{
        .label = config.target_label,
        .input = input,
        .residual_program = Program,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
}

fn DualTarget(comptime target_label: []const u8) type {
    const Program = DualProgram;
    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    @setEvalBranchQuota(2_000_000);
    const source_ref = Program.Evidence.refFor(
        Program.Evidence.domains.program_plan,
        Program.compiled_plan.hash(),
        .{ .label = Program.contract.label },
    );
    const first_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = DualFirstSite.index,
        .protocol_label = "approval-dual",
        .protocol_op_fingerprint = DualFirstSite.fingerprint,
        .semantic_label = "approval-dual.first",
        .name = "first",
        .mode = "transform",
        .value_ref = Program.Evidence.BoundaryValueRef.fromValueRef(DualFirstSite.payload_ref),
        .expected_resume_ref = Program.Evidence.BoundaryValueRef.fromValueRef(DualFirstSite.resume_ref),
        .result_ref = Program.Evidence.BoundaryValueRef.fromValueRef(DualFirstSite.result_ref),
    });
    const second_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = DualSecondSite.index,
        .protocol_label = "approval-dual",
        .protocol_op_fingerprint = DualSecondSite.fingerprint,
        .semantic_label = "approval-dual.second",
        .name = "second",
        .mode = "transform",
        .value_ref = Program.Evidence.BoundaryValueRef.fromValueRef(DualSecondSite.payload_ref),
        .expected_resume_ref = Program.Evidence.BoundaryValueRef.fromValueRef(DualSecondSite.resume_ref),
        .result_ref = Program.Evidence.BoundaryValueRef.fromValueRef(DualSecondSite.result_ref),
    });
    const first_port = Closure.WorldPort.init(.{
        .label = "world-image-v1-oracle-dual-first-port",
        .kind = .test_fixture,
        .effect_shape_ref = first_shape.evidenceRef(),
        .effect_shape_witness = first_shape,
        .supported_protocol_labels = &.{"approval-dual"},
        .supported_site_indexes = &.{DualFirstSite.index},
        .supported_protocol_op_fingerprints = &.{DualFirstSite.fingerprint},
    });
    const second_port = Closure.WorldPort.init(.{
        .label = "world-image-v1-oracle-dual-second-port",
        .kind = .test_fixture,
        .effect_shape_ref = second_shape.evidenceRef(),
        .effect_shape_witness = second_shape,
        .supported_protocol_labels = &.{"approval-dual"},
        .supported_site_indexes = &.{DualSecondSite.index},
        .supported_protocol_op_fingerprints = &.{DualSecondSite.fingerprint},
    });
    const graph = Closure.Graph.init("world-image-v1-oracle-dual-graph", &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .effect_shape_count = 2,
        .world_port_refs = &.{ first_port.evidenceRef(), second_port.evidenceRef() },
        .open_world_port_count = 2,
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .world_ports = &.{ first_port, second_port },
        .policy = Elaboration.Policy.auditOnly(),
    };
    return Elaboration.Target.compileComptime(.{
        .label = target_label,
        .input = input,
        .residual_program = Program,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
}

const ScalarTarget = ClosedTarget(ScalarProgram, "world-image-v1-oracle-scalar-target", "world-image-v1-oracle-scalar-graph");
const HelperTarget = ClosedTarget(HelperProgram, "world-image-v1-oracle-helper-target", "world-image-v1-oracle-helper-graph");
const PortableWordTarget = ClosedTarget(PortableWordProgram, "world-image-v1-oracle-portable-word-target", "world-image-v1-oracle-portable-word-graph");
const OneEffectTarget = SinglePortTarget(
    OneEffectProgram,
    OneEffectSite,
    .{
        .target_label = "world-image-v1-oracle-one-effect-target",
        .graph_label = "world-image-v1-oracle-one-effect-graph",
        .port_label = "world-image-v1-oracle-one-effect-port",
        .protocol_label = "approval",
        .semantic_label = "approval.request",
    },
);
const StructuredTarget = SinglePortTarget(
    StructuredProgram,
    StructuredSite,
    .{
        .target_label = "world-image-v1-oracle-structured-target",
        .graph_label = "world-image-v1-oracle-structured-graph",
        .port_label = "world-image-v1-oracle-structured-port",
        .protocol_label = "approval-structured",
        .semantic_label = "approval-structured.request",
    },
);
const NestedHelperTarget = SinglePortTarget(
    NestedHelperProgram,
    NestedHelperSite,
    .{
        .target_label = "world-image-v1-oracle-nested-helper-target",
        .graph_label = "world-image-v1-oracle-nested-helper-graph",
        .port_label = "world-image-v1-oracle-nested-helper-port",
        .protocol_label = "approval",
        .semantic_label = "approval.request.nested-helper",
    },
);
const MultipleTarget = DualTarget("world-image-v1-oracle-multiple-target");

fn expectLoadedStringRequestParity(
    comptime Program: type,
    comptime Target: type,
    comptime Site: type,
    allocator: std.mem.Allocator,
    generated_request: anytype,
    loaded_request: anytype,
) !void {
    if (Target.WorldDispatchTable.lookup(generated_request.operation_site_index) != loaded_request.world_port_id or
        generated_request.operation_site_index != loaded_request.residual_site_index or
        generated_request.operation_site_fingerprint != loaded_request.residual_site_fingerprint or
        loaded_request.response_kind != .@"resume")
    {
        return error.OracleSemanticMismatch;
    }
    const expected_payload_ref = Program.Evidence.BoundaryValueRef.fromValueRef(Site.payload_ref);
    const expected_response_ref = Program.Evidence.BoundaryValueRef.fromValueRef(Site.resume_ref);
    if (!loaded_request.payload_ref.eql(expected_payload_ref) or
        !loaded_request.expected_response_ref.eql(expected_response_ref))
    {
        return error.OracleSemanticMismatch;
    }

    const typed_request = try generated_request.as(Site);
    const generated_payload: Site.Payload = try typed_request.payload();
    var payload_arena = Target.Module.LoadedValueArena.init(allocator);
    defer payload_arena.deinit();
    const schema_set = Target.Module.LoadedValueSchemaSet{
        .schemas = Target.Program.compiled_plan.value_schemas,
        .fields = Target.Program.compiled_plan.value_fields,
        .variants = Target.Program.compiled_plan.value_variants,
    };
    const loaded_payload = try Target.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &payload_arena,
        schema_set,
        .{ .codec = .string },
        loaded_request.canonical_payload_image,
        .{},
    );
    try expectEqualBytes(generated_payload, loaded_payload.bytes);
}

fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.Io.Dir.path.join(allocator, parts);
}

fn pathKindNoFollow(io: std.Io, path: []const u8) !?std.Io.File.Kind {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    return stat.kind;
}

fn requireDirectory(io: std.Io, path: []const u8) !void {
    const kind = try pathKindNoFollow(io, path) orelse return error.OracleDirectoryMissing;
    if (kind != .directory) return error.UnsafeOraclePath;
}

fn createFreshDirectory(io: std.Io, path: []const u8) !void {
    if (try pathKindNoFollow(io, path) != null) return error.OracleOutputExists;
    if (std.Io.Dir.path.dirname(path)) |parent| try requireDirectory(io, parent);
    try std.Io.Dir.cwd().createDir(io, path, .default_dir);
}

fn deleteDirectoryIfPresent(io: std.Io, path: []const u8) !void {
    const kind = try pathKindNoFollow(io, path) orelse return;
    if (kind != .directory) return error.UnsafeOraclePath;
    try std.Io.Dir.cwd().deleteTree(io, path);
}

fn renameDirectoryToMissing(io: std.Io, source: []const u8, target: []const u8) !void {
    try requireDirectory(io, source);
    if (try pathKindNoFollow(io, target) != null) return error.OraclePublicationConflict;
    const cwd = std.Io.Dir.cwd();
    try cwd.rename(source, cwd, target, io);
}

fn writeArtifact(
    io: std.Io,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    relative_path: []const u8,
    bytes: []const u8,
) !void {
    const path = try joinPath(allocator, &.{ output_dir, relative_path });
    defer allocator.free(path);
    if (std.Io.Dir.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn writeArtifactFromDir(
    io: std.Io,
    dir: std.Io.Dir,
    relative_path: []const u8,
    bytes: []const u8,
) !void {
    try validateCanonicalOracleRelativePath(relative_path);
    if (std.Io.Dir.path.dirname(relative_path)) |parent| try dir.createDirPath(io, parent);
    try dir.writeFile(io, .{ .sub_path = relative_path, .data = bytes });
}

fn deleteArtifact(io: std.Io, allocator: std.mem.Allocator, output_dir: []const u8, relative_path: []const u8) !void {
    const path = try joinPath(allocator, &.{ output_dir, relative_path });
    defer allocator.free(path);
    try std.Io.Dir.cwd().deleteFile(io, path);
}

fn expectEqualBytes(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) return error.OracleSemanticMismatch;
}

fn expectEqualI32(expected: i32, actual: i32) !void {
    if (expected != actual) return error.OracleSemanticMismatch;
}

fn emitModule(
    comptime Target: type,
    io: std.Io,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    relative_path: []const u8,
) ![]u8 {
    const bytes = try Target.Module.fullImage(allocator);
    errdefer allocator.free(bytes);
    _ = try Target.Module.validate(bytes, .{ .require_full_module = true });
    try writeArtifact(io, allocator, output_dir, relative_path, bytes);
    return bytes;
}

fn emitScalarAndBudget(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        ScalarTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/scalar-pure.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try ScalarProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();

    var loaded = try ScalarTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try ScalarTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        ScalarTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = ScalarTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const loaded_result = try ScalarTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        .{},
        .{ .codec = .i32 },
        loaded_done.canonical_result_image,
        .{},
    );
    try expectEqualI32(generated_done.value, loaded_result.i32);
    try expectEqualI32(41, loaded_result.i32);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/scalar-pure.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/scalar-pure.completed.loaded-session", completed_state);

    const scalar_transcript = try std.fmt.allocPrint(allocator,
        \\case_id: scalar-pure
        \\generated_status: completed
        \\loaded_status: completed
        \\generated_result_i32: {d}
        \\loaded_result_i32: {d}
        \\module_fingerprint: 0x{x:0>16}
        \\session_fingerprint: 0x{x:0>16}
        \\result_fingerprint: 0x{x:0>16}
        \\module: artifacts/modules/scalar-pure.full-module
        \\state: artifacts/states/scalar-pure.completed.loaded-session
        \\result: artifacts/values/scalar-pure.result.loaded-value
        \\
    , .{
        generated_done.value,
        loaded_result.i32,
        loaded.moduleFingerprint(),
        loaded_session.session_fingerprint,
        loaded_done.result_fingerprint,
    });
    defer allocator.free(scalar_transcript);
    try writeArtifact(io, allocator, output_dir, "cases/scalar-pure.txt", scalar_transcript);

    var constrained_profile = ScalarTarget.Module.LoadedExecutionProfile.portableV2();
    constrained_profile.limits.maximum_instructions_per_advancement = 2;
    var constrained = try ScalarTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        constrained_profile,
    );
    defer constrained.deinit();
    const failure = switch (constrained.next()) {
        .failed => |failed| failed,
        .request => return error.UnexpectedLoadedRequest,
        .done => return error.UnexpectedLoadedDone,
    };
    if (failure.kind != .execution_budget_exceeded) return error.UnexpectedFailureKind;
    const failed_state = try constrained.freeze(allocator);
    defer allocator.free(failed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/budget-exhaustion.failed.loaded-session", failed_state);
    var failure_image = try ScalarTarget.Module.LoadedSessionImage.decode(allocator, failed_state);
    defer failure_image.deinit(allocator);
    const budget_transcript = try std.fmt.allocPrint(allocator,
        \\case_id: budget-exhaustion
        \\loaded_status: failed
        \\failure_kind: {s}
        \\diagnostic_summary: {s}
        \\instruction_limit: {d}
        \\advancements: {d}
        \\instructions_consumed: {d}
        \\module: artifacts/modules/scalar-pure.full-module
        \\state: artifacts/states/budget-exhaustion.failed.loaded-session
        \\
    , .{
        @tagName(failure.kind),
        failure.diagnostic_summary,
        constrained_profile.limits.maximum_instructions_per_advancement,
        failure_image.budget.advancements,
        failure_image.budget.instructions_consumed,
    });
    defer allocator.free(budget_transcript);
    try writeArtifact(io, allocator, output_dir, "cases/budget-exhaustion.txt", budget_transcript);
}

fn emitHelperCall(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        HelperTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/helper-call.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try HelperProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();

    var loaded = try HelperTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try HelperTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        HelperTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = HelperTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const result = try HelperTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        .{},
        .{ .codec = .i32 },
        loaded_done.canonical_result_image,
        .{},
    );
    try expectEqualI32(generated_done.value, result.i32);
    try expectEqualI32(42, result.i32);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/helper-call.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/helper-call.completed.loaded-session", completed_state);
    const transcript = try std.fmt.allocPrint(allocator,
        \\case_id: helper-call
        \\generated_status: completed
        \\loaded_status: completed
        \\generated_result_i32: {d}
        \\loaded_result_i32: {d}
        \\module_fingerprint: 0x{x:0>16}
        \\result_fingerprint: 0x{x:0>16}
        \\module: artifacts/modules/helper-call.full-module
        \\state: artifacts/states/helper-call.completed.loaded-session
        \\result: artifacts/values/helper-call.result.loaded-value
        \\
    , .{ generated_done.value, result.i32, loaded.moduleFingerprint(), loaded_done.result_fingerprint });
    defer allocator.free(transcript);
    try writeArtifact(io, allocator, output_dir, "cases/helper-call.txt", transcript);
}

fn emitPortableWord(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        PortableWordTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/portable-word.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try PortableWordProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();

    var loaded = try PortableWordTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try PortableWordTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        PortableWordTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = PortableWordTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const loaded_result = try PortableWordTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        .{},
        .{ .codec = .usize },
        loaded_done.canonical_result_image,
        .{},
    );
    const generated_result: u64 = @intCast(generated_done.value);
    if (generated_result != std.math.maxInt(u64) - 1 or loaded_result.word_u64 != generated_result) {
        return error.OracleSemanticMismatch;
    }
    try writeArtifact(io, allocator, output_dir, "artifacts/values/portable-word.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/portable-word.completed.loaded-session", completed_state);
    const transcript = try std.fmt.allocPrint(allocator,
        \\case_id: portable-word
        \\generated_status: completed
        \\loaded_status: completed
        \\literal_u64: {d}
        \\generated_result_u64: {d}
        \\loaded_result_u64: {d}
        \\module: artifacts/modules/portable-word.full-module
        \\state: artifacts/states/portable-word.completed.loaded-session
        \\result: artifacts/values/portable-word.result.loaded-value
        \\
    , .{ std.math.maxInt(u64), generated_result, loaded_result.word_u64 });
    defer allocator.free(transcript);
    try writeArtifact(io, allocator, output_dir, "cases/portable-word.txt", transcript);
}

fn emitOneEffect(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        OneEffectTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/one-effect.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try OneEffectProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    const generated_request = switch (try generated.next()) {
        .request => |request| request,
        .done => return error.UnexpectedGeneratedDone,
        .after => return error.UnexpectedGeneratedAfter,
    };
    var generated_envelope = try OneEffectProgram.Exchange.RequestEnvelope.fromRequest(allocator, generated_request, .{});
    defer generated_envelope.deinit();
    try generated_envelope.validate();
    try writeArtifact(io, allocator, output_dir, "artifacts/requests/one-effect.generated-request-envelope", generated_envelope.bytes);
    var generated_capsule = try generated.capture(allocator);
    defer generated_capsule.deinit();
    var generated_capsule_image = try generated_capsule.encode(allocator);
    defer generated_capsule_image.deinit();
    try writeArtifact(io, allocator, output_dir, "artifacts/capsules/one-effect.parked.program-session", generated_capsule_image.bytes);

    var loaded = try OneEffectTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try OneEffectTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        OneEffectTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_request = switch (loaded_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    try expectLoadedStringRequestParity(OneEffectProgram, OneEffectTarget, OneEffectSite, allocator, generated_request, loaded_request);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/one-effect.payload.loaded-value", loaded_request.canonical_payload_image);
    const parked_state = try loaded_session.freeze(allocator);
    defer allocator.free(parked_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/one-effect.parked.loaded-session", parked_state);

    const wrong_response = try OneEffectTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        .{},
        .{ .codec = .bool },
        .{ .boolean = true },
        .{},
    );
    defer allocator.free(wrong_response);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/malformed-response.wrong-schema.loaded-value", wrong_response);
    var malformed_error: ?anyerror = null;
    loaded_session.@"resume"(loaded_request, wrong_response) catch |err| {
        malformed_error = err;
    };
    if (malformed_error == null or malformed_error.? != error.InvalidResume) return error.MalformedResponseAccepted;
    const after_malformed_state = try loaded_session.freeze(allocator);
    defer allocator.free(after_malformed_state);
    try expectEqualBytes(parked_state, after_malformed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/malformed-response.after-rejection.loaded-session", after_malformed_state);

    const response = try OneEffectTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        .{},
        .{ .codec = .i32 },
        .{ .i32 = 7 },
        .{},
    );
    defer allocator.free(response);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/one-effect.response.loaded-value", response);
    try generated.@"resume"(generated_request, @as(i32, 7));
    try loaded_session.@"resume"(loaded_request, response);

    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = OneEffectTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const result = try OneEffectTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        .{},
        .{ .codec = .i32 },
        loaded_done.canonical_result_image,
        .{},
    );
    try expectEqualI32(generated_done.value, result.i32);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/one-effect.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/one-effect.completed.loaded-session", completed_state);

    const transcript = try std.fmt.allocPrint(allocator,
        \\case_id: one-effect
        \\generated_status: completed
        \\loaded_status: completed
        \\effect_site_index: {d}
        \\effect_site_fingerprint: 0x{x:0>16}
        \\world_port_id: {d}
        \\request_fingerprint: 0x{x:0>16}
        \\continuation_fingerprint: 0x{x:0>16}
        \\generated_result_i32: {d}
        \\loaded_result_i32: {d}
        \\module: artifacts/modules/one-effect.full-module
        \\generated_request: artifacts/requests/one-effect.generated-request-envelope
        \\generated_capsule: artifacts/capsules/one-effect.parked.program-session
        \\parked_state: artifacts/states/one-effect.parked.loaded-session
        \\completed_state: artifacts/states/one-effect.completed.loaded-session
        \\
    , .{
        loaded_request.residual_site_index,
        loaded_request.residual_site_fingerprint,
        loaded_request.world_port_id,
        loaded_request.canonical_request_fingerprint,
        loaded_request.deterministic_continuation_fingerprint,
        generated_done.value,
        result.i32,
    });
    defer allocator.free(transcript);
    try writeArtifact(io, allocator, output_dir, "cases/one-effect.txt", transcript);

    const malformed_transcript = try std.fmt.allocPrint(allocator,
        \\case_id: malformed-response
        \\input_kind: wrong-schema-loaded-value
        \\expected_error: {s}
        \\state_unchanged: true
        \\request_fingerprint: 0x{x:0>16}
        \\input: artifacts/values/malformed-response.wrong-schema.loaded-value
        \\prior_state: artifacts/states/one-effect.parked.loaded-session
        \\next_state: artifacts/states/malformed-response.after-rejection.loaded-session
        \\
    , .{ @errorName(malformed_error.?), loaded_request.canonical_request_fingerprint });
    defer allocator.free(malformed_transcript);
    try writeArtifact(io, allocator, output_dir, "cases/malformed-response.txt", malformed_transcript);
}

fn emitStructured(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        StructuredTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/typed-product-sum.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try StructuredProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    const generated_request = switch (try generated.next()) {
        .request => |request| request,
        .done => return error.UnexpectedGeneratedDone,
        .after => return error.UnexpectedGeneratedAfter,
    };
    var generated_envelope = try StructuredProgram.Exchange.RequestEnvelope.fromRequest(allocator, generated_request, .{});
    defer generated_envelope.deinit();
    try generated_envelope.validate();
    try writeArtifact(io, allocator, output_dir, "artifacts/requests/typed-product-sum.generated-request-envelope", generated_envelope.bytes);
    var generated_capsule = try generated.capture(allocator);
    defer generated_capsule.deinit();
    var generated_capsule_image = try generated_capsule.encode(allocator);
    defer generated_capsule_image.deinit();
    try writeArtifact(io, allocator, output_dir, "artifacts/capsules/typed-product-sum.parked.program-session", generated_capsule_image.bytes);

    var loaded = try StructuredTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try StructuredTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        StructuredTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_request = switch (loaded_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    try expectLoadedStringRequestParity(StructuredProgram, StructuredTarget, StructuredSite, allocator, generated_request, loaded_request);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/typed-product-sum.payload.loaded-value", loaded_request.canonical_payload_image);
    const parked_state = try loaded_session.freeze(allocator);
    defer allocator.free(parked_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/typed-product-sum.parked.loaded-session", parked_state);

    const schema_set = StructuredTarget.Module.LoadedValueSchemaSet{
        .schemas = StructuredTarget.Program.compiled_plan.value_schemas,
        .fields = StructuredTarget.Program.compiled_plan.value_fields,
        .variants = StructuredTarget.Program.compiled_plan.value_variants,
    };
    const action_ref = StructuredRegistry.valueRef(StructuredAction).?;
    const decision_ref = StructuredRegistry.valueRef(StructuredDecision).?;
    const loaded_items = [_][]const u8{ "alpha", "beta" };
    const product_fields = [_]StructuredTarget.Module.LoadedValue{
        .{ .list = &loaded_items },
        .{ .i32 = 42 },
    };
    const product_value = StructuredTarget.Module.LoadedValue{ .product = &product_fields };
    const sum_value = StructuredTarget.Module.LoadedValue{ .sum = .{
        .variant_index = 1,
        .payload = &product_value,
    } };
    const response = try StructuredTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        schema_set,
        .{ .codec = .sum, .schema_index = action_ref.schema_index },
        sum_value,
        .{},
    );
    defer allocator.free(response);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/typed-product-sum.response.loaded-value", response);

    const malformed_response = try allocator.alloc(u8, response.len + 1);
    defer allocator.free(malformed_response);
    @memcpy(malformed_response[0..response.len], response);
    malformed_response[malformed_response.len - 1] = 0;
    try writeArtifact(io, allocator, output_dir, "artifacts/values/typed-product-sum.response.trailing-bytes", malformed_response);
    var malformed_error: ?anyerror = null;
    loaded_session.@"resume"(loaded_request, malformed_response) catch |err| {
        malformed_error = err;
    };
    if (malformed_error == null or malformed_error.? != error.InvalidResume) return error.MalformedResponseAccepted;
    const after_malformed = try loaded_session.freeze(allocator);
    defer allocator.free(after_malformed);
    try expectEqualBytes(parked_state, after_malformed);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/typed-product-sum.after-malformed.loaded-session", after_malformed);

    var generated_items = [_][]const u8{ "alpha", "beta" };
    try generated.@"resume"(generated_request, StructuredAction{ .tool = .{
        .items = &generated_items,
        .score = 42,
    } });
    try loaded_session.@"resume"(loaded_request, response);
    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = StructuredTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const result = try StructuredTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        schema_set,
        .{ .codec = .product, .schema_index = decision_ref.schema_index },
        loaded_done.canonical_result_image,
        .{},
    );
    if (result.product.len != 2 or result.product[0].list.len != 2) return error.OracleSemanticMismatch;
    try expectEqualBytes(generated_done.value.items[0], result.product[0].list[0]);
    try expectEqualBytes(generated_done.value.items[1], result.product[0].list[1]);
    try expectEqualI32(generated_done.value.score, result.product[1].i32);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/typed-product-sum.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/typed-product-sum.completed.loaded-session", completed_state);

    const transcript = try std.fmt.allocPrint(allocator,
        \\case_id: typed-product-sum
        \\generated_status: completed
        \\loaded_status: completed
        \\effect_site_index: {d}
        \\effect_site_fingerprint: 0x{x:0>16}
        \\request_fingerprint: 0x{x:0>16}
        \\response_schema: sum
        \\result_schema: product
        \\result_items: alpha,beta
        \\result_score: {d}
        \\malformed_response_error: {s}
        \\malformed_response_state_unchanged: true
        \\module: artifacts/modules/typed-product-sum.full-module
        \\generated_request: artifacts/requests/typed-product-sum.generated-request-envelope
        \\generated_capsule: artifacts/capsules/typed-product-sum.parked.program-session
        \\parked_state: artifacts/states/typed-product-sum.parked.loaded-session
        \\completed_state: artifacts/states/typed-product-sum.completed.loaded-session
        \\
    , .{
        loaded_request.residual_site_index,
        loaded_request.residual_site_fingerprint,
        loaded_request.canonical_request_fingerprint,
        result.product[1].i32,
        @errorName(malformed_error.?),
    });
    defer allocator.free(transcript);
    try writeArtifact(io, allocator, output_dir, "cases/typed-product-sum.txt", transcript);
}

fn emitHelperPark(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        NestedHelperTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/helper-park.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try NestedHelperProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    const generated_request = switch (try generated.next()) {
        .request => |request| request,
        .done => return error.UnexpectedGeneratedDone,
        .after => return error.UnexpectedGeneratedAfter,
    };
    var generated_envelope = try NestedHelperProgram.Exchange.RequestEnvelope.fromRequest(allocator, generated_request, .{});
    defer generated_envelope.deinit();
    try generated_envelope.validate();
    try writeArtifact(io, allocator, output_dir, "artifacts/requests/helper-park.generated-request-envelope", generated_envelope.bytes);
    var generated_capsule = try generated.capture(allocator);
    defer generated_capsule.deinit();
    var generated_capsule_image = try generated_capsule.encode(allocator);
    defer generated_capsule_image.deinit();
    try writeArtifact(io, allocator, output_dir, "artifacts/capsules/helper-park.parked.program-session", generated_capsule_image.bytes);

    var loaded = try NestedHelperTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try NestedHelperTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        NestedHelperTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_request = switch (loaded_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    try expectLoadedStringRequestParity(NestedHelperProgram, NestedHelperTarget, NestedHelperSite, allocator, generated_request, loaded_request);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/helper-park.payload.loaded-value", loaded_request.canonical_payload_image);
    const parked_state = try loaded_session.freeze(allocator);
    defer allocator.free(parked_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/helper-park.parked.loaded-session", parked_state);
    var parked_image = try NestedHelperTarget.Module.LoadedSessionImage.decode(allocator, parked_state);
    defer parked_image.deinit(allocator);
    const frame_count = if (parked_image.continuation) |continuation| continuation.frame_images.len else 0;
    if (frame_count != 3) return error.UnexpectedFrameCount;

    const response = try NestedHelperTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        .{},
        .{ .codec = .i32 },
        .{ .i32 = 31 },
        .{},
    );
    defer allocator.free(response);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/helper-park.response.loaded-value", response);
    try generated.@"resume"(generated_request, @as(i32, 31));
    try loaded_session.@"resume"(loaded_request, response);
    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = NestedHelperTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const result = try NestedHelperTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        .{},
        .{ .codec = .i32 },
        loaded_done.canonical_result_image,
        .{},
    );
    try expectEqualI32(generated_done.value, result.i32);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/helper-park.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/helper-park.completed.loaded-session", completed_state);

    const transcript = try std.fmt.allocPrint(allocator,
        \\case_id: helper-park
        \\generated_status: completed
        \\loaded_status: completed
        \\effect_site_index: {d}
        \\effect_site_fingerprint: 0x{x:0>16}
        \\request_fingerprint: 0x{x:0>16}
        \\continuation_fingerprint: 0x{x:0>16}
        \\parked_frame_count: {d}
        \\generated_result_i32: {d}
        \\loaded_result_i32: {d}
        \\module: artifacts/modules/helper-park.full-module
        \\generated_request: artifacts/requests/helper-park.generated-request-envelope
        \\generated_capsule: artifacts/capsules/helper-park.parked.program-session
        \\parked_state: artifacts/states/helper-park.parked.loaded-session
        \\completed_state: artifacts/states/helper-park.completed.loaded-session
        \\
    , .{
        loaded_request.residual_site_index,
        loaded_request.residual_site_fingerprint,
        loaded_request.canonical_request_fingerprint,
        loaded_request.deterministic_continuation_fingerprint,
        frame_count,
        generated_done.value,
        result.i32,
    });
    defer allocator.free(transcript);
    try writeArtifact(io, allocator, output_dir, "cases/helper-park.txt", transcript);
}

fn emitMultipleResidual(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const io = init.io;
    const module_bytes = try emitModule(
        MultipleTarget,
        io,
        allocator,
        output_dir,
        "artifacts/modules/multiple-residual.full-module",
    );
    defer allocator.free(module_bytes);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated = try DualProgram.Session.start(&runtime, .{});
    defer generated.deinit();
    const generated_first = switch (try generated.next()) {
        .request => |request| request,
        .done => return error.UnexpectedGeneratedDone,
        .after => return error.UnexpectedGeneratedAfter,
    };
    var generated_first_envelope = try DualProgram.Exchange.RequestEnvelope.fromRequest(allocator, generated_first, .{});
    defer generated_first_envelope.deinit();
    try generated_first_envelope.validate();
    try writeArtifact(io, allocator, output_dir, "artifacts/requests/multiple-residual.first.generated-request-envelope", generated_first_envelope.bytes);
    var generated_first_capsule = try generated.capture(allocator);
    defer generated_first_capsule.deinit();
    var generated_first_capsule_image = try generated_first_capsule.encode(allocator);
    defer generated_first_capsule_image.deinit();
    try writeArtifact(io, allocator, output_dir, "artifacts/capsules/multiple-residual.first.program-session", generated_first_capsule_image.bytes);

    var loaded = try MultipleTarget.Module.decode(allocator, module_bytes);
    defer loaded.deinit();
    var loaded_session = try MultipleTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        MultipleTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_session.deinit();
    const loaded_first = switch (loaded_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    try expectLoadedStringRequestParity(DualProgram, MultipleTarget, DualFirstSite, allocator, generated_first, loaded_first);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/multiple-residual.first.payload.loaded-value", loaded_first.canonical_payload_image);
    const first_state = try loaded_session.freeze(allocator);
    defer allocator.free(first_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/multiple-residual.first.parked.loaded-session", first_state);

    const first_response = try MultipleTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        .{},
        .{ .codec = .i32 },
        .{ .i32 = 7 },
        .{},
    );
    defer allocator.free(first_response);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/multiple-residual.first.response.loaded-value", first_response);
    try generated.@"resume"(generated_first, @as(i32, 7));
    try loaded_session.@"resume"(loaded_first, first_response);

    var generated_duplicate_error: ?anyerror = null;
    generated.@"resume"(generated_first, @as(i32, 7)) catch |err| {
        generated_duplicate_error = err;
    };
    if (generated_duplicate_error == null or generated_duplicate_error.? != error.ProgramContractViolation) {
        return error.DuplicateResponseAccepted;
    }
    var duplicate_error: ?anyerror = null;
    loaded_session.@"resume"(loaded_first, first_response) catch |err| {
        duplicate_error = err;
    };
    if (duplicate_error == null or duplicate_error.? != error.InvalidResume) return error.DuplicateResponseAccepted;

    const generated_second = switch (try generated.next()) {
        .request => |request| request,
        .done => return error.UnexpectedGeneratedDone,
        .after => return error.UnexpectedGeneratedAfter,
    };
    var generated_second_envelope = try DualProgram.Exchange.RequestEnvelope.fromRequest(allocator, generated_second, .{});
    defer generated_second_envelope.deinit();
    try generated_second_envelope.validate();
    try writeArtifact(io, allocator, output_dir, "artifacts/requests/multiple-residual.second.generated-request-envelope", generated_second_envelope.bytes);
    var generated_second_capsule = try generated.capture(allocator);
    defer generated_second_capsule.deinit();
    var generated_second_capsule_image = try generated_second_capsule.encode(allocator);
    defer generated_second_capsule_image.deinit();
    try writeArtifact(io, allocator, output_dir, "artifacts/capsules/multiple-residual.second.program-session", generated_second_capsule_image.bytes);
    try writeArtifact(
        io,
        allocator,
        output_dir,
        "artifacts/capsules/multiple-residual.after-duplicate.program-session",
        generated_second_capsule_image.bytes,
    );

    var control_runtime = boundary.Runtime.init(allocator);
    defer control_runtime.deinit();
    var generated_control = try DualProgram.Session.restore(&control_runtime, .{}, &generated_first_capsule);
    defer generated_control.deinit();
    const generated_control_first = switch (try generated_control.current()) {
        .request => |request| request,
        .after => return error.UnexpectedGeneratedAfter,
        .none => return error.UnexpectedGeneratedDone,
    };
    try generated_control.@"resume"(generated_control_first, @as(i32, 7));
    _ = switch (try generated_control.next()) {
        .request => |request| request,
        .done => return error.UnexpectedGeneratedDone,
        .after => return error.UnexpectedGeneratedAfter,
    };
    var generated_before_duplicate = try generated_control.capture(allocator);
    defer generated_before_duplicate.deinit();
    var generated_before_duplicate_image = try generated_before_duplicate.encode(allocator);
    defer generated_before_duplicate_image.deinit();
    try expectEqualBytes(generated_before_duplicate_image.bytes, generated_second_capsule_image.bytes);
    try writeArtifact(
        io,
        allocator,
        output_dir,
        "artifacts/capsules/multiple-residual.before-duplicate.program-session",
        generated_before_duplicate_image.bytes,
    );

    const loaded_second = switch (loaded_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    try expectLoadedStringRequestParity(DualProgram, MultipleTarget, DualSecondSite, allocator, generated_second, loaded_second);
    if (loaded_first.canonical_request_fingerprint == loaded_second.canonical_request_fingerprint) return error.RequestIdentityCollision;
    try writeArtifact(io, allocator, output_dir, "artifacts/values/multiple-residual.second.payload.loaded-value", loaded_second.canonical_payload_image);
    const second_state = try loaded_session.freeze(allocator);
    defer allocator.free(second_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/multiple-residual.second.parked.loaded-session", second_state);
    try writeArtifact(
        io,
        allocator,
        output_dir,
        "artifacts/states/multiple-residual.after-duplicate.loaded-session",
        second_state,
    );

    var loaded_control = try MultipleTarget.Module.LoadedModule.Session.startExecutable(
        allocator,
        &loaded,
        MultipleTarget.Module.LoadedExecutionProfile.portableV2(),
    );
    defer loaded_control.deinit();
    const loaded_control_first = switch (loaded_control.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    try loaded_control.@"resume"(loaded_control_first, first_response);
    _ = switch (loaded_control.next()) {
        .request => |request| request,
        .done => return error.UnexpectedLoadedDone,
        .failed => return error.UnexpectedLoadedFailure,
    };
    const loaded_before_duplicate = try loaded_control.freeze(allocator);
    defer allocator.free(loaded_before_duplicate);
    try expectEqualBytes(loaded_before_duplicate, second_state);
    try writeArtifact(
        io,
        allocator,
        output_dir,
        "artifacts/states/multiple-residual.before-duplicate.loaded-session",
        loaded_before_duplicate,
    );

    const second_response = try MultipleTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        .{},
        .{ .codec = .i32 },
        .{ .i32 = 13 },
        .{},
    );
    defer allocator.free(second_response);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/multiple-residual.second.response.loaded-value", second_response);
    var generated_stale_error: ?anyerror = null;
    generated.@"resume"(generated_first, @as(i32, 13)) catch |err| {
        generated_stale_error = err;
    };
    if (generated_stale_error == null or generated_stale_error.? != error.ProgramContractViolation) {
        return error.StaleResponseAccepted;
    }
    var generated_after_stale = try generated.capture(allocator);
    defer generated_after_stale.deinit();
    var generated_after_stale_image = try generated_after_stale.encode(allocator);
    defer generated_after_stale_image.deinit();
    try expectEqualBytes(generated_second_capsule_image.bytes, generated_after_stale_image.bytes);
    try writeArtifact(
        io,
        allocator,
        output_dir,
        "artifacts/capsules/multiple-residual.after-stale.program-session",
        generated_after_stale_image.bytes,
    );
    var stale_error: ?anyerror = null;
    loaded_session.@"resume"(loaded_first, second_response) catch |err| {
        stale_error = err;
    };
    if (stale_error == null or stale_error.? != error.InvalidResume) return error.StaleResponseAccepted;
    const after_stale_state = try loaded_session.freeze(allocator);
    defer allocator.free(after_stale_state);
    try expectEqualBytes(second_state, after_stale_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/multiple-residual.after-stale.loaded-session", after_stale_state);

    try generated.@"resume"(generated_second, @as(i32, 13));
    try loaded_session.@"resume"(loaded_second, second_response);
    var generated_done = switch (try generated.next()) {
        .done => |done| done,
        .request => return error.UnexpectedGeneratedRequest,
        .after => return error.UnexpectedGeneratedAfter,
    };
    defer generated_done.deinit();
    const loaded_done = switch (loaded_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };
    var result_arena = MultipleTarget.Module.LoadedValueArena.init(allocator);
    defer result_arena.deinit();
    const result = try MultipleTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &result_arena,
        .{},
        .{ .codec = .i32 },
        loaded_done.canonical_result_image,
        .{},
    );
    try expectEqualI32(generated_done.value, result.i32);
    try expectEqualI32(13, result.i32);
    try writeArtifact(io, allocator, output_dir, "artifacts/values/multiple-residual.result.loaded-value", loaded_done.canonical_result_image);
    const completed_state = try loaded_session.freeze(allocator);
    defer allocator.free(completed_state);
    try writeArtifact(io, allocator, output_dir, "artifacts/states/multiple-residual.completed.loaded-session", completed_state);

    const transcript = try std.fmt.allocPrint(allocator,
        \\case_id: multiple-residual
        \\generated_status: completed
        \\loaded_status: completed
        \\request_count: 2
        \\first_site_index: {d}
        \\first_site_fingerprint: 0x{x:0>16}
        \\first_request_fingerprint: 0x{x:0>16}
        \\second_site_index: {d}
        \\second_site_fingerprint: 0x{x:0>16}
        \\second_request_fingerprint: 0x{x:0>16}
        \\generated_result_i32: {d}
        \\loaded_result_i32: {d}
        \\module: artifacts/modules/multiple-residual.full-module
        \\first_state: artifacts/states/multiple-residual.first.parked.loaded-session
        \\second_state: artifacts/states/multiple-residual.second.parked.loaded-session
        \\completed_state: artifacts/states/multiple-residual.completed.loaded-session
        \\
    , .{
        loaded_first.residual_site_index,
        loaded_first.residual_site_fingerprint,
        loaded_first.canonical_request_fingerprint,
        loaded_second.residual_site_index,
        loaded_second.residual_site_fingerprint,
        loaded_second.canonical_request_fingerprint,
        generated_done.value,
        result.i32,
    });
    defer allocator.free(transcript);
    try writeArtifact(io, allocator, output_dir, "cases/multiple-residual.txt", transcript);

    const rejection_transcript = try std.fmt.allocPrint(allocator,
        \\case_id: duplicate-stale-response
        \\generated_duplicate_error: {s}
        \\duplicate_error: {s}
        \\generated_stale_error: {s}
        \\stale_error: {s}
        \\generated_state_unchanged_after_duplicate: true
        \\loaded_state_unchanged_after_duplicate: true
        \\generated_state_unchanged_after_stale: true
        \\second_state_unchanged_after_stale: true
        \\first_request_fingerprint: 0x{x:0>16}
        \\second_request_fingerprint: 0x{x:0>16}
        \\prior_state: artifacts/states/multiple-residual.second.parked.loaded-session
        \\next_state: artifacts/states/multiple-residual.after-stale.loaded-session
        \\generated_prior_state: artifacts/capsules/multiple-residual.second.program-session
        \\generated_next_state: artifacts/capsules/multiple-residual.after-stale.program-session
        \\
    , .{
        @errorName(generated_duplicate_error.?),
        @errorName(duplicate_error.?),
        @errorName(generated_stale_error.?),
        @errorName(stale_error.?),
        loaded_first.canonical_request_fingerprint,
        loaded_second.canonical_request_fingerprint,
    });
    defer allocator.free(rejection_transcript);
    try writeArtifact(io, allocator, output_dir, "cases/duplicate-stale-response.txt", rejection_transcript);
}

fn emitAgentArtifacts(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    try agent_loop.exportWorldImageV1Oracle(init, allocator, output_dir);
}

const Case = struct {
    case_id: []const u8,
    transcript: []const u8,
};

const cases = [_]Case{
    .{ .case_id = "scalar-pure", .transcript = "cases/scalar-pure.txt" },
    .{ .case_id = "one-effect", .transcript = "cases/one-effect.txt" },
    .{ .case_id = "typed-product-sum", .transcript = "cases/typed-product-sum.txt" },
    .{ .case_id = "helper-call", .transcript = "cases/helper-call.txt" },
    .{ .case_id = "portable-word", .transcript = "cases/portable-word.txt" },
    .{ .case_id = "helper-park", .transcript = "cases/helper-park.txt" },
    .{ .case_id = "multiple-residual", .transcript = "cases/multiple-residual.txt" },
    .{ .case_id = "budget-exhaustion", .transcript = "cases/budget-exhaustion.txt" },
    .{ .case_id = "malformed-response", .transcript = "cases/malformed-response.txt" },
    .{ .case_id = "duplicate-stale-response", .transcript = "cases/duplicate-stale-response.txt" },
    .{ .case_id = "agent-skeleton", .transcript = "cases/agent-skeleton.txt" },
    .{ .case_id = "agent-file-fixture", .transcript = "cases/agent-file-fixture.txt" },
    .{ .case_id = "loaded-provider", .transcript = "cases/loaded-provider.txt" },
};

const OwnedPaths = struct {
    allocator: std.mem.Allocator,
    items: [][]u8,

    fn deinit(self: *@This()) void {
        for (self.items) |item| self.allocator.free(item);
        self.allocator.free(self.items);
        self.items = &.{};
    }
};

fn pathLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn isWindowsReservedOracleComponent(component: []const u8) bool {
    const stem_end = std.mem.findScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    if (std.ascii.eqlIgnoreCase(stem, "CON") or
        std.ascii.eqlIgnoreCase(stem, "PRN") or
        std.ascii.eqlIgnoreCase(stem, "AUX") or
        std.ascii.eqlIgnoreCase(stem, "NUL"))
    {
        return true;
    }
    if (stem.len == 4 and
        (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and
        stem[3] >= '1' and stem[3] <= '9')
    {
        return true;
    }
    return false;
}

fn validateCanonicalOracleRelativePath(path: []const u8) !void {
    if (path.len == 0 or path[0] == '/' or path[path.len - 1] == '/') return error.NonPortableOraclePath;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or
            std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, "..") or
            component[component.len - 1] == '.' or
            component[component.len - 1] == ' ' or
            isWindowsReservedOracleComponent(component))
        {
            return error.NonPortableOraclePath;
        }
        for (component) |byte| {
            // The v0 corpus uses printable ASCII names so its checkout
            // equivalence relation is exactly the ASCII fold implemented below.
            if (byte < 0x20 or byte >= 0x7f or std.mem.findScalar(u8, "<>:\"|?*", byte) != null) {
                return error.NonPortableOraclePath;
            }
        }
    }
}

fn oraclePathsEqualFolded(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

fn oraclePathsConflictOnPortableCheckout(lhs: []const u8, rhs: []const u8) bool {
    var left_components = std.mem.splitScalar(u8, lhs, '/');
    var right_components = std.mem.splitScalar(u8, rhs, '/');
    while (true) {
        const left = left_components.next();
        const right = right_components.next();
        if (left == null or right == null) return left == null or right == null;
        if (!std.ascii.eqlIgnoreCase(left.?, right.?)) return false;
        if (!std.mem.eql(u8, left.?, right.?)) return true;
    }
}

fn canonicalOracleRelativePath(
    allocator: std.mem.Allocator,
    walked_path: []const u8,
    walk_separator: u8,
) ![]u8 {
    std.debug.assert(walk_separator == '/' or walk_separator == '\\');
    const canonical = try allocator.dupe(u8, walked_path);
    errdefer allocator.free(canonical);
    for (canonical) |*byte| {
        if (byte.* == walk_separator) {
            byte.* = '/';
        } else if (byte.* == '\\') {
            return error.NonPortableOraclePath;
        }
    }
    try validateCanonicalOracleRelativePath(canonical);
    return canonical;
}

fn openOracleRootNoFollow(io: std.Io, root_path: []const u8) !std.Io.Dir {
    if (root_path.len == 0) return error.UnsafeOraclePath;
    var components = std.Io.Dir.path.componentIterator(root_path);
    var current = std.Io.Dir.cwd();
    var owns_current = false;
    errdefer if (owns_current) current.close(io);

    if (components.root()) |root| {
        current = std.Io.Dir.openDirAbsolute(io, root, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| return mapOracleRootOpenError(err);
        owns_current = true;
    }
    while (components.next()) |component| {
        if (std.mem.eql(u8, component.name, ".")) continue;
        if (std.mem.eql(u8, component.name, "..")) return error.UnsafeOraclePath;
        const child = current.openDir(io, component.name, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| return mapOracleRootOpenError(err);
        if (owns_current) current.close(io);
        current = child;
        owns_current = true;
    }
    if (!owns_current) return error.UnsafeOraclePath;
    return current;
}

fn mapOracleRootOpenError(err: anyerror) anyerror {
    return switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.SymLinkLoop,
        error.BadPathName,
        error.NameTooLong,
        => error.UnsafeOraclePath,
        else => err,
    };
}

fn listFiles(io: std.Io, allocator: std.mem.Allocator, root: []const u8) !OwnedPaths {
    var dir = try openOracleRootNoFollow(io, root);
    defer dir.close(io);
    return listFilesFromDir(io, allocator, dir);
}

fn listFilesFromDir(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir) !OwnedPaths {
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var items: std.ArrayList([]u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .file => try items.append(
                allocator,
                try canonicalOracleRelativePath(allocator, entry.path, std.Io.Dir.path.sep),
            ),
            .directory => {},
            .block_device,
            .character_device,
            .named_pipe,
            .sym_link,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedOracleTreeEntry,
        }
    }
    const owned = try items.toOwnedSlice(allocator);
    errdefer {
        for (owned) |item| allocator.free(item);
        allocator.free(owned);
    }
    std.mem.sort([]u8, owned, {}, pathLessThan);
    for (owned, 0..) |path, index| {
        for (owned[index + 1 ..]) |other| {
            if (oraclePathsConflictOnPortableCheckout(path, other)) return error.NonPortableOraclePathCollision;
        }
    }
    return .{ .allocator = allocator, .items = owned };
}

fn readRelative(
    io: std.Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    relative_path: []const u8,
) ![]u8 {
    var dir = try openOracleRootNoFollow(io, root);
    defer dir.close(io);
    return readRelativeFromDir(io, allocator, dir, relative_path);
}

fn readRelativeFromDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    root: std.Io.Dir,
    relative_path: []const u8,
) ![]u8 {
    try validateCanonicalOracleRelativePath(relative_path);

    var components = std.mem.splitScalar(u8, relative_path, '/');
    var leaf = components.next() orelse return error.NonPortableOraclePath;
    var dir = root;
    var owns_dir = false;
    defer if (owns_dir) dir.close(io);
    while (components.next()) |next| {
        const child = try dir.openDir(io, leaf, .{
            .follow_symlinks = false,
        });
        if (owns_dir) dir.close(io);
        dir = child;
        owns_dir = true;
        leaf = next;
    }

    var file = try openOracleFileNoFollowNonblocking(io, dir, leaf);
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file) return error.UnsupportedOracleTreeEntry;

    var reader = file.reader(io, &.{});
    return reader.interface.allocRemaining(allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        else => |read_err| return read_err,
    };
}

fn openOracleFileNoFollowNonblocking(
    io: std.Io,
    parent: std.Io.Dir,
    leaf: []const u8,
) !std.Io.File {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) {
        return parent.openFile(io, leaf, .{
            .allow_directory = false,
            .follow_symlinks = false,
        });
    }

    var flags: std.posix.O = .{};
    if (@hasField(std.posix.O, "NONBLOCK")) {
        @field(flags, "NONBLOCK") = true;
    } else {
        @compileError("Boundary oracle validation requires nonblocking file opens");
    }
    if (@hasField(std.posix.O, "NOFOLLOW")) {
        @field(flags, "NOFOLLOW") = true;
    } else {
        @compileError("Boundary oracle validation requires no-follow file opens");
    }
    if (@hasField(std.posix.O, "CLOEXEC")) {
        @field(flags, "CLOEXEC") = true;
    }
    return .{
        .handle = try std.posix.openat(parent.handle, leaf, flags, 0),
        .flags = .{ .nonblocking = true },
    };
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest = [_]u8{0} ** 32;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn digestHex(digest: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

fn parseReceiverPin(bytes: []const u8) ![]const u8 {
    if (bytes.len != 65 or bytes[64] != '\n') return error.InvalidOracleReceiverPin;
    for (bytes[0..64]) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) {
            return error.InvalidOracleReceiverPin;
        }
    }
    return bytes[0..64];
}

fn appendFmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const bytes = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(bytes);
    try out.appendSlice(allocator, bytes);
}

const OracleManifestSemanticSource = struct {
    package: []const u8,
    package_version: []const u8,
    baseline_commit: []const u8,
    baseline_tree: []const u8,
    module_magic: []const u8,
    loaded_execution_profile: u32,
    loaded_session_image: u32,
    zig_version: []const u8,
};

const oracle_semantic_source = OracleManifestSemanticSource{
    .package = "boundary",
    .package_version = boundary.Protocol.Manifest.boundary_package_version,
    .baseline_commit = "6a416951f8d22d0854616f094f23b2d44ab021a2",
    .baseline_tree = "950838431ef965f21926b4ea14361f69bc16c2dd",
    .module_magic = ScalarProgram.Evidence.BoundaryTargetModule.magic,
    .loaded_execution_profile = ScalarTarget.Module.LoadedExecution.loaded_execution_profile_format_version_v2,
    .loaded_session_image = ScalarTarget.Module.LoadedExecution.loaded_session_image_format_version_v2,
    .zig_version = builtin.zig_version_string,
};

fn writeManifest(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    var paths = try listFiles(init.io, allocator, output_dir);
    defer paths.deinit();
    if (paths.items.len == 0) return error.EmptyOracle;

    var artifact_set_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (paths.items) |relative_path| {
        const bytes = try readRelative(init.io, allocator, output_dir, relative_path);
        defer allocator.free(bytes);
        const digest = sha256(bytes);
        var length_bytes = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &length_bytes, @intCast(bytes.len), .little);
        artifact_set_hasher.update(relative_path);
        artifact_set_hasher.update(&.{0});
        artifact_set_hasher.update(&length_bytes);
        artifact_set_hasher.update(&digest);
    }
    var artifact_set_digest = [_]u8{0} ** 32;
    artifact_set_hasher.final(&artifact_set_digest);
    const artifact_set_hex = digestHex(artifact_set_digest);

    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(allocator);
    const semantic_source_json = try std.json.Stringify.valueAlloc(
        allocator,
        oracle_semantic_source,
        .{},
    );
    defer allocator.free(semantic_source_json);
    const generator_json = try std.json.Stringify.valueAlloc(allocator, oracle_generator_command, .{});
    defer allocator.free(generator_json);
    const normal_check_json = try std.json.Stringify.valueAlloc(allocator, oracle_normal_check_command, .{});
    defer allocator.free(normal_check_json);
    try manifest.appendSlice(allocator,
        \\{
        \\  "format": "boundary-world-image-v1-rewrite-oracle-v0",
        \\  "format_version": 1,
        \\  "semantic_source":
    );
    try manifest.append(allocator, ' ');
    try manifest.appendSlice(allocator, semantic_source_json);
    try manifest.appendSlice(allocator, ",\n  \"generator\": ");
    try manifest.appendSlice(allocator, generator_json);
    try manifest.appendSlice(allocator, ",\n  \"normal_check\": ");
    try manifest.appendSlice(allocator, normal_check_json);
    try manifest.appendSlice(allocator, ",\n");
    try appendFmt(&manifest, allocator, "  \"case_count\": {d},\n", .{cases.len});
    try manifest.appendSlice(allocator, "  \"cases\": [");
    for (cases, 0..) |case, index| {
        try appendFmt(
            &manifest,
            allocator,
            "    {{\"id\":\"{s}\",\"transcript\":\"{s}\"}}{s}\n",
            .{ case.case_id, case.transcript, if (index + 1 == cases.len) "" else "," },
        );
    }
    try appendFmt(&manifest, allocator,
        \\  ],
        \\  "artifact_set_sha256": "{s}",
        \\  "artifact_count": {d},
        \\  "artifacts": [
        \\
    , .{ &artifact_set_hex, paths.items.len });
    for (paths.items, 0..) |relative_path, index| {
        const bytes = try readRelative(init.io, allocator, output_dir, relative_path);
        defer allocator.free(bytes);
        const hex = digestHex(sha256(bytes));
        try appendFmt(
            &manifest,
            allocator,
            "    {{\"path\":\"{s}\",\"length\":{d},\"sha256\":\"{s}\"}}{s}\n",
            .{ relative_path, bytes.len, &hex, if (index + 1 == paths.items.len) "" else "," },
        );
    }
    try manifest.appendSlice(allocator,
        \\  ]
        \\}
        \\
    );
    try writeArtifact(init.io, allocator, output_dir, "manifest.json", manifest.items);
}

fn checksumsBytesWithPrefixAndMarker(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    path_prefix: []const u8,
    marker: []const u8,
) ![]u8 {
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return checksumsBytesWithPrefixAndMarkerFromDir(
        init.io,
        allocator,
        dir,
        path_prefix,
        marker,
    );
}

fn checksumsBytesWithPrefixAndMarkerFromDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    path_prefix: []const u8,
    marker: []const u8,
) ![]u8 {
    var paths = try listFilesFromDir(io, allocator, dir);
    defer paths.deinit();
    var checksums: std.ArrayList(u8) = .empty;
    errdefer checksums.deinit(allocator);
    for (paths.items) |relative_path| {
        if (std.mem.eql(u8, relative_path, "checksums.sha256")) continue;
        const bytes = try readRelativeFromDir(io, allocator, dir, relative_path);
        defer allocator.free(bytes);
        const hex = digestHex(sha256(bytes));
        try appendFmt(&checksums, allocator, "{s}{s}{s}{s}\n", .{ &hex, marker, path_prefix, relative_path });
    }
    return checksums.toOwnedSlice(allocator);
}

fn checksumsBytes(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) ![]u8 {
    return checksumsBytesWithPrefixAndMarker(init, allocator, output_dir, "", " *");
}

fn writeChecksums(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const checksums = try checksumsBytes(init, allocator, output_dir);
    defer allocator.free(checksums);
    try writeArtifact(init.io, allocator, output_dir, "checksums.sha256", checksums);
}

fn rewriteOracleMetadata(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    try deleteArtifact(init.io, allocator, output_dir, "manifest.json");
    try deleteArtifact(init.io, allocator, output_dir, "checksums.sha256");
    try writeManifest(init, allocator, output_dir);
    try writeChecksums(init, allocator, output_dir);
    try validateManifest(init, allocator, output_dir, .generated);
    try validateChecksums(init, allocator, output_dir, .current);
}

fn validateRequiredCases(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return validateRequiredCasesFromDir(init.io, allocator, dir);
}

fn validateRequiredCasesFromDir(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir) !void {
    for (cases) |case| {
        const bytes = try readRelativeFromDir(io, allocator, dir, case.transcript);
        defer allocator.free(bytes);
        const expected = try std.fmt.allocPrint(allocator, "case_id: {s}\n", .{case.case_id});
        defer allocator.free(expected);
        if (!std.mem.startsWith(u8, bytes, expected)) return error.MalformedCaseTranscript;
    }
}

const OracleManifestCase = struct {
    id: []const u8,
    transcript: []const u8,
};

const OracleManifestArtifact = struct {
    path: []const u8,
    length: usize,
    sha256: []const u8,
};

const OracleManifest = struct {
    format: []const u8,
    format_version: u16,
    semantic_source: OracleManifestSemanticSource,
    generator: []const u8,
    normal_check: []const u8,
    case_count: usize,
    cases: []const OracleManifestCase,
    artifact_set_sha256: []const u8,
    artifact_count: usize,
    artifacts: []const OracleManifestArtifact,
};

fn isOracleMetadataPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "manifest.json") or std.mem.eql(u8, path, "checksums.sha256");
}

const OracleManifestPolicy = enum {
    integrity,
    generated,
    current,
};

fn validateManifest(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    policy: OracleManifestPolicy,
) !void {
    try requireDirectory(init.io, output_dir);
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return validateManifestFromDir(init.io, allocator, dir, policy);
}

fn validateManifestFromDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    policy: OracleManifestPolicy,
) !void {
    // Inventory first so unsupported entries are rejected before any path is
    // opened as a byte stream (notably FIFOs at manifest or case paths).
    var paths = try listFilesFromDir(io, allocator, dir);
    defer paths.deinit();
    const manifest_bytes = try readRelativeFromDir(io, allocator, dir, "manifest.json");
    defer allocator.free(manifest_bytes);
    const parsed = std.json.parseFromSlice(OracleManifest, allocator, manifest_bytes, .{
        .ignore_unknown_fields = false,
    }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.InvalidOracleManifest,
    };
    defer parsed.deinit();
    const manifest = parsed.value;
    if (!std.mem.eql(u8, manifest.format, "boundary-world-image-v1-rewrite-oracle-v0") or
        manifest.format_version != 1 or
        manifest.case_count != manifest.cases.len or
        manifest.case_count == 0 or
        manifest.artifact_count == 0)
    {
        return error.InvalidOracleManifest;
    }
    if (policy != .integrity) {
        if (manifest.case_count != cases.len) return error.InvalidOracleManifest;
        const source = manifest.semantic_source;
        if (!std.mem.eql(u8, source.package, oracle_semantic_source.package) or
            !std.mem.eql(u8, source.package_version, oracle_semantic_source.package_version) or
            !std.mem.eql(u8, source.baseline_commit, oracle_semantic_source.baseline_commit) or
            !std.mem.eql(u8, source.baseline_tree, oracle_semantic_source.baseline_tree) or
            !std.mem.eql(u8, source.module_magic, oracle_semantic_source.module_magic) or
            source.loaded_execution_profile != oracle_semantic_source.loaded_execution_profile or
            source.loaded_session_image != oracle_semantic_source.loaded_session_image or
            !std.mem.eql(u8, source.zig_version, oracle_semantic_source.zig_version) or
            !std.mem.eql(u8, manifest.generator, oracle_generator_command) or
            !std.mem.eql(u8, manifest.normal_check, oracle_normal_check_command))
        {
            return error.InvalidOracleManifest;
        }
        for (cases, manifest.cases) |expected, actual| {
            if (!std.mem.eql(u8, expected.case_id, actual.id) or
                !std.mem.eql(u8, expected.transcript, actual.transcript))
            {
                return error.InvalidOracleManifest;
            }
        }
    }

    var payload_count: usize = 0;
    for (paths.items) |path| if (!isOracleMetadataPath(path)) {
        payload_count += 1;
    };
    if (manifest.artifact_count != payload_count or manifest.artifacts.len != payload_count) {
        return error.InvalidOracleManifest;
    }

    var artifact_set_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var artifact_index: usize = 0;
    for (paths.items) |relative_path| {
        if (isOracleMetadataPath(relative_path)) continue;
        const bytes = try readRelativeFromDir(io, allocator, dir, relative_path);
        defer allocator.free(bytes);
        const digest = sha256(bytes);
        const hex = digestHex(digest);
        const artifact = manifest.artifacts[artifact_index];
        if (!std.mem.eql(u8, artifact.path, relative_path) or artifact.length != bytes.len or
            !std.mem.eql(u8, artifact.sha256, &hex))
        {
            return error.InvalidOracleManifest;
        }
        var length_bytes = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &length_bytes, @intCast(bytes.len), .little);
        artifact_set_hasher.update(relative_path);
        artifact_set_hasher.update(&.{0});
        artifact_set_hasher.update(&length_bytes);
        artifact_set_hasher.update(&digest);
        artifact_index += 1;
    }
    var artifact_set_digest = [_]u8{0} ** 32;
    artifact_set_hasher.final(&artifact_set_digest);
    const artifact_set_hex = digestHex(artifact_set_digest);
    if (!std.mem.eql(u8, manifest.artifact_set_sha256, &artifact_set_hex)) {
        return error.InvalidOracleManifest;
    }
    for (manifest.cases) |case| {
        try validateCanonicalOracleRelativePath(case.transcript);
        if (isOracleMetadataPath(case.transcript)) return error.InvalidOracleManifest;
        var retained = false;
        for (paths.items) |path| {
            if (std.mem.eql(u8, case.transcript, path)) {
                retained = true;
                break;
            }
        }
        if (!retained) return error.InvalidOracleManifest;
        const transcript = try readRelativeFromDir(io, allocator, dir, case.transcript);
        defer allocator.free(transcript);
        const expected_prefix = try std.fmt.allocPrint(allocator, "case_id: {s}\n", .{case.id});
        defer allocator.free(expected_prefix);
        if (!std.mem.startsWith(u8, transcript, expected_prefix)) return error.InvalidOracleManifest;
    }
}

fn oracleReceiverPin(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) ![64]u8 {
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return oracleReceiverPinFromDir(init.io, allocator, dir);
}

fn oracleReceiverPinFromDir(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir) ![64]u8 {
    const checksum_bytes = try readRelativeFromDir(io, allocator, dir, "checksums.sha256");
    defer allocator.free(checksum_bytes);
    return digestHex(sha256(checksum_bytes));
}

fn validateOracleReceiverPinFromDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    receiver_pin: []const u8,
) !void {
    const candidate_pin = try oracleReceiverPinFromDir(io, allocator, dir);
    if (!std.mem.eql(u8, receiver_pin, &candidate_pin)) return error.OracleReceiverPinMismatch;
}

const OracleChecksumPolicy = enum {
    integrity,
    current,
};

fn validateChecksums(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    policy: OracleChecksumPolicy,
) !void {
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return validateChecksumsFromDir(init.io, allocator, dir, policy);
}

fn validateChecksumsFromDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    policy: OracleChecksumPolicy,
) !void {
    const actual = try readRelativeFromDir(io, allocator, dir, "checksums.sha256");
    defer allocator.free(actual);
    const expected = try checksumsBytesWithPrefixAndMarkerFromDir(io, allocator, dir, "", " *");
    defer allocator.free(expected);
    if (std.mem.eql(u8, expected, actual)) return;
    if (policy == .integrity) {
        const legacy_relative = try checksumsBytesWithPrefixAndMarkerFromDir(io, allocator, dir, "", "  ");
        defer allocator.free(legacy_relative);
        if (std.mem.eql(u8, legacy_relative, actual)) return;
        const legacy_prefixed = try checksumsBytesWithPrefixAndMarkerFromDir(
            io,
            allocator,
            dir,
            corpus_path ++ "/",
            "  ",
        );
        defer allocator.free(legacy_prefixed);
        if (std.mem.eql(u8, legacy_prefixed, actual)) return;
    }
    return error.InvalidOracleChecksums;
}

fn validateOracleTree(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    receiver_pin: []const u8,
) !void {
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return validateOracleTreeFromDir(init.io, allocator, dir, receiver_pin);
}

fn validateOracleTreeIntegrity(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    try requireDirectory(init.io, output_dir);
    var dir = try openOracleRootNoFollow(init.io, output_dir);
    defer dir.close(init.io);
    return validateOracleTreeIntegrityFromDir(init.io, allocator, dir);
}

fn validateOracleTreeFromDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    receiver_pin: []const u8,
) !void {
    try validateManifestFromDir(io, allocator, dir, .current);
    try validateRequiredCasesFromDir(io, allocator, dir);
    try validateChecksumsFromDir(io, allocator, dir, .current);
    try validateOracleReceiverPinFromDir(io, allocator, dir, receiver_pin);
}

fn validateOracleTreeIntegrityFromDir(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir) !void {
    try validateManifestFromDir(io, allocator, dir, .integrity);
    try validateChecksumsFromDir(io, allocator, dir, .integrity);
}

fn generateFresh(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    try createFreshDirectory(init.io, output_dir);
    errdefer deleteDirectoryIfPresent(init.io, output_dir) catch {};
    try emitScalarAndBudget(init, allocator, output_dir);
    try emitHelperCall(init, allocator, output_dir);
    try emitPortableWord(init, allocator, output_dir);
    try emitOneEffect(init, allocator, output_dir);
    try emitStructured(init, allocator, output_dir);
    try emitHelperPark(init, allocator, output_dir);
    try emitMultipleResidual(init, allocator, output_dir);
    try emitAgentArtifacts(init, allocator, output_dir);
    try validateRequiredCases(init, allocator, output_dir);
    try writeManifest(init, allocator, output_dir);
    try writeChecksums(init, allocator, output_dir);
    try requireDirectory(init.io, output_dir);
    try validateRequiredCases(init, allocator, output_dir);
    try validateManifest(init, allocator, output_dir, .generated);
    try validateChecksums(init, allocator, output_dir, .current);
}

fn copyOracleTree(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    source_dir: []const u8,
    target_dir: []const u8,
) !void {
    try requireDirectory(init.io, source_dir);
    try createFreshDirectory(init.io, target_dir);
    errdefer deleteDirectoryIfPresent(init.io, target_dir) catch {};
    var paths = try listFiles(init.io, allocator, source_dir);
    defer paths.deinit();
    for (paths.items) |relative_path| {
        const bytes = try readRelative(init.io, allocator, source_dir, relative_path);
        defer allocator.free(bytes);
        try writeArtifact(init.io, allocator, target_dir, relative_path, bytes);
    }
}

const PublicationPaths = struct {
    target: []const u8,
    stage: []const u8,
    backup: []const u8,
};

const PublicationRoot = struct {
    dir: std.Io.Dir,
    target: []const u8,
    stage: []const u8,
    backup: []const u8,

    fn open(io: std.Io, paths: PublicationPaths) !PublicationRoot {
        const parent = std.Io.Dir.path.dirname(paths.target) orelse return error.UnsafeOraclePath;
        if (!std.mem.eql(u8, parent, std.Io.Dir.path.dirname(paths.stage) orelse return error.UnsafeOraclePath) or
            !std.mem.eql(u8, parent, std.Io.Dir.path.dirname(paths.backup) orelse return error.UnsafeOraclePath))
        {
            return error.UnsafeOraclePath;
        }
        const target = std.Io.Dir.path.basename(paths.target);
        const stage = std.Io.Dir.path.basename(paths.stage);
        const backup = std.Io.Dir.path.basename(paths.backup);
        inline for (.{ target, stage, backup }) |leaf| {
            if (leaf.len == 0 or
                std.mem.eql(u8, leaf, ".") or
                std.mem.eql(u8, leaf, "..") or
                std.Io.Dir.path.isAbsolute(leaf) or
                std.mem.findScalar(u8, leaf, '/') != null or
                std.mem.findScalar(u8, leaf, '\\') != null)
            {
                return error.UnsafeOraclePath;
            }
        }
        if (std.mem.eql(u8, target, stage) or
            std.mem.eql(u8, target, backup) or
            std.mem.eql(u8, stage, backup))
        {
            return error.UnsafeOraclePath;
        }
        return .{
            .dir = try openOracleRootNoFollow(io, parent),
            .target = target,
            .stage = stage,
            .backup = backup,
        };
    }

    fn close(root: PublicationRoot, io: std.Io) void {
        root.dir.close(io);
    }

    fn openTree(root: PublicationRoot, io: std.Io, leaf: []const u8) !std.Io.Dir {
        return root.dir.openDir(io, leaf, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| return mapOracleRootOpenError(err);
    }

    fn pathKind(root: PublicationRoot, io: std.Io, leaf: []const u8) !?std.Io.File.Kind {
        const stat = root.dir.statFile(io, leaf, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        return stat.kind;
    }

    fn requireDirectory(root: PublicationRoot, io: std.Io, leaf: []const u8) !void {
        const kind = try root.pathKind(io, leaf) orelse return error.OracleDirectoryMissing;
        if (kind != .directory) return error.UnsafeOraclePath;
    }

    fn createFreshDirectory(root: PublicationRoot, io: std.Io, leaf: []const u8) !void {
        if (try root.pathKind(io, leaf) != null) return error.OracleOutputExists;
        try root.dir.createDir(io, leaf, .default_dir);
    }

    fn deleteDirectoryIfPresent(root: PublicationRoot, io: std.Io, leaf: []const u8) !void {
        const kind = try root.pathKind(io, leaf) orelse return;
        if (kind != .directory) return error.UnsafeOraclePath;
        try root.dir.deleteTree(io, leaf);
    }

    fn renameDirectoryToMissing(
        root: PublicationRoot,
        io: std.Io,
        source: []const u8,
        target: []const u8,
    ) !void {
        try root.requireDirectory(io, source);
        if (try root.pathKind(io, target) != null) return error.OraclePublicationConflict;
        try root.dir.rename(source, root.dir, target, io);
    }
};

fn copyOracleTreeToPublicationLeaf(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    source_dir: []const u8,
    root: PublicationRoot,
    target: []const u8,
) !void {
    try requireDirectory(init.io, source_dir);
    try root.createFreshDirectory(init.io, target);
    errdefer root.deleteDirectoryIfPresent(init.io, target) catch {};
    var target_dir = try root.openTree(init.io, target);
    defer target_dir.close(init.io);
    var paths = try listFiles(init.io, allocator, source_dir);
    defer paths.deinit();
    for (paths.items) |relative_path| {
        const bytes = try readRelative(init.io, allocator, source_dir, relative_path);
        defer allocator.free(bytes);
        try writeArtifactFromDir(init.io, target_dir, relative_path, bytes);
    }
}

fn validateOracleTreeAtPublicationLeaf(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    root: PublicationRoot,
    leaf: []const u8,
    receiver_pin: []const u8,
) !void {
    try root.requireDirectory(init.io, leaf);
    var dir = try root.openTree(init.io, leaf);
    defer dir.close(init.io);
    try validateOracleTreeFromDir(init.io, allocator, dir, receiver_pin);
}

fn validateOracleTreeIntegrityAtPublicationLeaf(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    root: PublicationRoot,
    leaf: []const u8,
) !void {
    try root.requireDirectory(init.io, leaf);
    var dir = try root.openTree(init.io, leaf);
    defer dir.close(init.io);
    try validateOracleTreeIntegrityFromDir(init.io, allocator, dir);
}

fn writeArtifactAtPublicationLeaf(
    init: std.process.Init,
    root: PublicationRoot,
    leaf: []const u8,
    relative_path: []const u8,
    bytes: []const u8,
) !void {
    try root.requireDirectory(init.io, leaf);
    var dir = try root.openTree(init.io, leaf);
    defer dir.close(init.io);
    try writeArtifactFromDir(init.io, dir, relative_path, bytes);
}

const PublicationFault = enum {
    none,
    after_backup,
    rollback_conflict,
    during_backup_cleanup,
};

const PublicationOutcome = union(enum) {
    committed,
    committed_cleanup_pending: anyerror,
};

const PublicationRequest = struct {
    candidate_dir: []const u8,
    receiver_pin: []const u8,
    paths: PublicationPaths,
    fault: PublicationFault,
};

fn publicationRequest(
    candidate_dir: []const u8,
    receiver_pin: []const u8,
    paths: PublicationPaths,
    fault: PublicationFault,
) PublicationRequest {
    return .{
        .candidate_dir = candidate_dir,
        .receiver_pin = receiver_pin,
        .paths = paths,
        .fault = fault,
    };
}

fn isOracleIntegrityFailure(err: anyerror) bool {
    return switch (err) {
        error.InvalidOracleManifest,
        error.InvalidOracleChecksums,
        error.OracleDirectoryMissing,
        error.UnsafeOraclePath,
        error.UnsupportedOracleTreeEntry,
        error.NonPortableOraclePath,
        error.NonPortableOraclePathCollision,
        error.FileNotFound,
        error.IsDir,
        error.NotDir,
        error.StreamTooLong,
        error.SymLinkLoop,
        error.BadPathName,
        error.NameTooLong,
        => true,
        else => false,
    };
}

fn recoverPublication(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    paths: PublicationPaths,
) !void {
    const root = try PublicationRoot.open(init.io, paths);
    defer root.close(init.io);
    try recoverPublicationAtRoot(init, allocator, root);
}

fn recoverPublicationAtRoot(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    root: PublicationRoot,
) !void {
    const backup_kind = try root.pathKind(init.io, root.backup);
    const target_kind = try root.pathKind(init.io, root.target);
    if (backup_kind) |kind| {
        if (kind != .directory) return error.UnsafeOraclePath;
        if (target_kind == null) {
            try validateOracleTreeIntegrityAtPublicationLeaf(init, allocator, root, root.backup);
            try root.renameDirectoryToMissing(init.io, root.backup, root.target);
        } else {
            if (target_kind.? != .directory) return error.UnsafeOraclePath;
            var target_valid = true;
            validateOracleTreeIntegrityAtPublicationLeaf(init, allocator, root, root.target) catch |err| {
                if (!isOracleIntegrityFailure(err)) return err;
                target_valid = false;
            };
            if (target_valid) {
                try root.deleteDirectoryIfPresent(init.io, root.backup);
            } else {
                try validateOracleTreeIntegrityAtPublicationLeaf(init, allocator, root, root.backup);
                try root.deleteDirectoryIfPresent(init.io, root.target);
                try root.renameDirectoryToMissing(init.io, root.backup, root.target);
            }
        }
    } else if (target_kind) |kind| {
        if (kind != .directory) return error.UnsafeOraclePath;
    }

    const stage_kind = try root.pathKind(init.io, root.stage);
    if (stage_kind) |kind| {
        if (kind != .directory) return error.UnsafeOraclePath;
        try root.deleteDirectoryIfPresent(init.io, root.stage);
    }
}

fn publishOracleTree(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    request: PublicationRequest,
) !PublicationOutcome {
    const root = try PublicationRoot.open(init.io, request.paths);
    defer root.close(init.io);
    try recoverPublicationAtRoot(init, allocator, root);
    try validateOracleTree(init, allocator, request.candidate_dir, request.receiver_pin);
    try validateOracleTreeIntegrityAtPublicationLeaf(init, allocator, root, root.target);
    try copyOracleTreeToPublicationLeaf(init, allocator, request.candidate_dir, root, root.stage);
    errdefer root.deleteDirectoryIfPresent(init.io, root.stage) catch {};
    try validateOracleTreeAtPublicationLeaf(init, allocator, root, root.stage, request.receiver_pin);

    try root.renameDirectoryToMissing(init.io, root.target, root.backup);
    var target_promoted = false;
    promoteOracleTree(init, allocator, request, root, &target_promoted) catch |promotion_error| {
        if (target_promoted) try root.deleteDirectoryIfPresent(init.io, root.target);
        try root.renameDirectoryToMissing(init.io, root.backup, root.target);
        return promotion_error;
    };
    if (request.fault == .during_backup_cleanup) {
        try writeArtifactAtPublicationLeaf(
            init,
            root,
            root.backup,
            "cases/scalar-pure.txt",
            "partial-backup\n",
        );
        return .{ .committed_cleanup_pending = error.InjectedOracleBackupCleanupFailure };
    }
    root.deleteDirectoryIfPresent(init.io, root.backup) catch |err| {
        return .{ .committed_cleanup_pending = err };
    };
    return .committed;
}

fn promoteOracleTree(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    request: PublicationRequest,
    root: PublicationRoot,
    target_promoted: *bool,
) !void {
    if (request.fault == .after_backup) return error.InjectedOraclePublicationFailure;
    if (request.fault == .rollback_conflict) {
        try root.dir.writeFile(init.io, .{ .sub_path = root.target, .data = "rollback-conflict\n" });
        return error.InjectedOraclePublicationFailure;
    }
    try root.renameDirectoryToMissing(init.io, root.stage, root.target);
    target_promoted.* = true;
    try validateOracleTreeAtPublicationLeaf(init, allocator, root, root.target, request.receiver_pin);
}

fn publishTrackedOracle(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    candidate_dir: []const u8,
    receiver_pin: []const u8,
) !void {
    const outcome = publishOracleTree(init, allocator, .{
        .candidate_dir = candidate_dir,
        .receiver_pin = receiver_pin,
        .paths = .{
            .target = corpus_path,
            .stage = tracked_publication_stage_path,
            .backup = tracked_publication_backup_path,
        },
        .fault = .none,
    }) catch |err| {
        if (err == error.OracleReceiverPinMismatch) {
            const candidate_pin = try oracleReceiverPin(init, allocator, candidate_dir);
            std.debug.print(
                "oracle receiver pin mismatch: expected {s}, candidate {s}, candidate tree {s}\n",
                .{ receiver_pin, &candidate_pin, candidate_dir },
            );
        }
        return err;
    };
    switch (outcome) {
        .committed => {},
        .committed_cleanup_pending => |cleanup_error| std.debug.print(
            "oracle publication committed; backup cleanup remains pending after {s}\n",
            .{@errorName(cleanup_error)},
        ),
    }
}

fn compareTrees(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    expected_dir: []const u8,
    actual_dir: []const u8,
) !void {
    var expected_paths = try listFiles(init.io, allocator, expected_dir);
    defer expected_paths.deinit();
    var actual_paths = try listFiles(init.io, allocator, actual_dir);
    defer actual_paths.deinit();
    if (expected_paths.items.len != actual_paths.items.len) return error.OracleFileSetDrift;
    for (expected_paths.items, actual_paths.items) |expected_path, actual_path| {
        if (!std.mem.eql(u8, expected_path, actual_path)) return error.OracleFileSetDrift;
        const expected = try readRelative(init.io, allocator, expected_dir, expected_path);
        defer allocator.free(expected);
        const actual = try readRelative(init.io, allocator, actual_dir, actual_path);
        defer allocator.free(actual);
        if (!std.mem.eql(u8, expected, actual)) return error.OracleByteDrift;
    }
}

fn expectPublicationError(expected: anyerror, actual: ?anyerror) !void {
    const received = actual orelse return error.ExpectedOraclePublicationFailure;
    if (received != expected) return received;
}

fn createNamedPipeForPublicationTest(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    path: []const u8,
) !bool {
    switch (builtin.os.tag) {
        .linux, .macos => {},
        else => return false,
    }
    const result = try std.process.run(allocator, init.io, .{
        .argv = &.{ "mkfifo", path },
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.NamedPipeFixtureUnavailable,
        else => return error.NamedPipeFixtureUnavailable,
    }
    return true;
}

fn writeEmptyIntegrityBundle(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    output_dir: []const u8,
) !void {
    const semantic_source_json = try std.json.Stringify.valueAlloc(
        allocator,
        oracle_semantic_source,
        .{},
    );
    defer allocator.free(semantic_source_json);
    const generator_json = try std.json.Stringify.valueAlloc(allocator, oracle_generator_command, .{});
    defer allocator.free(generator_json);
    const normal_check_json = try std.json.Stringify.valueAlloc(allocator, oracle_normal_check_command, .{});
    defer allocator.free(normal_check_json);
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(allocator);
    try manifest.appendSlice(allocator,
        \\{
        \\  "format": "boundary-world-image-v1-rewrite-oracle-v0",
        \\  "format_version": 1,
        \\  "semantic_source":
    );
    try manifest.append(allocator, ' ');
    try manifest.appendSlice(allocator, semantic_source_json);
    try manifest.appendSlice(allocator, ",\n  \"generator\": ");
    try manifest.appendSlice(allocator, generator_json);
    try manifest.appendSlice(allocator, ",\n  \"normal_check\": ");
    try manifest.appendSlice(allocator, normal_check_json);
    try manifest.appendSlice(allocator,
        \\,
        \\  "case_count": 0,
        \\  "cases": [],
        \\  "artifact_set_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        \\  "artifact_count": 0,
        \\  "artifacts": []
        \\}
        \\
    );
    try writeArtifact(init.io, allocator, output_dir, "manifest.json", manifest.items);
    try writeChecksums(init, allocator, output_dir);
}

const RejectedCandidateRequest = struct {
    candidate: []const u8,
    expected_target: []const u8,
    receiver_pin: []const u8,
    expected_error: anyerror,
    paths: PublicationPaths,
};

fn expectSelfConsistentCandidateRejected(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    request: RejectedCandidateRequest,
) !void {
    try rewriteOracleMetadata(init, allocator, request.candidate);
    var candidate_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        request.candidate,
        request.receiver_pin,
        request.paths,
        .none,
    )) catch |err| {
        candidate_error = err;
    };
    try expectPublicationError(request.expected_error, candidate_error);
    try compareTrees(init, allocator, request.expected_target, request.paths.target);
    if (try pathKindNoFollow(init.io, request.paths.stage) != null or
        try pathKindNoFollow(init.io, request.paths.backup) != null)
    {
        return error.OraclePublicationResidue;
    }
}

fn testPublication(init: std.process.Init, allocator: std.mem.Allocator, receiver_pin: []const u8) !void {
    const root = "publication-sandbox";
    const candidate = root ++ "/candidate";
    const target = root ++ "/tracked";
    const stage = root ++ "/stage";
    const backup = root ++ "/backup";
    const invalid_candidate = root ++ "/invalid-candidate";
    const partial_candidate = root ++ "/partial-candidate";
    const rehashed_module_candidate = root ++ "/rehashed-module-candidate";
    const rehashed_session_candidate = root ++ "/rehashed-session-candidate";
    const truncated_transcript_candidate = root ++ "/truncated-transcript-candidate";
    const stale_provenance_candidate = root ++ "/stale-provenance-candidate";
    const alternate_provenance_candidate = root ++ "/alternate-provenance-candidate";
    const metadata_variant_candidate = root ++ "/metadata-variant-candidate";
    const special_entry_candidate = root ++ "/special-entry-candidate";
    const escaping_reference_candidate = root ++ "/escaping-reference-candidate";
    const existing_output = root ++ "/existing-output";
    const paths = PublicationPaths{ .target = target, .stage = stage, .backup = backup };
    const cwd = std.Io.Dir.cwd();

    const windows_path = try canonicalOracleRelativePath(
        allocator,
        "artifacts\\states\\one-effect.parked.loaded-session",
        '\\',
    );
    defer allocator.free(windows_path);
    try expectEqualBytes("artifacts/states/one-effect.parked.loaded-session", windows_path);

    var nonportable_error: ?anyerror = null;
    const nonportable_path: ?[]u8 = canonicalOracleRelativePath(
        allocator,
        "artifacts/states/literal\\backslash.bin",
        '/',
    ) catch |err| failed: {
        nonportable_error = err;
        break :failed null;
    };
    if (nonportable_path) |path| allocator.free(path);
    try expectPublicationError(error.NonPortableOraclePath, nonportable_error);

    inline for (.{ "CON", "aux.txt", "COM1.bin", "lpt9", "COM\xc2\xb9.bin", "lpt\xc2\xb3", "trailing." }) |reserved_path| {
        const candidate_path = try std.fmt.allocPrint(allocator, "artifacts/{s}", .{reserved_path});
        defer allocator.free(candidate_path);
        var reserved_error: ?anyerror = null;
        const canonical_reserved: ?[]u8 = canonicalOracleRelativePath(allocator, candidate_path, '/') catch |err| failed: {
            reserved_error = err;
            break :failed null;
        };
        if (canonical_reserved) |path| allocator.free(path);
        try expectPublicationError(error.NonPortableOraclePath, reserved_error);
    }
    if (!oraclePathsEqualFolded("cases/agent-skeleton.txt", "CASES/AGENT-SKELETON.TXT")) {
        return error.NonPortableOraclePathCollisionNotDetected;
    }
    if (oraclePathsEqualFolded("cases/agent-skeleton.txt", "cases/agent-fixture.txt")) {
        return error.DistinctOraclePathsCollided;
    }
    if (!oraclePathsConflictOnPortableCheckout("Cases/new.txt", "cases/other.txt") or
        !oraclePathsConflictOnPortableCheckout("artifacts/item", "artifacts/ITEM/child.bin") or
        oraclePathsConflictOnPortableCheckout("cases/one.txt", "cases/two.txt"))
    {
        return error.NonPortableOraclePathCollisionNotDetected;
    }
    if (isOracleIntegrityFailure(error.AccessDenied) or isOracleIntegrityFailure(error.OutOfMemory)) {
        return error.OperationalOracleFailureMisclassified;
    }
    inline for (.{
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        error.SystemResources,
        error.NetworkNotFound,
    }) |operational_error| {
        if (mapOracleRootOpenError(operational_error) != operational_error) {
            return error.OperationalOracleFailureMisclassified;
        }
    }
    inline for (.{ error.NotDir, error.SymLinkLoop, error.BadPathName, error.NameTooLong }) |path_error| {
        if (mapOracleRootOpenError(path_error) != error.UnsafeOraclePath) {
            return error.UnsafeOraclePathMisclassified;
        }
    }
    if (!isOracleIntegrityFailure(error.InvalidOracleManifest) or !isOracleIntegrityFailure(error.FileNotFound)) {
        return error.OracleIntegrityFailureMisclassified;
    }

    try createFreshDirectory(init.io, root);
    defer deleteDirectoryIfPresent(init.io, root) catch {};
    try generateFresh(init, allocator, candidate);
    try validateOracleTree(init, allocator, candidate, receiver_pin);
    try copyOracleTree(init, allocator, candidate, target);
    try compareTrees(init, allocator, candidate, target);

    try copyOracleTree(init, allocator, candidate, special_entry_candidate);
    try deleteArtifact(init.io, allocator, special_entry_candidate, "manifest.json");
    const special_manifest_path = try joinPath(allocator, &.{ special_entry_candidate, "manifest.json" });
    defer allocator.free(special_manifest_path);
    if (try createNamedPipeForPublicationTest(init, allocator, special_manifest_path)) {
        var direct_read_error: ?anyerror = null;
        const unexpected_bytes = readRelative(
            init.io,
            allocator,
            special_entry_candidate,
            "manifest.json",
        ) catch |err| failed: {
            direct_read_error = err;
            break :failed null;
        };
        if (unexpected_bytes) |bytes| allocator.free(bytes);
        try expectPublicationError(error.UnsupportedOracleTreeEntry, direct_read_error);

        var special_entry_error: ?anyerror = null;
        validateOracleTreeIntegrity(init, allocator, special_entry_candidate) catch |err| {
            special_entry_error = err;
        };
        try expectPublicationError(error.UnsupportedOracleTreeEntry, special_entry_error);
    }

    try createFreshDirectory(init.io, existing_output);
    try writeArtifact(init.io, allocator, existing_output, "sentinel.txt", "preserve-me\n");
    var existing_error: ?anyerror = null;
    generateFresh(init, allocator, existing_output) catch |err| {
        existing_error = err;
    };
    try expectPublicationError(error.OracleOutputExists, existing_error);
    const sentinel = try readRelative(init.io, allocator, existing_output, "sentinel.txt");
    defer allocator.free(sentinel);
    try expectEqualBytes("preserve-me\n", sentinel);

    try copyOracleTree(init, allocator, candidate, invalid_candidate);
    try writeArtifact(init.io, allocator, invalid_candidate, "cases/scalar-pure.txt", "corrupt\n");
    var invalid_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        invalid_candidate,
        receiver_pin,
        paths,
        .none,
    )) catch |err| {
        invalid_error = err;
    };
    if (invalid_error == null) return error.InvalidOracleCandidatePublished;
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    try copyOracleTree(init, allocator, candidate, partial_candidate);
    try deleteArtifact(init.io, allocator, partial_candidate, "artifacts/values/scalar-pure.result.loaded-value");
    try expectSelfConsistentCandidateRejected(init, allocator, .{
        .candidate = partial_candidate,
        .expected_target = candidate,
        .receiver_pin = receiver_pin,
        .expected_error = error.OracleReceiverPinMismatch,
        .paths = paths,
    });

    try copyOracleTree(init, allocator, candidate, rehashed_module_candidate);
    const module_bytes = try readRelative(init.io, allocator, rehashed_module_candidate, "artifacts/modules/scalar-pure.full-module");
    defer allocator.free(module_bytes);
    module_bytes[0] = 'X';
    try writeArtifact(init.io, allocator, rehashed_module_candidate, "artifacts/modules/scalar-pure.full-module", module_bytes);
    try expectSelfConsistentCandidateRejected(init, allocator, .{
        .candidate = rehashed_module_candidate,
        .expected_target = candidate,
        .receiver_pin = receiver_pin,
        .expected_error = error.OracleReceiverPinMismatch,
        .paths = paths,
    });

    try copyOracleTree(init, allocator, candidate, rehashed_session_candidate);
    const session_bytes = try readRelative(init.io, allocator, rehashed_session_candidate, "artifacts/states/scalar-pure.completed.loaded-session");
    defer allocator.free(session_bytes);
    session_bytes[session_bytes.len / 2] ^= 0x01;
    try writeArtifact(init.io, allocator, rehashed_session_candidate, "artifacts/states/scalar-pure.completed.loaded-session", session_bytes);
    try expectSelfConsistentCandidateRejected(init, allocator, .{
        .candidate = rehashed_session_candidate,
        .expected_target = candidate,
        .receiver_pin = receiver_pin,
        .expected_error = error.OracleReceiverPinMismatch,
        .paths = paths,
    });

    try copyOracleTree(init, allocator, candidate, truncated_transcript_candidate);
    try writeArtifact(init.io, allocator, truncated_transcript_candidate, "cases/scalar-pure.txt", "case_id: scalar-pure\n");
    try expectSelfConsistentCandidateRejected(init, allocator, .{
        .candidate = truncated_transcript_candidate,
        .expected_target = candidate,
        .receiver_pin = receiver_pin,
        .expected_error = error.OracleReceiverPinMismatch,
        .paths = paths,
    });

    try copyOracleTree(init, allocator, candidate, stale_provenance_candidate);
    const current_manifest = try readRelative(init.io, allocator, stale_provenance_candidate, "manifest.json");
    defer allocator.free(current_manifest);
    if (std.mem.find(u8, current_manifest, oracle_semantic_source.baseline_commit) == null) {
        return error.InvalidOracleManifest;
    }
    const stale_manifest = try std.mem.replaceOwned(
        u8,
        allocator,
        current_manifest,
        oracle_semantic_source.baseline_commit,
        "0000000000000000000000000000000000000000",
    );
    defer allocator.free(stale_manifest);
    try writeArtifact(init.io, allocator, stale_provenance_candidate, "manifest.json", stale_manifest);
    try writeChecksums(init, allocator, stale_provenance_candidate);
    var stale_provenance_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        stale_provenance_candidate,
        receiver_pin,
        paths,
        .none,
    )) catch |err| {
        stale_provenance_error = err;
    };
    try expectPublicationError(error.InvalidOracleManifest, stale_provenance_error);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    try copyOracleTree(init, allocator, candidate, alternate_provenance_candidate);
    const strict_manifest = try readRelative(init.io, allocator, alternate_provenance_candidate, "manifest.json");
    defer allocator.free(strict_manifest);
    const manifest_with_alternate_provenance = try std.mem.replaceOwned(
        u8,
        allocator,
        strict_manifest,
        "  \"generator\": ",
        "  \"alternate_provenance\": {\"source\":\"untrusted\"},\n  \"generator\": ",
    );
    defer allocator.free(manifest_with_alternate_provenance);
    if (manifest_with_alternate_provenance.len == strict_manifest.len) return error.InvalidOracleManifest;
    try writeArtifact(init.io, allocator, alternate_provenance_candidate, "manifest.json", manifest_with_alternate_provenance);
    try writeChecksums(init, allocator, alternate_provenance_candidate);
    var alternate_provenance_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        alternate_provenance_candidate,
        receiver_pin,
        paths,
        .none,
    )) catch |err| {
        alternate_provenance_error = err;
    };
    try expectPublicationError(error.InvalidOracleManifest, alternate_provenance_error);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    try copyOracleTree(init, allocator, candidate, metadata_variant_candidate);
    const canonical_manifest = try readRelative(init.io, allocator, metadata_variant_candidate, "manifest.json");
    defer allocator.free(canonical_manifest);
    const whitespace_manifest = try std.mem.replaceOwned(u8, allocator, canonical_manifest, "{\n", "{ \n");
    defer allocator.free(whitespace_manifest);
    if (whitespace_manifest.len == canonical_manifest.len) return error.InvalidOracleManifest;
    try writeArtifact(init.io, allocator, metadata_variant_candidate, "manifest.json", whitespace_manifest);
    try writeChecksums(init, allocator, metadata_variant_candidate);
    var metadata_variant_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        metadata_variant_candidate,
        receiver_pin,
        paths,
        .none,
    )) catch |err| {
        metadata_variant_error = err;
    };
    try expectPublicationError(error.OracleReceiverPinMismatch, metadata_variant_error);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    try copyOracleTree(init, allocator, candidate, escaping_reference_candidate);
    const escaping_manifest = try readRelative(init.io, allocator, escaping_reference_candidate, "manifest.json");
    defer allocator.free(escaping_manifest);
    const current_case_binding = "{\"id\":\"scalar-pure\",\"transcript\":\"cases/scalar-pure.txt\"}";
    if (std.mem.find(u8, escaping_manifest, current_case_binding) == null) return error.InvalidOracleManifest;
    const escaping_case_binding = "{\"id\":\"scalar-pure\",\"transcript\":\"../outside.txt\"}";
    const manifest_with_escape = try std.mem.replaceOwned(
        u8,
        allocator,
        escaping_manifest,
        current_case_binding,
        escaping_case_binding,
    );
    defer allocator.free(manifest_with_escape);
    try writeArtifact(init.io, allocator, escaping_reference_candidate, "manifest.json", manifest_with_escape);
    try writeChecksums(init, allocator, escaping_reference_candidate);
    try writeArtifact(init.io, allocator, root, "outside.txt", "case_id: scalar-pure\n");
    var escaping_reference_error: ?anyerror = null;
    validateOracleTreeIntegrity(init, allocator, escaping_reference_candidate) catch |err| {
        escaping_reference_error = err;
    };
    try expectPublicationError(error.NonPortableOraclePath, escaping_reference_error);

    try deleteDirectoryIfPresent(init.io, target);
    try copyOracleTree(init, allocator, stale_provenance_candidate, target);
    var stale_prior_fault: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        candidate,
        receiver_pin,
        paths,
        .after_backup,
    )) catch |err| {
        stale_prior_fault = err;
    };
    try expectPublicationError(error.InjectedOraclePublicationFailure, stale_prior_fault);
    try compareTrees(init, allocator, stale_provenance_candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    try renameDirectoryToMissing(init.io, target, backup);
    try recoverPublication(init, allocator, paths);
    try compareTrees(init, allocator, stale_provenance_candidate, target);

    try copyOracleTree(init, allocator, candidate, backup);
    try writeArtifact(init.io, allocator, backup, "cases/scalar-pure.txt", "partial-backup\n");
    try recoverPublication(init, allocator, paths);
    try compareTrees(init, allocator, stale_provenance_candidate, target);
    if (try pathKindNoFollow(init.io, backup) != null) return error.OraclePublicationResidue;

    _ = try publishOracleTree(init, allocator, publicationRequest(candidate, receiver_pin, paths, .none));
    try compareTrees(init, allocator, candidate, target);

    try deleteDirectoryIfPresent(init.io, target);
    try createFreshDirectory(init.io, backup);
    try writeEmptyIntegrityBundle(init, allocator, backup);
    var empty_integrity_error: ?anyerror = null;
    recoverPublication(init, allocator, paths) catch |err| {
        empty_integrity_error = err;
    };
    try expectPublicationError(error.InvalidOracleManifest, empty_integrity_error);
    if (try pathKindNoFollow(init.io, target) != null or
        try pathKindNoFollow(init.io, backup) != .directory)
    {
        return error.EmptyOracleIntegrityEvidencePromoted;
    }
    try deleteDirectoryIfPresent(init.io, backup);
    try copyOracleTree(init, allocator, candidate, target);

    var rollback_conflict_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        candidate,
        receiver_pin,
        paths,
        .rollback_conflict,
    )) catch |err| {
        rollback_conflict_error = err;
    };
    try expectPublicationError(error.OraclePublicationConflict, rollback_conflict_error);
    if (try pathKindNoFollow(init.io, backup) != .directory or try pathKindNoFollow(init.io, target) != .file) {
        return error.OraclePublicationRecoveryFailed;
    }
    try validateOracleTreeIntegrity(init, allocator, backup);
    if (try pathKindNoFollow(init.io, stage) != null) return error.OraclePublicationResidue;
    try cwd.deleteFile(init.io, target);
    try recoverPublication(init, allocator, paths);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, backup) != null) return error.OraclePublicationResidue;

    var injected_error: ?anyerror = null;
    _ = publishOracleTree(init, allocator, publicationRequest(
        candidate,
        receiver_pin,
        paths,
        .after_backup,
    )) catch |err| {
        injected_error = err;
    };
    try expectPublicationError(error.InjectedOraclePublicationFailure, injected_error);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    try renameDirectoryToMissing(init.io, target, backup);
    try copyOracleTree(init, allocator, candidate, stage);
    try recoverPublication(init, allocator, paths);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationRecoveryFailed;
    }

    const cleanup_outcome = try publishOracleTree(init, allocator, publicationRequest(
        candidate,
        receiver_pin,
        paths,
        .during_backup_cleanup,
    ));
    switch (cleanup_outcome) {
        .committed => return error.ExpectedOraclePublicationResidue,
        .committed_cleanup_pending => |cleanup_error| {
            if (cleanup_error != error.InjectedOracleBackupCleanupFailure) return cleanup_error;
        },
    }
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, backup) == null) return error.ExpectedOraclePublicationResidue;
    try recoverPublication(init, allocator, paths);
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, backup) != null) return error.OraclePublicationResidue;

    _ = try publishOracleTree(init, allocator, publicationRequest(candidate, receiver_pin, paths, .none));
    try compareTrees(init, allocator, candidate, target);

    try cwd.writeFile(init.io, .{ .sub_path = stage, .data = "unsafe-stage\n" });
    var unsafe_stage_error: ?anyerror = null;
    recoverPublication(init, allocator, paths) catch |err| {
        unsafe_stage_error = err;
    };
    try expectPublicationError(error.UnsafeOraclePath, unsafe_stage_error);
    try cwd.deleteFile(init.io, stage);
    try compareTrees(init, allocator, candidate, target);

    const external = root ++ "/external";
    const linked_parent = root ++ "/linked-parent";
    const external_target = external ++ "/tracked";
    try createFreshDirectory(init.io, external);
    try copyOracleTree(init, allocator, candidate, external_target);
    try writeArtifact(init.io, allocator, external, "sentinel.txt", "outside-publication\n");
    const symlink_created = created: {
        cwd.symLink(init.io, "external", linked_parent, .{ .is_directory = true }) catch |err| switch (err) {
            error.AccessDenied, error.PermissionDenied, error.FileSystem => break :created false,
            else => return err,
        };
        break :created true;
    };
    if (symlink_created) {
        defer cwd.deleteFile(init.io, linked_parent) catch {};
        var linked_candidate_error: ?anyerror = null;
        validateOracleTree(init, allocator, linked_parent ++ "/tracked", receiver_pin) catch |err| {
            linked_candidate_error = err;
        };
        try expectPublicationError(error.UnsafeOraclePath, linked_candidate_error);
        var intermediate_symlink_error: ?anyerror = null;
        recoverPublication(init, allocator, .{
            .target = linked_parent ++ "/tracked",
            .stage = linked_parent ++ "/stage",
            .backup = linked_parent ++ "/backup",
        }) catch |err| {
            intermediate_symlink_error = err;
        };
        try expectPublicationError(error.UnsafeOraclePath, intermediate_symlink_error);
        const external_sentinel_bytes = try readRelative(init.io, allocator, external, "sentinel.txt");
        defer allocator.free(external_sentinel_bytes);
        try expectEqualBytes("outside-publication\n", external_sentinel_bytes);
        try compareTrees(init, allocator, candidate, external_target);

        const retained_ancestor = root ++ "/retained-ancestor";
        const displaced_retained_ancestor = root ++ "/retained-ancestor-original";
        const retained_parent = retained_ancestor ++ "/publication";
        const external_retained_ancestor = root ++ "/retained-external";
        const external_retained_parent = external_retained_ancestor ++ "/publication";
        const retained_paths = PublicationPaths{
            .target = retained_parent ++ "/tracked",
            .stage = retained_parent ++ "/stage",
            .backup = retained_parent ++ "/backup",
        };
        try createFreshDirectory(init.io, retained_ancestor);
        try createFreshDirectory(init.io, retained_parent);
        try copyOracleTree(init, allocator, candidate, retained_paths.target);
        try copyOracleTree(init, allocator, candidate, retained_paths.stage);
        try createFreshDirectory(init.io, external_retained_ancestor);
        try createFreshDirectory(init.io, external_retained_parent);
        try copyOracleTree(init, allocator, candidate, external_retained_parent ++ "/tracked");
        try copyOracleTree(init, allocator, candidate, external_retained_parent ++ "/stage");
        try copyOracleTree(init, allocator, candidate, external_retained_parent ++ "/backup");
        try writeArtifact(
            init.io,
            allocator,
            external_retained_parent,
            "sentinel.txt",
            "outside-retained-parent\n",
        );
        const retained_root = try PublicationRoot.open(init.io, retained_paths);
        defer retained_root.close(init.io);
        try cwd.rename(retained_ancestor, cwd, displaced_retained_ancestor, init.io);
        try cwd.symLink(init.io, "retained-external", retained_ancestor, .{ .is_directory = true });
        try recoverPublicationAtRoot(init, allocator, retained_root);
        if (try pathKindNoFollow(init.io, displaced_retained_ancestor ++ "/publication/stage") != null) {
            return error.OraclePublicationResidue;
        }
        try compareTrees(
            init,
            allocator,
            candidate,
            displaced_retained_ancestor ++ "/publication/tracked",
        );
        inline for (.{ "tracked", "stage", "backup" }) |leaf| {
            const external_tree = try joinPath(allocator, &.{ external_retained_parent, leaf });
            defer allocator.free(external_tree);
            try compareTrees(init, allocator, candidate, external_tree);
        }
        const retained_external_sentinel = try readRelative(
            init.io,
            allocator,
            external_retained_parent,
            "sentinel.txt",
        );
        defer allocator.free(retained_external_sentinel);
        try expectEqualBytes("outside-retained-parent\n", retained_external_sentinel);
        try cwd.deleteFile(init.io, retained_ancestor);
        try cwd.rename(displaced_retained_ancestor, cwd, retained_ancestor, init.io);

        const substituted_parent = root ++ "/substituted-parent";
        const displaced_parent = root ++ "/substituted-parent-original";
        const substituted_publication_parent = substituted_parent ++ "/publication";
        const external_publication_parent = external ++ "/publication";
        const external_substitution_target = external_publication_parent ++ "/tracked";
        try createFreshDirectory(init.io, substituted_parent);
        try createFreshDirectory(init.io, substituted_publication_parent);
        try createFreshDirectory(init.io, external_publication_parent);
        try copyOracleTree(init, allocator, candidate, external_substitution_target);
        try writeArtifact(
            init.io,
            allocator,
            external_publication_parent,
            "sentinel.txt",
            "outside-substitution\n",
        );
        try cwd.rename(substituted_parent, cwd, displaced_parent, init.io);
        try cwd.symLink(init.io, "external", substituted_parent, .{ .is_directory = true });
        var substituted_parent_error: ?anyerror = null;
        recoverPublication(init, allocator, .{
            .target = substituted_publication_parent ++ "/tracked",
            .stage = substituted_publication_parent ++ "/stage",
            .backup = substituted_publication_parent ++ "/backup",
        }) catch |err| {
            substituted_parent_error = err;
        };
        try expectPublicationError(error.UnsafeOraclePath, substituted_parent_error);
        const external_substitution_sentinel = try readRelative(
            init.io,
            allocator,
            external_publication_parent,
            "sentinel.txt",
        );
        defer allocator.free(external_substitution_sentinel);
        try expectEqualBytes("outside-substitution\n", external_substitution_sentinel);
        try compareTrees(init, allocator, candidate, external_substitution_target);
        try cwd.deleteFile(init.io, substituted_parent);
        try cwd.rename(displaced_parent, cwd, substituted_parent, init.io);
    }
}

fn argumentValue(args: []const []const u8, flag: []const u8) ![]const u8 {
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], flag)) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
            return args[index];
        }
    }
    return error.InvalidArguments;
}

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();
    var iterator = std.process.Args.Iterator.init(init.minimal.args);
    defer iterator.deinit();
    _ = iterator.next();
    const command = iterator.next() orelse return error.InvalidArguments;
    var argv: std.ArrayList([]const u8) = .empty;
    while (iterator.next()) |arg| try argv.append(allocator, arg);

    if (std.mem.eql(u8, command, "generate")) {
        if (argv.items.len != 0) return error.InvalidArguments;
        return generateFresh(init, allocator, generated_bundle_path);
    }
    if (std.mem.eql(u8, command, "publish-tracked")) {
        if (argv.items.len != 4) return error.InvalidArguments;
        const candidate_dir = try argumentValue(argv.items, "--candidate-dir");
        const receiver_pin_path = try argumentValue(argv.items, "--receiver-pin");
        const receiver_pin_bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            receiver_pin_path,
            allocator,
            .limited(66),
        );
        defer allocator.free(receiver_pin_bytes);
        const receiver_pin = try parseReceiverPin(receiver_pin_bytes);
        return publishTrackedOracle(init, allocator, candidate_dir, receiver_pin);
    }
    if (std.mem.eql(u8, command, "test-publication")) {
        if (argv.items.len != 2) return error.InvalidArguments;
        const receiver_pin_path = try argumentValue(argv.items, "--receiver-pin");
        const receiver_pin_bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            receiver_pin_path,
            allocator,
            .limited(66),
        );
        defer allocator.free(receiver_pin_bytes);
        const receiver_pin = try parseReceiverPin(receiver_pin_bytes);
        return testPublication(init, allocator, receiver_pin);
    }
    if (std.mem.eql(u8, command, "compare")) {
        if (argv.items.len != 6) return error.InvalidArguments;
        const expected_dir = try argumentValue(argv.items, "--expected-dir");
        const first_dir = try argumentValue(argv.items, "--first-dir");
        const second_dir = try argumentValue(argv.items, "--second-dir");
        try compareTrees(init, allocator, first_dir, second_dir);
        try compareTrees(init, allocator, expected_dir, first_dir);
        return;
    }
    if (std.mem.eql(u8, command, "verify")) {
        if (argv.items.len != 4) return error.InvalidArguments;
        const expected_dir = try argumentValue(argv.items, "--expected-dir");
        const actual_dir = try argumentValue(argv.items, "--actual-dir");
        return compareTrees(init, allocator, expected_dir, actual_dir);
    }
    return error.InvalidArguments;
}
