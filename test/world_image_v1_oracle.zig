// zlinter-disable declaration_naming field_naming field_ordering no_inferred_error_unions no_swallow_error require_doc_comment require_errdefer_dealloc
// The manifest decoder mirrors external JSON field names, including the schema key `id`.
const agent_loop = @import("agent_loop");
const boundary = @import("boundary");
const std = @import("std");

const corpus_path = "conformance/world-image-v1/v0/boundary";
const checksum_prefix = corpus_path ++ "/";
const generated_bundle_path = "bundle";
const tracked_publication_stage_path = "conformance/world-image-v1/v0/.boundary-oracle-stage";
const tracked_publication_backup_path = "conformance/world-image-v1/v0/.boundary-oracle-backup";

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
    if (generated_request.operation_site_index != loaded_request.residual_site_index) return error.OracleSemanticMismatch;
    if (generated_request.operation_site_fingerprint != loaded_request.residual_site_fingerprint) return error.OracleSemanticMismatch;
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
    if (generated_request.operation_site_index != loaded_request.residual_site_index) return error.OracleSemanticMismatch;
    if (generated_request.operation_site_fingerprint != loaded_request.residual_site_fingerprint) return error.OracleSemanticMismatch;
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
    if (generated_request.operation_site_index != loaded_request.residual_site_index) return error.OracleSemanticMismatch;
    if (generated_request.operation_site_fingerprint != loaded_request.residual_site_fingerprint) return error.OracleSemanticMismatch;
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
    if (generated_first.operation_site_index != loaded_first.residual_site_index) return error.OracleSemanticMismatch;
    if (generated_first.operation_site_fingerprint != loaded_first.residual_site_fingerprint) return error.OracleSemanticMismatch;
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
    if (generated_second.operation_site_index != loaded_second.residual_site_index) return error.OracleSemanticMismatch;
    if (generated_second.operation_site_fingerprint != loaded_second.residual_site_fingerprint) return error.OracleSemanticMismatch;
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

fn listFiles(io: std.Io, allocator: std.mem.Allocator, root: []const u8) !OwnedPaths {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false });
    defer dir.close(io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var items: std.ArrayList([]u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .file => try items.append(allocator, try allocator.dupe(u8, entry.path)),
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
    std.mem.sort([]u8, owned, {}, pathLessThan);
    return .{ .allocator = allocator, .items = owned };
}

fn readRelative(
    io: std.Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    relative_path: []const u8,
) ![]u8 {
    const path = try joinPath(allocator, &.{ root, relative_path });
    defer allocator.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest = [_]u8{0} ** 32;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn digestHex(digest: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

fn appendFmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const bytes = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(bytes);
    try out.appendSlice(allocator, bytes);
}

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
    try manifest.appendSlice(allocator,
        \\{
        \\  "format": "boundary-world-image-v1-rewrite-oracle-v0",
        \\  "format_version": 1,
        \\  "semantic_source": {
        \\    "package": "boundary",
        \\    "package_version": "0.6.2",
        \\    "baseline_commit": "6a416951f8d22d0854616f094f23b2d44ab021a2",
        \\    "baseline_tree": "950838431ef965f21926b4ea14361f69bc16c2dd",
        \\    "module_magic": "BCBMOD1",
        \\    "loaded_execution_profile": 2,
        \\    "loaded_session_image": 2,
        \\    "zig_version": "0.16.0"
        \\  },
        \\  "generator": "zig build update-boundary-world-image-v1-oracle",
        \\  "normal_check": "zig build check-boundary-world-image-v1-oracle --summary all",
        \\  "case_count": 12,
        \\  "cases": [
    );
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

fn checksumsBytes(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) ![]u8 {
    var paths = try listFiles(init.io, allocator, output_dir);
    defer paths.deinit();
    var checksums: std.ArrayList(u8) = .empty;
    errdefer checksums.deinit(allocator);
    for (paths.items) |relative_path| {
        if (std.mem.eql(u8, relative_path, "checksums.sha256")) continue;
        const bytes = try readRelative(init.io, allocator, output_dir, relative_path);
        defer allocator.free(bytes);
        const hex = digestHex(sha256(bytes));
        try appendFmt(&checksums, allocator, "{s}  {s}{s}\n", .{ &hex, checksum_prefix, relative_path });
    }
    return checksums.toOwnedSlice(allocator);
}

fn writeChecksums(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const checksums = try checksumsBytes(init, allocator, output_dir);
    defer allocator.free(checksums);
    try writeArtifact(init.io, allocator, output_dir, "checksums.sha256", checksums);
}

fn validateRequiredCases(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    for (cases) |case| {
        const bytes = try readRelative(init.io, allocator, output_dir, case.transcript);
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
    case_count: usize,
    cases: []const OracleManifestCase,
    artifact_set_sha256: []const u8,
    artifact_count: usize,
    artifacts: []const OracleManifestArtifact,
};

fn isOracleMetadataPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "manifest.json") or std.mem.eql(u8, path, "checksums.sha256");
}

fn validateManifest(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const manifest_bytes = try readRelative(init.io, allocator, output_dir, "manifest.json");
    defer allocator.free(manifest_bytes);
    const parsed = std.json.parseFromSlice(OracleManifest, allocator, manifest_bytes, .{
        .ignore_unknown_fields = true,
    }) catch return error.InvalidOracleManifest;
    defer parsed.deinit();
    const manifest = parsed.value;
    if (!std.mem.eql(u8, manifest.format, "boundary-world-image-v1-rewrite-oracle-v0") or
        manifest.format_version != 1 or manifest.case_count != cases.len or
        manifest.cases.len != cases.len)
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

    var paths = try listFiles(init.io, allocator, output_dir);
    defer paths.deinit();
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
        const bytes = try readRelative(init.io, allocator, output_dir, relative_path);
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
}

fn validateChecksums(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const actual = try readRelative(init.io, allocator, output_dir, "checksums.sha256");
    defer allocator.free(actual);
    const expected = try checksumsBytes(init, allocator, output_dir);
    defer allocator.free(expected);
    if (!std.mem.eql(u8, expected, actual)) return error.InvalidOracleChecksums;
}

fn validateOracleTree(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    try requireDirectory(init.io, output_dir);
    try validateRequiredCases(init, allocator, output_dir);
    try validateManifest(init, allocator, output_dir);
    try validateChecksums(init, allocator, output_dir);
}

fn generateFresh(init: std.process.Init, allocator: std.mem.Allocator, output_dir: []const u8) !void {
    try createFreshDirectory(init.io, output_dir);
    errdefer deleteDirectoryIfPresent(init.io, output_dir) catch {};
    try emitScalarAndBudget(init, allocator, output_dir);
    try emitHelperCall(init, allocator, output_dir);
    try emitOneEffect(init, allocator, output_dir);
    try emitStructured(init, allocator, output_dir);
    try emitHelperPark(init, allocator, output_dir);
    try emitMultipleResidual(init, allocator, output_dir);
    try emitAgentArtifacts(init, allocator, output_dir);
    try validateRequiredCases(init, allocator, output_dir);
    try writeManifest(init, allocator, output_dir);
    try writeChecksums(init, allocator, output_dir);
    try validateOracleTree(init, allocator, output_dir);
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

const PublicationFault = enum {
    none,
    after_backup,
};

fn recoverPublication(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    paths: PublicationPaths,
) !void {
    const backup_kind = try pathKindNoFollow(init.io, paths.backup);
    const target_kind = try pathKindNoFollow(init.io, paths.target);
    if (backup_kind) |kind| {
        if (kind != .directory) return error.UnsafeOraclePath;
        try validateOracleTree(init, allocator, paths.backup);
        if (target_kind == null) {
            try renameDirectoryToMissing(init.io, paths.backup, paths.target);
        } else {
            if (target_kind.? != .directory) return error.UnsafeOraclePath;
            validateOracleTree(init, allocator, paths.target) catch {
                try deleteDirectoryIfPresent(init.io, paths.target);
                try renameDirectoryToMissing(init.io, paths.backup, paths.target);
            };
            if (try pathKindNoFollow(init.io, paths.backup) != null) {
                try deleteDirectoryIfPresent(init.io, paths.backup);
            }
        }
    } else if (target_kind) |kind| {
        if (kind != .directory) return error.UnsafeOraclePath;
    }

    const stage_kind = try pathKindNoFollow(init.io, paths.stage);
    if (stage_kind) |kind| {
        if (kind != .directory) return error.UnsafeOraclePath;
        try deleteDirectoryIfPresent(init.io, paths.stage);
    }
}

fn publishOracleTree(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    candidate_dir: []const u8,
    paths: PublicationPaths,
    fault: PublicationFault,
) !void {
    try recoverPublication(init, allocator, paths);
    try validateOracleTree(init, allocator, candidate_dir);
    try validateOracleTree(init, allocator, paths.target);
    try copyOracleTree(init, allocator, candidate_dir, paths.stage);
    errdefer deleteDirectoryIfPresent(init.io, paths.stage) catch {};
    try validateOracleTree(init, allocator, paths.stage);

    try renameDirectoryToMissing(init.io, paths.target, paths.backup);
    var backup_active = true;
    var target_promoted = false;
    errdefer if (backup_active) {
        if (target_promoted) deleteDirectoryIfPresent(init.io, paths.target) catch {};
        renameDirectoryToMissing(init.io, paths.backup, paths.target) catch {};
    };
    if (fault == .after_backup) return error.InjectedOraclePublicationFailure;
    try renameDirectoryToMissing(init.io, paths.stage, paths.target);
    target_promoted = true;
    try validateOracleTree(init, allocator, paths.target);
    try deleteDirectoryIfPresent(init.io, paths.backup);
    backup_active = false;
}

fn publishTrackedOracle(init: std.process.Init, allocator: std.mem.Allocator, candidate_dir: []const u8) !void {
    return publishOracleTree(init, allocator, candidate_dir, .{
        .target = corpus_path,
        .stage = tracked_publication_stage_path,
        .backup = tracked_publication_backup_path,
    }, .none);
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

fn testPublication(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const root = "publication-sandbox";
    const candidate = root ++ "/candidate";
    const target = root ++ "/tracked";
    const stage = root ++ "/stage";
    const backup = root ++ "/backup";
    const invalid_candidate = root ++ "/invalid-candidate";
    const existing_output = root ++ "/existing-output";
    const paths = PublicationPaths{ .target = target, .stage = stage, .backup = backup };
    const cwd = std.Io.Dir.cwd();

    try createFreshDirectory(init.io, root);
    defer deleteDirectoryIfPresent(init.io, root) catch {};
    try generateFresh(init, allocator, candidate);
    try copyOracleTree(init, allocator, candidate, target);
    try compareTrees(init, allocator, candidate, target);

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
    publishOracleTree(init, allocator, invalid_candidate, paths, .none) catch |err| {
        invalid_error = err;
    };
    if (invalid_error == null) return error.InvalidOracleCandidatePublished;
    try compareTrees(init, allocator, candidate, target);
    if (try pathKindNoFollow(init.io, stage) != null or try pathKindNoFollow(init.io, backup) != null) {
        return error.OraclePublicationResidue;
    }

    var injected_error: ?anyerror = null;
    publishOracleTree(init, allocator, candidate, paths, .after_backup) catch |err| {
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

    try publishOracleTree(init, allocator, candidate, paths, .none);
    try compareTrees(init, allocator, candidate, target);

    try cwd.symLink(init.io, target, stage, .{ .is_directory = true });
    var symlink_error: ?anyerror = null;
    recoverPublication(init, allocator, paths) catch |err| {
        symlink_error = err;
    };
    try expectPublicationError(error.UnsafeOraclePath, symlink_error);
    try cwd.deleteFile(init.io, stage);
    try compareTrees(init, allocator, candidate, target);
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

fn exactArgumentValue(args: []const []const u8, flag: []const u8) ![]const u8 {
    if (args.len != 2 or !std.mem.eql(u8, args[0], flag) or args[1].len == 0) {
        return error.InvalidArguments;
    }
    return args[1];
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
        const candidate_dir = try exactArgumentValue(argv.items, "--candidate-dir");
        return publishTrackedOracle(init, allocator, candidate_dir);
    }
    if (std.mem.eql(u8, command, "test-publication")) {
        if (argv.items.len != 0) return error.InvalidArguments;
        return testPublication(init, allocator);
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
