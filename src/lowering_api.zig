// zlinter-disable require_doc_comment field_naming field_ordering no_undefined no_unused
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

pub const ProgramPlan = program_plan.ProgramPlan;
pub const ValueCodec = program_plan.ValueCodec;
pub const ValueRef = program_plan.ValueRef;
pub const ValueSchemaRegistryForTypes = program_plan.ValueSchemaRegistryForTypes;

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

pub const NestedWithTarget = struct {
    metadata: []const u8,
    function_index: u16,
};
pub const max_capability_blockers = 64;
pub const CapabilityBlockerTag = enum {
    helper_cycle,
    nested_with_unresolved,
    nested_with_target_has_parameters,
    nested_with_result_codec,
    result_codec,
    parameter_codec,
    payload_codec,
    resume_codec,
    local_codec,
    native_usize_literal,
};
pub const CapabilityBlocker = struct {
    tag: CapabilityBlockerTag,
    function_index: u16 = std.math.maxInt(u16),
    instruction_index: u32 = std.math.maxInt(u32),
    codec: ValueCodec = .unit,
};
pub const SessionBlockerTag = enum {
    helper_cycle,
    nested_with_unresolved,
    nested_with_target_has_parameters,
    nested_with_result_codec,
    result_codec,
    parameter_codec,
    payload_codec,
    resume_codec,
    local_codec,
    native_usize_literal,
};
pub const SessionBlocker = struct {
    tag: SessionBlockerTag,
    function_index: u16 = std.math.maxInt(u16),
    instruction_index: u32 = std.math.maxInt(u32),
    op_index: u16 = std.math.maxInt(u16),
    codec: ValueCodec = .unit,
};
pub const ExecutablePlanSupportError = error{
    UnsupportedHelperCycle,
    UnsupportedNestedWith,
    UnsupportedAfterHook,
    UnsupportedResultCodec,
    UnsupportedParameterCodec,
    UnsupportedPayloadCodec,
    UnsupportedResumeCodec,
    UnsupportedLocalCodec,
    UnsupportedNativeUsizeLiteral,
};
pub const SessionPlanSupportError = error{
    UnsupportedSessionPlan,
};

fn appendCapabilityBlocker(
    comptime blockers: *[max_capability_blockers]CapabilityBlocker,
    comptime count: *usize,
    comptime truncated: *bool,
    comptime blocker: CapabilityBlocker,
) void {
    if (count.* == max_capability_blockers) {
        truncated.* = true;
        return;
    }
    blockers[count.*] = blocker;
    count.* += 1;
}

fn appendSessionBlocker(
    comptime blockers: *[max_capability_blockers]SessionBlocker,
    comptime count: *usize,
    comptime truncated: *bool,
    comptime blocker: SessionBlocker,
) void {
    if (count.* == max_capability_blockers) {
        truncated.* = true;
        return;
    }
    blockers[count.*] = blocker;
    count.* += 1;
}

fn sessionBlockerTagForCapability(comptime tag: CapabilityBlockerTag) SessionBlockerTag {
    return switch (tag) {
        .helper_cycle => .helper_cycle,
        .nested_with_unresolved => .nested_with_unresolved,
        .nested_with_target_has_parameters => .nested_with_target_has_parameters,
        .nested_with_result_codec => .nested_with_result_codec,
        .result_codec => .result_codec,
        .parameter_codec => .parameter_codec,
        .payload_codec => .payload_codec,
        .resume_codec => .resume_codec,
        .local_codec => .local_codec,
        .native_usize_literal => .native_usize_literal,
    };
}

pub fn ExecutableCapabilityLedgerForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) type {
    const data = comptime blk: {
        var blockers: [max_capability_blockers]CapabilityBlocker = undefined;
        var count: usize = 0;
        var truncated = false;
        const analysis = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch {
            appendCapabilityBlocker(&blockers, &count, &truncated, .{ .tag = .local_codec });
            const items = blockers[0..count].*;
            break :blk .{ .items = items, .truncated = truncated };
        };
        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (!executableTypedRef(schema_types, .{ .codec = local.codec, .schema_index = local.schema_index })) {
                    appendCapabilityBlocker(&blockers, &count, &truncated, .{
                        .tag = .parameter_codec,
                        .function_index = @intCast(function_index),
                        .codec = local.codec,
                    });
                }
            }
            if (!executableTypedRef(schema_types, program_plan.functionResultRef(function))) {
                appendCapabilityBlocker(&blockers, &count, &truncated, .{
                    .tag = .result_codec,
                    .function_index = @intCast(function_index),
                    .codec = program_plan.functionResultCodec(function),
                });
            }
        }
        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            const owner_index = instructionOwnerFunctionIndex(compiled_plan, instruction_index) orelse std.math.maxInt(usize);
            const owner: ?program_plan.FunctionPlan = if (owner_index == std.math.maxInt(usize)) null else compiled_plan.functions[owner_index];
            switch (instruction.kind) {
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .nested_with_unresolved,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                        });
                        continue;
                    };
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .nested_with_target_has_parameters,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                        });
                    }
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch .unit;
                    const completion_ref = effectiveCompletionRefForFunction(analysis, target, target_index);
                    if (!executableTypedRef(schema_types, .{ .codec = result_codec }) or
                        completion_ref.codec != result_codec or
                        completion_ref.schema_index != null)
                    {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .nested_with_result_codec,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                            .codec = result_codec,
                        });
                    } else if (owner) |owner_function| {
                        if (result_codec != .unit and !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner_function, instruction.dst)) {
                            appendCapabilityBlocker(&blockers, &count, &truncated, .{
                                .tag = .local_codec,
                                .function_index = @intCast(owner_index),
                                .instruction_index = @intCast(instruction_index),
                                .codec = result_codec,
                            });
                        }
                        if (analysis.terminal_functions[target_index] and
                            !program_plan.functionResultRef(target).eql(program_plan.functionResultRef(owner_function)))
                        {
                            appendCapabilityBlocker(&blockers, &count, &truncated, .{
                                .tag = .nested_with_result_codec,
                                .function_index = @intCast(owner_index),
                                .instruction_index = @intCast(instruction_index),
                                .codec = program_plan.functionResultCodec(target),
                            });
                        }
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (!executableTypedRef(schema_types, .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index })) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{ .tag = .payload_codec, .function_index = @intCast(owner_index), .instruction_index = @intCast(instruction_index), .codec = op.payload_codec });
                    }
                    if (!executableTypedRef(schema_types, .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index })) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{ .tag = .resume_codec, .function_index = @intCast(owner_index), .instruction_index = @intCast(instruction_index), .codec = op.resume_codec });
                    }
                },
                .const_usize => {
                    if (!constUsizeLiteralFitsNative(instruction)) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .native_usize_literal,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                            .codec = .usize,
                        });
                    }
                },
                else => {},
            }
        }
        const items = blockers[0..count].*;
        break :blk .{ .items = items, .truncated = truncated };
    };
    return struct {
        pub const blockers = data.items;
        pub const truncated = data.truncated;
    };
}

pub fn executableCapabilitySummary(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) []const u8 {
    const ledger = ExecutableCapabilityLedgerForPlan(compiled_plan, schema_types, nested_with_targets);
    if (ledger.blockers.len == 0) return "capability ledger: blockers=0 truncated=false";
    const first = ledger.blockers[0];
    return std.fmt.comptimePrint(
        "capability ledger: blockers={d} truncated={} cap={d} first_tag={s} first_function={d} first_instruction={d}",
        .{
            ledger.blockers.len,
            ledger.truncated,
            max_capability_blockers,
            @tagName(first.tag),
            first.function_index,
            first.instruction_index,
        },
    );
}

pub fn SessionCapabilityLedgerForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) type {
    const data = comptime blk: {
        var blockers: [max_capability_blockers]SessionBlocker = undefined;
        var count: usize = 0;
        var truncated = false;
        _ = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch {
            appendSessionBlocker(&blockers, &count, &truncated, .{ .tag = .local_codec });
            break :blk .{ .items = blockers[0..count].*, .truncated = truncated };
        };
        break :blk .{ .items = blockers[0..count].*, .truncated = truncated };
    };
    return struct {
        pub const blockers = data.items;
        pub const truncated = data.truncated;
    };
}

pub fn TypedSessionCapabilityLedgerForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) type {
    const data = comptime blk: {
        var blockers: [max_capability_blockers]SessionBlocker = undefined;
        var count: usize = 0;
        var truncated = false;
        const executable_ledger = ExecutableCapabilityLedgerForPlan(compiled_plan, schema_types, nested_with_targets);
        for (executable_ledger.blockers) |blocker| {
            appendSessionBlocker(&blockers, &count, &truncated, .{
                .tag = sessionBlockerTagForCapability(blocker.tag),
                .function_index = blocker.function_index,
                .instruction_index = blocker.instruction_index,
                .codec = blocker.codec,
            });
        }
        const session_ledger = SessionCapabilityLedgerForPlan(compiled_plan, nested_with_targets);
        for (session_ledger.blockers) |blocker| {
            appendSessionBlocker(&blockers, &count, &truncated, blocker);
        }
        break :blk .{ .items = blockers[0..count].*, .truncated = truncated or executable_ledger.truncated or session_ledger.truncated };
    };
    return struct {
        pub const blockers = data.items;
        pub const truncated = data.truncated;
    };
}

pub fn sessionCapabilitySummary(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) []const u8 {
    const ledger = SessionCapabilityLedgerForPlan(compiled_plan, nested_with_targets);
    if (ledger.blockers.len == 0) return "session capability ledger: blockers=0 truncated=false";
    const first = ledger.blockers[0];
    return std.fmt.comptimePrint(
        "session capability ledger: blockers={d} truncated={} cap={d} first_tag={s} first_function={d} first_instruction={d} first_op={d}",
        .{
            ledger.blockers.len,
            ledger.truncated,
            max_capability_blockers,
            @tagName(first.tag),
            first.function_index,
            first.instruction_index,
            first.op_index,
        },
    );
}

pub fn typedSessionCapabilitySummary(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) []const u8 {
    const ledger = TypedSessionCapabilityLedgerForPlan(compiled_plan, schema_types, nested_with_targets);
    if (ledger.blockers.len == 0) return "session capability ledger: blockers=0 truncated=false";
    const first = ledger.blockers[0];
    return std.fmt.comptimePrint(
        "session capability ledger: blockers={d} truncated={} cap={d} first_tag={s} first_function={d} first_instruction={d} first_op={d}",
        .{
            ledger.blockers.len,
            ledger.truncated,
            max_capability_blockers,
            @tagName(first.tag),
            first.function_index,
            first.instruction_index,
            first.op_index,
        },
    );
}

pub fn validateSessionPlanSupportWithNestedTargets(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) SessionPlanSupportError!void {
    comptime {
        const ledger = SessionCapabilityLedgerForPlan(compiled_plan, nested_with_targets);
        if (ledger.blockers.len != 0) return error.UnsupportedSessionPlan;
    }
}

pub fn validateTypedSessionExecutablePlanSupportWithNestedTargets(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) ExecutablePlanSupportError!void {
    try validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, nested_with_targets);
    validateSessionPlanSupportWithNestedTargets(compiled_plan, nested_with_targets) catch return error.UnsupportedLocalCodec;
}

pub fn executableResultCodecForType(comptime T: type) program_plan.CodecError!program_plan.ValueCodec {
    return program_plan.codecForType(T);
}

pub fn executableResultCodecForPlan(comptime compiled_plan: program_plan.ProgramPlan) program_plan.ValueCodec {
    return program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]);
}

pub fn executableResultRefForPlan(comptime compiled_plan: program_plan.ProgramPlan) program_plan.ValueRef {
    return program_plan.functionResultRef(compiled_plan.functions[compiled_plan.entry_index]);
}

fn constUsizeLiteralFitsNative(comptime instruction: program_plan.Instruction) bool {
    _ = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch return false;
    return true;
}

pub fn validateExecutablePlanSupport(comptime compiled_plan: program_plan.ProgramPlan) ExecutablePlanSupportError!void {
    comptime {
        const analysis = program_plan.entryExecutionAnalysis(compiled_plan) catch return error.UnsupportedLocalCodec;
        if (analysis.helper_cycle) return error.UnsupportedHelperCycle;

        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (!executableScalarCodec(local.codec)) return error.UnsupportedParameterCodec;
            }
            if ((analysis.terminal_functions[function_index] or analysis.after_result_functions[function_index]) and
                !executableScalarCodec(program_plan.functionResultCodec(function)))
            {
                return error.UnsupportedResultCodec;
            }
        }

        const entry = compiled_plan.functions[compiled_plan.entry_index];
        if (!executableScalarCodec(program_plan.functionResultCodec(entry))) return error.UnsupportedResultCodec;

        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            switch (instruction.kind) {
                .call_nested_with => return error.UnsupportedNestedWith,
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (!executableScalarCodec(op.payload_codec)) return error.UnsupportedPayloadCodec;
                    if (!executableScalarCodec(op.resume_codec)) return error.UnsupportedResumeCodec;
                    if (op.payload_codec != .unit and !instructionLocalHasExecutableScalarCodec(
                        compiled_plan,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.aux,
                    )) return error.UnsupportedLocalCodec;
                    if (op.resume_codec != .unit and instruction.dst != std.math.maxInt(u16) and !instructionLocalHasExecutableScalarCodec(
                        compiled_plan,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.dst,
                    )) return error.UnsupportedLocalCodec;
                },
                .call_helper => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    const callee = compiled_plan.functions[instruction.operand];
                    if (callee.parameter_count != 0) {
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, local_id)) return error.UnsupportedLocalCodec;
                        }
                    }
                    if (program_plan.functionResultCodec(callee) != .unit and instruction.dst != std.math.maxInt(u16) and
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .add_const_i32, .const_i32, .const_string, .const_usize => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst)) return error.UnsupportedLocalCodec;
                    if (instruction.kind == .add_const_i32 and !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand)) {
                        return error.UnsupportedLocalCodec;
                    }
                    if (instruction.kind == .const_usize and !constUsizeLiteralFitsNative(instruction)) {
                        return error.UnsupportedNativeUsizeLiteral;
                    }
                },
                .add_i32 => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst) or
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand) or
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.aux))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .compare_eq_zero, .sub_one => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst) or
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .sum_variant_is, .sum_extract_payload, .product_extract_field => return error.UnsupportedLocalCodec,
                .return_value => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand)) return error.UnsupportedLocalCodec;
                },
                .return_error => {},
            }
        }
    }
}

pub fn validateTypedExecutablePlanSupport(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
) ExecutablePlanSupportError!void {
    return validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, &.{});
}

pub fn validateTypedExecutablePlanSupportWithNestedTargets(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) ExecutablePlanSupportError!void {
    return validateTypedExecutablePlanSupportWithIdentity(
        compiled_plan,
        schema_types,
        nested_with_targets,
        .legacy_session,
    );
}

fn validateTypedExecutablePlanSupportWithIdentity(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    comptime identity: YieldSiteAnalysisIdentity,
) ExecutablePlanSupportError!void {
    comptime {
        const analysis = switch (identity) {
            .legacy_session => program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets),
            .static_machine_v1 => program_plan.staticEntryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets),
        } catch return error.UnsupportedLocalCodec;

        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (!executableTypedRef(schema_types, .{ .codec = local.codec, .schema_index = local.schema_index })) return error.UnsupportedParameterCodec;
            }
            if ((analysis.terminal_functions[function_index] or analysis.after_result_functions[function_index]) and
                !executableTypedRef(schema_types, program_plan.functionResultRef(function)))
            {
                return error.UnsupportedResultCodec;
            }
        }

        const entry = compiled_plan.functions[compiled_plan.entry_index];
        if (!executableTypedRef(schema_types, program_plan.functionResultRef(entry))) return error.UnsupportedResultCodec;

        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            switch (instruction.kind) {
                .call_nested_with => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse return error.UnsupportedNestedWith;
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) return error.UnsupportedNestedWith;
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch return error.UnsupportedResultCodec;
                    if (!executableTypedRef(schema_types, .{ .codec = result_codec })) return error.UnsupportedResultCodec;
                    const completion_ref = effectiveCompletionRefForFunction(analysis, target, target_index);
                    if (completion_ref.codec != result_codec or completion_ref.schema_index != null) return error.UnsupportedResultCodec;
                    if (result_codec != .unit and !instructionLocalHasExecutableTypedRef(
                        compiled_plan,
                        schema_types,
                        owner,
                        instruction.dst,
                    )) return error.UnsupportedLocalCodec;
                    if (analysis.terminal_functions[target_index] and
                        !program_plan.functionResultRef(target).eql(program_plan.functionResultRef(owner)))
                    {
                        return error.UnsupportedResultCodec;
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (!executableTypedRef(schema_types, .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index })) return error.UnsupportedPayloadCodec;
                    if (!executableTypedRef(schema_types, .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index })) return error.UnsupportedResumeCodec;
                    if (op.payload_codec != .unit and !instructionLocalHasExecutableTypedRef(
                        compiled_plan,
                        schema_types,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.aux,
                    )) return error.UnsupportedLocalCodec;
                    if (op.resume_codec != .unit and instruction.dst != std.math.maxInt(u16) and !instructionLocalHasExecutableTypedRef(
                        compiled_plan,
                        schema_types,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.dst,
                    )) return error.UnsupportedLocalCodec;
                },
                .call_helper => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    const callee = compiled_plan.functions[instruction.operand];
                    if (callee.parameter_count != 0) {
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, local_id)) return error.UnsupportedLocalCodec;
                        }
                    }
                    if (program_plan.functionResultCodec(callee) != .unit and instruction.dst != std.math.maxInt(u16) and
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .add_const_i32, .const_i32, .const_string, .const_usize => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst)) return error.UnsupportedLocalCodec;
                    if (instruction.kind == .add_const_i32 and !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand)) {
                        return error.UnsupportedLocalCodec;
                    }
                    if (instruction.kind == .const_usize and !constUsizeLiteralFitsNative(instruction)) {
                        return error.UnsupportedNativeUsizeLiteral;
                    }
                },
                .add_i32 => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.aux))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .compare_eq_zero, .sub_one => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .sum_variant_is => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .sum_extract_payload, .product_extract_field => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .return_value => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand)) return error.UnsupportedLocalCodec;
                },
                .return_error => {},
            }
        }
    }
}

pub fn executablePlanNeedsBodyValueSchemaTypes(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) bool {
    comptime {
        const analysis = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch return false;
        const entry = compiled_plan.functions[compiled_plan.entry_index];
        if (valueRefNeedsSchemaTypes(program_plan.functionResultRef(entry))) return true;

        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (valueRefNeedsSchemaTypes(.{ .codec = local.codec, .schema_index = local.schema_index })) return true;
            }
            if ((analysis.terminal_functions[function_index] or analysis.after_result_functions[function_index]) and
                valueRefNeedsSchemaTypes(program_plan.functionResultRef(function)))
            {
                return true;
            }
        }

        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return false;
            switch (instruction.kind) {
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse continue;
                    const target = compiled_plan.functions[target_index];
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch continue;
                    if (structuredSchemaCodec(result_codec)) return true;
                    const completion_ref = effectiveCompletionRefForFunction(analysis, target, target_index);
                    if (valueRefNeedsSchemaTypes(completion_ref)) return true;
                    if (result_codec != .unit) {
                        const local_ref = functionLocalRef(compiled_plan, owner, instruction.dst) orelse return false;
                        if (valueRefNeedsSchemaTypes(local_ref)) return true;
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (valueRefNeedsSchemaTypes(.{ .codec = op.payload_codec, .schema_index = op.payload_schema_index }) or
                        valueRefNeedsSchemaTypes(.{ .codec = op.resume_codec, .schema_index = op.resume_schema_index }))
                    {
                        return true;
                    }
                },
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    for (0..callee.parameter_count) |arg_index| {
                        const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                        const local_ref = functionLocalRef(compiled_plan, owner, local_id) orelse return false;
                        if (valueRefNeedsSchemaTypes(local_ref)) return true;
                    }
                    if (program_plan.functionResultCodec(callee) != .unit and instruction.dst != std.math.maxInt(u16)) {
                        const local_ref = functionLocalRef(compiled_plan, owner, instruction.dst) orelse return false;
                        if (valueRefNeedsSchemaTypes(local_ref)) return true;
                    }
                },
                .return_value => {
                    const local_ref = functionLocalRef(compiled_plan, owner, instruction.operand) orelse return false;
                    if (valueRefNeedsSchemaTypes(local_ref)) return true;
                },
                .sum_extract_payload, .sum_variant_is, .product_extract_field => {
                    const source_ref = functionLocalRef(compiled_plan, owner, instruction.operand) orelse return false;
                    const dst_ref = functionLocalRef(compiled_plan, owner, instruction.dst) orelse return false;
                    if (valueRefNeedsSchemaTypes(source_ref) or valueRefNeedsSchemaTypes(dst_ref)) return true;
                },
                .add_const_i32, .add_i32, .compare_eq_zero, .const_i32, .const_string, .const_usize, .return_error, .sub_one => {},
            }
        }

        return false;
    }
}

fn executableScalarCodec(comptime codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .unit, .bool, .i32, .usize, .string => true,
        .product, .sum, .string_list => false,
    };
}

fn structuredSchemaCodec(comptime codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .product, .sum => true,
        .unit, .bool, .i32, .usize, .string, .string_list => false,
    };
}

fn valueRefNeedsSchemaTypes(comptime ref: program_plan.ValueRef) bool {
    return structuredSchemaCodec(ref.codec);
}

fn executableTypedRef(comptime schema_types: anytype, comptime ref: program_plan.ValueRef) bool {
    return switch (ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => ref.schema_index == null,
        .product, .sum => if (ref.schema_index) |index| index < schema_types.len else false,
    };
}

fn instructionOwnerFunction(comptime compiled_plan: program_plan.ProgramPlan, comptime instruction_index: usize) ?program_plan.FunctionPlan {
    inline for (compiled_plan.functions) |function| {
        const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
        if (instruction_index >= function.first_instruction and instruction_index < instruction_end) return function;
    }
    return null;
}

fn instructionOwnerFunctionIndex(comptime compiled_plan: program_plan.ProgramPlan, comptime instruction_index: usize) ?usize {
    inline for (compiled_plan.functions, 0..) |function, function_index| {
        const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
        if (instruction_index >= function.first_instruction and instruction_index < instruction_end) return function_index;
    }
    return null;
}

fn instructionLocalHasExecutableScalarCodec(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    comptime local_id: u16,
) bool {
    const local_codec = functionLocalCodec(compiled_plan, function, local_id) orelse return false;
    return executableScalarCodec(local_codec);
}

fn instructionLocalHasExecutableTypedRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function: program_plan.FunctionPlan,
    comptime local_id: u16,
) bool {
    const local_ref = functionLocalRef(compiled_plan, function, local_id) orelse return false;
    return executableTypedRef(schema_types, local_ref);
}

fn functionValueRef(function: program_plan.FunctionPlan) program_plan.ValueRef {
    return .{ .codec = function.value_codec, .schema_index = function.value_schema_index };
}

fn StaticPlanIdentity(comptime compiled_plan: program_plan.ProgramPlan) type {
    return struct {
        pub const fingerprint: u64 = compute();

        fn compute() u64 {
            @setEvalBranchQuota(1_000_000);
            return compiled_plan.canonicalHash();
        }
    };
}

/// Target-neutral ProgramPlan identity used by Boundary StaticMachine v1.
pub fn staticPlanFingerprint(comptime compiled_plan: program_plan.ProgramPlan) u64 {
    return StaticPlanIdentity(compiled_plan).fingerprint;
}

fn effectiveCompletionRefForFunction(
    comptime analysis: anytype,
    comptime function: program_plan.FunctionPlan,
    comptime function_index: usize,
) program_plan.ValueRef {
    if (analysis.after_result_functions[function_index]) return program_plan.functionResultRef(function);
    return functionValueRef(function);
}

pub fn authoredBoundProgramPlan(
    comptime label: []const u8,
    comptime Payload: type,
    comptime Resume: type,
    comptime Answer: type,
    comptime mode: program_plan.ControlMode,
) ?program_plan.ProgramPlan {
    return program_plan.authoredBoundPlan(label, Payload, Resume, Answer, mode);
}

const max_interpreter_steps = 10_000;
const static_usize_bits: u8 = 32;
const static_usize_max: u64 = std.math.maxInt(u32);

/// Stable version tag mixed into Program.Session trace fingerprints.
pub const trace_fingerprint_version: u32 = 2;

/// Static metadata for one entry-reachable Program.Session operation yield site.
pub const SessionOperationYieldSite = struct {
    index: usize,
    fingerprint: u64,
    canonical_fingerprint: u64,
    legacy_fingerprint: u64,
    semantic_label: ?[]const u8 = null,
    function_index: usize,
    function_symbol_name: []const u8,
    block_index: usize,
    instruction_index: usize,
    requirement_index: u16,
    requirement_label: []const u8,
    op_index: u16,
    op_name: []const u8,
    op_mode: program_plan.ControlMode,
    payload_ref: program_plan.ValueRef,
    resume_ref: program_plan.ValueRef,
    result_ref: program_plan.ValueRef,
    has_after: bool,
    host_may_resume: bool,
    host_may_return_now: bool,
    can_yield_after: bool,
};

/// Static metadata for one entry-reachable Program.Session after-continuation site.
pub const SessionAfterYieldSite = struct {
    index: usize,
    fingerprint: u64,
    canonical_fingerprint: u64,
    legacy_fingerprint: u64,
    semantic_label: ?[]const u8 = null,
    source_operation_site_index: usize,
    source_operation_site_fingerprint: u64,
    source_operation_site_canonical_fingerprint: u64,
    source_operation_site_legacy_fingerprint: u64,
    source_function_index: usize,
    source_block_index: usize,
    source_instruction_index: usize,
    original_requirement_index: u16,
    original_requirement_label: []const u8,
    original_op_index: u16,
    original_op_name: []const u8,
    // Dynamic current/output refs depend on the concrete after stack and are exposed by AfterRequest.trace().
    result_ref: program_plan.ValueRef,
};

fn sessionSiteHashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
    sessionSiteHashUsize(hasher, value.len);
    hasher.update(value);
}

fn sessionSiteHashBool(hasher: *std.hash.Wyhash, value: bool) void {
    hasher.update(&[_]u8{@intFromBool(value)});
}

fn sessionSiteHashU8(hasher: *std.hash.Wyhash, value: u8) void {
    hasher.update(&[_]u8{value});
}

fn sessionSiteHashU16(hasher: *std.hash.Wyhash, value: u16) void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    hasher.update(&bytes);
}

fn sessionSiteHashU32(hasher: *std.hash.Wyhash, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn sessionSiteHashU64(hasher: *std.hash.Wyhash, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn sessionSiteHashUsize(hasher: *std.hash.Wyhash, value: usize) void {
    sessionSiteHashU64(hasher, @intCast(value));
}

fn sessionSiteHashOptionalU16(hasher: *std.hash.Wyhash, value: ?u16) void {
    sessionSiteHashBool(hasher, value != null);
    if (value) |actual| sessionSiteHashU16(hasher, actual);
}

fn sessionSiteHashCodec(hasher: *std.hash.Wyhash, codec: program_plan.ValueCodec) void {
    sessionSiteHashU8(hasher, @intFromEnum(codec));
}

fn sessionSiteHashMode(hasher: *std.hash.Wyhash, mode: program_plan.ControlMode) void {
    sessionSiteHashBytes(hasher, @tagName(mode));
}

fn sessionSiteHashValueRef(hasher: *std.hash.Wyhash, ref: program_plan.ValueRef) void {
    sessionSiteHashCodec(hasher, ref.codec);
    sessionSiteHashOptionalU16(hasher, ref.schema_index);
}

fn sessionSiteHashStaticCarrierType(hasher: *std.hash.Wyhash, comptime T: type) void {
    if (T == void) return sessionSiteHashBytes(hasher, "unit");
    if (T == noreturn) return sessionSiteHashBytes(hasher, "noreturn");
    if (T == bool) return sessionSiteHashBytes(hasher, "bool");
    if (T == i32) return sessionSiteHashBytes(hasher, "i32");
    if (T == u64) return sessionSiteHashBytes(hasher, "u64");
    if (T == usize) return sessionSiteHashBytes(hasher, "usize32");
    if (T == []const u8) return sessionSiteHashBytes(hasher, "string");
    if (T == []const []const u8) return sessionSiteHashBytes(hasher, "string-list");
    if (T == [][]const u8) return sessionSiteHashBytes(hasher, "mutable-string-list");

    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            sessionSiteHashBytes(hasher, "product");
            sessionSiteHashUsize(hasher, info.fields.len);
            inline for (info.fields) |field| {
                sessionSiteHashBytes(hasher, field.name);
                sessionSiteHashStaticCarrierType(hasher, field.type);
            }
        },
        .@"enum" => |info| {
            sessionSiteHashBytes(hasher, "sum-enum");
            const tag_info = @typeInfo(info.tag_type).int;
            sessionSiteHashBytes(hasher, @tagName(tag_info.signedness));
            sessionSiteHashU16(hasher, tag_info.bits);
            sessionSiteHashBool(hasher, info.is_exhaustive);
            sessionSiteHashUsize(hasher, info.fields.len);
            inline for (info.fields) |field| {
                sessionSiteHashBytes(hasher, field.name);
                sessionSiteHashBytes(hasher, std.fmt.comptimePrint("{d}", .{field.value}));
            }
        },
        .optional => |info| {
            sessionSiteHashBytes(hasher, "sum-optional");
            sessionSiteHashStaticCarrierType(hasher, info.child);
        },
        .@"union" => |info| {
            sessionSiteHashBytes(hasher, "sum-union");
            const Tag = info.tag_type orelse @compileError("unsupported untagged Boundary StaticMachine union carrier");
            sessionSiteHashStaticCarrierType(hasher, Tag);
            sessionSiteHashUsize(hasher, info.fields.len);
            inline for (info.fields) |field| {
                sessionSiteHashBytes(hasher, field.name);
                sessionSiteHashStaticCarrierType(hasher, field.type);
            }
        },
        else => @compileError("unsupported Boundary StaticMachine schema carrier type: " ++ @typeName(T)),
    }
}

fn sessionSiteHashStaticSchemaCarriers(hasher: *std.hash.Wyhash, comptime schema_types: anytype) void {
    sessionSiteHashUsize(hasher, schema_types.len);
    inline for (schema_types, 0..) |SchemaType, schema_index| {
        sessionSiteHashUsize(hasher, schema_index);
        sessionSiteHashStaticCarrierType(hasher, SchemaType);
    }
}

fn sessionHostMayResume(mode: program_plan.ControlMode) bool {
    return mode != .abort;
}

fn sessionHostMayReturnNow(mode: program_plan.ControlMode) bool {
    return mode != .transform;
}

fn sessionOperationSiteFingerprint(
    comptime compiled_plan: program_plan.ProgramPlan,
    site: SessionOperationYieldSite,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    sessionSiteHashBytes(&hasher, "boundary.session.static_site");
    sessionSiteHashU32(&hasher, trace_fingerprint_version);
    sessionSiteHashBytes(&hasher, "operation");
    sessionSiteHashU64(&hasher, compiled_plan.hash());
    sessionSiteHashUsize(&hasher, site.index);
    sessionSiteHashUsize(&hasher, site.function_index);
    sessionSiteHashBytes(&hasher, site.function_symbol_name);
    sessionSiteHashUsize(&hasher, site.block_index);
    sessionSiteHashUsize(&hasher, site.instruction_index);
    sessionSiteHashU16(&hasher, site.requirement_index);
    sessionSiteHashBytes(&hasher, site.requirement_label);
    sessionSiteHashU16(&hasher, site.op_index);
    sessionSiteHashBytes(&hasher, site.op_name);
    sessionSiteHashMode(&hasher, site.op_mode);
    sessionSiteHashValueRef(&hasher, site.payload_ref);
    sessionSiteHashValueRef(&hasher, site.resume_ref);
    sessionSiteHashValueRef(&hasher, site.result_ref);
    sessionSiteHashBool(&hasher, site.has_after);
    sessionSiteHashBool(&hasher, site.host_may_resume);
    sessionSiteHashBool(&hasher, site.host_may_return_now);
    sessionSiteHashBool(&hasher, site.can_yield_after);
    return hasher.final();
}

fn staticMachineOperationSiteFingerprint(
    canonical_plan_fingerprint: u64,
    site: SessionOperationYieldSite,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    sessionSiteHashBytes(&hasher, "boundary.static-machine.static-site.v1");
    sessionSiteHashBytes(&hasher, "operation");
    sessionSiteHashU64(&hasher, canonical_plan_fingerprint);
    sessionSiteHashUsize(&hasher, site.index);
    sessionSiteHashUsize(&hasher, site.function_index);
    sessionSiteHashBytes(&hasher, site.function_symbol_name);
    sessionSiteHashUsize(&hasher, site.block_index);
    sessionSiteHashUsize(&hasher, site.instruction_index);
    sessionSiteHashU16(&hasher, site.requirement_index);
    sessionSiteHashBytes(&hasher, site.requirement_label);
    sessionSiteHashU16(&hasher, site.op_index);
    sessionSiteHashBytes(&hasher, site.op_name);
    sessionSiteHashMode(&hasher, site.op_mode);
    sessionSiteHashValueRef(&hasher, site.payload_ref);
    sessionSiteHashValueRef(&hasher, site.resume_ref);
    sessionSiteHashValueRef(&hasher, site.result_ref);
    sessionSiteHashBool(&hasher, site.has_after);
    sessionSiteHashBool(&hasher, site.host_may_resume);
    sessionSiteHashBool(&hasher, site.host_may_return_now);
    sessionSiteHashBool(&hasher, site.can_yield_after);
    return hasher.final();
}

fn sessionAfterSiteFingerprint(
    comptime compiled_plan: program_plan.ProgramPlan,
    site: SessionAfterYieldSite,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    sessionSiteHashBytes(&hasher, "boundary.session.static_site");
    sessionSiteHashU32(&hasher, trace_fingerprint_version);
    sessionSiteHashBytes(&hasher, "after");
    sessionSiteHashU64(&hasher, compiled_plan.hash());
    sessionSiteHashUsize(&hasher, site.index);
    sessionSiteHashUsize(&hasher, site.source_operation_site_index);
    sessionSiteHashU64(&hasher, site.source_operation_site_fingerprint);
    sessionSiteHashUsize(&hasher, site.source_function_index);
    sessionSiteHashUsize(&hasher, site.source_block_index);
    sessionSiteHashUsize(&hasher, site.source_instruction_index);
    sessionSiteHashU16(&hasher, site.original_requirement_index);
    sessionSiteHashBytes(&hasher, site.original_requirement_label);
    sessionSiteHashU16(&hasher, site.original_op_index);
    sessionSiteHashBytes(&hasher, site.original_op_name);
    sessionSiteHashValueRef(&hasher, site.result_ref);
    return hasher.final();
}

fn staticMachineAfterSiteFingerprint(
    canonical_plan_fingerprint: u64,
    site: SessionAfterYieldSite,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    sessionSiteHashBytes(&hasher, "boundary.static-machine.static-site.v1");
    sessionSiteHashBytes(&hasher, "after");
    sessionSiteHashU64(&hasher, canonical_plan_fingerprint);
    sessionSiteHashUsize(&hasher, site.index);
    sessionSiteHashUsize(&hasher, site.source_operation_site_index);
    sessionSiteHashU64(&hasher, site.source_operation_site_canonical_fingerprint);
    sessionSiteHashUsize(&hasher, site.source_function_index);
    sessionSiteHashUsize(&hasher, site.source_block_index);
    sessionSiteHashUsize(&hasher, site.source_instruction_index);
    sessionSiteHashU16(&hasher, site.original_requirement_index);
    sessionSiteHashBytes(&hasher, site.original_requirement_label);
    sessionSiteHashU16(&hasher, site.original_op_index);
    sessionSiteHashBytes(&hasher, site.original_op_name);
    sessionSiteHashValueRef(&hasher, site.result_ref);
    return hasher.final();
}

const YieldSiteAnalysisIdentity = enum {
    legacy_session,
    static_machine_v1,
};

fn yieldSiteEntryAnalysis(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime identity: YieldSiteAnalysisIdentity,
) program_plan.EntryExecutionAnalysis(compiled_plan) {
    return comptime switch (identity) {
        .legacy_session => program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets),
        .static_machine_v1 => program_plan.staticEntryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets),
    } catch |err| @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
}

fn operationYieldSiteCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime identity: YieldSiteAnalysisIdentity,
) usize {
    const analysis = yieldSiteEntryAnalysis(compiled_plan, nested_with_targets, identity);
    var count: usize = 0;
    inline for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
        if (analysis.reachable_instructions[instruction_index] and instruction.kind == .call_op) count += 1;
    }
    return count;
}

fn sessionOperationYieldSiteCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) usize {
    return operationYieldSiteCount(compiled_plan, nested_with_targets, .legacy_session);
}

fn staticMachineOperationYieldSiteCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) usize {
    return operationYieldSiteCount(compiled_plan, nested_with_targets, .static_machine_v1);
}

fn afterYieldSiteCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime identity: YieldSiteAnalysisIdentity,
) usize {
    const analysis = yieldSiteEntryAnalysis(compiled_plan, nested_with_targets, identity);
    var count: usize = 0;
    inline for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
        if (analysis.reachable_instructions[instruction_index] and
            instruction.kind == .call_op and
            instruction.operand < compiled_plan.ops.len and
            compiled_plan.ops[instruction.operand].has_after)
        {
            count += 1;
        }
    }
    return count;
}

fn sessionAfterYieldSiteCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) usize {
    return afterYieldSiteCount(compiled_plan, nested_with_targets, .legacy_session);
}

fn staticMachineAfterYieldSiteCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) usize {
    return afterYieldSiteCount(compiled_plan, nested_with_targets, .static_machine_v1);
}

fn siteLabelForInstruction(comptime site_metadata: anytype, comptime instruction_index: usize) ?[]const u8 {
    comptime var label: ?[]const u8 = null;
    inline for (site_metadata) |entry| {
        if (entry.instruction_index == instruction_index) {
            if (label != null) @compileError("Body.site_metadata has duplicate label for one instruction index");
            if (entry.label.len == 0) @compileError("Body.site_metadata labels must be non-empty");
            label = entry.label;
        }
    }
    return label;
}

fn fillSessionOperationYieldSites(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime site_metadata: anytype,
    comptime identity: YieldSiteAnalysisIdentity,
    sites: anytype,
) void {
    const analysis = yieldSiteEntryAnalysis(compiled_plan, nested_with_targets, identity);
    var next_site: usize = 0;
    inline for (compiled_plan.functions, 0..) |function, function_index| {
        const function_block_end = @as(usize, function.first_block) + function.block_count;
        block_loop: inline for (compiled_plan.blocks[function.first_block..function_block_end], function.first_block..) |block, block_index| {
            if (!analysis.reachable_blocks[block_index]) continue :block_loop;
            const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
            instruction_loop: inline for (compiled_plan.instructions[block.first_instruction..instruction_end], block.first_instruction..) |instruction, instruction_index| {
                if (!analysis.reachable_instructions[instruction_index] or instruction.kind != .call_op) continue :instruction_loop;
                if (instruction.operand >= compiled_plan.ops.len) @compileError("reachable call_op references an invalid op index");
                const op = compiled_plan.ops[instruction.operand];
                const requirement = compiled_plan.requirements[op.requirement_index];
                var site: SessionOperationYieldSite = .{
                    .index = next_site,
                    .fingerprint = 0,
                    .canonical_fingerprint = 0,
                    .legacy_fingerprint = 0,
                    .semantic_label = siteLabelForInstruction(site_metadata, instruction_index),
                    .function_index = function_index,
                    .function_symbol_name = function.symbol_name,
                    .block_index = block_index,
                    .instruction_index = instruction_index,
                    .requirement_index = op.requirement_index,
                    .requirement_label = requirement.label,
                    .op_index = instruction.operand,
                    .op_name = op.op_name,
                    .op_mode = op.mode,
                    .payload_ref = .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index },
                    .resume_ref = .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index },
                    .result_ref = program_plan.functionResultRef(function),
                    .has_after = op.has_after,
                    .host_may_resume = sessionHostMayResume(op.mode),
                    .host_may_return_now = sessionHostMayReturnNow(op.mode),
                    .can_yield_after = op.has_after,
                };
                site.fingerprint = sessionOperationSiteFingerprint(compiled_plan, site);
                site.legacy_fingerprint = site.fingerprint;
                sites[next_site] = site;
                next_site += 1;
            }
        }
    }
}

/// Build the deterministic entry-reachable Program.Session operation site catalog for a plan.
pub fn sessionOperationYieldSitesForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) [sessionOperationYieldSiteCount(compiled_plan, nested_with_targets)]SessionOperationYieldSite {
    return sessionOperationYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, .{});
}

/// Build the deterministic entry-reachable Program.Session operation site catalog
/// and attach optional non-fingerprint semantic labels.
pub fn sessionOperationYieldSitesForPlanWithMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime site_metadata: anytype,
) [sessionOperationYieldSiteCount(compiled_plan, nested_with_targets)]SessionOperationYieldSite {
    var sites: [sessionOperationYieldSiteCount(compiled_plan, nested_with_targets)]SessionOperationYieldSite = undefined;
    fillSessionOperationYieldSites(compiled_plan, nested_with_targets, site_metadata, .legacy_session, &sites);
    return sites;
}

/// Build the target-neutral StaticMachine operation site catalog for a plan.
pub fn staticMachineOperationYieldSitesForPlanWithMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime site_metadata: anytype,
) [staticMachineOperationYieldSiteCount(compiled_plan, nested_with_targets)]SessionOperationYieldSite {
    var sites: [staticMachineOperationYieldSiteCount(compiled_plan, nested_with_targets)]SessionOperationYieldSite = undefined;
    fillSessionOperationYieldSites(compiled_plan, nested_with_targets, site_metadata, .static_machine_v1, &sites);
    const legacy_sites = sessionOperationYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    const canonical_plan_fingerprint = staticPlanFingerprint(compiled_plan);
    inline for (&sites) |*site| {
        comptime var legacy_fingerprint: ?u64 = null;
        inline for (legacy_sites) |legacy_site| {
            if (legacy_site.function_index == site.function_index and
                legacy_site.block_index == site.block_index and
                legacy_site.instruction_index == site.instruction_index)
            {
                legacy_fingerprint = legacy_site.fingerprint;
            }
        }
        site.legacy_fingerprint = legacy_fingerprint orelse
            @compileError("StaticMachine operation site is absent from the legacy Program.Session catalog");
        site.canonical_fingerprint = staticMachineOperationSiteFingerprint(canonical_plan_fingerprint, site.*);
        site.fingerprint = site.canonical_fingerprint;
    }
    return sites;
}

/// Build the deterministic entry-reachable Program.Session after site catalog for a plan.
pub fn sessionAfterYieldSitesForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) [sessionAfterYieldSiteCount(compiled_plan, nested_with_targets)]SessionAfterYieldSite {
    return sessionAfterYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, .{});
}

/// Build the deterministic entry-reachable Program.Session after site catalog
/// and attach optional non-fingerprint semantic labels.
pub fn sessionAfterYieldSitesForPlanWithMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime site_metadata: anytype,
) [sessionAfterYieldSiteCount(compiled_plan, nested_with_targets)]SessionAfterYieldSite {
    const operation_sites = sessionOperationYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    var sites: [sessionAfterYieldSiteCount(compiled_plan, nested_with_targets)]SessionAfterYieldSite = undefined;
    fillSessionAfterYieldSites(compiled_plan, operation_sites, &sites);
    return sites;
}

/// Build the target-neutral StaticMachine after-continuation site catalog for a plan.
pub fn staticMachineAfterYieldSitesForPlanWithMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime site_metadata: anytype,
) [staticMachineAfterYieldSiteCount(compiled_plan, nested_with_targets)]SessionAfterYieldSite {
    const operation_sites = staticMachineOperationYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    const legacy_sites = sessionAfterYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    var sites: [staticMachineAfterYieldSiteCount(compiled_plan, nested_with_targets)]SessionAfterYieldSite = undefined;
    fillSessionAfterYieldSites(compiled_plan, operation_sites, &sites);
    const canonical_plan_fingerprint = staticPlanFingerprint(compiled_plan);
    inline for (&sites) |*site| {
        comptime var legacy_fingerprint: ?u64 = null;
        inline for (legacy_sites) |legacy_site| {
            if (legacy_site.source_function_index == site.source_function_index and
                legacy_site.source_block_index == site.source_block_index and
                legacy_site.source_instruction_index == site.source_instruction_index)
            {
                legacy_fingerprint = legacy_site.fingerprint;
                site.source_operation_site_legacy_fingerprint = legacy_site.source_operation_site_legacy_fingerprint;
            }
        }
        site.legacy_fingerprint = legacy_fingerprint orelse
            @compileError("StaticMachine after site is absent from the legacy Program.Session catalog");
        const operation_site = operation_sites[site.source_operation_site_index];
        site.source_operation_site_fingerprint = operation_site.fingerprint;
        site.source_operation_site_canonical_fingerprint = operation_site.canonical_fingerprint;
        site.canonical_fingerprint = staticMachineAfterSiteFingerprint(canonical_plan_fingerprint, site.*);
        site.fingerprint = site.canonical_fingerprint;
    }
    return sites;
}

fn fillSessionAfterYieldSites(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime operation_sites: anytype,
    sites: anytype,
) void {
    var next_after_site: usize = 0;
    inline for (operation_sites) |operation_site| {
        if (!operation_site.has_after) continue;
        var site: SessionAfterYieldSite = .{
            .index = next_after_site,
            .fingerprint = 0,
            .canonical_fingerprint = 0,
            .legacy_fingerprint = 0,
            .semantic_label = operation_site.semantic_label,
            .source_operation_site_index = operation_site.index,
            .source_operation_site_fingerprint = operation_site.legacy_fingerprint,
            .source_operation_site_canonical_fingerprint = operation_site.canonical_fingerprint,
            .source_operation_site_legacy_fingerprint = operation_site.legacy_fingerprint,
            .source_function_index = operation_site.function_index,
            .source_block_index = operation_site.block_index,
            .source_instruction_index = operation_site.instruction_index,
            .original_requirement_index = operation_site.requirement_index,
            .original_requirement_label = operation_site.requirement_label,
            .original_op_index = operation_site.op_index,
            .original_op_name = operation_site.op_name,
            .result_ref = operation_site.result_ref,
        };
        site.fingerprint = sessionAfterSiteFingerprint(compiled_plan, site);
        site.legacy_fingerprint = site.fingerprint;
        sites[next_after_site] = site;
        next_after_site += 1;
    }
}

const SchemaValue = struct {
    schema_index: u16,
    ptr: *const anyopaque,
};

const ExecutableValue = union(enum) {
    none,
    bool: bool,
    i32: i32,
    usize: usize,
    word_u64: u64,
    string: []const u8,
    string_list: []const []const u8,
    schema: SchemaValue,
};

fn maxSchemaValueSize(comptime schema_types: anytype) comptime_int {
    var max_size: comptime_int = 0;
    inline for (schema_types) |SchemaType| {
        if (@sizeOf(SchemaType) > max_size) max_size = @sizeOf(SchemaType);
    }
    return max_size;
}

fn maxSchemaValueAlign(comptime schema_types: anytype) comptime_int {
    var max_align: comptime_int = 1;
    inline for (schema_types) |SchemaType| {
        if (@alignOf(SchemaType) > max_align) max_align = @alignOf(SchemaType);
    }
    return max_align;
}

fn ValueTypeForCodec(comptime codec: program_plan.ValueCodec) type {
    return switch (codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .product => @compileError("product ValueCodec requires a schema-specific typed decoder"),
        .usize => usize,
        .string => []const u8,
        .string_list => []const []const u8,
        .sum => @compileError("sum ValueCodec requires a schema-specific typed decoder"),
    };
}

fn ValueTypeForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
) type {
    _ = compiled_plan;
    return switch (ref.codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .usize => usize,
        .string => []const u8,
        .string_list => []const []const u8,
        .product, .sum => schema_types[ref.schema_index orelse @compileError("structured ValueRef is missing a schema index")],
    };
}

fn isStringListCarrier(comptime T: type) bool {
    return T == []const []const u8 or T == [][]const u8;
}

fn typeMayBorrowRuntimeStorage(comptime T: type) bool {
    if (T == []const u8 or isStringListCarrier(T)) return true;
    return switch (@typeInfo(T)) {
        .optional => |optional_info| typeMayBorrowRuntimeStorage(optional_info.child),
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (typeMayBorrowRuntimeStorage(field.type)) return true;
            }
            return false;
        },
        .@"union" => |union_info| {
            inline for (union_info.fields) |field| {
                if (typeMayBorrowRuntimeStorage(field.type)) return true;
            }
            return false;
        },
        else => false,
    };
}

fn typedValueMayBorrowRuntimeStorage(value: anytype) bool {
    const ValueType = @TypeOf(value);
    if (ValueType == []const u8 or isStringListCarrier(ValueType)) return true;
    return switch (@typeInfo(ValueType)) {
        .optional => {
            if (value == null) return false;
            return typedValueMayBorrowRuntimeStorage(value.?);
        },
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (typedValueMayBorrowRuntimeStorage(@field(value, field.name))) return true;
            }
            return false;
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return typeMayBorrowRuntimeStorage(ValueType);
            const active = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active == @field(Tag, field.name)) {
                    if (field.type == void) return false;
                    return typedValueMayBorrowRuntimeStorage(@field(value, field.name));
                }
            }
            return false;
        },
        else => false,
    };
}

fn typeMatchesRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    comptime T: type,
) bool {
    return switch (ref.codec) {
        .string_list => isStringListCarrier(T),
        else => T == ValueTypeForRef(compiled_plan, schema_types, ref),
    };
}

fn typeMatchesRuntimeRef(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    comptime T: type,
) bool {
    if (T == void) return ref.eql(.{ .codec = .unit });
    if (T == bool) return ref.eql(.{ .codec = .bool });
    if (T == i32) return ref.eql(.{ .codec = .i32 });
    if (T == usize) return ref.eql(.{ .codec = .usize });
    if (T == []const u8) return ref.eql(.{ .codec = .string });
    if (comptime isStringListCarrier(T)) return ref.eql(.{ .codec = .string_list });
    const structured_codec: program_plan.ValueCodec = switch (@typeInfo(T)) {
        .@"struct" => .product,
        .@"enum", .@"union", .optional => .sum,
        else => return false,
    };
    if (ref.codec != structured_codec) return false;
    const schema_index = ref.schema_index orelse return false;
    inline for (schema_types, 0..) |SchemaType, index| {
        if (schema_index == index) return SchemaType == T;
    }
    return false;
}

fn typeMatchesSchemaFieldRuntimeRef(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    comptime T: type,
) bool {
    if (T == u64) return ref.eql(.{ .codec = .usize });
    return typeMatchesRuntimeRef(schema_types, ref, T);
}

const RuntimeRefMatchMode = enum {
    strict,
    schema_field,
};

fn encodeScalarValue(value: anytype) ExecutableValue {
    if (comptime isStringListCarrier(@TypeOf(value))) return .{ .string_list = value };
    return switch (@TypeOf(value)) {
        void => .none,
        bool => .{ .bool = value },
        i32 => .{ .i32 = value },
        u64 => .{ .word_u64 = value },
        usize => .{ .usize = value },
        []const u8 => .{ .string = value },
        else => @compileError("unsupported authored scalar result type"),
    };
}

fn executableWordU64(value: ExecutableValue) error{ProgramContractViolation}!u64 {
    return switch (value) {
        .usize => |typed| @intCast(typed),
        .word_u64 => |typed| typed,
        else => error.ProgramContractViolation,
    };
}

fn RunResultTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    return struct {
        value: ValueTypeForCodec(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index])),
    };
}

fn TypedRunResultTypeForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
) type {
    return struct {
        value: ValueTypeForRef(compiled_plan, schema_types, program_plan.functionResultRef(compiled_plan.functions[compiled_plan.entry_index])),
    };
}

fn executableValueRef(codec: program_plan.ValueCodec, value: ExecutableValue) ?program_plan.ValueRef {
    return switch (codec) {
        .unit => switch (value) {
            .none => .{ .codec = .unit },
            else => null,
        },
        .bool => switch (value) {
            .bool => .{ .codec = .bool },
            else => null,
        },
        .i32 => switch (value) {
            .i32 => .{ .codec = .i32 },
            else => null,
        },
        .usize => switch (value) {
            .usize => .{ .codec = .usize },
            .word_u64 => .{ .codec = .usize },
            else => null,
        },
        .string => switch (value) {
            .string => .{ .codec = .string },
            else => null,
        },
        .string_list => switch (value) {
            .string_list => .{ .codec = .string_list },
            else => null,
        },
        .product, .sum => switch (value) {
            .schema => |schema| .{ .codec = codec, .schema_index = schema.schema_index },
            else => null,
        },
    };
}

fn decodeArg(
    comptime codec: program_plan.ValueCodec,
    value: ExecutableValue,
) error{ProgramContractViolation}!ValueTypeForCodec(codec) {
    return switch (codec) {
        .unit => switch (value) {
            .none => {},
            else => error.ProgramContractViolation,
        },
        .bool => switch (value) {
            .bool => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .i32 => switch (value) {
            .i32 => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .usize => switch (value) {
            .usize => |typed| typed,
            .word_u64 => |typed| if (typed <= std.math.maxInt(usize)) @intCast(typed) else error.ProgramContractViolation,
            else => error.ProgramContractViolation,
        },
        .string => switch (value) {
            .string => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .string_list => switch (value) {
            .string_list => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .product, .sum => error.ProgramContractViolation,
    };
}

fn decodeTypedValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    value: ExecutableValue,
) error{ProgramContractViolation}!ValueTypeForRef(compiled_plan, schema_types, ref) {
    return switch (comptime ref.codec) {
        .unit => try decodeArg(.unit, value),
        .bool => try decodeArg(.bool, value),
        .i32 => try decodeArg(.i32, value),
        .usize => try decodeArg(.usize, value),
        .string => try decodeArg(.string, value),
        .string_list => try decodeArg(.string_list, value),
        .product, .sum => switch (value) {
            .schema => |schema| blk: {
                const expected_index = ref.schema_index orelse return error.ProgramContractViolation;
                if (schema.schema_index != expected_index) return error.ProgramContractViolation;
                const T = ValueTypeForRef(compiled_plan, schema_types, ref);
                const typed: *const T = @ptrCast(@alignCast(schema.ptr));
                break :blk typed.*;
            },
            else => error.ProgramContractViolation,
        },
    };
}

fn encodeTypedValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    value: ValueTypeForRef(compiled_plan, schema_types, ref),
) ExecutableValue {
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value),
        .product, .sum => .{
            .schema = .{
                .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
                .ptr = &value,
            },
        },
    };
}

fn schemaIndexForType(comptime schema_types: anytype, comptime T: type) ?u16 {
    inline for (schema_types, 0..) |SchemaType, index| {
        if (SchemaType == T) return @intCast(index);
    }
    return null;
}

fn valueRefForType(comptime schema_types: anytype, comptime T: type) program_plan.ValueRef {
    if (T == void) return .{ .codec = .unit };
    if (T == bool) return .{ .codec = .bool };
    if (T == i32) return .{ .codec = .i32 };
    if (T == u64) return .{ .codec = .usize };
    if (T == usize) return .{ .codec = .usize };
    if (T == []const u8) return .{ .codec = .string };
    if (isStringListCarrier(T)) return .{ .codec = .string_list };
    const schema_index = schemaIndexForType(schema_types, T) orelse
        @compileError("authored structured value type is not present in Body.value_schema_types: " ++ @typeName(T));
    return switch (@typeInfo(T)) {
        .@"struct" => .{ .codec = .product, .schema_index = schema_index },
        .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
        else => @compileError("unsupported authored value type: " ++ @typeName(T)),
    };
}

fn runtimeValueRefForType(comptime schema_types: anytype, comptime T: type) ?program_plan.ValueRef {
    if (T == void) return .{ .codec = .unit };
    if (T == bool) return .{ .codec = .bool };
    if (T == i32) return .{ .codec = .i32 };
    if (T == u64) return .{ .codec = .usize };
    if (T == usize) return .{ .codec = .usize };
    if (T == []const u8) return .{ .codec = .string };
    if (isStringListCarrier(T)) return .{ .codec = .string_list };
    const schema_index = schemaIndexForType(schema_types, T) orelse return null;
    return switch (@typeInfo(T)) {
        .@"struct" => .{ .codec = .product, .schema_index = schema_index },
        .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
        else => null,
    };
}

fn runtimeSurfaceValueRefForType(comptime schema_types: anytype, comptime T: type) ?program_plan.ValueRef {
    if (T == u64) return null;
    return runtimeValueRefForType(schema_types, T);
}

fn ReturnPayloadType(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn CallableReturnPayloadType(comptime callable: anytype) type {
    return ReturnPayloadType(@typeInfo(@TypeOf(callable)).@"fn".return_type.?);
}

fn CallableParamPayloadType(comptime callable: anytype, comptime param_index: usize) type {
    const info = @typeInfo(@TypeOf(callable)).@"fn";
    if (param_index >= info.params.len) @compileError("callable parameter index out of bounds");
    return info.params[param_index].type orelse @compileError("callable parameter is missing a type");
}

fn runtimeTypeNeedsSchemaStorage(comptime schema_types: anytype, comptime T: type) bool {
    const ref = runtimeValueRefForType(schema_types, T) orelse return false;
    return structuredSchemaCodec(ref.codec);
}

fn PreparedRuntimeValue(comptime T: type, comptime structured: bool) type {
    return struct {
        schema_index: u16 = 0,
        ptr: ?*T = null,

        fn encode(self: @This(), value: T) ExecutableValue {
            if (comptime structured) {
                const ptr = self.ptr.?;
                ptr.* = value;
                return .{ .schema = .{
                    .schema_index = self.schema_index,
                    .ptr = ptr,
                } };
            }
            return encodeScalarValue(value);
        }
    };
}

fn prepareRuntimeValueForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    scratch: anytype,
) std.mem.Allocator.Error!PreparedRuntimeValue(
    ValueTypeForRef(compiled_plan, schema_types, ref),
    structuredSchemaCodec(ref.codec),
) {
    const Expected = ValueTypeForRef(compiled_plan, schema_types, ref);
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => .{},
        .product, .sum => .{
            .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            .ptr = try scratch.reserveSchemaValueStorage(
                Expected,
            ),
        },
    };
}

fn prepareRuntimeValueForType(
    comptime schema_types: anytype,
    scratch: anytype,
    comptime T: type,
) anyerror!struct {
    value: PreparedRuntimeValue(T, runtimeTypeNeedsSchemaStorage(schema_types, T)),
    ref: program_plan.ValueRef,
} {
    const ref = comptime runtimeValueRefForType(schema_types, T) orelse return error.ProgramContractViolation;
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => .{ .value = .{}, .ref = ref },
        .product, .sum => .{
            .value = .{
                .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
                .ptr = try scratch.reserveSchemaValueStorage(
                    T,
                ),
            },
            .ref = ref,
        },
    };
}

fn encodeRuntimeValueForRuntimeRef(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const Value = @TypeOf(value);
    if (!typeMatchesRuntimeRef(schema_types, ref, Value)) return error.ProgramContractViolation;
    return encodeRuntimeValueForMatchedRuntimeRef(ref, scratch, value);
}

fn encodeSchemaFieldRuntimeValueForRuntimeRef(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const Value = @TypeOf(value);
    if (!typeMatchesSchemaFieldRuntimeRef(schema_types, ref, Value)) return error.ProgramContractViolation;
    return encodeRuntimeValueForMatchedRuntimeRef(ref, scratch, value);
}

fn encodeRuntimeValueForMatchedRuntimeRef(
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const Value = @TypeOf(value);
    if (comptime Value == void or Value == bool or Value == i32 or Value == u64 or Value == usize or Value == []const u8 or isStringListCarrier(Value)) {
        return encodeScalarValue(value);
    }
    return scratch.storeSchemaValue(
        Value,
        ref.schema_index orelse return error.ProgramContractViolation,
        value,
    );
}

fn decodeRuntimeValueAs(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    value: ExecutableValue,
    comptime T: type,
) error{ProgramContractViolation}!T {
    if (!typeMatchesRuntimeRef(schema_types, ref, T)) return error.ProgramContractViolation;
    if (T == void) return switch (value) {
        .none => {},
        else => error.ProgramContractViolation,
    };
    if (T == bool) return switch (value) {
        .bool => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == i32) return switch (value) {
        .i32 => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == u64) return switch (value) {
        .usize => |typed| @intCast(typed),
        .word_u64 => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == usize) return switch (value) {
        .usize => |typed| typed,
        .word_u64 => |typed| if (typed <= std.math.maxInt(usize)) @intCast(typed) else error.ProgramContractViolation,
        else => error.ProgramContractViolation,
    };
    if (T == []const u8) return switch (value) {
        .string => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == []const []const u8) return switch (value) {
        .string_list => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == [][]const u8) return error.ProgramContractViolation;
    const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
    const expected_codec: program_plan.ValueCodec = comptime switch (@typeInfo(T)) {
        .@"struct" => .product,
        .@"enum", .@"union", .optional => .sum,
        else => return error.ProgramContractViolation,
    };
    if (ref.codec != expected_codec) return error.ProgramContractViolation;
    return switch (value) {
        .schema => |schema| blk: {
            if (schema.schema_index != schema_index) return error.ProgramContractViolation;
            const typed: *const T = @ptrCast(@alignCast(schema.ptr));
            break :blk typed.*;
        },
        else => error.ProgramContractViolation,
    };
}

fn encodeRuntimeValueForPreparedRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    prepared: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    if (comptime !typeMatchesRef(compiled_plan, schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
    return prepared.encode(value);
}

fn encodeRuntimeValue(
    comptime schema_types: anytype,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const ref = comptime valueRefForType(schema_types, @TypeOf(value));
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value),
        .product, .sum => try scratch.storeSchemaValue(
            @TypeOf(value),
            ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            value,
        ),
    };
}

const RuntimeValueWithRef = struct {
    value: ExecutableValue,
    ref: program_plan.ValueRef,
};

fn encodeRuntimeValueWithInferredRef(
    comptime schema_types: anytype,
    scratch: anytype,
    value: anytype,
) anyerror!RuntimeValueWithRef {
    const Value = @TypeOf(value);
    if (comptime isStringListCarrier(Value)) return .{ .value = .{ .string_list = value }, .ref = .{ .codec = .string_list } };
    return switch (Value) {
        void => .{ .value = .none, .ref = .{ .codec = .unit } },
        bool => .{ .value = .{ .bool = value }, .ref = .{ .codec = .bool } },
        i32 => .{ .value = .{ .i32 = value }, .ref = .{ .codec = .i32 } },
        usize => .{ .value = .{ .usize = value }, .ref = .{ .codec = .usize } },
        []const u8 => .{ .value = .{ .string = value }, .ref = .{ .codec = .string } },
        else => blk: {
            const schema_index = comptime schemaIndexForType(schema_types, Value) orelse std.math.maxInt(u16);
            if (comptime schema_index == std.math.maxInt(u16)) return error.ProgramContractViolation;
            const ref: program_plan.ValueRef = comptime switch (@typeInfo(Value)) {
                .@"struct" => .{ .codec = .product, .schema_index = schema_index },
                .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
                else => return error.ProgramContractViolation,
            };
            break :blk .{
                .value = try scratch.storeSchemaValue(Value, schema_index, value),
                .ref = ref,
            };
        },
    };
}

fn activeVariantOrdinalForTyped(
    comptime T: type,
    value: T,
) error{ProgramContractViolation}!u16 {
    return switch (@typeInfo(T)) {
        .@"enum" => |enum_info| {
            inline for (enum_info.fields, 0..) |field, field_index| {
                if (value == @field(T, field.name)) return @intCast(field_index);
            }
            return error.ProgramContractViolation;
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
            const active = std.meta.activeTag(value);
            inline for (union_info.fields, 0..) |field, field_index| {
                if (active == @field(Tag, field.name)) return @intCast(field_index);
            }
            return error.ProgramContractViolation;
        },
        .optional => if (value == null) 0 else 1,
        else => error.ProgramContractViolation,
    };
}

fn activeVariantOrdinalForExecutable(
    comptime schema_types: anytype,
    value: ExecutableValue,
) error{ProgramContractViolation}!u16 {
    const schema = switch (value) {
        .schema => |typed| typed,
        else => return error.ProgramContractViolation,
    };
    inline for (schema_types, 0..) |SchemaType, schema_index| {
        if (schema.schema_index == schema_index) {
            const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
            return activeVariantOrdinalForTyped(SchemaType, typed.*);
        }
    }
    return error.ProgramContractViolation;
}

fn extractVariantPayloadForTyped(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    comptime T: type,
    value: T,
    variant_ordinal: u16,
) anyerror!RuntimeValueWithRef {
    const active = try activeVariantOrdinalForTyped(T, value);
    if (active != variant_ordinal) return error.ProgramContractViolation;
    return switch (@typeInfo(T)) {
        .@"union" => |union_info| {
            inline for (union_info.fields, 0..) |field, field_index| {
                if (variant_ordinal == field_index) {
                    if (field.type == void) return error.ProgramContractViolation;
                    return .{
                        .value = try encodeSchemaFieldRuntimeValueForRuntimeRef(schema_types, ref, scratch, @field(value, field.name)),
                        .ref = ref,
                    };
                }
            }
            return error.ProgramContractViolation;
        },
        .optional => |optional_info| {
            _ = optional_info;
            if (variant_ordinal != 1) return error.ProgramContractViolation;
            return .{
                .value = try encodeSchemaFieldRuntimeValueForRuntimeRef(schema_types, ref, scratch, value.?),
                .ref = ref,
            };
        },
        else => error.ProgramContractViolation,
    };
}

fn extractVariantPayloadForExecutable(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: ExecutableValue,
    variant_ordinal: u16,
) anyerror!RuntimeValueWithRef {
    const schema = switch (value) {
        .schema => |typed| typed,
        else => return error.ProgramContractViolation,
    };
    inline for (schema_types, 0..) |SchemaType, schema_index| {
        if (schema.schema_index == schema_index) {
            const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
            return extractVariantPayloadForTyped(schema_types, ref, scratch, SchemaType, typed.*, variant_ordinal);
        }
    }
    return error.ProgramContractViolation;
}

fn extractProductFieldForTyped(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    comptime T: type,
    value: T,
    field_ordinal: u16,
) anyerror!RuntimeValueWithRef {
    return switch (@typeInfo(T)) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields, 0..) |field, field_index| {
                if (field_ordinal == field_index) {
                    return .{
                        .value = try encodeSchemaFieldRuntimeValueForRuntimeRef(schema_types, ref, scratch, @field(value, field.name)),
                        .ref = ref,
                    };
                }
            }
            return error.ProgramContractViolation;
        },
        else => error.ProgramContractViolation,
    };
}

fn extractProductFieldForExecutable(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: ExecutableValue,
    field_ordinal: u16,
) anyerror!RuntimeValueWithRef {
    const schema = switch (value) {
        .schema => |typed| typed,
        else => return error.ProgramContractViolation,
    };
    inline for (schema_types, 0..) |SchemaType, schema_index| {
        if (schema.schema_index == schema_index) {
            const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
            return extractProductFieldForTyped(schema_types, ref, scratch, SchemaType, typed.*, field_ordinal);
        }
    }
    return error.ProgramContractViolation;
}

fn encodeRuntimeValueForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    if (comptime !typeMatchesRef(compiled_plan, schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
    const Expected = ValueTypeForRef(compiled_plan, schema_types, ref);
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value),
        .product, .sum => try scratch.storeSchemaValue(
            Expected,
            ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            value,
        ),
    };
}

fn encodeBorrowedTypedValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    value: *const ValueTypeForRef(compiled_plan, schema_types, ref),
) ExecutableValue {
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value.*),
        .product, .sum => .{ .schema = .{
            .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            .ptr = value,
        } },
    };
}

fn valueMatchesRef(ref: program_plan.ValueRef, value: ExecutableValue) bool {
    const actual = executableValueRef(ref.codec, value) orelse return false;
    return actual.eql(ref);
}

fn valueMatchesCodec(codec: program_plan.ValueCodec, value: ExecutableValue) bool {
    return executableValueRef(codec, value) != null;
}

fn codecForScalarValue(value: ExecutableValue) program_plan.ValueCodec {
    return switch (value) {
        .none => .unit,
        .bool => .bool,
        .i32 => .i32,
        .usize => .usize,
        .word_u64 => .usize,
        .string => .string,
        .string_list => .string_list,
        .schema => unreachable,
    };
}

fn executableValueFromPublic(value: lowered_machine.ProgramValue) ExecutableValue {
    return switch (value) {
        .none => .none,
        .bool => |typed| .{ .bool = typed },
        .i32 => |typed| .{ .i32 = typed },
        .usize => |typed| .{ .usize = typed },
        .string => |typed| .{ .string = typed },
    };
}

fn functionLocalCodec(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    local_id: u16,
) ?program_plan.ValueCodec {
    if (compiled_plan.locals.len == 0) return null;
    const index = @as(usize, function.first_local) + local_id;
    if (index >= compiled_plan.locals.len) return null;
    return compiled_plan.locals[index].codec;
}

fn functionLocalRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    local_id: u16,
) ?program_plan.ValueRef {
    if (compiled_plan.locals.len == 0) return null;
    const index = @as(usize, function.first_local) + local_id;
    if (index >= compiled_plan.locals.len) return null;
    const local = compiled_plan.locals[index];
    return .{ .codec = local.codec, .schema_index = local.schema_index };
}

const OperationDispatch = struct {
    value: ExecutableValue,
    resumes: bool,
};

const ExecutionResult = struct {
    value: ExecutableValue,
    terminal: bool,
};

const AfterApplication = struct {
    value: ExecutableValue,
    ref: program_plan.ValueRef,
};

const AfterOutputRefMode = enum {
    inferred,
    exact,
};

const CompletionKind = enum {
    normal,
    terminal,
};

const CompletionValue = struct {
    value: ExecutableValue,
    initial_ref: program_plan.ValueRef,
    after_stack: []const SessionAfterStackEntry,
    kind: CompletionKind,
};

const SessionAfterStackEntry = struct {
    op_index: u16,
    operation_site_index: u16 = 0,
    after_site_index: u16 = 0,
};

const InterpreterFrame = struct {
    locals_start: usize,
    locals_len: usize,
    call_args_start: usize,
    after_start: usize,
};

const OwnedSchemaValue = struct {
    ptr: *anyopaque,
    destroy: *const fn (std.mem.Allocator, *anyopaque) void,
};

fn SchemaDestroyer(comptime T: type) type {
    return struct {
        fn destroy(allocator: std.mem.Allocator, ptr: *anyopaque) void {
            const typed: *T = @ptrCast(@alignCast(ptr));
            allocator.destroy(typed);
        }
    };
}

const InterpreterAfterStorage = enum { embedded, lazy };

fn InterpreterScratch(
    comptime after_stack_capacity: usize,
    comptime after_storage: InterpreterAfterStorage,
) type {
    return struct {
        const AfterStackStorage = if (after_storage == .lazy)
            std.ArrayList(SessionAfterStackEntry)
        else
            [after_stack_capacity]SessionAfterStackEntry;

        allocator: std.mem.Allocator,
        locals: std.ArrayList(ExecutableValue) = .empty,
        call_args: std.ArrayList(ExecutableValue) = .empty,
        owned_schema_values: std.ArrayList(OwnedSchemaValue) = .empty,
        owned_strings: std.ArrayList([]u8) = .empty,
        owned_string_lists: std.ArrayList([][]const u8) = .empty,
        after_stack: AfterStackStorage = if (after_storage == .lazy)
            .empty
        else
            [_]SessionAfterStackEntry{.{ .op_index = 0 }} ** after_stack_capacity,
        after_stack_len: usize = 0,

        const OwnershipCheckpoint = struct {
            schema_values: usize,
            string_lists: usize,
            strings: usize,
        };

        fn init(
            allocator: std.mem.Allocator,
            max_active_local_slots: usize,
            max_active_call_arg_slots: usize,
        ) std.mem.Allocator.Error!@This() {
            var scratch: @This() = .{ .allocator = allocator };
            errdefer scratch.deinit();
            try scratch.locals.ensureTotalCapacity(allocator, max_active_local_slots);
            try scratch.call_args.ensureTotalCapacity(allocator, max_active_call_arg_slots);
            return scratch;
        }

        fn deinit(self: *@This()) void {
            for (self.owned_schema_values.items) |owned| owned.destroy(self.allocator, owned.ptr);
            self.owned_schema_values.deinit(self.allocator);
            for (self.owned_string_lists.items) |owned| self.allocator.free(owned);
            self.owned_string_lists.deinit(self.allocator);
            for (self.owned_strings.items) |owned| self.allocator.free(owned);
            self.owned_strings.deinit(self.allocator);
            if (comptime after_storage == .lazy) self.after_stack.deinit(self.allocator);
            self.call_args.deinit(self.allocator);
            self.locals.deinit(self.allocator);
        }

        fn ownershipCheckpoint(self: *const @This()) OwnershipCheckpoint {
            return .{
                .schema_values = self.owned_schema_values.items.len,
                .string_lists = self.owned_string_lists.items.len,
                .strings = self.owned_strings.items.len,
            };
        }

        fn rollbackOwned(self: *@This(), checkpoint: OwnershipCheckpoint) void {
            std.debug.assert(checkpoint.schema_values <= self.owned_schema_values.items.len);
            std.debug.assert(checkpoint.string_lists <= self.owned_string_lists.items.len);
            std.debug.assert(checkpoint.strings <= self.owned_strings.items.len);

            var schema_index = self.owned_schema_values.items.len;
            while (schema_index > checkpoint.schema_values) {
                schema_index -= 1;
                const owned = self.owned_schema_values.items[schema_index];
                owned.destroy(self.allocator, owned.ptr);
            }
            self.owned_schema_values.shrinkRetainingCapacity(checkpoint.schema_values);

            var list_index = self.owned_string_lists.items.len;
            while (list_index > checkpoint.string_lists) {
                list_index -= 1;
                self.allocator.free(self.owned_string_lists.items[list_index]);
            }
            self.owned_string_lists.shrinkRetainingCapacity(checkpoint.string_lists);

            var string_index = self.owned_strings.items.len;
            while (string_index > checkpoint.strings) {
                string_index -= 1;
                self.allocator.free(self.owned_strings.items[string_index]);
            }
            self.owned_strings.shrinkRetainingCapacity(checkpoint.strings);
        }

        fn storeOwnedString(self: *@This(), value: []const u8) std.mem.Allocator.Error![]const u8 {
            const owned = try self.allocator.dupe(u8, value);
            errdefer self.allocator.free(owned);
            try self.owned_strings.append(self.allocator, owned);
            return owned;
        }

        fn storeOwnedMutableStringList(self: *@This(), value: []const []const u8) std.mem.Allocator.Error![][]const u8 {
            const owned = try self.allocator.alloc([]const u8, value.len);
            errdefer self.allocator.free(owned);
            for (value, 0..) |item, index| {
                owned[index] = try self.storeOwnedString(item);
            }
            try self.owned_string_lists.append(self.allocator, owned);
            return owned;
        }

        fn storeOwnedStringList(self: *@This(), value: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
            return try self.storeOwnedMutableStringList(value);
        }

        fn reserveSchemaValueStorage(self: *@This(), comptime T: type) std.mem.Allocator.Error!*T {
            const typed = try self.allocator.create(T);
            errdefer self.allocator.destroy(typed);
            try self.owned_schema_values.append(self.allocator, .{
                .ptr = typed,
                .destroy = SchemaDestroyer(T).destroy,
            });
            return typed;
        }

        fn storeSchemaValue(self: *@This(), comptime T: type, schema_index: u16, value: T) std.mem.Allocator.Error!ExecutableValue {
            const typed = try self.reserveSchemaValueStorage(T);
            typed.* = value;
            return .{ .schema = .{
                .schema_index = schema_index,
                .ptr = typed,
            } };
        }

        fn pushFrame(self: *@This(), local_count: usize) std.mem.Allocator.Error!InterpreterFrame {
            const frame: InterpreterFrame = .{
                .locals_start = self.locals.items.len,
                .locals_len = local_count,
                .call_args_start = self.call_args.items.len,
                .after_start = self.afterEntries().len,
            };
            try self.locals.resize(self.allocator, frame.locals_start + local_count);
            @memset(self.locals.items[frame.locals_start..][0..local_count], .none);
            return frame;
        }

        fn popFrame(self: *@This(), frame: InterpreterFrame) void {
            if (comptime after_storage == .lazy) {
                self.after_stack.shrinkRetainingCapacity(frame.after_start);
            } else {
                self.after_stack_len = frame.after_start;
            }
            self.call_args.shrinkRetainingCapacity(frame.call_args_start);
            self.locals.shrinkRetainingCapacity(frame.locals_start);
        }

        fn frameLocals(self: *@This(), frame: InterpreterFrame) []ExecutableValue {
            return self.locals.items[frame.locals_start..][0..frame.locals_len];
        }

        fn frameLocalsConst(self: *const @This(), frame: InterpreterFrame) []const ExecutableValue {
            return self.locals.items[frame.locals_start..][0..frame.locals_len];
        }

        fn pushCallArgs(self: *@This(), count: usize) std.mem.Allocator.Error![]ExecutableValue {
            const start = self.call_args.items.len;
            try self.call_args.resize(self.allocator, start + count);
            return self.call_args.items[start..][0..count];
        }

        fn popCallArgs(self: *@This(), args: []const ExecutableValue) void {
            self.call_args.shrinkRetainingCapacity(self.call_args.items.len - args.len);
        }

        fn reserveAfterSlot(self: *@This()) (std.mem.Allocator.Error || error{ExecutionBudgetExceeded})!void {
            const len = self.afterEntries().len;
            if (len >= after_stack_capacity) return error.ExecutionBudgetExceeded;
            if (comptime after_storage == .lazy) {
                const required = len + 1;
                if (self.after_stack.capacity < required) {
                    const doubled = if (self.after_stack.capacity == 0)
                        @min(@as(usize, 8), after_stack_capacity)
                    else
                        @min(self.after_stack.capacity * 2, after_stack_capacity);
                    try self.after_stack.ensureTotalCapacityPrecise(self.allocator, @max(required, doubled));
                }
            }
        }

        fn appendReservedAfter(self: *@This(), entry: SessionAfterStackEntry) void {
            const len = self.afterEntries().len;
            std.debug.assert(len < after_stack_capacity);
            if (comptime after_storage == .lazy) {
                std.debug.assert(len < self.after_stack.capacity);
                self.after_stack.appendAssumeCapacity(entry);
            } else if (comptime after_stack_capacity == 0) {
                unreachable;
            } else {
                self.after_stack[len] = entry;
                self.after_stack_len = len + 1;
            }
        }

        fn frameAfterStack(self: *@This(), frame: InterpreterFrame) []const SessionAfterStackEntry {
            return self.afterEntries()[frame.after_start..];
        }

        fn afterEntries(self: *const @This()) []const SessionAfterStackEntry {
            if (comptime after_storage == .lazy) return self.after_stack.items;
            return self.after_stack[0..self.after_stack_len];
        }

        fn prepareAfterEntries(
            self: *@This(),
            len: usize,
        ) (std.mem.Allocator.Error || error{ExecutionBudgetExceeded})![]SessionAfterStackEntry {
            if (len > after_stack_capacity) return error.ExecutionBudgetExceeded;
            if (comptime after_storage == .lazy) {
                try self.after_stack.ensureTotalCapacityPrecise(self.allocator, len);
                self.after_stack.items.len = len;
                return self.after_stack.items;
            }
            self.after_stack_len = len;
            return self.after_stack[0..len];
        }

        fn copyAfterEntries(
            self: *@This(),
            entries: []const SessionAfterStackEntry,
        ) (std.mem.Allocator.Error || error{ExecutionBudgetExceeded})!void {
            const destination = try self.prepareAfterEntries(entries.len);
            @memcpy(destination, entries);
        }
    };
}

fn consumeInterpreterStep(remaining_steps: *usize) error{ExecutionBudgetExceeded}!void {
    if (remaining_steps.* == 0) return error.ExecutionBudgetExceeded;
    remaining_steps.* -= 1;
}

fn constI32Value(instruction: program_plan.Instruction) error{ProgramContractViolation}!i32 {
    if (instruction.string_literal.len != 0) {
        return std.fmt.parseInt(i32, instruction.string_literal, 0) catch error.ProgramContractViolation;
    }
    return @intCast(instruction.operand);
}

fn mappedReturnError(comptime ErrorSet: type, comptime literal: []const u8) anyerror {
    return switch (@typeInfo(ErrorSet)) {
        .error_set => |errors| blk: {
            if (errors) |decls| {
                inline for (decls) |decl| {
                    if (std.mem.eql(u8, decl.name, literal)) break :blk @field(ErrorSet, decl.name);
                }
            } else {
                break :blk @field(ErrorSet, literal);
            }
            break :blk error.ProgramContractViolation;
        },
        else => @compileError("ProgramPlan return_error mapping requires an error set"),
    };
}

fn mappedReturnErrorForInstruction(
    comptime ErrorSet: type,
    comptime compiled_plan: program_plan.ProgramPlan,
    instruction_index: usize,
) anyerror {
    inline for (compiled_plan.instructions, 0..) |instruction, index| {
        if (instruction_index == index and instruction.kind == .return_error) {
            return mappedReturnError(ErrorSet, instruction.string_literal);
        }
    }
    return error.ProgramContractViolation;
}

fn HandlerSetType(comptime HandlersPtr: type) type {
    return switch (@typeInfo(HandlersPtr)) {
        .pointer => |pointer| pointer.child,
        else => HandlersPtr,
    };
}

fn HandlerFieldPtrType(comptime HandlersPtr: type, comptime field_name: []const u8) type {
    const Field = @FieldType(HandlerSetType(HandlersPtr), field_name);
    return switch (@typeInfo(Field)) {
        .pointer => Field,
        else => switch (@typeInfo(HandlersPtr)) {
            .pointer => |pointer| if (pointer.is_const) *const Field else *Field,
            else => *Field,
        },
    };
}

fn handlerFieldPtr(handlers: anytype, comptime field_name: []const u8) HandlerFieldPtrType(@TypeOf(handlers), field_name) {
    const Field = @FieldType(HandlerSetType(@TypeOf(handlers)), field_name);
    return switch (@typeInfo(Field)) {
        .pointer => switch (@typeInfo(@TypeOf(handlers))) {
            .pointer => @field(handlers.*, field_name),
            else => @field(handlers, field_name),
        },
        else => switch (@typeInfo(@TypeOf(handlers))) {
            .pointer => &@field(handlers.*, field_name),
            else => &@field(handlers, field_name),
        },
    };
}

fn opNameIsUnique(comptime compiled_plan: program_plan.ProgramPlan, comptime op_name: []const u8) bool {
    comptime var count: usize = 0;
    inline for (compiled_plan.ops) |candidate| {
        if (std.mem.eql(u8, candidate.op_name, op_name)) count += 1;
    }
    return count == 1;
}

fn HandlerType(comptime HandlerPtr: type) type {
    return switch (@typeInfo(HandlerPtr)) {
        .pointer => |pointer| pointer.child,
        else => HandlerPtr,
    };
}

fn afterDispatchReceiverMatches(comptime Authored: type, comptime Receiver: type) bool {
    if (Receiver == Authored) return true;
    return switch (@typeInfo(Receiver)) {
        .pointer => |pointer| pointer.size == .one and pointer.child == Authored,
        else => false,
    };
}

fn afterDispatchHasRuntimeShape(comptime AuthoredPtr: type) bool {
    const Authored = HandlerType(AuthoredPtr);
    const after_dispatch_info = @typeInfo(@TypeOf(Authored.afterDispatch)).@"fn";
    if (after_dispatch_info.params.len != 2) return false;
    const receiver = after_dispatch_info.params[0].type;
    return after_dispatch_info.params[1].type != null and
        after_dispatch_info.return_type != null and
        (receiver == null or afterDispatchReceiverMatches(Authored, receiver.?));
}

fn afterDispatchAccepts(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime AuthoredPtr: type,
    comptime input_ref: program_plan.ValueRef,
) bool {
    const Authored = HandlerType(AuthoredPtr);
    if (!afterDispatchHasRuntimeShape(Authored)) return false;
    const after_dispatch_info = @typeInfo(@TypeOf(Authored.afterDispatch)).@"fn";
    const ValueParamType = after_dispatch_info.params[1].type.?;
    return typeMatchesRef(compiled_plan, schema_types, input_ref, ValueParamType);
}

fn dispatchAuthored(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime op: program_plan.OpPlan,
    comptime terminal_ref: program_plan.ValueRef,
    authored: anytype,
    payload: ExecutableValue,
    scratch: anytype,
) anyerror!OperationDispatch {
    const resume_ref: program_plan.ValueRef = comptime .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index };
    const payload_ref: program_plan.ValueRef = .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index };
    return switch (comptime op.mode) {
        .abort => blk: {
            const output = try prepareRuntimeValueForRef(compiled_plan, schema_types, terminal_ref, scratch);
            const dispatched = if (comptime op.payload_codec == .unit)
                try authored.dispatch()
            else
                try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
            break :blk .{
                .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, terminal_ref, output, dispatched),
                .resumes = false,
            };
        },
        .transform => blk: {
            const output = try prepareRuntimeValueForRef(compiled_plan, schema_types, resume_ref, scratch);
            const dispatched = if (comptime op.payload_codec == .unit)
                try authored.dispatch()
            else
                try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
            break :blk .{
                .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, resume_ref, output, dispatched),
                .resumes = true,
            };
        },
        .choice => blk: {
            const resume_output = try prepareRuntimeValueForRef(compiled_plan, schema_types, resume_ref, scratch);
            const terminal_output = try prepareRuntimeValueForRef(compiled_plan, schema_types, terminal_ref, scratch);
            const dispatched = if (comptime op.payload_codec == .unit)
                try authored.dispatch()
            else
                try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
            break :blk switch (dispatched) {
                .resume_with => |resume_value| .{
                    .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, resume_ref, resume_output, resume_value),
                    .resumes = true,
                },
                .return_now => |answer| .{
                    .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, terminal_ref, terminal_output, answer),
                    .resumes = false,
                },
            };
        },
    };
}

fn callOpByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime terminal_ref: program_plan.ValueRef,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    payload: ExecutableValue,
) anyerror!OperationDispatch {
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            const requirement = comptime compiled_plan.requirements[op.requirement_index];
            const HandlerSet = HandlerSetType(@TypeOf(handlers));
            const authored = if (comptime @hasField(HandlerSet, requirement.label) and
                @hasDecl(HandlerType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "dispatch"))
                handlerFieldPtr(handlers, requirement.label)
            else if (comptime @hasField(HandlerSet, requirement.label) and
                @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), op.op_name))
            blk: {
                const requirement_handler = handlerFieldPtr(handlers, requirement.label);
                break :blk handlerFieldPtr(requirement_handler, op.op_name);
            } else if (comptime @hasField(HandlerSet, requirement.label) and
                @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "authored"))
            blk: {
                const requirement_handler = handlerFieldPtr(handlers, requirement.label);
                break :blk handlerFieldPtr(requirement_handler, "authored");
            } else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
                handlerFieldPtr(handlers, op.op_name)
            else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
                handlerFieldPtr(handlers, "authored")
            else if (comptime @hasDecl(HandlerSet, "dispatch"))
                handlers
            else
                @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, direct handler, or authored fallback");
            const result = try dispatchAuthored(compiled_plan, schema_types, op, terminal_ref, authored, payload, scratch);
            if (result.resumes and !valueMatchesRef(.{
                .codec = op.resume_codec,
                .schema_index = op.resume_schema_index,
            }, result.value)) return error.ProgramContractViolation;
            return result;
        }
    }
    return error.ProgramContractViolation;
}

fn callOpByIndexForFunctionIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    payload: ExecutableValue,
) anyerror!OperationDispatch {
    inline for (compiled_plan.functions, 0..) |function, index| {
        if (function_index == index) {
            return callOpByIndex(
                compiled_plan,
                schema_types,
                program_plan.functionResultRef(function),
                handlers,
                scratch,
                op_index,
                payload,
            );
        }
    }
    return error.ProgramContractViolation;
}

fn planCallArgAt(comptime compiled_plan: program_plan.ProgramPlan, index: usize) u16 {
    if (compiled_plan.call_args.len == 0 or index >= compiled_plan.call_args.len) {
        return std.math.maxInt(u16);
    }
    return compiled_plan.call_args[index];
}

fn afterDispatchHandler(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime op: program_plan.OpPlan,
    handlers: anytype,
) @TypeOf(blk: {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(@TypeOf(handlers));
    const authored = if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "dispatch"))
        handlerFieldPtr(handlers, requirement.label)
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), op.op_name))
    op_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :op_field handlerFieldPtr(requirement_handler, op.op_name);
    } else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "authored"))
    authored_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :authored_field handlerFieldPtr(requirement_handler, "authored");
    } else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, op.op_name)
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, "authored")
    else if (comptime @hasDecl(HandlerSet, "dispatch"))
        handlers
    else
        @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, direct handler, or authored fallback");
    break :blk authored;
}) {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(@TypeOf(handlers));
    return if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "dispatch"))
        handlerFieldPtr(handlers, requirement.label)
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), op.op_name))
    op_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :op_field handlerFieldPtr(requirement_handler, op.op_name);
    } else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "authored"))
    authored_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :authored_field handlerFieldPtr(requirement_handler, "authored");
    } else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, op.op_name)
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, "authored")
    else if (comptime @hasDecl(HandlerSet, "dispatch"))
        handlers
    else
        @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, direct handler, or authored fallback");
}

fn AfterDispatchHandlerType(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime op: program_plan.OpPlan,
    comptime HandlersPtr: type,
) type {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(HandlersPtr);
    return if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@FieldType(HandlerSet, requirement.label)), "dispatch"))
        HandlerType(@FieldType(HandlerSet, requirement.label))
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name))
        HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name))
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored"))
        HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored"))
    else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        HandlerType(@FieldType(HandlerSet, op.op_name))
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        HandlerType(@FieldType(HandlerSet, "authored"))
    else if (comptime @hasDecl(HandlerSet, "dispatch"))
        HandlerSet
    else
        @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, direct handler, or authored fallback");
}

fn hasAfterDispatchHandlerType(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime op: program_plan.OpPlan,
    comptime HandlersPtr: type,
) bool {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(HandlersPtr);
    return if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@FieldType(HandlerSet, requirement.label)), "dispatch"))
        @hasDecl(HandlerType(@FieldType(HandlerSet, requirement.label)), "afterDispatch")
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name))
        @hasDecl(HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name)), "afterDispatch")
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored"))
        @hasDecl(HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored")), "afterDispatch")
    else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        @hasDecl(HandlerType(@FieldType(HandlerSet, op.op_name)), "afterDispatch")
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        @hasDecl(HandlerType(@FieldType(HandlerSet, "authored")), "afterDispatch")
    else if (comptime @hasDecl(HandlerSet, "dispatch"))
        @hasDecl(HandlerSet, "afterDispatch")
    else
        false;
}

const SessionAfterHandlerContract = struct {
    has_handler: bool,
    has_runtime_shape: bool,
    input_ref: ?program_plan.ValueRef,
    output_ref: ?program_plan.ValueRef,
};

fn sessionAfterHandlerContractForOp(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    comptime op: program_plan.OpPlan,
) SessionAfterHandlerContract {
    if (!op.has_after) @compileError("Program.Session after handler contract requested for operation without after continuation");
    if (comptime !hasAfterDispatchHandlerType(compiled_plan, op, HandlersType)) {
        return .{
            .has_handler = false,
            .has_runtime_shape = false,
            .input_ref = null,
            .output_ref = null,
        };
    }

    const Authored = AfterDispatchHandlerType(compiled_plan, op, HandlersType);
    if (comptime !afterDispatchHasRuntimeShape(Authored)) {
        return .{
            .has_handler = true,
            .has_runtime_shape = false,
            .input_ref = null,
            .output_ref = null,
        };
    }

    const Input = CallableParamPayloadType(Authored.afterDispatch, 1);
    const Output = CallableReturnPayloadType(Authored.afterDispatch);
    return .{
        .has_handler = true,
        .has_runtime_shape = true,
        .input_ref = runtimeSurfaceValueRefForType(schema_types, Input) orelse
            @compileError("afterDispatch input type is not representable by Program.Session protocol: " ++ @typeName(Input)),
        .output_ref = runtimeSurfaceValueRefForType(schema_types, Output) orelse
            @compileError("afterDispatch output type is not representable by Program.Session protocol: " ++ @typeName(Output)),
    };
}

fn validateStaticMachineAfterHandlerContracts(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    comptime operation_yield_sites: anytype,
) void {
    inline for (operation_yield_sites) |site| {
        if (!site.has_after) continue;
        const op = compiled_plan.ops[site.op_index];
        const contract = sessionAfterHandlerContractForOp(compiled_plan, schema_types, HandlersType, op);
        if (contract.has_handler and !contract.has_runtime_shape) {
            @compileError("Boundary StaticMachine v1 requires afterDispatch to have a receiver, one value parameter, and a return value");
        }
        if (contract.has_handler and
            staticMachineAfterSiteMayBeInnermost(compiled_plan, nested_with_targets, site) and
            !contract.input_ref.?.eql(functionValueRef(compiled_plan.functions[site.function_index])))
        {
            @compileError("Boundary StaticMachine v1 requires every potentially innermost afterDispatch input to match its function value");
        }
        if (contract.has_handler and
            staticMachineAfterSiteMayBeOutermost(compiled_plan, nested_with_targets, site) and
            !contract.output_ref.?.eql(site.result_ref))
        {
            @compileError("Boundary StaticMachine v1 requires every potentially final afterDispatch output to match its function result");
        }
        if (!contract.has_handler and
            staticMachineAfterSiteMayBeNested(compiled_plan, nested_with_targets, operation_yield_sites, site) and
            staticMachineAfterSiteMayBeInnermost(compiled_plan, nested_with_targets, site) and
            !functionValueRef(compiled_plan.functions[site.function_index]).eql(site.result_ref))
        {
            @compileError("Boundary StaticMachine v1 requires every nested handlerless innermost after continuation to receive its function result type");
        }
    }

    outer_sites: inline for (operation_yield_sites) |outer_site| {
        if (!outer_site.has_after) continue :outer_sites;
        const outer_op = compiled_plan.ops[outer_site.op_index];
        const outer_contract = sessionAfterHandlerContractForOp(compiled_plan, schema_types, HandlersType, outer_op);
        inner_sites: inline for (operation_yield_sites) |inner_site| {
            if (!inner_site.has_after or inner_site.function_index != outer_site.function_index) continue :inner_sites;
            if (!staticMachineAfterSitesMayBeAdjacent(
                compiled_plan,
                nested_with_targets,
                outer_site,
                inner_site,
            )) continue :inner_sites;

            const inner_op = compiled_plan.ops[inner_site.op_index];
            const inner_contract = sessionAfterHandlerContractForOp(compiled_plan, schema_types, HandlersType, inner_op);
            const inner_output_ref = inner_contract.output_ref orelse inner_site.result_ref;
            if (outer_contract.has_handler) {
                if (!inner_output_ref.eql(outer_contract.input_ref.?)) {
                    @compileError("Boundary StaticMachine v1 requires every reachable inner after output to match its enclosing afterDispatch input");
                }
            } else if (staticMachineAfterSiteMayBeNested(
                compiled_plan,
                nested_with_targets,
                operation_yield_sites,
                outer_site,
            ) and !inner_output_ref.eql(outer_site.result_ref)) {
                @compileError("Boundary StaticMachine v1 requires every nested handlerless after continuation to receive its function result type");
            }
        }
    }
}

const StaticMachineAfterPathGoal = union(enum) {
    instruction: usize,
    function_return,
};

const StaticConditionPredicate = struct {
    kind: program_plan.InstructionKind,
    operand: u16,
    aux: u16,

    fn eql(self: @This(), other: @This()) bool {
        return self.kind == other.kind and
            self.operand == other.operand and
            self.aux == other.aux;
    }
};

const StaticMachineConditionValue = enum(u2) {
    unknown,
    false_value,
    true_value,
};

fn staticMachineConditionPredicateForInstruction(
    instruction: program_plan.Instruction,
) ?StaticConditionPredicate {
    return switch (instruction.kind) {
        .compare_eq_zero => .{
            .kind = instruction.kind,
            .operand = instruction.operand,
            .aux = 0,
        },
        .sum_variant_is => .{
            .kind = instruction.kind,
            .operand = instruction.operand,
            .aux = instruction.aux,
        },
        else => null,
    };
}

fn staticMachineFunctionConditionPredicateCount(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
) usize {
    if (function_index >= compiled_plan.functions.len) return 0;
    const function = compiled_plan.functions[function_index];
    const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
    var count: usize = 0;
    for (compiled_plan.instructions[function.first_instruction..instruction_end], function.first_instruction..) |instruction, instruction_index| {
        const predicate = staticMachineConditionPredicateForInstruction(instruction) orelse continue;
        var prior_index: usize = function.first_instruction;
        while (prior_index < instruction_index) : (prior_index += 1) {
            if (staticMachineConditionPredicateForInstruction(compiled_plan.instructions[prior_index])) |prior| {
                if (predicate.eql(prior)) break;
            }
        } else {
            count += 1;
        }
    }
    return count;
}

fn staticMachineMaximumConditionPredicateCount(
    comptime compiled_plan: program_plan.ProgramPlan,
) usize {
    var maximum: usize = 0;
    for (0..compiled_plan.functions.len) |function_index| {
        maximum = @max(
            maximum,
            staticMachineFunctionConditionPredicateCount(compiled_plan, function_index),
        );
    }
    return maximum;
}

fn staticMachineConditionPredicateIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    predicate: StaticConditionPredicate,
) ?usize {
    if (function_index >= compiled_plan.functions.len) return null;
    const function = compiled_plan.functions[function_index];
    const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
    var unique_index: usize = 0;
    for (compiled_plan.instructions[function.first_instruction..instruction_end], function.first_instruction..) |instruction, instruction_index| {
        const candidate = staticMachineConditionPredicateForInstruction(instruction) orelse continue;
        var prior_index: usize = function.first_instruction;
        while (prior_index < instruction_index) : (prior_index += 1) {
            if (staticMachineConditionPredicateForInstruction(compiled_plan.instructions[prior_index])) |prior| {
                if (candidate.eql(prior)) break;
            }
        } else {
            if (candidate.eql(predicate)) return unique_index;
            unique_index += 1;
        }
    }
    return null;
}

fn staticMachineConditionPredicateForIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    target_index: usize,
) ?StaticConditionPredicate {
    if (function_index >= compiled_plan.functions.len) return null;
    const function = compiled_plan.functions[function_index];
    const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
    var unique_index: usize = 0;
    for (compiled_plan.instructions[function.first_instruction..instruction_end], function.first_instruction..) |instruction, instruction_index| {
        const candidate = staticMachineConditionPredicateForInstruction(instruction) orelse continue;
        var prior_index: usize = function.first_instruction;
        while (prior_index < instruction_index) : (prior_index += 1) {
            if (staticMachineConditionPredicateForInstruction(compiled_plan.instructions[prior_index])) |prior| {
                if (candidate.eql(prior)) break;
            }
        } else {
            if (unique_index == target_index) return candidate;
            unique_index += 1;
        }
    }
    return null;
}

fn staticMachineConditionPredicateIndexForRuntimeFunction(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    predicate: StaticConditionPredicate,
) ?usize {
    inline for (0..compiled_plan.functions.len) |candidate_function_index| {
        if (function_index == candidate_function_index) {
            return staticMachineConditionPredicateIndex(
                compiled_plan,
                candidate_function_index,
                predicate,
            );
        }
    }
    return null;
}

fn staticMachineConditionPredicateForRuntimeFunctionIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    predicate_index: usize,
) ?StaticConditionPredicate {
    inline for (0..compiled_plan.functions.len) |candidate_function_index| {
        if (function_index == candidate_function_index) {
            return staticMachineConditionPredicateForIndex(
                compiled_plan,
                candidate_function_index,
                predicate_index,
            );
        }
    }
    return null;
}

fn staticMachineFunctionBlockStartNode(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    block_index: usize,
) ?usize {
    if (function_index >= compiled_plan.functions.len or block_index >= compiled_plan.blocks.len) return null;
    const function = compiled_plan.functions[function_index];
    const block_end = @as(usize, function.first_block) + function.block_count;
    if (block_index < function.first_block or block_index >= block_end) return null;
    const block = compiled_plan.blocks[block_index];
    return if (block.instruction_count == 0)
        compiled_plan.instructions.len + block_index
    else
        block.first_instruction;
}

fn staticMachineInstructionMayWriteLocal(
    instruction: program_plan.Instruction,
    local_index: u16,
) bool {
    return switch (instruction.kind) {
        .call_op,
        .call_helper,
        .call_nested_with,
        .add_const_i32,
        .add_i32,
        .sub_one,
        .const_i32,
        .const_string,
        .const_usize,
        .compare_eq_zero,
        .sum_variant_is,
        .sum_extract_payload,
        .product_extract_field,
        => instruction.dst == local_index,
        .return_value, .return_error => false,
    };
}

fn staticMachineFunctionMayWriteLocal(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    local_index: u16,
) bool {
    if (function_index >= compiled_plan.functions.len) return false;
    const function = compiled_plan.functions[function_index];
    const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
    for (compiled_plan.instructions[function.first_instruction..instruction_end]) |instruction| {
        if (staticMachineInstructionMayWriteLocal(instruction, local_index)) return true;
    }
    return false;
}

const PredicateHistoryPhase = enum(u2) {
    before_candidate,
    candidate_seen,
    distinct_seen,
};

fn staticMachineFunctionHasInterleavedPredicateRevisit(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime analysis: anytype,
    comptime function_index: usize,
) bool {
    @setEvalBranchQuota(10_000_000);
    const predicate_count = staticMachineFunctionConditionPredicateCount(
        compiled_plan,
        function_index,
    );
    if (predicate_count < 2) return false;
    const control_node_count = compiled_plan.instructions.len + compiled_plan.blocks.len;
    if (control_node_count == 0 or control_node_count > static_max_control_nodes) return false;
    const state_count = control_node_count * 3;
    const StateIndex = std.math.IntFittingRange(0, state_count - 1);
    const StateVisited = std.StaticBitSet(state_count);
    const function = compiled_plan.functions[function_index];
    const function_block_end = @as(usize, function.first_block) + function.block_count;
    const entry_node = staticMachineFunctionEntryNode(compiled_plan, function_index) orelse
        return false;

    const State = struct {
        node: usize,
        phase: PredicateHistoryPhase,
    };
    const encodeState = struct {
        fn call(state: State) usize {
            return state.node * 3 + @intFromEnum(state.phase);
        }
    }.call;
    const enqueue = struct {
        fn call(
            queue: *[state_count]StateIndex,
            queue_len: *usize,
            visited: *StateVisited,
            state: State,
        ) void {
            const encoded = encodeState(state);
            if (visited.isSet(encoded)) return;
            visited.set(encoded);
            queue[queue_len.*] = @intCast(encoded);
            queue_len.* += 1;
        }
    }.call;

    for (0..predicate_count) |candidate_index| {
        const candidate = staticMachineConditionPredicateForIndex(
            compiled_plan,
            function_index,
            candidate_index,
        ) orelse return true;
        var queue: [state_count]StateIndex = undefined;
        var visited = StateVisited.initEmpty();
        var queue_len: usize = 0;
        var queue_index: usize = 0;
        enqueue(&queue, &queue_len, &visited, .{
            .node = entry_node,
            .phase = .before_candidate,
        });

        predicate_search: while (queue_index < queue_len) : (queue_index += 1) {
            const encoded: usize = @intCast(queue[queue_index]);
            var state = State{
                .node = encoded / 3,
                .phase = @enumFromInt(encoded % 3),
            };
            if (state.node < compiled_plan.instructions.len) {
                var block_index: usize = function.first_block;
                const owner_block = while (block_index < function_block_end) : (block_index += 1) {
                    const block = compiled_plan.blocks[block_index];
                    const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
                    if (state.node >= block.first_instruction and state.node < instruction_end) {
                        break block_index;
                    }
                } else return true;
                const instruction = compiled_plan.instructions[state.node];
                switch (instruction.kind) {
                    .return_error => continue :predicate_search,
                    .call_helper => if (instruction.operand >= compiled_plan.functions.len or
                        !analysis.completion_functions[instruction.operand]) continue :predicate_search,
                    .call_nested_with => {
                        const target_index = nestedWithTargetIndexForMetadata(
                            compiled_plan,
                            nested_with_targets,
                            instruction.string_literal,
                        ) orelse continue :predicate_search;
                        if (!analysis.completion_functions[target_index]) continue :predicate_search;
                    },
                    .call_op => {
                        if (instruction.operand >= compiled_plan.ops.len) return true;
                        if (compiled_plan.ops[instruction.operand].mode == .abort) continue :predicate_search;
                    },
                    else => {},
                }

                if (staticMachineConditionPredicateForInstruction(instruction)) |predicate| {
                    if (predicate.eql(candidate)) {
                        if (state.phase == .distinct_seen) return true;
                        state.phase = .candidate_seen;
                    } else if (state.phase == .candidate_seen) {
                        state.phase = .distinct_seen;
                    }
                }
                if (staticMachineInstructionMayWriteLocal(instruction, candidate.operand)) {
                    state.phase = .before_candidate;
                }

                const block = compiled_plan.blocks[owner_block];
                const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
                state.node = if (state.node + 1 == instruction_end)
                    compiled_plan.instructions.len + owner_block
                else
                    state.node + 1;
                enqueue(&queue, &queue_len, &visited, state);
                continue :predicate_search;
            }

            const block_index = state.node - compiled_plan.instructions.len;
            if (block_index < function.first_block or block_index >= function_block_end) return true;
            const terminator = compiled_plan.terminators[compiled_plan.blocks[block_index].terminator_index];
            const targets = switch (terminator.kind) {
                .branch_if => [2]?u16{ terminator.primary, terminator.secondary },
                .jump => [2]?u16{ terminator.primary, null },
                .return_unit, .return_value => [2]?u16{ null, null },
            };
            target_search: for (targets) |target_optional| {
                const target = target_optional orelse continue :target_search;
                state.node = staticMachineFunctionBlockStartNode(
                    compiled_plan,
                    function_index,
                    target,
                ) orelse return true;
                enqueue(&queue, &queue_len, &visited, state);
            }
        }
    }
    return false;
}

fn validateStaticMachineRepresentableStateAuthority(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime analysis: anytype,
) void {
    for (compiled_plan.functions, 0..) |function, function_index| {
        if (!analysis.reachable_functions[function_index]) continue;
        if (staticMachineFunctionHasInterleavedPredicateRevisit(
            compiled_plan,
            nested_with_targets,
            analysis,
            function_index,
        )) {
            @compileError("Boundary StaticMachine v1 does not support an unchanged condition predicate revisited after a distinct predicate");
        }
        if (function_index == compiled_plan.entry_index) continue;
        for (0..function.parameter_count) |parameter_index| {
            if (staticMachineFunctionMayWriteLocal(
                compiled_plan,
                function_index,
                @intCast(parameter_index),
            )) {
                @compileError("Boundary StaticMachine v1 does not support reachable helper functions that write parameter locals");
            }
        }
    }
}

const StaticAfterConditionGoal = union(enum) {
    instruction: SessionOperationYieldSite,
    function_return,
};

fn staticMachineAfterSiteHasConditionCompatiblePath(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime outer_site: SessionOperationYieldSite,
    comptime goal: StaticAfterConditionGoal,
) bool {
    @setEvalBranchQuota(10_000_000);
    const control_node_count = compiled_plan.instructions.len + compiled_plan.blocks.len;
    if (comptime control_node_count == 0) return false;
    const function_index = outer_site.function_index;
    if (function_index >= compiled_plan.functions.len) return false;
    switch (goal) {
        .instruction => |inner_site| if (function_index != inner_site.function_index) return false,
        .function_return => {},
    }
    const predicate_count = staticMachineFunctionConditionPredicateCount(compiled_plan, function_index);
    if (comptime predicate_count == 0) return true;
    const predicate_slot_count = predicate_count + 1;
    const phase_count = 2;
    const condition_value_count = 3;
    const source_validity_count = 2;
    const state_count = std.math.mul(
        usize,
        control_node_count,
        phase_count * predicate_slot_count * condition_value_count * source_validity_count,
    ) catch @compileError("Boundary StaticMachine v1 after-condition path-state count overflowed");
    if (state_count > static_max_control_work_units) {
        @compileError("Boundary StaticMachine v1 after-condition path analysis exceeds the v1 limit");
    }
    const StateIndex = std.math.IntFittingRange(0, state_count - 1);
    const StateVisited = std.StaticBitSet(state_count);
    const analysis = comptime program_plan.staticEntryExecutionAnalysisWithNestedTargets(
        compiled_plan,
        nested_with_targets,
    ) catch return false;
    const function = compiled_plan.functions[function_index];
    const function_block_end = @as(usize, function.first_block) + function.block_count;
    const entry_node = staticMachineFunctionEntryNode(compiled_plan, function_index) orelse return false;

    const State = struct {
        node: usize,
        after_outer: bool,
        predicate_slot: usize,
        value: StaticMachineConditionValue,
        source_valid: bool,
    };
    const encodeState = struct {
        fn call(state: State) usize {
            var encoded = state.node;
            encoded = encoded * phase_count + @intFromBool(state.after_outer);
            encoded = encoded * predicate_slot_count + state.predicate_slot;
            encoded = encoded * condition_value_count + @intFromEnum(state.value);
            encoded = encoded * source_validity_count + @intFromBool(state.source_valid);
            return encoded;
        }
    }.call;
    const decodeState = struct {
        fn call(encoded_value: usize) State {
            var encoded = encoded_value;
            const source_valid = encoded % source_validity_count != 0;
            encoded /= source_validity_count;
            const value: StaticMachineConditionValue = @enumFromInt(encoded % condition_value_count);
            encoded /= condition_value_count;
            const predicate_slot = encoded % predicate_slot_count;
            encoded /= predicate_slot_count;
            const after_outer = encoded % phase_count != 0;
            encoded /= phase_count;
            return .{
                .node = encoded,
                .after_outer = after_outer,
                .predicate_slot = predicate_slot,
                .value = value,
                .source_valid = source_valid,
            };
        }
    }.call;

    var queue: [state_count]StateIndex = undefined;
    var visited = StateVisited.initEmpty();
    var queue_len: usize = 0;
    var queue_index: usize = 0;
    const enqueue = struct {
        fn call(
            target_queue: *[state_count]StateIndex,
            target_len: *usize,
            target_visited: *StateVisited,
            state: State,
        ) void {
            const encoded = encodeState(state);
            if (target_visited.isSet(encoded)) return;
            target_visited.set(encoded);
            target_queue[target_len.*] = @intCast(encoded);
            target_len.* += 1;
        }
    }.call;
    enqueue(&queue, &queue_len, &visited, .{
        .node = entry_node,
        .after_outer = false,
        .predicate_slot = 0,
        .value = .unknown,
        .source_valid = false,
    });

    while (queue_index < queue_len) : (queue_index += 1) {
        var state = decodeState(@intCast(queue[queue_index]));
        if (!state.after_outer and state.node == outer_site.instruction_index) {
            const next_node = staticMachineNodeAfterSite(compiled_plan, outer_site) orelse return false;
            const outer_instruction = compiled_plan.instructions[outer_site.instruction_index];
            if (state.predicate_slot != 0) {
                const predicate_index = state.predicate_slot - 1;
                const predicate = staticMachineConditionPredicateForIndex(
                    compiled_plan,
                    function_index,
                    predicate_index,
                ) orelse return false;
                if (staticMachineInstructionMayWriteLocal(outer_instruction, predicate.operand)) {
                    state.source_valid = false;
                }
            }
            state.node = next_node;
            state.after_outer = true;
            enqueue(&queue, &queue_len, &visited, state);
            continue;
        }
        if (state.after_outer) switch (goal) {
            .instruction => |inner_site| if (state.node == inner_site.instruction_index) return true,
            .function_return => {},
        };

        if (state.node < compiled_plan.instructions.len) {
            var block_index: usize = function.first_block;
            const owner_block = while (block_index < function_block_end) : (block_index += 1) {
                const candidate = compiled_plan.blocks[block_index];
                const instruction_end = @as(usize, candidate.first_instruction) + candidate.instruction_count;
                if (state.node >= candidate.first_instruction and state.node < instruction_end) break block_index;
            } else return false;
            const instruction = compiled_plan.instructions[state.node];
            switch (instruction.kind) {
                .return_error => continue,
                .call_helper => if (instruction.operand >= compiled_plan.functions.len or
                    !analysis.completion_functions[instruction.operand]) continue,
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(
                        compiled_plan,
                        nested_with_targets,
                        instruction.string_literal,
                    ) orelse continue;
                    if (!analysis.completion_functions[target_index]) continue;
                },
                .call_op => {
                    if (instruction.operand >= compiled_plan.ops.len) return false;
                    const op = compiled_plan.ops[instruction.operand];
                    if (op.mode == .abort or (state.after_outer and op.has_after)) continue;
                },
                else => {},
            }

            if (staticMachineConditionPredicateForInstruction(instruction)) |predicate| {
                const predicate_index = staticMachineConditionPredicateIndex(
                    compiled_plan,
                    function_index,
                    predicate,
                ) orelse return false;
                if (state.predicate_slot != predicate_index + 1 or !state.source_valid) {
                    state.predicate_slot = predicate_index + 1;
                    state.value = .unknown;
                }
                state.source_valid = !staticMachineInstructionMayWriteLocal(
                    instruction,
                    predicate.operand,
                );
            } else if (state.predicate_slot != 0) {
                const predicate = staticMachineConditionPredicateForIndex(
                    compiled_plan,
                    function_index,
                    state.predicate_slot - 1,
                ) orelse return false;
                if (staticMachineInstructionMayWriteLocal(instruction, predicate.operand)) {
                    state.source_valid = false;
                }
            }

            const block = compiled_plan.blocks[owner_block];
            const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
            state.node = if (state.node + 1 == instruction_end)
                compiled_plan.instructions.len + owner_block
            else
                state.node + 1;
            enqueue(&queue, &queue_len, &visited, state);
            continue;
        }

        const block_index = state.node - compiled_plan.instructions.len;
        if (block_index < function.first_block or block_index >= function_block_end) return false;
        const terminator = compiled_plan.terminators[compiled_plan.blocks[block_index].terminator_index];
        switch (terminator.kind) {
            .branch_if => switch (state.value) {
                .false_value, .true_value => {
                    const condition = state.value == .true_value;
                    state.node = staticMachineFunctionBlockStartNode(
                        compiled_plan,
                        function_index,
                        if (condition) terminator.primary else terminator.secondary,
                    ) orelse return false;
                    enqueue(&queue, &queue_len, &visited, state);
                },
                .unknown => {
                    var false_state = state;
                    false_state.value = .false_value;
                    false_state.node = staticMachineFunctionBlockStartNode(
                        compiled_plan,
                        function_index,
                        terminator.secondary,
                    ) orelse return false;
                    enqueue(&queue, &queue_len, &visited, false_state);
                    state.value = .true_value;
                    state.node = staticMachineFunctionBlockStartNode(
                        compiled_plan,
                        function_index,
                        terminator.primary,
                    ) orelse return false;
                    enqueue(&queue, &queue_len, &visited, state);
                },
            },
            .jump => {
                state.node = staticMachineFunctionBlockStartNode(
                    compiled_plan,
                    function_index,
                    terminator.primary,
                ) orelse return false;
                enqueue(&queue, &queue_len, &visited, state);
            },
            .return_unit, .return_value => switch (goal) {
                .instruction => {},
                .function_return => if (state.after_outer) return true,
            },
        }
    }
    return false;
}

fn staticMachineAfterFreePathExists(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime function_index: usize,
    comptime start_node: usize,
    comptime goal: StaticMachineAfterPathGoal,
) bool {
    @setEvalBranchQuota(1_000_000);
    const control_node_count = compiled_plan.instructions.len + compiled_plan.blocks.len;
    if (comptime control_node_count == 0) return false;
    if (function_index >= compiled_plan.functions.len or start_node >= control_node_count) return false;
    const analysis = comptime program_plan.staticEntryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch
        return false;
    const function = compiled_plan.functions[function_index];
    const function_block_end = @as(usize, function.first_block) + function.block_count;

    var queue: [control_node_count]usize = undefined;
    var visited = [_]bool{false} ** control_node_count;
    var queue_len: usize = 1;
    var queue_index: usize = 0;
    queue[0] = start_node;
    visited[start_node] = true;

    while (queue_index < queue_len) : (queue_index += 1) {
        const node = queue[queue_index];
        switch (goal) {
            .instruction => |target| if (node == target) return true,
            .function_return => {},
        }

        if (node < compiled_plan.instructions.len) {
            var block_index: usize = function.first_block;
            const owner_block = while (block_index < function_block_end) : (block_index += 1) {
                const candidate = compiled_plan.blocks[block_index];
                const instruction_end = @as(usize, candidate.first_instruction) + candidate.instruction_count;
                if (node >= candidate.first_instruction and node < instruction_end) break block_index;
            } else return false;
            const instruction = compiled_plan.instructions[node];
            switch (instruction.kind) {
                .return_error => continue,
                .call_helper => {
                    if (instruction.operand >= compiled_plan.functions.len or
                        !analysis.completion_functions[instruction.operand])
                    {
                        continue;
                    }
                },
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(
                        compiled_plan,
                        nested_with_targets,
                        instruction.string_literal,
                    ) orelse continue;
                    if (!analysis.completion_functions[target_index]) continue;
                },
                .call_op => {
                    if (instruction.operand >= compiled_plan.ops.len) return false;
                    const op = compiled_plan.ops[instruction.operand];
                    if (op.mode == .abort or op.has_after) continue;
                },
                else => {},
            }
            const block = compiled_plan.blocks[owner_block];
            const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
            const next_node = if (node + 1 == instruction_end)
                compiled_plan.instructions.len + owner_block
            else
                node + 1;
            if (!visited[next_node]) {
                visited[next_node] = true;
                queue[queue_len] = next_node;
                queue_len += 1;
            }
            continue;
        }

        const block_index = node - compiled_plan.instructions.len;
        if (block_index < function.first_block or block_index >= function_block_end) return false;
        const terminator = compiled_plan.terminators[compiled_plan.blocks[block_index].terminator_index];
        switch (goal) {
            .instruction => {},
            .function_return => if (terminator.kind == .return_unit or terminator.kind == .return_value) {
                return true;
            },
        }
        const targets = switch (terminator.kind) {
            .branch_if => [2]?u16{ terminator.primary, terminator.secondary },
            .jump => [2]?u16{ terminator.primary, null },
            .return_unit, .return_value => [2]?u16{ null, null },
        };
        target_loop: for (targets) |target_optional| {
            const target = target_optional orelse continue :target_loop;
            if (target < function.first_block or target >= function_block_end) return false;
            const target_block = compiled_plan.blocks[target];
            const next_node = if (target_block.instruction_count == 0)
                compiled_plan.instructions.len + target
            else
                target_block.first_instruction;
            if (!visited[next_node]) {
                visited[next_node] = true;
                queue[queue_len] = next_node;
                queue_len += 1;
            }
        }
    }
    return false;
}

fn staticMachineFunctionEntryNode(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
) ?usize {
    if (function_index >= compiled_plan.functions.len) return null;
    const function = compiled_plan.functions[function_index];
    const entry_block_index = @as(usize, function.first_block) + function.entry_block;
    if (entry_block_index >= compiled_plan.blocks.len) return null;
    const entry_block = compiled_plan.blocks[entry_block_index];
    return if (entry_block.instruction_count == 0)
        compiled_plan.instructions.len + entry_block_index
    else
        entry_block.first_instruction;
}

fn staticMachineNodeAfterSite(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime site: SessionOperationYieldSite,
) ?usize {
    if (site.block_index >= compiled_plan.blocks.len or site.instruction_index >= compiled_plan.instructions.len) return null;
    const block = compiled_plan.blocks[site.block_index];
    const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
    if (site.instruction_index < block.first_instruction or site.instruction_index >= instruction_end) return null;
    return if (site.instruction_index + 1 == instruction_end)
        compiled_plan.instructions.len + site.block_index
    else
        site.instruction_index + 1;
}

fn staticMachineAfterSiteMayBeOutermost(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime target_site: SessionOperationYieldSite,
) bool {
    const start_node = staticMachineFunctionEntryNode(compiled_plan, target_site.function_index) orelse return false;
    return staticMachineAfterFreePathExists(
        compiled_plan,
        nested_with_targets,
        target_site.function_index,
        start_node,
        .{ .instruction = target_site.instruction_index },
    );
}

fn staticMachineAfterSiteMayBeInnermost(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime target_site: SessionOperationYieldSite,
) bool {
    const start_node = staticMachineNodeAfterSite(compiled_plan, target_site) orelse return false;
    if (!staticMachineAfterFreePathExists(
        compiled_plan,
        nested_with_targets,
        target_site.function_index,
        start_node,
        .function_return,
    )) return false;
    return staticMachineAfterSiteHasConditionCompatiblePath(
        compiled_plan,
        nested_with_targets,
        target_site,
        .function_return,
    );
}

fn staticMachineAfterSitesMayBeAdjacent(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime outer_site: SessionOperationYieldSite,
    comptime inner_site: SessionOperationYieldSite,
) bool {
    if (outer_site.function_index != inner_site.function_index) return false;
    const start_node = staticMachineNodeAfterSite(compiled_plan, outer_site) orelse return false;
    if (!staticMachineAfterFreePathExists(
        compiled_plan,
        nested_with_targets,
        outer_site.function_index,
        start_node,
        .{ .instruction = inner_site.instruction_index },
    )) return false;
    return staticMachineAfterSiteHasConditionCompatiblePath(
        compiled_plan,
        nested_with_targets,
        outer_site,
        .{ .instruction = inner_site },
    );
}

fn staticMachineAfterSiteMayBeNested(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime operation_yield_sites: anytype,
    comptime target_site: SessionOperationYieldSite,
) bool {
    inline for (operation_yield_sites) |outer_site| {
        if (!outer_site.has_after or outer_site.function_index != target_site.function_index) continue;
        if (staticMachineAfterSitesMayBeAdjacent(compiled_plan, nested_with_targets, outer_site, target_site)) {
            return true;
        }
    }
    return false;
}

/// Static input value ref accepted by the host-visible after site for one operation site.
pub fn sessionAfterProtocolInputRefForOperationSite(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    comptime operation_site: SessionOperationYieldSite,
) ?program_plan.ValueRef {
    const op = compiled_plan.ops[operation_site.op_index];
    if (!op.has_after) @compileError("Program.Session after protocol ref requested for operation without after continuation");
    return sessionAfterHandlerContractForOp(compiled_plan, schema_types, HandlersType, op).input_ref;
}

/// Static output value ref produced by the host-visible after site for one operation site.
pub fn sessionAfterProtocolOutputRefForOperationSite(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    comptime operation_site: SessionOperationYieldSite,
) program_plan.ValueRef {
    const op = compiled_plan.ops[operation_site.op_index];
    if (!op.has_after) @compileError("Program.Session after protocol ref requested for operation without after continuation");
    const contract = sessionAfterHandlerContractForOp(compiled_plan, schema_types, HandlersType, op);
    return contract.output_ref orelse operation_site.result_ref;
}

// zlinter-disable max_positional_args - after dispatch preserves explicit input/output refs while keeping the op, plan, handlers, and scratch state visible.
fn applyAfterByIndexForRefExact(
    comptime input_ref: program_plan.ValueRef,
    comptime output_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
) anyerror!AfterApplication {
    _ = function_index;
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            if (!op.has_after) return error.ProgramContractViolation;
            const authored = afterDispatchHandler(compiled_plan, op, handlers);
            if (comptime !afterDispatchAccepts(compiled_plan, schema_types, @TypeOf(authored), input_ref)) return error.ProgramContractViolation;
            const decoded = try decodeTypedValue(compiled_plan, schema_types, input_ref, value);
            const output = try prepareRuntimeValueForRef(compiled_plan, schema_types, output_ref, scratch);
            const completed = try authored.afterDispatch(decoded);
            return .{
                .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, output_ref, output, completed),
                .ref = output_ref,
            };
        }
    }
    return error.ProgramContractViolation;
}

// zlinter-disable max_positional_args - after dispatch preserves inferred intermediate refs while keeping interpreter state visible.
fn applyAfterByIndexForRefInferred(
    comptime input_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
) anyerror!AfterApplication {
    _ = function_index;
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            if (!op.has_after) return error.ProgramContractViolation;
            const authored = afterDispatchHandler(compiled_plan, op, handlers);
            if (comptime !afterDispatchAccepts(compiled_plan, schema_types, @TypeOf(authored), input_ref)) return error.ProgramContractViolation;
            const decoded = try decodeTypedValue(compiled_plan, schema_types, input_ref, value);
            const Value = CallableReturnPayloadType(HandlerType(@TypeOf(authored)).afterDispatch);
            if (comptime Value == u64) return error.ProgramContractViolation;
            var output = try prepareRuntimeValueForType(schema_types, scratch, Value);
            const completed = try authored.afterDispatch(decoded);
            return .{
                .value = output.value.encode(completed),
                .ref = output.ref,
            };
        }
    }
    return error.ProgramContractViolation;
}

// zlinter-disable max_positional_args - output-ref dispatch mirrors input-ref dispatch without hiding the interpreter state.
fn applyAfterByIndexWithExactOutputRef(
    comptime output_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
    current_ref: program_plan.ValueRef,
) anyerror!AfterApplication {
    return switch (current_ref.codec) {
        .unit => applyAfterByIndexForRefExact(.{ .codec = .unit }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .bool => applyAfterByIndexForRefExact(.{ .codec = .bool }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .i32 => applyAfterByIndexForRefExact(.{ .codec = .i32 }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .usize => applyAfterByIndexForRefExact(.{ .codec = .usize }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string => applyAfterByIndexForRefExact(.{ .codec = .string }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string_list => applyAfterByIndexForRefExact(.{ .codec = .string_list }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .product => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefExact(.{ .codec = .product, .schema_index = @intCast(schema_index) }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
        .sum => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefExact(.{ .codec = .sum, .schema_index = @intCast(schema_index) }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
    };
}

// zlinter-disable max_positional_args - inferred output-ref dispatch mirrors exact output dispatch for intermediate after frames.
fn applyAfterByIndexWithInferredOutputRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
    current_ref: program_plan.ValueRef,
) anyerror!AfterApplication {
    return switch (current_ref.codec) {
        .unit => applyAfterByIndexForRefInferred(.{ .codec = .unit }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .bool => applyAfterByIndexForRefInferred(.{ .codec = .bool }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .i32 => applyAfterByIndexForRefInferred(.{ .codec = .i32 }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .usize => applyAfterByIndexForRefInferred(.{ .codec = .usize }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string => applyAfterByIndexForRefInferred(.{ .codec = .string }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string_list => applyAfterByIndexForRefInferred(.{ .codec = .string_list }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .product => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefInferred(.{ .codec = .product, .schema_index = @intCast(schema_index) }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
        .sum => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefInferred(.{ .codec = .sum, .schema_index = @intCast(schema_index) }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
    };
}

// zlinter-disable max_positional_args - after-stack unwinding needs the current op, next op, and final function result refs together.
fn applyAfterByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
    current_ref: program_plan.ValueRef,
    next_after_op_index: ?u16,
    comptime final_ref: program_plan.ValueRef,
) anyerror!AfterApplication {
    if (next_after_op_index != null) {
        return applyAfterByIndexWithInferredOutputRef(
            compiled_plan,
            schema_types,
            function_index,
            handlers,
            scratch,
            op_index,
            value,
            current_ref,
        );
    }
    return applyAfterByIndexWithExactOutputRef(
        final_ref,
        compiled_plan,
        schema_types,
        function_index,
        handlers,
        scratch,
        op_index,
        value,
        current_ref,
    );
}

fn sessionAfterOutputRefByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    comptime validate_final_input_contract: bool,
    op_index: u16,
    current_ref: program_plan.ValueRef,
    remaining: usize,
    final_ref: program_plan.ValueRef,
) anyerror!program_plan.ValueRef {
    if (remaining == 0) return error.ProgramContractViolation;
    if (!validate_final_input_contract and remaining == 1) return final_ref;
    if (op_index >= compiled_plan.ops.len) return error.ProgramContractViolation;
    const op = compiled_plan.ops[op_index];
    if (!op.has_after) return error.ProgramContractViolation;
    const contracts = comptime blk: {
        var values: [compiled_plan.ops.len]SessionAfterHandlerContract = undefined;
        for (compiled_plan.ops, 0..) |candidate, index| {
            if (candidate.has_after) {
                values[index] = sessionAfterHandlerContractForOp(
                    compiled_plan,
                    schema_types,
                    HandlersType,
                    candidate,
                );
            } else {
                values[index] = .{
                    .has_handler = false,
                    .has_runtime_shape = false,
                    .input_ref = null,
                    .output_ref = null,
                };
            }
        }
        break :blk values;
    };
    const contract = contracts[op_index];
    if (validate_final_input_contract and remaining == 1 and !contract.has_handler) return final_ref;
    if (!contract.has_handler) {
        if (current_ref.eql(final_ref)) return final_ref;
        return error.ProgramContractViolation;
    }
    if (!contract.has_runtime_shape) return error.ProgramContractViolation;
    const expected_input_ref = contract.input_ref orelse return error.ProgramContractViolation;
    if (!current_ref.eql(expected_input_ref)) return error.ProgramContractViolation;
    const output_ref = contract.output_ref orelse return error.ProgramContractViolation;
    if (remaining == 1 and !output_ref.eql(final_ref)) return error.ProgramContractViolation;
    return output_ref;
}

fn completeFunctionValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    const function = comptime compiled_plan.functions[function_index];
    const result_ref = comptime program_plan.functionResultRef(function);
    const value_ref: program_plan.ValueRef = comptime .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    var completed = completion.value;
    var current_ref = completion.initial_ref;
    const final_ref = if (completion.kind == .terminal or completion.after_stack.len != 0) result_ref else value_ref;
    if (completion.kind == .normal) {
        var remaining = completion.after_stack.len;
        while (remaining != 0) {
            remaining -= 1;
            const next_after = if (remaining == 0) null else completion.after_stack[remaining - 1].op_index;
            const after = try applyAfterByIndex(
                compiled_plan,
                schema_types,
                function_index,
                handlers,
                scratch,
                completion.after_stack[remaining].op_index,
                completed,
                current_ref,
                next_after,
                result_ref,
            );
            completed = after.value;
            current_ref = after.ref;
        }
    }
    if (!valueMatchesRef(final_ref, completed)) return error.ProgramContractViolation;
    return completed;
}

// zlinter-disable max_positional_args - interpreter recursion keeps the comptime plan, error set, handler bundle, and call frame explicit.
fn executeKnownFunction(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    comptime function_index: usize,
    args: []const ExecutableValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    if (comptime function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = comptime compiled_plan.functions[function_index];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;

    const frame = try scratch.pushFrame(function.local_count);
    defer scratch.popFrame(frame);
    var locals = scratch.frameLocals(frame);
    if (comptime function.parameter_count != 0) {
        for (args, 0..) |arg, index| {
            const local = compiled_plan.locals[function.first_local + index];
            if (!valueMatchesRef(.{ .codec = local.codec, .schema_index = local.schema_index }, arg)) return error.ProgramContractViolation;
            locals[index] = arg;
        }
    }

    var block_index: usize = @as(usize, function.first_block) + function.entry_block;
    var last_return: ExecutableValue = .none;
    var last_condition: bool = false;
    while (true) {
        locals = scratch.frameLocals(frame);
        try consumeInterpreterStep(remaining_steps);
        const function_block_end = @as(usize, function.first_block) + function.block_count;
        if (block_index < function.first_block or block_index >= function_block_end) return error.ProgramContractViolation;
        const block = compiled_plan.blocks[block_index];
        const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
        for (compiled_plan.instructions[block.first_instruction..instruction_end], block.first_instruction..) |instruction, instruction_index| {
            try consumeInterpreterStep(remaining_steps);
            switch (instruction.kind) {
                .add_const_i32 => {
                    const operand = try decodeArg(.i32, locals[instruction.operand]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, operand, @as(i32, @intCast(instruction.aux))) catch return error.ProgramContractViolation,
                    };
                },
                .add_i32 => {
                    const lhs = try decodeArg(.i32, locals[instruction.operand]);
                    const rhs = try decodeArg(.i32, locals[instruction.aux]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, lhs, rhs) catch return error.ProgramContractViolation,
                    };
                },
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    const call_args = blk: {
                        if (callee.parameter_count == 0) break :blk &[_]ExecutableValue{};
                        if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                        if (comptime compiled_plan.call_args.len == 0) return error.ProgramContractViolation;

                        const buffer = try scratch.pushCallArgs(callee.parameter_count);
                        const arg_start = instruction.aux;
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, arg_start + arg_index);
                            if (local_id >= locals.len) return error.ProgramContractViolation;
                            buffer[arg_index] = locals[local_id];
                        }
                        break :blk buffer[0..callee.parameter_count];
                    };
                    const helper_result = executeFunction(ErrorSet, runtime, compiled_plan, schema_types, handlers, scratch, instruction.operand, call_args, remaining_steps) catch |err| {
                        if (callee.parameter_count != 0) scratch.popCallArgs(call_args);
                        return err;
                    };
                    if (callee.parameter_count != 0) scratch.popCallArgs(call_args);
                    locals = scratch.frameLocals(frame);
                    if (helper_result.terminal) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                schema_types,
                                function_index,
                                handlers,
                                scratch,
                                .{
                                    .value = helper_result.value,
                                    .initial_ref = program_plan.functionResultRef(function),
                                    .after_stack = scratch.frameAfterStack(frame),
                                    .kind = .terminal,
                                },
                            ),
                            .terminal = true,
                        };
                    }
                    if (instruction.dst != std.math.maxInt(u16)) switch (helper_result.value) {
                        .none => {},
                        else => locals[instruction.dst] = helper_result.value,
                    };
                },
                .call_nested_with => return error.ProgramContractViolation,
                .call_op => {
                    if (comptime compiled_plan.ops.len == 0) return error.ProgramContractViolation;
                    if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                    const op = compiled_plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    if (op.has_after) try scratch.reserveAfterSlot();
                    const op_result = try callOpByIndex(
                        compiled_plan,
                        schema_types,
                        program_plan.functionResultRef(function),
                        handlers,
                        scratch,
                        instruction.operand,
                        payload,
                    );
                    if (!op_result.resumes) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                schema_types,
                                function_index,
                                handlers,
                                scratch,
                                .{
                                    .value = op_result.value,
                                    .initial_ref = program_plan.functionResultRef(function),
                                    .after_stack = scratch.frameAfterStack(frame),
                                    .kind = .terminal,
                                },
                            ),
                            .terminal = true,
                        };
                    }
                    if (!valueMatchesRef(.{ .codec = op.resume_codec, .schema_index = op.resume_schema_index }, op_result.value)) return error.ProgramContractViolation;
                    if (op.has_after) scratch.appendReservedAfter(.{ .op_index = instruction.operand });
                    if (op.resume_codec == .unit) {
                        last_return = op_result.value;
                    } else if (instruction.dst != std.math.maxInt(u16)) {
                        locals[instruction.dst] = op_result.value;
                    } else {
                        last_return = op_result.value;
                    }
                },
                .compare_eq_zero => {
                    const is_zero = switch (functionLocalCodec(compiled_plan, function, instruction.operand) orelse return error.ProgramContractViolation) {
                        .bool => !(try decodeArg(.bool, locals[instruction.operand])),
                        .i32 => (try decodeArg(.i32, locals[instruction.operand])) == 0,
                        .usize => (try executableWordU64(locals[instruction.operand])) == 0,
                        else => return error.ProgramContractViolation,
                    };
                    locals[instruction.dst] = .{ .bool = is_zero };
                    last_condition = is_zero;
                },
                .sum_variant_is => {
                    const is_variant = (try activeVariantOrdinalForExecutable(schema_types, locals[instruction.operand])) == instruction.aux;
                    locals[instruction.dst] = .{ .bool = is_variant };
                    last_condition = is_variant;
                },
                .sum_extract_payload => {
                    const dst_ref = functionLocalRef(compiled_plan, function, instruction.dst) orelse return error.ProgramContractViolation;
                    const extracted = try extractVariantPayloadForExecutable(schema_types, dst_ref, scratch, locals[instruction.operand], instruction.aux);
                    if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                    locals[instruction.dst] = extracted.value;
                },
                .product_extract_field => {
                    const dst_ref = functionLocalRef(compiled_plan, function, instruction.dst) orelse return error.ProgramContractViolation;
                    const extracted = try extractProductFieldForExecutable(schema_types, dst_ref, scratch, locals[instruction.operand], instruction.aux);
                    if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                    locals[instruction.dst] = extracted.value;
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = try constI32Value(instruction) },
                .const_string => locals[instruction.dst] = .{ .string = instruction.string_literal },
                .const_usize => {
                    locals[instruction.dst] = .{
                        .word_u64 = std.fmt.parseUnsigned(u64, instruction.string_literal, 0) catch return error.ProgramContractViolation,
                    };
                },
                .return_error => return mappedReturnErrorForInstruction(ErrorSet, compiled_plan, instruction_index),
                .return_value => last_return = locals[instruction.operand],
                .sub_one => {
                    locals[instruction.dst] = switch (functionLocalCodec(compiled_plan, function, instruction.operand) orelse return error.ProgramContractViolation) {
                        .i32 => .{ .i32 = std.math.sub(i32, try decodeArg(.i32, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        .usize => .{ .word_u64 = std.math.sub(u64, try executableWordU64(locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        else => return error.ProgramContractViolation,
                    };
                },
            }
        }
        const terminator = compiled_plan.terminators[block.terminator_index];
        switch (terminator.kind) {
            .branch_if => {
                block_index = if (last_condition) terminator.primary else terminator.secondary;
            },
            .jump => block_index = terminator.primary,
            .return_unit => return .{
                .value = try completeFunctionValue(
                    compiled_plan,
                    schema_types,
                    function_index,
                    handlers,
                    scratch,
                    .{
                        .value = if (function.value_codec == .unit) .none else last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(frame),
                        .kind = .normal,
                    },
                ),
                .terminal = false,
            },
            .return_value => return .{
                .value = try completeFunctionValue(
                    compiled_plan,
                    schema_types,
                    function_index,
                    handlers,
                    scratch,
                    .{
                        .value = last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(frame),
                        .kind = .normal,
                    },
                ),
                .terminal = false,
            },
        }
    }
}

// zlinter-disable max_positional_args - dynamic helper dispatch mirrors executeKnownFunction while selecting the comptime function body.
fn executeFunction(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    function_index: usize,
    args: []const ExecutableValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return executeKnownFunction(ErrorSet, runtime, compiled_plan, schema_types, handlers, scratch, index, args, remaining_steps);
        }
    }
    return error.ProgramContractViolation;
}

const ActiveInterpreterFrame = struct {
    function_index: usize,
    frame: InterpreterFrame,
    block_index: usize,
    instruction_index: usize,
    instruction_end: usize,
    last_return: ExecutableValue = .none,
    last_condition: bool = false,
    waiting_helper_dst: ?u16 = null,
};

const inline_active_frame_capacity = 16;

const ActiveFrameStack = struct {
    inline_buffer: [inline_active_frame_capacity]ActiveInterpreterFrame = undefined,
    heap_frames: std.ArrayList(ActiveInterpreterFrame) = .empty,
    inline_len: usize = 0,

    fn init(
        allocator: std.mem.Allocator,
        initial_capacity: usize,
    ) std.mem.Allocator.Error!@This() {
        var self: @This() = .{};
        errdefer self.deinit(allocator);
        if (initial_capacity > self.inline_buffer.len) try self.heap_frames.ensureTotalCapacity(allocator, initial_capacity);
        return self;
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.heap_frames.deinit(allocator);
    }

    fn usingHeap(self: @This()) bool {
        return self.heap_frames.capacity != 0;
    }

    fn append(self: *@This(), allocator: std.mem.Allocator, frame: ActiveInterpreterFrame) (std.mem.Allocator.Error || error{ExecutionBudgetExceeded})!void {
        if (self.len() == max_interpreter_steps) return error.ExecutionBudgetExceeded;
        if (self.usingHeap()) {
            try self.heap_frames.append(allocator, frame);
            return;
        }
        if (self.inline_len < self.inline_buffer.len) {
            self.inline_buffer[self.inline_len] = frame;
            self.inline_len += 1;
            return;
        }
        try self.heap_frames.ensureTotalCapacity(allocator, self.inline_buffer.len * 2);
        try self.heap_frames.appendSlice(allocator, self.inline_buffer[0..self.inline_len]);
        try self.heap_frames.append(allocator, frame);
        self.inline_len = 0;
    }

    fn pop(self: *@This()) ?ActiveInterpreterFrame {
        if (self.usingHeap()) return self.heap_frames.pop();
        if (self.inline_len == 0) return null;
        self.inline_len -= 1;
        return self.inline_buffer[self.inline_len];
    }

    fn top(self: *@This()) *ActiveInterpreterFrame {
        if (self.usingHeap()) return &self.heap_frames.items[self.heap_frames.items.len - 1];
        return &self.inline_buffer[self.inline_len - 1];
    }

    fn at(self: *const @This(), index: usize) ?ActiveInterpreterFrame {
        if (self.usingHeap()) {
            if (index >= self.heap_frames.items.len) return null;
            return self.heap_frames.items[index];
        }
        if (index >= self.inline_len) return null;
        return self.inline_buffer[index];
    }

    fn len(self: @This()) usize {
        if (self.usingHeap()) return self.heap_frames.items.len;
        return self.inline_len;
    }
};

fn localRefForFunctionIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    local_id: u16,
) ?program_plan.ValueRef {
    if (comptime compiled_plan.locals.len == 0) return null;
    if (function_index >= compiled_plan.functions.len) return null;
    const function = compiled_plan.functions[function_index];
    if (local_id >= function.local_count) return null;
    const local = compiled_plan.locals[function.first_local + local_id];
    return .{ .codec = local.codec, .schema_index = local.schema_index };
}

fn blockInstructionBounds(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    block_index: usize,
) error{ProgramContractViolation}!struct { first: usize, end: usize } {
    if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = compiled_plan.functions[function_index];
    const function_block_end = @as(usize, function.first_block) + function.block_count;
    if (block_index < function.first_block or block_index >= function_block_end) return error.ProgramContractViolation;
    const block = compiled_plan.blocks[block_index];
    const first = @as(usize, block.first_instruction);
    return .{ .first = first, .end = first + block.instruction_count };
}

fn completeFunctionValueByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    function_index: usize,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return completeFunctionValue(compiled_plan, schema_types, index, handlers, scratch, completion);
        }
    }
    return error.ProgramContractViolation;
}

fn nestedWithTargetForMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    metadata: []const u8,
) ?program_plan.FunctionPlan {
    inline for (nested_with_targets) |target| {
        if (std.mem.eql(u8, target.metadata, metadata)) {
            if (target.function_index >= compiled_plan.functions.len) return null;
            return compiled_plan.functions[target.function_index];
        }
    }
    return null;
}

fn nestedWithTargetIndexForMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    metadata: []const u8,
) ?usize {
    inline for (nested_with_targets) |target| {
        if (std.mem.eql(u8, target.metadata, metadata)) {
            if (target.function_index >= compiled_plan.functions.len) return null;
            return target.function_index;
        }
    }
    return null;
}

fn pushActiveInterpreterFrame(
    allocator: std.mem.Allocator,
    comptime compiled_plan: program_plan.ProgramPlan,
    scratch: anytype,
    frames: *ActiveFrameStack,
    function_index: usize,
    args: []const ExecutableValue,
) anyerror!void {
    if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = compiled_plan.functions[function_index];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;

    const frame = try scratch.pushFrame(function.local_count);
    errdefer scratch.popFrame(frame);
    var locals = scratch.frameLocals(frame);
    if (comptime compiled_plan.locals.len == 0) {
        if (args.len != 0) return error.ProgramContractViolation;
    } else {
        for (args, 0..) |arg, index| {
            const local = compiled_plan.locals[function.first_local + index];
            if (!valueMatchesRef(.{ .codec = local.codec, .schema_index = local.schema_index }, arg)) return error.ProgramContractViolation;
            locals[index] = arg;
        }
    }

    const entry_block = @as(usize, function.first_block) + function.entry_block;
    const bounds = try blockInstructionBounds(compiled_plan, function_index, entry_block);
    try frames.append(allocator, .{
        .function_index = function_index,
        .frame = frame,
        .block_index = entry_block,
        .instruction_index = bounds.first,
        .instruction_end = bounds.end,
    });
}

// zlinter-disable max_positional_args - the trampoline keeps runtime execution, plan data, handlers, and frame state explicit.
fn returnFromActiveFrame(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    frames: *ActiveFrameStack,
    initial_returned: ExecutionResult,
) anyerror!?ExecutionResult {
    var returned = initial_returned;
    while (true) {
        if (frames.len() == 0) return error.ProgramContractViolation;
        const completed_frame = frames.pop().?;
        scratch.popFrame(completed_frame.frame);

        if (frames.len() == 0) return returned;
        var parent = frames.top();
        if (returned.terminal) {
            const parent_function = compiled_plan.functions[parent.function_index];
            const completed = try completeFunctionValueByIndex(
                compiled_plan,
                schema_types,
                handlers,
                scratch,
                parent.function_index,
                .{
                    .value = returned.value,
                    .initial_ref = program_plan.functionResultRef(parent_function),
                    .after_stack = scratch.frameAfterStack(parent.frame),
                    .kind = .terminal,
                },
            );
            returned = .{ .value = completed, .terminal = true };
            continue;
        }

        const dst = parent.waiting_helper_dst orelse return error.ProgramContractViolation;
        parent.waiting_helper_dst = null;
        if (dst != std.math.maxInt(u16)) switch (returned.value) {
            .none => {},
            else => scratch.frameLocals(parent.frame)[dst] = returned.value,
        };
        return null;
    }
}

// zlinter-disable max_positional_args - explicit frame-machine executor avoids host recursion for helper calls.
fn executeFunctionWithFrameStack(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    handlers: anytype,
    scratch: anytype,
    function_index: usize,
    args: []const ExecutableValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    _ = runtime;
    const analysis = comptime program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const allocator = scratch.allocator;
    var frames = try ActiveFrameStack.init(allocator, analysis.max_active_frame_depth);
    defer frames.deinit(allocator);
    defer {
        while (frames.len() != 0) {
            const active = frames.pop().?;
            scratch.popFrame(active.frame);
        }
    }

    try pushActiveInterpreterFrame(allocator, compiled_plan, scratch, &frames, function_index, args);
    while (frames.len() != 0) {
        try consumeInterpreterStep(remaining_steps);
        const active = frames.top();
        if (active.waiting_helper_dst != null) return error.ProgramContractViolation;

        if (active.instruction_index < active.instruction_end) {
            if (comptime compiled_plan.instructions.len == 0) return error.ProgramContractViolation;
            const instruction_index = active.instruction_index;
            active.instruction_index += 1;

            const instruction = compiled_plan.instructions[instruction_index];
            const function = compiled_plan.functions[active.function_index];
            var locals = scratch.frameLocals(active.frame);
            switch (instruction.kind) {
                .add_const_i32 => {
                    const operand = try decodeArg(.i32, locals[instruction.operand]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, operand, @as(i32, @intCast(instruction.aux))) catch return error.ProgramContractViolation,
                    };
                },
                .add_i32 => {
                    const lhs = try decodeArg(.i32, locals[instruction.operand]);
                    const rhs = try decodeArg(.i32, locals[instruction.aux]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, lhs, rhs) catch return error.ProgramContractViolation,
                    };
                },
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    const buffer = try scratch.pushCallArgs(callee.parameter_count);
                    var args_popped = false;
                    errdefer if (!args_popped) scratch.popCallArgs(buffer[0..callee.parameter_count]);
                    if (callee.parameter_count != 0) {
                        if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (local_id >= locals.len) return error.ProgramContractViolation;
                            buffer[arg_index] = locals[local_id];
                        }
                    }
                    active.waiting_helper_dst = instruction.dst;
                    try pushActiveInterpreterFrame(
                        allocator,
                        compiled_plan,
                        scratch,
                        &frames,
                        instruction.operand,
                        buffer[0..callee.parameter_count],
                    );
                    frames.top().frame.call_args_start -= callee.parameter_count;
                    scratch.popCallArgs(buffer[0..callee.parameter_count]);
                    args_popped = true;
                },
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse return error.ProgramContractViolation;
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) return error.ProgramContractViolation;
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch return error.ProgramContractViolation;
                    if (result_codec != .unit and instruction.dst == std.math.maxInt(u16)) return error.ProgramContractViolation;
                    active.waiting_helper_dst = instruction.dst;
                    try pushActiveInterpreterFrame(
                        allocator,
                        compiled_plan,
                        scratch,
                        &frames,
                        target_index,
                        &.{},
                    );
                },
                .call_op => {
                    if (comptime compiled_plan.ops.len == 0) return error.ProgramContractViolation;
                    if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                    const op = compiled_plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    if (op.has_after) try scratch.reserveAfterSlot();
                    const op_result = try callOpByIndexForFunctionIndex(
                        compiled_plan,
                        schema_types,
                        active.function_index,
                        handlers,
                        scratch,
                        instruction.operand,
                        payload,
                    );
                    if (!op_result.resumes) {
                        const completed = try completeFunctionValueByIndex(
                            compiled_plan,
                            schema_types,
                            handlers,
                            scratch,
                            active.function_index,
                            .{
                                .value = op_result.value,
                                .initial_ref = program_plan.functionResultRef(function),
                                .after_stack = scratch.frameAfterStack(active.frame),
                                .kind = .terminal,
                            },
                        );
                        if (try returnFromActiveFrame(compiled_plan, schema_types, handlers, scratch, &frames, .{ .value = completed, .terminal = true })) |result| return result;
                    } else {
                        if (!valueMatchesRef(.{ .codec = op.resume_codec, .schema_index = op.resume_schema_index }, op_result.value)) return error.ProgramContractViolation;
                        if (op.has_after) scratch.appendReservedAfter(.{ .op_index = instruction.operand });
                        if (op.resume_codec == .unit) {
                            active.last_return = op_result.value;
                        } else if (instruction.dst != std.math.maxInt(u16)) {
                            locals[instruction.dst] = op_result.value;
                        } else {
                            active.last_return = op_result.value;
                        }
                    }
                },
                .compare_eq_zero => {
                    const operand_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.operand) orelse return error.ProgramContractViolation;
                    const is_zero = switch (operand_ref.codec) {
                        .bool => !(try decodeArg(.bool, locals[instruction.operand])),
                        .i32 => (try decodeArg(.i32, locals[instruction.operand])) == 0,
                        .usize => (try executableWordU64(locals[instruction.operand])) == 0,
                        else => return error.ProgramContractViolation,
                    };
                    locals[instruction.dst] = .{ .bool = is_zero };
                    active.last_condition = is_zero;
                },
                .sum_variant_is => {
                    const is_variant = (try activeVariantOrdinalForExecutable(schema_types, locals[instruction.operand])) == instruction.aux;
                    locals[instruction.dst] = .{ .bool = is_variant };
                    active.last_condition = is_variant;
                },
                .sum_extract_payload => {
                    const dst_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.dst) orelse return error.ProgramContractViolation;
                    const extracted = try extractVariantPayloadForExecutable(schema_types, dst_ref, scratch, locals[instruction.operand], instruction.aux);
                    if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                    locals[instruction.dst] = extracted.value;
                },
                .product_extract_field => {
                    const dst_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.dst) orelse return error.ProgramContractViolation;
                    const extracted = try extractProductFieldForExecutable(schema_types, dst_ref, scratch, locals[instruction.operand], instruction.aux);
                    if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                    locals[instruction.dst] = extracted.value;
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = try constI32Value(instruction) },
                .const_string => locals[instruction.dst] = .{ .string = instruction.string_literal },
                .const_usize => {
                    locals[instruction.dst] = .{
                        .word_u64 = std.fmt.parseUnsigned(u64, instruction.string_literal, 0) catch return error.ProgramContractViolation,
                    };
                },
                .return_error => return mappedReturnErrorForInstruction(ErrorSet, compiled_plan, instruction_index),
                .return_value => active.last_return = locals[instruction.operand],
                .sub_one => {
                    const operand_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.operand) orelse return error.ProgramContractViolation;
                    locals[instruction.dst] = switch (operand_ref.codec) {
                        .i32 => .{ .i32 = std.math.sub(i32, try decodeArg(.i32, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        .usize => .{ .word_u64 = std.math.sub(u64, try executableWordU64(locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        else => return error.ProgramContractViolation,
                    };
                },
            }
            continue;
        }

        const block = compiled_plan.blocks[active.block_index];
        const terminator = compiled_plan.terminators[block.terminator_index];
        const function = compiled_plan.functions[active.function_index];
        switch (terminator.kind) {
            .branch_if => {
                const next_block = if (active.last_condition) terminator.primary else terminator.secondary;
                const bounds = try blockInstructionBounds(compiled_plan, active.function_index, next_block);
                active.block_index = next_block;
                active.instruction_index = bounds.first;
                active.instruction_end = bounds.end;
            },
            .jump => {
                const bounds = try blockInstructionBounds(compiled_plan, active.function_index, terminator.primary);
                active.block_index = terminator.primary;
                active.instruction_index = bounds.first;
                active.instruction_end = bounds.end;
            },
            .return_unit => {
                const completed = try completeFunctionValueByIndex(
                    compiled_plan,
                    schema_types,
                    handlers,
                    scratch,
                    active.function_index,
                    .{
                        .value = if (function.value_codec == .unit) .none else active.last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(active.frame),
                        .kind = .normal,
                    },
                );
                if (try returnFromActiveFrame(compiled_plan, schema_types, handlers, scratch, &frames, .{ .value = completed, .terminal = false })) |result| return result;
            },
            .return_value => {
                const completed = try completeFunctionValueByIndex(
                    compiled_plan,
                    schema_types,
                    handlers,
                    scratch,
                    active.function_index,
                    .{
                        .value = active.last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(active.frame),
                        .kind = .normal,
                    },
                );
                if (try returnFromActiveFrame(compiled_plan, schema_types, handlers, scratch, &frames, .{ .value = completed, .terminal = false })) |result| return result;
            },
        }
    }
    return error.ProgramContractViolation;
}

fn completeSessionFunctionValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    const function = comptime compiled_plan.functions[function_index];
    if (completion.kind == .normal and completion.after_stack.len != 0) return error.ProgramContractViolation;
    const result_ref = comptime program_plan.functionResultRef(function);
    const value_ref: program_plan.ValueRef = comptime .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    const final_ref = if (completion.kind == .terminal or completion.initial_ref.eql(result_ref)) result_ref else value_ref;
    if (!valueMatchesRef(final_ref, completion.value)) return error.ProgramContractViolation;
    return completion.value;
}

fn completeSessionFunctionValueByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return completeSessionFunctionValue(compiled_plan, index, completion);
        }
    }
    return error.ProgramContractViolation;
}

fn returnFromSessionFrame(
    comptime compiled_plan: program_plan.ProgramPlan,
    scratch: anytype,
    frames: *ActiveFrameStack,
    initial_returned: ExecutionResult,
) anyerror!?ExecutionResult {
    var returned = initial_returned;
    while (true) {
        if (frames.len() == 0) return error.ProgramContractViolation;
        const completed_frame = frames.pop().?;
        scratch.popFrame(completed_frame.frame);

        if (frames.len() == 0) return returned;
        var parent = frames.top();
        if (returned.terminal) {
            const parent_function = compiled_plan.functions[parent.function_index];
            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                parent.function_index,
                .{
                    .value = returned.value,
                    .initial_ref = program_plan.functionResultRef(parent_function),
                    .after_stack = scratch.frameAfterStack(parent.frame),
                    .kind = .terminal,
                },
            );
            returned = .{ .value = completed, .terminal = true };
            continue;
        }

        const dst = parent.waiting_helper_dst orelse return error.ProgramContractViolation;
        parent.waiting_helper_dst = null;
        if (dst != std.math.maxInt(u16)) switch (returned.value) {
            .none => {},
            else => scratch.frameLocals(parent.frame)[dst] = returned.value,
        };
        return null;
    }
}

fn validateSessionTerminalPropagation(
    comptime compiled_plan: program_plan.ProgramPlan,
    scratch: anytype,
    frames: *const ActiveFrameStack,
    terminal_value: ExecutableValue,
) anyerror!void {
    const frame_count = frames.len();
    if (frame_count == 0) return error.ProgramContractViolation;

    var returned = terminal_value;
    var index = frame_count - 1;
    while (index > 0) {
        index -= 1;
        const parent = frames.at(index) orelse return error.ProgramContractViolation;
        const parent_function = compiled_plan.functions[parent.function_index];
        returned = try completeSessionFunctionValueByIndex(
            compiled_plan,
            parent.function_index,
            .{
                .value = returned,
                .initial_ref = program_plan.functionResultRef(parent_function),
                .after_stack = scratch.frameAfterStack(parent.frame),
                .kind = .terminal,
            },
        );
    }
}

fn BodySiteMetadata(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "site_metadata")) {
        return struct {
            pub const values = Body.site_metadata;
        };
    }
    return struct {
        pub const values = .{};
    };
}

const static_max_control_work_units: usize = 1 << 20;

fn staticFunctionHasControlCycle(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime analysis: anytype,
    comptime function_index: usize,
) bool {
    @setEvalBranchQuota(1_000_000);
    if (function_index >= compiled_plan.functions.len) return true;
    const function = compiled_plan.functions[function_index];
    if (function.block_count == 0) return false;
    const block_end = @as(usize, function.first_block) + function.block_count;
    var incoming = [_]usize{0} ** function.block_count;
    var reachable_count: usize = 0;

    for (compiled_plan.blocks[function.first_block..block_end], 0..) |block, relative_index| {
        const block_index = @as(usize, function.first_block) + relative_index;
        if (!analysis.reachable_blocks[block_index]) continue;
        reachable_count += 1;
        const terminator = compiled_plan.terminators[block.terminator_index];
        const targets = switch (terminator.kind) {
            .branch_if => [2]?u16{ terminator.primary, terminator.secondary },
            .jump => [2]?u16{ terminator.primary, null },
            .return_unit, .return_value => [2]?u16{ null, null },
        };
        incoming_targets: for (targets) |target_optional| {
            const target = target_optional orelse continue :incoming_targets;
            if (target < function.first_block or target >= block_end) return true;
            if (!analysis.reachable_blocks[target]) continue :incoming_targets;
            incoming[target - function.first_block] += 1;
        }
    }

    var queue: [function.block_count]u16 = undefined;
    var queue_len: usize = 0;
    var queue_index: usize = 0;
    for (incoming, 0..) |count, relative_index| {
        const block_index = @as(usize, function.first_block) + relative_index;
        if (analysis.reachable_blocks[block_index] and count == 0) {
            queue[queue_len] = @intCast(block_index);
            queue_len += 1;
        }
    }

    var visited_count: usize = 0;
    while (queue_index < queue_len) : (queue_index += 1) {
        const block_index = queue[queue_index];
        visited_count += 1;
        const block = compiled_plan.blocks[block_index];
        const terminator = compiled_plan.terminators[block.terminator_index];
        const targets = switch (terminator.kind) {
            .branch_if => [2]?u16{ terminator.primary, terminator.secondary },
            .jump => [2]?u16{ terminator.primary, null },
            .return_unit, .return_value => [2]?u16{ null, null },
        };
        outgoing_targets: for (targets) |target_optional| {
            const target = target_optional orelse continue :outgoing_targets;
            if (!analysis.reachable_blocks[target]) continue :outgoing_targets;
            const relative_target = target - function.first_block;
            if (incoming[relative_target] == 0) return true;
            incoming[relative_target] -= 1;
            if (incoming[relative_target] == 0) {
                queue[queue_len] = target;
                queue_len += 1;
            }
        }
    }
    return visited_count != reachable_count;
}

fn staticAfterStackCapacity(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime analysis: anytype,
) usize {
    if (analysis.reachable_after_count == 0) return 0;
    for (compiled_plan.functions, 0..) |function, function_index| {
        if (!analysis.reachable_functions[function_index]) continue;
        const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
        var has_reachable_after = false;
        reachable_after_instructions: for (compiled_plan.instructions[function.first_instruction..instruction_end], function.first_instruction..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index] or instruction.kind != .call_op) {
                continue :reachable_after_instructions;
            }
            if (instruction.operand >= compiled_plan.ops.len) return max_interpreter_steps;
            if (compiled_plan.ops[instruction.operand].has_after) {
                has_reachable_after = true;
                break;
            }
        }
        if (has_reachable_after and staticFunctionHasControlCycle(
            compiled_plan,
            analysis,
            function_index,
        )) return max_interpreter_steps;
    }
    return @min(analysis.reachable_after_count, max_interpreter_steps);
}

fn staticMachineControlValidationStepBound(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime analysis: anytype,
    comptime control_path_state_capacity: usize,
) ?usize {
    const control_node_count = compiled_plan.instructions.len + compiled_plan.blocks.len;
    const control_node_capacity = if (control_node_count == 0) 1 else control_node_count;
    const after_stack_capacity = staticAfterStackCapacity(compiled_plan, analysis);
    const path_search_count = std.math.add(
        usize,
        after_stack_capacity,
        analysis.max_active_frame_depth,
    ) catch return null;
    const path_work = std.math.mul(
        usize,
        path_search_count,
        control_path_state_capacity,
    ) catch return null;
    const local_work = std.math.mul(
        usize,
        analysis.max_active_local_slots,
        control_node_capacity,
    ) catch return null;
    const reachability_and_local_work = std.math.add(usize, path_work, local_work) catch return null;
    return std.math.add(usize, reachability_and_local_work, after_stack_capacity) catch null;
}

fn staticMachineContractFingerprint(
    comptime program_label: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    comptime operation_yield_sites: anytype,
    comptime maximum_state_bytes: usize,
    comptime control_validation_step_bound: usize,
) u64 {
    @setEvalBranchQuota(1_000_000);
    var hasher = std.hash.Wyhash.init(0);
    sessionSiteHashBytes(&hasher, "boundary.static-machine.contract.v1");
    sessionSiteHashBytes(&hasher, program_label);
    sessionSiteHashU8(&hasher, static_usize_bits);
    sessionSiteHashU64(&hasher, staticPlanFingerprint(compiled_plan));
    sessionSiteHashStaticSchemaCarriers(&hasher, schema_types);
    sessionSiteHashUsize(&hasher, maximum_state_bytes);
    sessionSiteHashUsize(&hasher, nested_with_targets.len);
    inline for (nested_with_targets) |target| {
        sessionSiteHashBytes(&hasher, target.metadata);
        sessionSiteHashU16(&hasher, target.function_index);
    }
    comptime var after_site_count: usize = 0;
    inline for (operation_yield_sites) |site| {
        if (!site.has_after) continue;
        after_site_count += 1;
    }
    sessionSiteHashUsize(&hasher, after_site_count);
    inline for (operation_yield_sites) |site| {
        if (!site.has_after) continue;
        sessionSiteHashUsize(&hasher, site.index);
        sessionSiteHashU64(&hasher, site.canonical_fingerprint);
        const input_ref = sessionAfterProtocolInputRefForOperationSite(
            compiled_plan,
            schema_types,
            HandlersType,
            site,
        );
        sessionSiteHashBool(&hasher, input_ref != null);
        if (input_ref) |ref| sessionSiteHashValueRef(&hasher, ref);
        sessionSiteHashValueRef(
            &hasher,
            sessionAfterProtocolOutputRefForOperationSite(
                compiled_plan,
                schema_types,
                HandlersType,
                site,
            ),
        );
    }
    sessionSiteHashUsize(&hasher, max_interpreter_steps);
    sessionSiteHashUsize(&hasher, static_max_control_work_units);
    sessionSiteHashUsize(&hasher, control_validation_step_bound);
    return hasher.final();
}

const ExecutableRequestIdentity = enum {
    legacy_session,
    canonical_static_machine,
};

const static_max_path_states: usize = 32 * 1024;
const static_max_control_nodes: usize = static_max_path_states / 8;
const StaticMaxPathVisited = std.StaticBitSet(static_max_path_states);
const static_max_path_scratch_bytes =
    static_max_path_states * @sizeOf(u16) +
    @sizeOf(StaticMaxPathVisited);

fn controlPathCapacityForCounts(
    instruction_count: usize,
    block_count: usize,
    predicate_count: usize,
) ?usize {
    const node_count = std.math.add(
        usize,
        instruction_count,
        block_count,
    ) catch return null;
    const node_capacity = if (node_count == 0) 1 else node_count;
    const predicate_slot_count = std.math.add(
        usize,
        predicate_count,
        1,
    ) catch return null;
    const condition_authority_count = std.math.mul(
        usize,
        predicate_slot_count,
        4,
    ) catch return null;
    const state_capacity = std.math.mul(
        usize,
        node_capacity,
        std.math.mul(usize, condition_authority_count, 2) catch return null,
    ) catch return null;
    if (state_capacity > static_max_path_states) return null;
    return state_capacity;
}

fn staticMachineControlPathStateCapacity(
    comptime compiled_plan: program_plan.ProgramPlan,
) ?usize {
    return controlPathCapacityForCounts(
        compiled_plan.instructions.len,
        compiled_plan.blocks.len,
        staticMachineMaximumConditionPredicateCount(compiled_plan),
    );
}

pub fn ExecutableSessionForPlan(
    comptime ErrorSet: type,
    comptime program_label: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    comptime HandlersType: type,
    comptime ProtocolOwner: type,
) type {
    const site_metadata = BodySiteMetadata(ProtocolOwner).values;
    const operation_yield_sites = sessionOperationYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    const after_yield_sites = sessionAfterYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    return ExecutableSessionForPlanWithSelectedIdentity(
        ErrorSet,
        program_label,
        compiled_plan,
        schema_types,
        nested_with_targets,
        HandlersType,
        ProtocolOwner,
        .legacy_session,
        operation_yield_sites,
        after_yield_sites,
        0,
        0,
        0,
        0,
    );
}

pub fn StaticExecutableSessionForPlan(
    comptime ErrorSet: type,
    comptime program_label: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    comptime HandlersType: type,
    comptime ProtocolOwner: type,
    comptime maximum_state_bytes: usize,
) type {
    const analysis = program_plan.staticEntryExecutionAnalysisWithNestedTargets(
        compiled_plan,
        nested_with_targets,
    ) catch |err| @compileError("Boundary StaticMachine v1 failed execution analysis: " ++ @errorName(err));
    if (analysis.helper_cycle) {
        @compileError("Boundary StaticMachine v1 rejects recursive helper and nested-provider frame graphs");
    }
    comptime validateStaticMachineRepresentableStateAuthority(
        compiled_plan,
        nested_with_targets,
        analysis,
    );
    comptime validateTypedExecutablePlanSupportWithIdentity(
        compiled_plan,
        schema_types,
        nested_with_targets,
        .static_machine_v1,
    ) catch |err| @compileError(
        "Boundary StaticMachine v1 failed executable support validation: " ++ @errorName(err),
    );
    comptime validateSessionPlanSupportWithNestedTargets(
        compiled_plan,
        nested_with_targets,
    ) catch |err| @compileError(
        "Boundary StaticMachine v1 failed session support validation: " ++ @errorName(err),
    );
    const site_metadata = BodySiteMetadata(ProtocolOwner).values;
    const operation_yield_sites = staticMachineOperationYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    comptime validateStaticMachineAfterHandlerContracts(
        compiled_plan,
        nested_with_targets,
        schema_types,
        HandlersType,
        operation_yield_sites,
    );
    const after_yield_sites = staticMachineAfterYieldSitesForPlanWithMetadata(compiled_plan, nested_with_targets, site_metadata);
    const control_path_state_capacity = staticMachineControlPathStateCapacity(compiled_plan) orelse
        @compileError("Boundary StaticMachine v1 control-path state space exceeds the v1 limit");
    const control_validation_step_bound = staticMachineControlValidationStepBound(
        compiled_plan,
        analysis,
        control_path_state_capacity,
    ) orelse @compileError("Boundary StaticMachine v1 control-validation work bound overflowed");
    if (control_validation_step_bound > static_max_control_work_units) {
        @compileError("Boundary StaticMachine v1 control-validation work exceeds the v1 limit");
    }
    const canonical_plan_identity = staticPlanFingerprint(compiled_plan);
    const static_contract_identity = staticMachineContractFingerprint(
        program_label,
        compiled_plan,
        nested_with_targets,
        schema_types,
        HandlersType,
        operation_yield_sites,
        maximum_state_bytes,
        control_validation_step_bound,
    );
    return ExecutableSessionForPlanWithSelectedIdentity(
        ErrorSet,
        program_label,
        compiled_plan,
        schema_types,
        nested_with_targets,
        HandlersType,
        ProtocolOwner,
        .canonical_static_machine,
        operation_yield_sites,
        after_yield_sites,
        canonical_plan_identity,
        static_contract_identity,
        control_path_state_capacity,
        control_validation_step_bound,
    );
}

fn ExecutableSessionForPlanWithSelectedIdentity(
    comptime ErrorSet: type,
    comptime program_label: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    comptime HandlersType: type,
    comptime ProtocolOwner: type,
    comptime request_identity: ExecutableRequestIdentity,
    comptime operation_yield_sites: anytype,
    comptime after_yield_sites: anytype,
    comptime canonical_plan_identity: u64,
    comptime static_contract_identity: u64,
    comptime static_control_path_state_capacity: usize,
    comptime static_control_validation_step_bound: usize,
) type {
    const entry = compiled_plan.functions[compiled_plan.entry_index];
    const canonical_request_identity = request_identity == .canonical_static_machine;
    const analysis = yieldSiteEntryAnalysis(
        compiled_plan,
        nested_with_targets,
        if (canonical_request_identity) .static_machine_v1 else .legacy_session,
    );
    const ResultValue = ValueTypeForRef(compiled_plan, schema_types, program_plan.functionResultRef(entry));
    const session_after_stack_capacity = if (analysis.reachable_after_count == 0) 0 else max_interpreter_steps;
    const Scratch = InterpreterScratch(
        session_after_stack_capacity,
        if (canonical_request_identity) .lazy else .embedded,
    );
    const plan_hash = if (canonical_request_identity)
        canonical_plan_identity
    else
        compiled_plan.hash();

    if (canonical_request_identity) comptime {
        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index] or instruction.kind != .const_usize) continue;
            const value = std.fmt.parseUnsigned(u64, instruction.string_literal, 0) catch
                @compileError("Boundary StaticMachine const_usize literal is not a valid u64");
            if (value > static_usize_max) {
                @compileError("Boundary StaticMachine v1 requires const_usize values to fit the canonical u32 domain");
            }
        }
    };

    return struct {
        const Self = @This();
        const request_payload_storage_size = maxSchemaValueSize(schema_types);
        const request_payload_storage_align = maxSchemaValueAlign(schema_types);

        /// Owned storage that keeps detached session result values alive after the session core closes.
        pub const ResultStorage = struct {
            scratch: Scratch,

            /// Release detached session result storage.
            pub fn deinit(self: *@This()) void {
                self.scratch.deinit();
            }
        };

        /// Terminal session result plus any storage needed by borrowed scalar or schema fields.
        const DetachedResult = struct {
            value: ResultValue,
            _storage: ?ResultStorage = null,

            /// Release storage still attached to this raw result.
            pub fn deinit(self: *@This()) void {
                if (self._storage) |*storage| storage.deinit();
                self._storage = null;
            }

            /// Move attached storage out so Program.Result can own it.
            pub fn takeStorage(self: *@This()) ?ResultStorage {
                const storage = self._storage;
                self._storage = null;
                return storage;
            }
        };

        const OpaqueResultOwner = struct {
            allocator: std.mem.Allocator,
            detached: DetachedResult,
        };

        /// Opaque terminal result owner used by the StaticMachine backend.
        pub const OpaqueResult = opaque {
            /// Borrow the typed terminal value from this owner.
            pub fn value(self: *const @This()) ResultValue {
                return Self.opaqueResultOwnerConst(self).detached.value;
            }

            /// Release this terminal result and its backing storage.
            pub fn deinit(self: *@This()) void {
                const owner = Self.opaqueResultOwner(self);
                owner.detached.deinit();
                const allocator = owner.allocator;
                allocator.destroy(owner);
            }
        };

        /// Backend-selected terminal result representation.
        pub const RawResult = if (canonical_request_identity) *OpaqueResult else DetachedResult;

        fn opaqueResultOwner(result: *OpaqueResult) *OpaqueResultOwner {
            return @ptrCast(@alignCast(result));
        }

        fn opaqueResultOwnerConst(result: *const OpaqueResult) *const OpaqueResultOwner {
            return @ptrCast(@alignCast(result));
        }

        const PendingRequest = struct {
            session_id: usize,
            token: u64,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            dst: u16,
            op_index: u16,
            operation_site_index: usize,
            operation_site_fingerprint: u64,
            turn_index: usize,
            payload_ref: program_plan.ValueRef,
            payload_local_id: u16,
            payload: ExecutableValue,
            payload_value_fingerprint: u64,
            request_fingerprint: u64,
            mode: program_plan.ControlMode,
            resume_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            has_after: bool,
            after_stack_entry: SessionAfterStackEntry,
        };

        const PendingAfter = struct {
            session_id: usize,
            token: u64,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            op_index: u16,
            after_site_index: usize,
            after_site_fingerprint: u64,
            source_operation_site_index: usize,
            source_operation_site_fingerprint: u64,
            turn_index: usize,
            value: ExecutableValue,
            value_fingerprint: u64,
            request_fingerprint: u64,
            value_ref: program_plan.ValueRef,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            remaining: usize,
        };

        const Pending = union(enum) {
            after: PendingAfter,
            op: PendingRequest,
        };

        const AfterUnwind = struct {
            function_index: usize,
            value: ExecutableValue,
            current_ref: program_plan.ValueRef,
            final_ref: program_plan.ValueRef,
            remaining: usize,
        };

        const RequestPayload = union(enum) {
            none,
            bool: bool,
            i32: i32,
            usize: usize,
            word_u64: u64,
            string: []const u8,
            string_list: []const []const u8,
            schema_index: u16,
        };

        // zlinter-disable declaration_naming - Program.Session.Trace is the documented host-facing trace namespace.
        pub const Trace = struct {
            pub const fingerprint_version = trace_fingerprint_version;

            pub const RequestKind = enum {
                after,
                operation,
            };

            pub const ResponseKind = enum {
                @"resume",
                return_now,
                resume_after,
            };

            pub const FingerprintError = error{
                TraceFingerprintMismatch,
            };

            pub const OperationRequest = struct {
                fingerprint_version: u32 = trace_fingerprint_version,
                program_label: []const u8,
                plan_label: []const u8,
                plan_hash: u64,
                turn_index: usize,
                kind: RequestKind = .operation,
                operation_site_index: usize,
                operation_site_fingerprint: u64,
                semantic_label: ?[]const u8 = null,
                function_index: usize,
                block_index: usize,
                instruction_index: usize,
                requirement_index: u16,
                requirement_label: []const u8,
                op_index: u16,
                op_name: []const u8,
                mode: program_plan.ControlMode,
                payload_ref: program_plan.ValueRef,
                has_payload: bool,
                payload_value_fingerprint: u64,
                resume_ref: program_plan.ValueRef,
                result_ref: program_plan.ValueRef,
                has_after: bool,
                fingerprint: u64,

                pub fn eql(self: @This(), expected: u64) bool {
                    return self.fingerprint == expected;
                }
            };

            pub const AfterRequest = struct {
                fingerprint_version: u32 = trace_fingerprint_version,
                program_label: []const u8,
                plan_label: []const u8,
                plan_hash: u64,
                turn_index: usize,
                kind: RequestKind = .after,
                after_site_index: usize,
                after_site_fingerprint: u64,
                semantic_label: ?[]const u8 = null,
                source_operation_site_index: usize,
                source_operation_site_fingerprint: u64,
                function_index: usize,
                block_index: usize,
                instruction_index: usize,
                original_requirement_index: u16,
                original_requirement_label: []const u8,
                original_op_index: u16,
                original_op_name: []const u8,
                current_value_ref: program_plan.ValueRef,
                current_value_fingerprint: u64,
                expected_output_ref: program_plan.ValueRef,
                result_ref: program_plan.ValueRef,
                fingerprint: u64,

                pub fn eql(self: @This(), expected: u64) bool {
                    return self.fingerprint == expected;
                }
            };

            pub const Response = struct {
                fingerprint_version: u32 = trace_fingerprint_version,
                request_fingerprint: u64,
                kind: ResponseKind,
                response_ref: program_plan.ValueRef,
                response_value_fingerprint: u64,
                fingerprint: u64,
            };
        };
        // zlinter-enable declaration_naming

        allocator: std.mem.Allocator,
        scratch: Scratch,
        frames: ActiveFrameStack,
        session_id: usize,
        remaining_steps: usize = max_interpreter_steps,
        next_token: u64 = 1,
        next_turn_index: usize = 0,
        pending: ?Pending = null,
        unwinding_after: ?AfterUnwind = null,
        terminal_failure_instruction_index: ?usize = null,
        terminal_runtime_failure: ?anyerror = null,
        completed: ?ExecutionResult = null,
        done_consumed: bool = false,

        pub const Request = struct {
            _session_id: usize,
            token: u64,
            operation_site_index: usize,
            operation_site_fingerprint: u64,
            canonical_operation_site_fingerprint: u64 = 0,
            semantic_label: ?[]const u8 = null,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            mode: program_plan.ControlMode,
            payload_ref: program_plan.ValueRef,
            has_payload: bool,
            resume_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            has_after: bool,
            _payload: RequestPayload,
            _payload_storage: [request_payload_storage_size]u8 align(request_payload_storage_align) = undefined,
            _turn_index: usize,
            _payload_value_fingerprint: u64,
            _fingerprint: u64,
            _plan_fingerprint: u64 = 0,

            pub fn payload(self: @This(), comptime T: type) error{ProgramContractViolation}!T {
                if (!typeMatchesRuntimeRef(schema_types, self.payload_ref, T)) return error.ProgramContractViolation;
                if (T == void) return switch (self._payload) {
                    .none => {},
                    else => error.ProgramContractViolation,
                };
                if (T == bool) return switch (self._payload) {
                    .bool => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == i32) return switch (self._payload) {
                    .i32 => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == usize) return switch (self._payload) {
                    .usize => |typed| typed,
                    .word_u64 => |typed| if (typed <= std.math.maxInt(usize)) @intCast(typed) else error.ProgramContractViolation,
                    else => error.ProgramContractViolation,
                };
                if (T == u64) return switch (self._payload) {
                    .usize => |typed| @intCast(typed),
                    .word_u64 => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const u8) return switch (self._payload) {
                    .string => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const []const u8) return switch (self._payload) {
                    .string_list => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == [][]const u8) return error.ProgramContractViolation;

                const schema_index = self.payload_ref.schema_index orelse return error.ProgramContractViolation;
                const expected_codec: program_plan.ValueCodec = comptime switch (@typeInfo(T)) {
                    .@"struct" => .product,
                    .@"enum", .@"union", .optional => .sum,
                    else => return error.ProgramContractViolation,
                };
                if (self.payload_ref.codec != expected_codec) return error.ProgramContractViolation;
                return switch (self._payload) {
                    .schema_index => |actual_index| blk: {
                        if (actual_index != schema_index) return error.ProgramContractViolation;
                        const typed: *const T = @ptrCast(@alignCast(&self._payload_storage));
                        break :blk typed.*;
                    },
                    else => error.ProgramContractViolation,
                };
            }

            pub fn matches(self: @This(), comptime Site: type) bool {
                comptime requireOperationProtocolSite(Site);
                const expected_fingerprint = if (canonical_request_identity)
                    Site.canonical_fingerprint
                else
                    Site.fingerprint;
                return self.operation_site_index == Site.index and
                    self.operation_site_fingerprint == expected_fingerprint and
                    self.canonical_operation_site_fingerprint == Site.canonical_fingerprint and
                    self.payload_ref.eql(Site.payload_ref) and
                    self.resume_ref.eql(Site.resume_ref) and
                    self.result_ref.eql(Site.result_ref);
            }

            pub fn expectSite(self: @This(), comptime Site: type) error{ProgramContractViolation}!void {
                if (!self.matches(Site)) return error.ProgramContractViolation;
            }

            pub fn as(self: @This(), comptime Site: type) error{ProgramContractViolation}!TypedOperationRequest(@This(), Site) {
                try self.expectSite(Site);
                return .{ .request = self };
            }

            pub fn trace(self: @This()) Trace.OperationRequest {
                return .{
                    .program_label = program_label,
                    .plan_label = compiled_plan.label,
                    .plan_hash = self._plan_fingerprint,
                    .turn_index = self._turn_index,
                    .operation_site_index = self.operation_site_index,
                    .operation_site_fingerprint = self.operation_site_fingerprint,
                    .semantic_label = self.semantic_label,
                    .function_index = self.function_index,
                    .block_index = self.block_index,
                    .instruction_index = self.instruction_index,
                    .requirement_index = self.requirement_index,
                    .requirement_label = self.requirement_label,
                    .op_index = self.op_index,
                    .op_name = self.op_name,
                    .mode = self.mode,
                    .payload_ref = self.payload_ref,
                    .has_payload = self.has_payload,
                    .payload_value_fingerprint = self._payload_value_fingerprint,
                    .resume_ref = self.resume_ref,
                    .result_ref = self.result_ref,
                    .has_after = self.has_after,
                    .fingerprint = self._fingerprint,
                };
            }

            pub fn fingerprint(self: @This()) u64 {
                return self._fingerprint;
            }

            pub fn expectFingerprint(self: @This(), expected: u64) Trace.FingerprintError!void {
                if (self._fingerprint != expected) return error.TraceFingerprintMismatch;
            }

            pub fn responseTrace(self: @This(), kind: Trace.ResponseKind, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                const response_ref = switch (kind) {
                    .@"resume" => blk: {
                        if (self.mode == .abort) return error.ProgramContractViolation;
                        break :blk self.resume_ref;
                    },
                    .return_now => blk: {
                        if (self.mode == .transform) return error.ProgramContractViolation;
                        break :blk self.result_ref;
                    },
                    .resume_after => return error.ProgramContractViolation,
                };
                const value_fingerprint = try Self.fingerprintTypedValueForRef(response_ref, response_value);
                return Self.responseTraceFor(self._fingerprint, kind, response_ref, value_fingerprint);
            }

            pub fn responseTraceFor(self: @This(), comptime Site: type, kind: Trace.ResponseKind, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                try self.expectSite(Site);
                switch (kind) {
                    .@"resume" => if (!Site.may_resume) return error.ProgramContractViolation,
                    .return_now => if (!Site.may_return_now) return error.ProgramContractViolation,
                    .resume_after => return error.ProgramContractViolation,
                }
                return self.responseTrace(kind, response_value);
            }

            fn setPayload(self: *@This(), payload_value: ExecutableValue) error{ProgramContractViolation}!void {
                self._payload = switch (payload_value) {
                    .none => .none,
                    .bool => |typed| .{ .bool = typed },
                    .i32 => |typed| .{ .i32 = typed },
                    .usize => |typed| .{ .usize = typed },
                    .word_u64 => |typed| .{ .word_u64 = typed },
                    .string => |typed| .{ .string = typed },
                    .string_list => |typed| .{ .string_list = typed },
                    .schema => |schema| try self.storeStructuredPayload(schema),
                };
            }

            fn storeStructuredPayload(self: *@This(), schema: SchemaValue) error{ProgramContractViolation}!RequestPayload {
                inline for (schema_types, 0..) |SchemaType, schema_index| {
                    if (schema.schema_index == @as(u16, @intCast(schema_index))) {
                        const source: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                        const destination: *SchemaType = @ptrCast(@alignCast(&self._payload_storage));
                        destination.* = source.*;
                        return .{ .schema_index = schema.schema_index };
                    }
                }
                return error.ProgramContractViolation;
            }
        };

        pub const AfterRequest = struct {
            _session_id: usize,
            token: u64,
            after_site_index: usize,
            after_site_fingerprint: u64,
            canonical_after_site_fingerprint: u64 = 0,
            semantic_label: ?[]const u8 = null,
            source_operation_site_index: usize,
            source_operation_site_fingerprint: u64,
            source_operation_site_canonical_fingerprint: u64 = 0,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            value_ref: program_plan.ValueRef,
            has_value: bool,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            _remaining: usize,
            _value: RequestPayload,
            _value_storage: [request_payload_storage_size]u8 align(request_payload_storage_align) = undefined,
            _turn_index: usize,
            _value_fingerprint: u64,
            _fingerprint: u64,
            _plan_fingerprint: u64 = 0,

            pub fn value(self: @This(), comptime T: type) error{ProgramContractViolation}!T {
                if (!typeMatchesRuntimeRef(schema_types, self.value_ref, T)) return error.ProgramContractViolation;
                if (T == void) return switch (self._value) {
                    .none => {},
                    else => error.ProgramContractViolation,
                };
                if (T == bool) return switch (self._value) {
                    .bool => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == i32) return switch (self._value) {
                    .i32 => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == usize) return switch (self._value) {
                    .usize => |typed| typed,
                    .word_u64 => |typed| if (typed <= std.math.maxInt(usize)) @intCast(typed) else error.ProgramContractViolation,
                    else => error.ProgramContractViolation,
                };
                if (T == u64) return switch (self._value) {
                    .usize => |typed| @intCast(typed),
                    .word_u64 => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const u8) return switch (self._value) {
                    .string => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const []const u8) return switch (self._value) {
                    .string_list => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == [][]const u8) return error.ProgramContractViolation;

                const schema_index = self.value_ref.schema_index orelse return error.ProgramContractViolation;
                const expected_codec: program_plan.ValueCodec = comptime switch (@typeInfo(T)) {
                    .@"struct" => .product,
                    .@"enum", .@"union", .optional => .sum,
                    else => return error.ProgramContractViolation,
                };
                if (self.value_ref.codec != expected_codec) return error.ProgramContractViolation;
                return switch (self._value) {
                    .schema_index => |actual_index| blk: {
                        if (actual_index != schema_index) return error.ProgramContractViolation;
                        const typed: *const T = @ptrCast(@alignCast(&self._value_storage));
                        break :blk typed.*;
                    },
                    else => error.ProgramContractViolation,
                };
            }

            pub fn matches(self: @This(), comptime Site: type) bool {
                comptime requireAfterProtocolSite(Site);
                const input_matches = if (comptime Site.has_static_input_ref) self.value_ref.eql(Site.input_ref.?) else true;
                const output_matches = if (canonical_request_identity) self.output_ref.eql(Site.output_ref) else true;
                const expected_after_fingerprint = if (canonical_request_identity)
                    Site.canonical_fingerprint
                else
                    Site.fingerprint;
                const expected_source_fingerprint = if (canonical_request_identity)
                    Site.source_operation_site_canonical_fingerprint
                else
                    Site.source_operation_site_fingerprint;
                return self.after_site_index == Site.index and
                    self.after_site_fingerprint == expected_after_fingerprint and
                    self.canonical_after_site_fingerprint == Site.canonical_fingerprint and
                    self.source_operation_site_index == Site.source_operation_site_index and
                    self.source_operation_site_fingerprint == expected_source_fingerprint and
                    self.source_operation_site_canonical_fingerprint == Site.source_operation_site_canonical_fingerprint and
                    input_matches and
                    output_matches and
                    self.result_ref.eql(Site.result_ref);
            }

            pub fn expectSite(self: @This(), comptime Site: type) error{ProgramContractViolation}!void {
                if (!self.matches(Site)) return error.ProgramContractViolation;
            }

            pub fn as(self: @This(), comptime Site: type) error{ProgramContractViolation}!TypedAfterRequest(@This(), Site) {
                try self.expectSite(Site);
                return .{ .request = self };
            }

            pub fn trace(self: @This()) Trace.AfterRequest {
                return .{
                    .program_label = program_label,
                    .plan_label = compiled_plan.label,
                    .plan_hash = self._plan_fingerprint,
                    .turn_index = self._turn_index,
                    .after_site_index = self.after_site_index,
                    .after_site_fingerprint = self.after_site_fingerprint,
                    .semantic_label = self.semantic_label,
                    .source_operation_site_index = self.source_operation_site_index,
                    .source_operation_site_fingerprint = self.source_operation_site_fingerprint,
                    .function_index = self.function_index,
                    .block_index = self.block_index,
                    .instruction_index = self.instruction_index,
                    .original_requirement_index = self.requirement_index,
                    .original_requirement_label = self.requirement_label,
                    .original_op_index = self.op_index,
                    .original_op_name = self.op_name,
                    .current_value_ref = self.value_ref,
                    .current_value_fingerprint = self._value_fingerprint,
                    .expected_output_ref = self.output_ref,
                    .result_ref = self.result_ref,
                    .fingerprint = self._fingerprint,
                };
            }

            pub fn fingerprint(self: @This()) u64 {
                return self._fingerprint;
            }

            pub fn expectFingerprint(self: @This(), expected: u64) Trace.FingerprintError!void {
                if (self._fingerprint != expected) return error.TraceFingerprintMismatch;
            }

            pub fn responseTrace(self: @This(), kind: Trace.ResponseKind, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                if (kind != .resume_after) return error.ProgramContractViolation;
                const value_fingerprint = try Self.fingerprintTypedValueForRef(self.output_ref, response_value);
                return Self.responseTraceFor(self._fingerprint, kind, self.output_ref, value_fingerprint);
            }

            pub fn responseTraceFor(self: @This(), comptime Site: type, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                try self.expectSite(Site);
                return self.responseTrace(.resume_after, response_value);
            }

            fn setValue(self: *@This(), current_value: ExecutableValue) error{ProgramContractViolation}!void {
                self._value = switch (current_value) {
                    .none => .none,
                    .bool => |typed| .{ .bool = typed },
                    .i32 => |typed| .{ .i32 = typed },
                    .usize => |typed| .{ .usize = typed },
                    .word_u64 => |typed| .{ .word_u64 = typed },
                    .string => |typed| .{ .string = typed },
                    .string_list => |typed| .{ .string_list = typed },
                    .schema => |schema| try self.storeStructuredValue(schema),
                };
            }

            fn storeStructuredValue(self: *@This(), schema: SchemaValue) error{ProgramContractViolation}!RequestPayload {
                inline for (schema_types, 0..) |SchemaType, schema_index| {
                    if (schema.schema_index == @as(u16, @intCast(schema_index))) {
                        const source: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                        const destination: *SchemaType = @ptrCast(@alignCast(&self._value_storage));
                        destination.* = source.*;
                        return .{ .schema_index = schema.schema_index };
                    }
                }
                return error.ProgramContractViolation;
            }
        };

        fn requireOperationProtocolSite(comptime Site: type) void {
            if (!hasDeclSafe(Site, "kind") or Site.kind != .operation) {
                @compileError("expected Program.protocol operation site descriptor");
            }
            if (!hasDeclSafe(Site, "owner_label") or
                !std.mem.eql(u8, Site.owner_label, program_label) or
                !hasDeclSafe(Site, "owner_plan_hash") or
                Site.owner_plan_hash != plan_hash or
                !hasDeclSafe(Site, "OwnerHandlers") or
                Site.OwnerHandlers != HandlersType or
                !hasDeclSafe(Site, "Owner") or
                Site.Owner != ProtocolOwner)
            {
                @compileError("Program.protocol descriptor belongs to another program");
            }
        }

        fn requireAfterProtocolSite(comptime Site: type) void {
            if (!hasDeclSafe(Site, "kind") or Site.kind != .after) {
                @compileError("expected Program.protocol after site descriptor");
            }
            if (!hasDeclSafe(Site, "owner_label") or
                !std.mem.eql(u8, Site.owner_label, program_label) or
                !hasDeclSafe(Site, "owner_plan_hash") or
                Site.owner_plan_hash != plan_hash or
                !hasDeclSafe(Site, "OwnerHandlers") or
                Site.OwnerHandlers != HandlersType or
                !hasDeclSafe(Site, "Owner") or
                Site.Owner != ProtocolOwner)
            {
                @compileError("Program.protocol descriptor belongs to another program");
            }
        }

        fn TypedOperationRequest(comptime RequestType: type, comptime Site: type) type {
            comptime requireOperationProtocolSite(Site);
            return struct {
                pub const Descriptor = Site;
                request: RequestType,

                pub fn payload(self: @This()) error{ProgramContractViolation}!Site.Payload {
                    return self.request.payload(Site.Payload);
                }

                pub fn responseTrace(self: @This(), kind: Trace.ResponseKind, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                    return self.request.responseTraceFor(Site, kind, response_value);
                }
            };
        }

        fn TypedAfterRequest(comptime AfterRequestType: type, comptime Site: type) type {
            comptime requireAfterProtocolSite(Site);
            if (comptime Site.has_static_input_ref) {
                return struct {
                    pub const Descriptor = Site;
                    request: AfterRequestType,

                    pub fn value(self: @This()) error{ProgramContractViolation}!Site.Input {
                        return self.request.value(Site.Input);
                    }

                    pub fn responseTrace(self: @This(), response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                        return self.request.responseTraceFor(Site, response_value);
                    }
                };
            }
            return struct {
                pub const Descriptor = Site;
                request: AfterRequestType,

                pub fn value(self: @This(), comptime T: type) error{ProgramContractViolation}!T {
                    return self.request.value(T);
                }

                pub fn responseTrace(self: @This(), response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                    return self.request.responseTraceFor(Site, response_value);
                }
            };
        }

        pub const Step = union(enum) {
            after: AfterRequest,
            done: RawResult,
            request: Request,
        };

        /// One fuel-bounded static-machine reduction outcome.
        pub const FuelStep = union(enum) {
            step: Step,
            yielded_fuel,
        };

        // zlinter-disable declaration_naming - these public constants mirror the metadata field names.
        pub const capsule_version: u32 = 1;
        pub const continuation_fingerprint_version: u32 = 1;
        // zlinter-enable declaration_naming

        pub const ParkedKind = enum {
            after,
            operation,
        };

        pub const Current = union(enum) {
            none,
            after: AfterRequest,
            request: Request,
        };

        pub const CapsuleMetadata = struct {
            version: u32 = capsule_version,
            continuation_fingerprint_version: u32 = Self.continuation_fingerprint_version,
            program_label: []const u8 = program_label,
            plan_label: []const u8 = compiled_plan.label,
            plan_hash: u64 = plan_hash,
            trace_fingerprint_version: u32 = trace_fingerprint_version,
            parked_kind: ParkedKind,
            current_turn_index: usize,
            current_request_fingerprint: u64,
            current_operation_site_index: ?usize = null,
            current_after_site_index: ?usize = null,
            source_operation_site_index: ?usize = null,
            result_ref: program_plan.ValueRef,
            frame_count: usize,
            pending_after_count: usize,
            function_index: ?usize = null,
            block_index: ?usize = null,
            instruction_index: ?usize = null,
            owns_copied_values: bool = true,
            reusable: bool = true,
            continuation_fingerprint: u64,
        };

        pub const Capsule = struct {
            core: Self,
            metadata_value: CapsuleMetadata,
            deinitialized: bool = false,

            pub fn deinit(self: *@This()) void {
                if (self.deinitialized) return;
                self.core.deinit();
                self.deinitialized = true;
            }

            pub fn metadata(self: *const @This()) CapsuleMetadata {
                return self.metadata_value;
            }

            pub fn fingerprint(self: *const @This()) u64 {
                return self.metadata_value.continuation_fingerprint;
            }

            pub fn clone(self: *const @This(), allocator: std.mem.Allocator) anyerror!@This() {
                if (self.deinitialized) return error.ProgramContractViolation;
                try validateCapsuleMetadata(self.metadata_value);
                var core = try self.core.cloneState(allocator);
                errdefer core.deinit();
                try core.validateCapsuleShape(self.metadata_value);
                return .{
                    .core = core,
                    .metadata_value = self.metadata_value,
                };
            }

            pub fn encode(self: *const @This(), allocator: std.mem.Allocator) anyerror![]u8 {
                if (self.deinitialized) return error.ProgramContractViolation;
                try validateCapsuleMetadata(self.metadata_value);
                try self.core.validateCapsuleShape(self.metadata_value);
                var writer = DurableWriter.init(allocator);
                errdefer writer.deinit();
                try writer.writeBytes(capsule_image_magic);
                try writer.writeU32(capsule_image_format_version);
                try writer.writeU32(capsule_image_fingerprint_version);
                try writeCapsuleMetadata(&writer, self.metadata_value);
                try writeCoreImage(&writer, &self.core);
                const payload = writer.bytes.items;
                const checksum = durableFingerprint("boundary.session.capsule.image.payload", payload);
                try writer.writeU64(checksum);
                return writer.toOwnedSlice();
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) anyerror!@This() {
                if (bytes.len < capsule_image_magic.len + 4 + 4 + 8) return error.ProgramContractViolation;
                const stored_checksum = std.mem.readInt(u64, bytes[bytes.len - 8 ..][0..8], .little);
                const payload = bytes[0 .. bytes.len - 8];
                if (stored_checksum != durableFingerprint("boundary.session.capsule.image.payload", payload)) {
                    return error.ProgramContractViolation;
                }
                var reader = DurableReader.init(payload);
                try reader.expectBytes(capsule_image_magic);
                if (try reader.readU32() != capsule_image_format_version) return error.ProgramContractViolation;
                if (try reader.readU32() != capsule_image_fingerprint_version) return error.ProgramContractViolation;
                const metadata_value = try readCapsuleMetadata(&reader);
                try validateCapsuleMetadata(metadata_value);
                var core = try readCoreImage(allocator, &reader);
                errdefer core.deinit();
                if (!reader.eof()) return error.ProgramContractViolation;
                try core.validateCapsuleShape(metadata_value);
                return .{
                    .core = core,
                    .metadata_value = metadata_value,
                };
            }
        };

        /// Encode any runnable or parked generated-machine state without runtime ownership data.
        pub fn encodeState(self: *const Self, allocator: std.mem.Allocator) anyerror![]u8 {
            return self.encodeStateBounded(allocator, null);
        }

        /// Encode authoritative continuation bytes while enforcing a structural byte limit during growth.
        pub fn encodeStateBounded(
            self: *const Self,
            allocator: std.mem.Allocator,
            maximum_bytes: ?usize,
        ) anyerror![]u8 {
            try @constCast(self).validateState();
            var writer = DurableWriter.initBounded(allocator, maximum_bytes);
            errdefer writer.deinit();
            try writeStateImagePayload(&writer, self);
            const payload = writer.bytes.items;
            try writer.writeU64(stateImageFingerprint(payload));
            return writer.toOwnedSlice();
        }

        fn writeStateImagePayload(writer: *DurableWriter, self: *const Self) anyerror!void {
            try writer.writeBytes(state_image_magic);
            try writer.writeU32(state_image_format_version);
            try writer.writeU32(state_image_fingerprint_version);
            try writer.writeLenBytes(program_label);
            try writer.writeLenBytes(compiled_plan.label);
            try writer.writeU64(contract_fingerprint);
            try writeCoreImage(writer, self);
        }

        /// Validate one runnable or parked state and its complete bounded canonical image shape.
        pub fn validateStateBounded(self: *Self, maximum_bytes: usize) error{ProgramContractViolation}!void {
            try self.validateState();
            var writer = DurableWriter.initCounting(self.allocator, maximum_bytes);
            defer writer.deinit();
            writeStateImagePayload(&writer, self) catch return error.ProgramContractViolation;
            writer.writeU64(0) catch return error.ProgramContractViolation;
        }

        /// Clone one canonical state for a transactional StaticMachine mutation.
        pub fn cloneExplicitState(self: *const Self) anyerror!Self {
            return self.cloneState(self.allocator);
        }

        /// Clone one canonical state into caller-selected transient ownership.
        pub fn cloneExplicitStateWithAllocator(self: *const Self, allocator: std.mem.Allocator) anyerror!Self {
            var cloned = try self.cloneState(allocator);
            errdefer cloned.deinit();
            try cloned.reidentifyClone();
            return cloned;
        }

        /// Whether the current terminal error was authored by the Boundary program.
        pub fn hasAuthoredTerminalFailure(self: *const Self) bool {
            return self.terminal_failure_instruction_index != null;
        }

        /// Decode and validate one canonical generated-machine state image.
        pub fn decodeState(allocator: std.mem.Allocator, bytes: []const u8) anyerror!Self {
            if (bytes.len < state_image_magic.len + 4 + 4 + 8) return error.ProgramContractViolation;
            const stored_checksum = std.mem.readInt(u64, bytes[bytes.len - 8 ..][0..8], .little);
            const payload = bytes[0 .. bytes.len - 8];
            if (stored_checksum != stateImageFingerprint(payload)) return error.ProgramContractViolation;
            var reader = DurableReader.initCanonical(payload);
            try reader.expectBytes(state_image_magic);
            if (try reader.readU32() != state_image_format_version) return error.ProgramContractViolation;
            if (try reader.readU32() != state_image_fingerprint_version) return error.ProgramContractViolation;
            if (!std.mem.eql(u8, try reader.readLenBytes(), program_label)) return error.ProgramContractViolation;
            if (!std.mem.eql(u8, try reader.readLenBytes(), compiled_plan.label)) return error.ProgramContractViolation;
            if (try reader.readU64() != contract_fingerprint) return error.ProgramContractViolation;
            var state = try readCoreImage(allocator, &reader);
            errdefer state.deinit();
            if (!reader.eof()) return error.ProgramContractViolation;
            if (comptime canonical_request_identity) try state.activateDecodedPending();
            try state.validateState();
            return state;
        }

        /// Validate one live generated-machine state without advancing it.
        pub fn validateState(self: *Self) error{ProgramContractViolation}!void {
            if (self.completed != null or
                self.done_consumed or
                self.terminal_failure_instruction_index != null or
                self.terminal_runtime_failure != null)
            {
                return error.ProgramContractViolation;
            }
            if (self.remaining_steps > max_interpreter_steps or self.next_turn_index > maximum_turn_count) {
                return error.ProgramContractViolation;
            }
            try self.validateDecodedFrameStack();
            try self.validateDecodedPendingState();
        }

        // zlinter-disable declaration_naming - public durable format constants intentionally use stable API names.
        pub const capsule_image_format_version: u32 = 1;
        pub const capsule_image_fingerprint_version: u32 = 1;
        pub const state_image_format_version: u32 = 1;
        pub const state_image_fingerprint_version: u32 = 1;
        pub const journal_format_version: u32 = 1;
        pub const journal_fingerprint_version: u32 = 1;
        pub const maximum_frame_depth: usize = analysis.max_active_frame_depth;
        pub const maximum_interpreter_fuel: usize = max_interpreter_steps;
        pub const maximum_turn_count: usize = max_interpreter_steps * 2;
        pub const canonical_usize_bits: u8 = static_usize_bits;
        pub const has_frame_cycle: bool = analysis.helper_cycle;
        pub const canonical_plan_fingerprint: u64 = canonical_plan_identity;
        pub const contract_fingerprint: u64 = static_contract_identity;
        pub const control_path_state_count: usize = control_path_state_capacity;
        pub const maximum_control_path_states: usize = static_max_path_states;
        pub const control_validation_scratch_bytes: usize =
            control_path_state_capacity * @sizeOf(ControlPathStateIndex) + @sizeOf(ControlPathVisited);
        pub const maximum_control_validation_scratch_bytes: usize =
            static_max_path_scratch_bytes;
        pub const maximum_control_validation_steps: usize =
            static_max_control_work_units;
        pub const control_validation_step_bound: usize =
            static_control_validation_step_bound;
        pub const control_instruction_metadata_bytes: usize =
            compiled_plan.instructions.len * @sizeOf(ControlInstructionMetadata);
        // zlinter-enable declaration_naming

        const capsule_image_magic = "ABL_CAP1";
        const state_image_magic = "ABL_STM1";
        const control_node_count = compiled_plan.instructions.len + compiled_plan.blocks.len;
        const control_node_capacity = if (control_node_count == 0) 1 else control_node_count;
        const control_predicate_slot_count = if (canonical_request_identity)
            staticMachineMaximumConditionPredicateCount(compiled_plan) + 1
        else
            1;
        const condition_validity_count = if (canonical_request_identity) 2 else 1;
        const condition_authority_count =
            control_predicate_slot_count * 2 * condition_validity_count;
        const control_path_state_capacity = if (canonical_request_identity)
            static_control_path_state_capacity
        else
            control_node_capacity * 2 * condition_authority_count;
        const ControlPathStateIndex = std.math.IntFittingRange(0, control_path_state_capacity - 1);
        const ControlPathVisited = std.StaticBitSet(control_path_state_capacity);
        const ControlConditionAuthority = std.StaticBitSet(condition_authority_count);
        const ControlNodeIndex = std.math.IntFittingRange(0, control_node_capacity - 1);
        const ControlNodeVisited = std.StaticBitSet(control_node_capacity);
        const invalid_control_metadata_index = std.math.maxInt(u16);

        const ControlInstructionMetadata = struct {
            block_index: u16 = invalid_control_metadata_index,
            nested_target_index: u16 = invalid_control_metadata_index,
        };

        const control_instruction_metadata = blk: {
            var values = [_]ControlInstructionMetadata{.{}} ** compiled_plan.instructions.len;
            for (compiled_plan.blocks, 0..) |block, block_index| {
                if (block_index >= invalid_control_metadata_index) {
                    @compileError("Boundary StaticMachine control metadata requires block indexes to fit u16");
                }
                const first: usize = block.first_instruction;
                const end = first + block.instruction_count;
                if (end > values.len) {
                    @compileError("Boundary StaticMachine control metadata observed an invalid block instruction range");
                }
                for (first..end) |instruction_index| {
                    values[instruction_index].block_index = @intCast(block_index);
                }
            }
            for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
                if (instruction.kind != .call_nested_with) continue;
                const target_index = nestedWithTargetIndexForMetadata(
                    compiled_plan,
                    nested_with_targets,
                    instruction.string_literal,
                ) orelse continue;
                if (target_index >= invalid_control_metadata_index) {
                    @compileError("Boundary StaticMachine control metadata requires nested target indexes to fit u16");
                }
                values[instruction_index].nested_target_index = @intCast(target_index);
            }
            break :blk values;
        };
        const effective_completion_refs = blk: {
            var values: [compiled_plan.functions.len]program_plan.ValueRef = undefined;
            for (compiled_plan.functions, 0..) |function, function_index| {
                values[function_index] = effectiveCompletionRefForFunction(
                    analysis,
                    function,
                    function_index,
                );
            }
            break :blk values;
        };

        const ControlValidationBudget = struct {
            remaining: usize = if (canonical_request_identity)
                static_control_validation_step_bound
            else
                static_max_control_work_units,

            fn consume(self: *@This()) error{ProgramContractViolation}!void {
                if (self.remaining == 0) return error.ProgramContractViolation;
                self.remaining -= 1;
            }
        };

        const ControlPathState = struct {
            node: usize,
            traversed_allowed_suspension: bool,
            predicate_slot: usize,
            condition_matches_reference: bool,
            source_valid: bool,
        };

        const DurableWriter = struct {
            allocator: std.mem.Allocator,
            bytes: std.ArrayList(u8) = .empty,
            length: usize = 0,
            maximum_bytes: ?usize = null,
            canonical_values: bool = false,
            count_only: bool = false,

            const WriteError = std.mem.Allocator.Error || error{ProgramContractViolation};

            fn init(allocator: std.mem.Allocator) @This() {
                return .{ .allocator = allocator };
            }

            fn initBounded(allocator: std.mem.Allocator, maximum_bytes: ?usize) @This() {
                return .{
                    .allocator = allocator,
                    .maximum_bytes = maximum_bytes,
                    .canonical_values = true,
                };
            }

            fn initCounting(allocator: std.mem.Allocator, maximum_bytes: usize) @This() {
                return .{
                    .allocator = allocator,
                    .maximum_bytes = maximum_bytes,
                    .canonical_values = true,
                    .count_only = true,
                };
            }

            fn deinit(self: *@This()) void {
                self.bytes.deinit(self.allocator);
            }

            fn toOwnedSlice(self: *@This()) std.mem.Allocator.Error![]u8 {
                std.debug.assert(!self.count_only);
                return self.bytes.toOwnedSlice(self.allocator);
            }

            fn writeBytes(self: *@This(), value: []const u8) WriteError!void {
                const next_len = std.math.add(usize, self.length, value.len) catch
                    return error.ProgramContractViolation;
                if (self.maximum_bytes) |maximum| {
                    if (next_len > maximum) return error.ProgramContractViolation;
                }
                self.length = next_len;
                if (self.count_only) return;
                try self.bytes.ensureUnusedCapacity(self.allocator, value.len);
                self.bytes.appendSliceAssumeCapacity(value);
            }

            fn writeLenBytes(self: *@This(), value: []const u8) WriteError!void {
                try self.writeUsize(value.len);
                try self.writeBytes(value);
            }

            fn writeBool(self: *@This(), value: bool) WriteError!void {
                try self.writeU8(@intFromBool(value));
            }

            fn writeU8(self: *@This(), value: u8) WriteError!void {
                try self.writeBytes(&.{value});
            }

            fn writeU16(self: *@This(), value: u16) WriteError!void {
                var buffer: [2]u8 = undefined;
                std.mem.writeInt(u16, &buffer, value, .little);
                try self.writeBytes(&buffer);
            }

            fn writeU32(self: *@This(), value: u32) WriteError!void {
                var buffer: [4]u8 = undefined;
                std.mem.writeInt(u32, &buffer, value, .little);
                try self.writeBytes(&buffer);
            }

            fn writeU64(self: *@This(), value: u64) WriteError!void {
                var buffer: [8]u8 = undefined;
                std.mem.writeInt(u64, &buffer, value, .little);
                try self.writeBytes(&buffer);
            }

            fn writeUsize(self: *@This(), value: usize) WriteError!void {
                if (self.canonical_values and @as(u64, @intCast(value)) > static_usize_max) {
                    return error.ProgramContractViolation;
                }
                try self.writeU64(@intCast(value));
            }

            fn writeI32(self: *@This(), value: i32) WriteError!void {
                try self.writeU32(@bitCast(value));
            }
        };

        const DurableReader = struct {
            bytes: []const u8,
            index: usize = 0,
            canonical_values: bool = false,

            fn init(bytes: []const u8) @This() {
                return .{ .bytes = bytes };
            }

            fn initCanonical(bytes: []const u8) @This() {
                return .{ .bytes = bytes, .canonical_values = true };
            }

            fn eof(self: @This()) bool {
                return self.index == self.bytes.len;
            }

            fn remaining(self: @This()) usize {
                return self.bytes.len - self.index;
            }

            fn readBytes(self: *@This(), len: usize) error{ProgramContractViolation}![]const u8 {
                const end = std.math.add(usize, self.index, len) catch return error.ProgramContractViolation;
                if (end > self.bytes.len) return error.ProgramContractViolation;
                const slice = self.bytes[self.index..end];
                self.index = end;
                return slice;
            }

            fn expectBytes(self: *@This(), expected: []const u8) error{ProgramContractViolation}!void {
                const actual = try self.readBytes(expected.len);
                if (!std.mem.eql(u8, actual, expected)) return error.ProgramContractViolation;
            }

            fn readLenBytes(self: *@This()) error{ProgramContractViolation}![]const u8 {
                const len = try self.readUsize();
                return self.readBytes(len);
            }

            fn readBool(self: *@This()) error{ProgramContractViolation}!bool {
                return switch (try self.readU8()) {
                    0 => false,
                    1 => true,
                    else => error.ProgramContractViolation,
                };
            }

            fn readU8(self: *@This()) error{ProgramContractViolation}!u8 {
                return (try self.readBytes(1))[0];
            }

            fn readU16(self: *@This()) error{ProgramContractViolation}!u16 {
                return std.mem.readInt(u16, (try self.readBytes(2))[0..2], .little);
            }

            fn readU32(self: *@This()) error{ProgramContractViolation}!u32 {
                return std.mem.readInt(u32, (try self.readBytes(4))[0..4], .little);
            }

            fn readU64(self: *@This()) error{ProgramContractViolation}!u64 {
                return std.mem.readInt(u64, (try self.readBytes(8))[0..8], .little);
            }

            fn readUsize(self: *@This()) error{ProgramContractViolation}!usize {
                const value = try self.readU64();
                if (self.canonical_values and value > static_usize_max) {
                    return error.ProgramContractViolation;
                }
                if (value > std.math.maxInt(usize)) return error.ProgramContractViolation;
                return @intCast(value);
            }

            fn readI32(self: *@This()) error{ProgramContractViolation}!i32 {
                return @bitCast(try self.readU32());
            }
        };

        fn durableFingerprint(domain: []const u8, bytes: []const u8) u64 {
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, domain);
            traceHashU32(&hasher, capsule_image_fingerprint_version);
            traceHashBytes(&hasher, bytes);
            return hasher.final();
        }

        fn stateImageFingerprint(bytes: []const u8) u64 {
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "boundary.static-machine.state.image");
            traceHashU32(&hasher, state_image_fingerprint_version);
            traceHashBytes(&hasher, bytes);
            return hasher.final();
        }

        fn writeOptionalUsize(writer: *DurableWriter, value: ?usize) DurableWriter.WriteError!void {
            try writer.writeBool(value != null);
            if (value) |actual| try writer.writeUsize(actual);
        }

        fn readOptionalUsize(reader: *DurableReader) error{ProgramContractViolation}!?usize {
            if (!try reader.readBool()) return null;
            return try reader.readUsize();
        }

        fn writeValueRef(writer: *DurableWriter, ref: program_plan.ValueRef) DurableWriter.WriteError!void {
            try writer.writeU8(@intFromEnum(ref.codec));
            try writer.writeBool(ref.schema_index != null);
            if (ref.schema_index) |schema_index| try writer.writeU16(schema_index);
        }

        fn readCodec(reader: *DurableReader) error{ProgramContractViolation}!program_plan.ValueCodec {
            return switch (try reader.readU8()) {
                @intFromEnum(program_plan.ValueCodec.unit) => .unit,
                @intFromEnum(program_plan.ValueCodec.bool) => .bool,
                @intFromEnum(program_plan.ValueCodec.i32) => .i32,
                @intFromEnum(program_plan.ValueCodec.product) => .product,
                @intFromEnum(program_plan.ValueCodec.usize) => .usize,
                @intFromEnum(program_plan.ValueCodec.string) => .string,
                @intFromEnum(program_plan.ValueCodec.string_list) => .string_list,
                @intFromEnum(program_plan.ValueCodec.sum) => .sum,
                else => error.ProgramContractViolation,
            };
        }

        fn readValueRef(reader: *DurableReader) error{ProgramContractViolation}!program_plan.ValueRef {
            const codec = try readCodec(reader);
            const schema_index = if (try reader.readBool()) try reader.readU16() else null;
            return .{ .codec = codec, .schema_index = schema_index };
        }

        fn writeParkedKind(writer: *DurableWriter, parked: ParkedKind) DurableWriter.WriteError!void {
            try writer.writeU8(switch (parked) {
                .operation => 0,
                .after => 1,
            });
        }

        fn readParkedKind(reader: *DurableReader) error{ProgramContractViolation}!ParkedKind {
            return switch (try reader.readU8()) {
                0 => .operation,
                1 => .after,
                else => error.ProgramContractViolation,
            };
        }

        fn writeControlMode(writer: *DurableWriter, mode: program_plan.ControlMode) DurableWriter.WriteError!void {
            try writer.writeU8(switch (mode) {
                .abort => 0,
                .choice => 1,
                .transform => 2,
            });
        }

        fn readControlMode(reader: *DurableReader) error{ProgramContractViolation}!program_plan.ControlMode {
            return switch (try reader.readU8()) {
                0 => .abort,
                1 => .choice,
                2 => .transform,
                else => error.ProgramContractViolation,
            };
        }

        const DurableValueImageContext = struct {
            allocator: std.mem.Allocator,
            strings: std.ArrayList([]const u8) = .empty,
            string_lists: std.ArrayList([]const []const u8) = .empty,

            fn init(allocator: std.mem.Allocator) @This() {
                return .{ .allocator = allocator };
            }

            fn deinit(self: *@This()) void {
                self.strings.deinit(self.allocator);
                self.string_lists.deinit(self.allocator);
            }

            fn stringIndex(self: *const @This(), value: []const u8) ?usize {
                for (self.strings.items, 0..) |existing, index| {
                    if (existing.ptr == value.ptr and existing.len == value.len) return index;
                }
                return null;
            }

            fn stringListIndex(self: *const @This(), value: []const []const u8) ?usize {
                for (self.string_lists.items, 0..) |existing, index| {
                    if (existing.ptr == value.ptr and existing.len == value.len) return index;
                }
                return null;
            }
        };

        fn writeImageString(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            value: []const u8,
        ) DurableWriter.WriteError!void {
            if (!writer.canonical_values) {
                if (context.stringIndex(value)) |index| {
                    try writer.writeU8(1);
                    try writer.writeUsize(index);
                    return;
                }
                try context.strings.append(context.allocator, value);
            }
            try writer.writeU8(0);
            try writer.writeLenBytes(value);
        }

        fn readImageString(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
        ) anyerror![]const u8 {
            return switch (try reader.readU8()) {
                0 => blk: {
                    const value = try scratch.storeOwnedString(try reader.readLenBytes());
                    if (!reader.canonical_values) try context.strings.append(context.allocator, value);
                    break :blk value;
                },
                1 => blk: {
                    if (reader.canonical_values) return error.ProgramContractViolation;
                    const index = try reader.readUsize();
                    if (index >= context.strings.items.len) return error.ProgramContractViolation;
                    break :blk context.strings.items[index];
                },
                else => error.ProgramContractViolation,
            };
        }

        fn writeImageStringList(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            value: []const []const u8,
        ) anyerror!void {
            if (!writer.canonical_values) {
                if (context.stringListIndex(value)) |index| {
                    try writer.writeU8(1);
                    try writer.writeUsize(index);
                    return;
                }
                try context.string_lists.append(context.allocator, value);
            }
            try writer.writeU8(0);
            try writer.writeUsize(value.len);
            for (value) |item| try writeImageString(writer, context, item);
        }

        fn readImageStringList(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
        ) anyerror![]const []const u8 {
            return switch (try reader.readU8()) {
                0 => blk: {
                    const count = try reader.readUsize();
                    if (count > reader.remaining() / 8) return error.ProgramContractViolation;
                    const items = try scratch.allocator.alloc([]const u8, count);
                    var items_owned = false;
                    errdefer if (!items_owned) scratch.allocator.free(items);
                    for (items) |*item| item.* = try readImageString(reader, scratch, context);
                    if (!reader.canonical_values) try context.string_lists.append(context.allocator, items);
                    try scratch.owned_string_lists.append(scratch.allocator, items);
                    items_owned = true;
                    break :blk items;
                },
                1 => blk: {
                    if (reader.canonical_values) return error.ProgramContractViolation;
                    const index = try reader.readUsize();
                    if (index >= context.string_lists.items.len) return error.ProgramContractViolation;
                    break :blk context.string_lists.items[index];
                },
                else => error.ProgramContractViolation,
            };
        }

        fn writeCapsuleMetadata(writer: *DurableWriter, metadata: CapsuleMetadata) DurableWriter.WriteError!void {
            try writer.writeU32(metadata.version);
            try writer.writeU32(metadata.continuation_fingerprint_version);
            try writer.writeLenBytes(metadata.program_label);
            try writer.writeLenBytes(metadata.plan_label);
            try writer.writeU64(metadata.plan_hash);
            try writer.writeU32(metadata.trace_fingerprint_version);
            try writeParkedKind(writer, metadata.parked_kind);
            try writer.writeUsize(metadata.current_turn_index);
            try writer.writeU64(metadata.current_request_fingerprint);
            try writeOptionalUsize(writer, metadata.current_operation_site_index);
            try writeOptionalUsize(writer, metadata.current_after_site_index);
            try writeOptionalUsize(writer, metadata.source_operation_site_index);
            try writeValueRef(writer, metadata.result_ref);
            try writer.writeUsize(metadata.frame_count);
            try writer.writeUsize(metadata.pending_after_count);
            try writeOptionalUsize(writer, metadata.function_index);
            try writeOptionalUsize(writer, metadata.block_index);
            try writeOptionalUsize(writer, metadata.instruction_index);
            try writer.writeBool(metadata.owns_copied_values);
            try writer.writeBool(metadata.reusable);
            try writer.writeU64(metadata.continuation_fingerprint);
        }

        fn readCapsuleMetadata(reader: *DurableReader) error{ProgramContractViolation}!CapsuleMetadata {
            const version = try reader.readU32();
            const continuation_version = try reader.readU32();
            const actual_program_label = try reader.readLenBytes();
            const actual_plan_label = try reader.readLenBytes();
            const actual_plan_hash = try reader.readU64();
            const trace_version = try reader.readU32();
            const parked_kind = try readParkedKind(reader);
            const current_turn_index = try reader.readUsize();
            const current_request_fingerprint = try reader.readU64();
            const current_operation_site_index = try readOptionalUsize(reader);
            const current_after_site_index = try readOptionalUsize(reader);
            const source_operation_site_index = try readOptionalUsize(reader);
            const result_ref = try readValueRef(reader);
            const frame_count = try reader.readUsize();
            const pending_after_count = try reader.readUsize();
            const function_index = try readOptionalUsize(reader);
            const block_index = try readOptionalUsize(reader);
            const instruction_index = try readOptionalUsize(reader);
            const owns_copied_values = try reader.readBool();
            const reusable = try reader.readBool();
            const continuation_fingerprint = try reader.readU64();
            if (!std.mem.eql(u8, actual_program_label, program_label)) return error.ProgramContractViolation;
            if (!std.mem.eql(u8, actual_plan_label, compiled_plan.label)) return error.ProgramContractViolation;
            return .{
                .version = version,
                .continuation_fingerprint_version = continuation_version,
                .program_label = program_label,
                .plan_label = compiled_plan.label,
                .plan_hash = actual_plan_hash,
                .trace_fingerprint_version = trace_version,
                .parked_kind = parked_kind,
                .current_turn_index = current_turn_index,
                .current_request_fingerprint = current_request_fingerprint,
                .current_operation_site_index = current_operation_site_index,
                .current_after_site_index = current_after_site_index,
                .source_operation_site_index = source_operation_site_index,
                .result_ref = result_ref,
                .frame_count = frame_count,
                .pending_after_count = pending_after_count,
                .function_index = function_index,
                .block_index = block_index,
                .instruction_index = instruction_index,
                .owns_copied_values = owns_copied_values,
                .reusable = reusable,
                .continuation_fingerprint = continuation_fingerprint,
            };
        }

        fn writeTypedValue(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            comptime ref: program_plan.ValueRef,
            value: anytype,
        ) anyerror!void {
            if (!typeMatchesSchemaFieldRuntimeRef(schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
            switch (comptime ref.codec) {
                .unit => {},
                .bool => try writer.writeBool(value),
                .i32 => try writer.writeI32(value),
                .usize => if (@TypeOf(value) == u64) try writer.writeU64(value) else try writer.writeUsize(value),
                .string => try writeImageString(writer, context, value),
                .string_list => try writeImageStringList(writer, context, value),
                .product => try writeProductValue(writer, context, ref.schema_index orelse return error.ProgramContractViolation, @TypeOf(value), value),
                .sum => try writeSumValue(writer, context, ref.schema_index orelse return error.ProgramContractViolation, @TypeOf(value), value),
            }
        }

        fn writeProductValue(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            comptime schema_index: usize,
            comptime T: type,
            value: T,
        ) anyerror!void {
            if (schema_index >= compiled_plan.value_schemas.len) return error.ProgramContractViolation;
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .product) return error.ProgramContractViolation;
            const fields = std.meta.fields(T);
            if (fields.len != schema.field_count) return error.ProgramContractViolation;
            try writer.writeU16(schema.first_field);
            try writer.writeU16(schema.field_count);
            inline for (0..schema.field_count) |field_offset| {
                const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                const FieldType = @TypeOf(@field(value, field.name));
                const field_ref: program_plan.ValueRef = .{ .codec = field.codec, .schema_index = field.schema_index };
                try writer.writeLenBytes(field.name);
                try writeValueRef(writer, field_ref);
                try writeTypedValue(writer, context, field_ref, @as(FieldType, @field(value, field.name)));
            }
        }

        fn writeSumValue(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            comptime schema_index: usize,
            comptime T: type,
            value: T,
        ) anyerror!void {
            if (schema_index >= compiled_plan.value_schemas.len) return error.ProgramContractViolation;
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .sum) return error.ProgramContractViolation;
            const active = try activeVariantOrdinalForTyped(T, value);
            if (active >= schema.variant_count) return error.ProgramContractViolation;
            try writer.writeU16(schema.first_variant);
            try writer.writeU16(schema.variant_count);
            try writer.writeU16(active);
            inline for (0..schema.variant_count) |variant_offset| {
                if (active == variant_offset) {
                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + variant_offset];
                    const variant_ref: program_plan.ValueRef = comptime .{ .codec = variant.codec, .schema_index = variant.schema_index };
                    try writer.writeLenBytes(variant.name);
                    try writeValueRef(writer, variant_ref);
                    switch (@typeInfo(T)) {
                        .@"enum" => try writeTypedValue(writer, context, variant_ref, {}),
                        .optional => {
                            if (variant_offset == 0) try writeTypedValue(writer, context, variant_ref, {}) else try writeTypedValue(writer, context, variant_ref, value.?);
                        },
                        .@"union" => |union_info| {
                            const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
                            const tag = std.meta.activeTag(value);
                            inline for (union_info.fields, 0..) |field, field_index| {
                                if (variant_offset == field_index and tag == @field(Tag, field.name)) {
                                    if (field.type == void) {
                                        try writeTypedValue(writer, context, variant_ref, {});
                                    } else {
                                        try writeTypedValue(writer, context, variant_ref, @field(value, field.name));
                                    }
                                    return;
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        else => return error.ProgramContractViolation,
                    }
                    return;
                }
            }
            return error.ProgramContractViolation;
        }

        fn readTypedValue(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            comptime ref: program_plan.ValueRef,
        ) anyerror!ValueTypeForRef(compiled_plan, schema_types, ref) {
            const T = ValueTypeForRef(compiled_plan, schema_types, ref);
            return switch (comptime ref.codec) {
                .unit => {},
                .bool => try reader.readBool(),
                .i32 => try reader.readI32(),
                .usize => try reader.readUsize(),
                .string => try readImageString(reader, scratch, context),
                .string_list => blk: {
                    const items = try readImageStringList(reader, scratch, context);
                    if (T == []const []const u8) break :blk items;
                    if (T == [][]const u8) break :blk @constCast(items);
                    return error.ProgramContractViolation;
                },
                .product => try readProductValue(reader, scratch, context, ref.schema_index orelse return error.ProgramContractViolation, T),
                .sum => try readSumValue(reader, scratch, context, ref.schema_index orelse return error.ProgramContractViolation, T),
            };
        }

        fn readProductValue(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            comptime schema_index: usize,
            comptime T: type,
        ) anyerror!T {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .product) return error.ProgramContractViolation;
            const fields = std.meta.fields(T);
            if (fields.len != schema.field_count) return error.ProgramContractViolation;
            if (try reader.readU16() != schema.first_field) return error.ProgramContractViolation;
            if (try reader.readU16() != schema.field_count) return error.ProgramContractViolation;
            var value: T = undefined;
            inline for (0..schema.field_count) |field_offset| {
                const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                const actual_name = try reader.readLenBytes();
                if (!std.mem.eql(u8, actual_name, field.name)) return error.ProgramContractViolation;
                const field_ref: program_plan.ValueRef = .{ .codec = field.codec, .schema_index = field.schema_index };
                if (!(try readValueRef(reader)).eql(field_ref)) return error.ProgramContractViolation;
                const struct_field = fields[field_offset];
                if (comptime field.codec == .usize and struct_field.type == u64) {
                    @field(value, field.name) = try reader.readU64();
                    continue;
                }
                const decoded_field = try readTypedValue(reader, scratch, context, field_ref);
                if (comptime field.codec == .string_list and struct_field.type == [][]const u8) {
                    @field(value, field.name) = @constCast(decoded_field);
                } else {
                    @field(value, field.name) = decoded_field;
                }
            }
            return value;
        }

        fn readSumValue(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            comptime schema_index: usize,
            comptime T: type,
        ) anyerror!T {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .sum) return error.ProgramContractViolation;
            if (try reader.readU16() != schema.first_variant) return error.ProgramContractViolation;
            if (try reader.readU16() != schema.variant_count) return error.ProgramContractViolation;
            const active = try reader.readU16();
            if (active >= schema.variant_count) return error.ProgramContractViolation;
            inline for (0..schema.variant_count) |variant_offset| {
                if (active == variant_offset) {
                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + variant_offset];
                    const actual_name = try reader.readLenBytes();
                    if (!std.mem.eql(u8, actual_name, variant.name)) return error.ProgramContractViolation;
                    const variant_ref: program_plan.ValueRef = comptime .{ .codec = variant.codec, .schema_index = variant.schema_index };
                    if (!(try readValueRef(reader)).eql(variant_ref)) return error.ProgramContractViolation;
                    return switch (@typeInfo(T)) {
                        .@"enum" => blk: {
                            inline for (std.meta.fields(T), 0..) |field, field_index| {
                                if (active == field_index) {
                                    if (!std.mem.eql(u8, field.name, variant.name)) return error.ProgramContractViolation;
                                    _ = try readTypedValue(reader, scratch, context, variant_ref);
                                    break :blk @field(T, field.name);
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        .optional => |optional_info| if (variant_offset == 0) blk: {
                            _ = try readTypedValue(reader, scratch, context, variant_ref);
                            break :blk null;
                        } else blk: {
                            if (comptime variant_ref.codec == .usize and optional_info.child == u64) {
                                break :blk try reader.readU64();
                            }
                            const decoded_payload = try readTypedValue(reader, scratch, context, variant_ref);
                            if (comptime variant_ref.codec == .string_list and optional_info.child == [][]const u8) {
                                break :blk @constCast(decoded_payload);
                            }
                            break :blk decoded_payload;
                        },
                        .@"union" => |union_info| blk: {
                            inline for (union_info.fields, 0..) |field, field_index| {
                                if (variant_offset == field_index) {
                                    if (!std.mem.eql(u8, field.name, variant.name)) return error.ProgramContractViolation;
                                    if (field.type == void) {
                                        _ = try readTypedValue(reader, scratch, context, variant_ref);
                                        break :blk @unionInit(T, field.name, {});
                                    }
                                    if (comptime variant_ref.codec == .usize and field.type == u64) {
                                        break :blk @unionInit(T, field.name, try reader.readU64());
                                    }
                                    const decoded_payload = try readTypedValue(reader, scratch, context, variant_ref);
                                    if (comptime variant_ref.codec == .string_list and field.type == [][]const u8) {
                                        break :blk @unionInit(T, field.name, @constCast(decoded_payload));
                                    }
                                    break :blk @unionInit(T, field.name, decoded_payload);
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        else => error.ProgramContractViolation,
                    };
                }
            }
            return error.ProgramContractViolation;
        }

        fn writeExecutableValueForRef(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
        ) anyerror!void {
            if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
            switch (ref.codec) {
                .unit => {},
                .bool => try writer.writeBool(try decodeArg(.bool, value)),
                .i32 => try writer.writeI32(try decodeArg(.i32, value)),
                .usize => {
                    const word = try executableWordU64(value);
                    if (writer.canonical_values and word > static_usize_max) {
                        return error.ProgramContractViolation;
                    }
                    try writer.writeU64(word);
                },
                .string => try writeImageString(writer, context, try decodeArg(.string, value)),
                .string_list => try writeImageStringList(writer, context, try decodeArg(.string_list, value)),
                .product, .sum => switch (value) {
                    .schema => |schema| {
                        const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                        if (schema.schema_index != schema_index) return error.ProgramContractViolation;
                        inline for (schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                const static_ref: program_plan.ValueRef = comptime .{
                                    .codec = compiled_plan.value_schemas[index].codec,
                                    .schema_index = @intCast(index),
                                };
                                if (!static_ref.eql(ref)) return error.ProgramContractViolation;
                                const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                                return writeTypedValue(writer, context, static_ref, typed.*);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                    else => return error.ProgramContractViolation,
                },
            }
        }

        fn readExecutableValueForRef(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
        ) anyerror!ExecutableValue {
            return switch (ref.codec) {
                .unit => .none,
                .bool => .{ .bool = try reader.readBool() },
                .i32 => .{ .i32 = try reader.readI32() },
                .usize => blk: {
                    const word = try reader.readU64();
                    if (reader.canonical_values and word > static_usize_max) {
                        return error.ProgramContractViolation;
                    }
                    break :blk .{ .word_u64 = word };
                },
                .string => .{ .string = try readImageString(reader, scratch, context) },
                .string_list => .{ .string_list = try readImageStringList(reader, scratch, context) },
                .product, .sum => blk: {
                    const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                    inline for (schema_types, 0..) |SchemaType, index| {
                        if (schema_index == index) {
                            const static_ref: program_plan.ValueRef = comptime .{
                                .codec = compiled_plan.value_schemas[index].codec,
                                .schema_index = @intCast(index),
                            };
                            if (!static_ref.eql(ref)) return error.ProgramContractViolation;
                            const typed = try readTypedValue(reader, scratch, context, static_ref);
                            break :blk try scratch.storeSchemaValue(SchemaType, schema_index, typed);
                        }
                    }
                    return error.ProgramContractViolation;
                },
            };
        }

        fn writeExecutableImageValueForRef(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
            decoded_locals: []const ExecutableValue,
        ) anyerror!void {
            if (!writer.canonical_values) {
                for (decoded_locals, 0..) |local, local_index| {
                    if (valueMatchesRef(ref, local) and executableValuesShareIdentity(local, value)) {
                        try writer.writeU8(1);
                        try writer.writeUsize(local_index);
                        return;
                    }
                }
            }
            try writer.writeU8(0);
            try writeExecutableValueForRef(writer, context, ref, value);
        }

        fn readExecutableImageValueForRef(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            decoded_locals: []const ExecutableValue,
        ) anyerror!ExecutableValue {
            return switch (try reader.readU8()) {
                0 => try readExecutableValueForRef(reader, scratch, context, ref),
                1 => blk: {
                    if (reader.canonical_values) return error.ProgramContractViolation;
                    const local_index = try reader.readUsize();
                    if (local_index >= decoded_locals.len) return error.ProgramContractViolation;
                    const value = decoded_locals[local_index];
                    if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
                    break :blk value;
                },
                else => error.ProgramContractViolation,
            };
        }

        fn writeMaybeExecutableValueForRef(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
        ) anyerror!void {
            const absent = false;
            const present = true;
            if (!valueMatchesRef(ref, value)) {
                switch (value) {
                    .none => {},
                    else => return error.ProgramContractViolation,
                }
                try writer.writeBool(absent);
                return;
            }
            try writer.writeBool(present);
            try writeExecutableValueForRef(writer, context, ref, value);
        }

        fn readMaybeExecutableValueForRef(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
        ) anyerror!ExecutableValue {
            if (!try reader.readBool()) return .none;
            return readExecutableValueForRef(reader, scratch, context, ref);
        }

        fn writeMaybeExecutableImageValueForRef(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
            decoded_locals: []const ExecutableValue,
        ) anyerror!void {
            if (!valueMatchesRef(ref, value)) {
                if (value != .none) return error.ProgramContractViolation;
                try writer.writeU8(0);
                return;
            }
            if (!writer.canonical_values) {
                for (decoded_locals, 0..) |local, local_index| {
                    if (valueMatchesRef(ref, local) and executableValuesShareIdentity(local, value)) {
                        try writer.writeU8(2);
                        try writer.writeUsize(local_index);
                        return;
                    }
                }
            }
            try writer.writeU8(1);
            try writeExecutableValueForRef(writer, context, ref, value);
        }

        fn readMaybeExecutableImageValueForRef(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            decoded_locals: []const ExecutableValue,
        ) anyerror!ExecutableValue {
            return switch (try reader.readU8()) {
                0 => blk: {
                    if (reader.canonical_values and ref.codec == .unit) return error.ProgramContractViolation;
                    break :blk .none;
                },
                1 => try readExecutableValueForRef(reader, scratch, context, ref),
                2 => blk: {
                    if (reader.canonical_values) return error.ProgramContractViolation;
                    const local_index = try reader.readUsize();
                    if (local_index >= decoded_locals.len) return error.ProgramContractViolation;
                    const value = decoded_locals[local_index];
                    if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
                    break :blk value;
                },
                else => error.ProgramContractViolation,
            };
        }

        fn writeSessionAfterEntry(writer: *DurableWriter, entry_value: SessionAfterStackEntry) DurableWriter.WriteError!void {
            try writer.writeU16(entry_value.op_index);
            try writer.writeU16(entry_value.operation_site_index);
            try writer.writeU16(entry_value.after_site_index);
        }

        fn readSessionAfterEntry(reader: *DurableReader) error{ProgramContractViolation}!SessionAfterStackEntry {
            return .{
                .op_index = try reader.readU16(),
                .operation_site_index = try reader.readU16(),
                .after_site_index = try reader.readU16(),
            };
        }

        fn validateSessionAfterEntry(entry_value: SessionAfterStackEntry) error{ProgramContractViolation}!void {
            if (entry_value.op_index >= compiled_plan.ops.len) return error.ProgramContractViolation;
            const op = compiled_plan.ops[entry_value.op_index];
            if (!op.has_after) return error.ProgramContractViolation;
            if (entry_value.operation_site_index >= operation_yield_sites.len) return error.ProgramContractViolation;
            if (entry_value.after_site_index >= after_yield_sites.len) return error.ProgramContractViolation;
            const operation_site = operation_yield_sites[entry_value.operation_site_index];
            const after_site = after_yield_sites[entry_value.after_site_index];
            if (operation_site.index != entry_value.operation_site_index or
                operation_site.op_index != entry_value.op_index or
                !operation_site.has_after or
                after_site.index != entry_value.after_site_index or
                after_site.source_operation_site_index != entry_value.operation_site_index or
                after_site.source_operation_site_fingerprint != operation_site.fingerprint or
                after_site.original_op_index != entry_value.op_index)
            {
                return error.ProgramContractViolation;
            }
        }

        fn validateSessionAfterEntryForOperationSite(
            entry_value: SessionAfterStackEntry,
            op_index: u16,
            operation_site_index: usize,
        ) error{ProgramContractViolation}!void {
            try validateSessionAfterEntry(entry_value);
            const after_site = afterSiteForOperationSite(operation_site_index) orelse return error.ProgramContractViolation;
            if (entry_value.op_index != op_index or
                @as(usize, entry_value.operation_site_index) != operation_site_index or
                @as(usize, entry_value.after_site_index) != after_site.index)
            {
                return error.ProgramContractViolation;
            }
        }

        fn pendingPayloadForImage(self: *const Self, op: PendingRequest) error{ProgramContractViolation}!ExecutableValue {
            if (op.payload_ref.codec == .unit) return .none;
            if (op.payload_local_id != std.math.maxInt(u16)) {
                if (self.frames.len() == 0) return error.ProgramContractViolation;
                const active_frame = self.frames.at(self.frames.len() - 1) orelse return error.ProgramContractViolation;
                if (active_frame.function_index != op.function_index) return error.ProgramContractViolation;
                const locals = self.scratch.frameLocalsConst(active_frame.frame);
                if (op.payload_local_id >= locals.len) return error.ProgramContractViolation;
                const local_payload = locals[op.payload_local_id];
                if (!valueMatchesRef(op.payload_ref, local_payload)) return error.ProgramContractViolation;
                return local_payload;
            }
            if (!valueMatchesRef(op.payload_ref, op.payload)) return error.ProgramContractViolation;
            return op.payload;
        }

        const OperationPendingSnapshot = struct {
            payload: ExecutableValue,
            payload_value_fingerprint: u64,
            request_fingerprint: u64,
        };

        fn operationPendingSnapshot(self: *const Self, op: PendingRequest) error{ProgramContractViolation}!OperationPendingSnapshot {
            if (op.op_index >= compiled_plan.ops.len) return error.ProgramContractViolation;
            const plan_op = compiled_plan.ops[op.op_index];
            const requirement = compiled_plan.requirements[plan_op.requirement_index];
            const payload = try self.pendingPayloadForImage(op);
            const payload_value_fingerprint = try Self.fingerprintExecutableValueForRef(op.payload_ref, payload);
            return .{
                .payload = payload,
                .payload_value_fingerprint = payload_value_fingerprint,
                .request_fingerprint = Self.operationRequestFingerprint(
                    canonical_request_identity,
                    op.turn_index,
                    op.operation_site_index,
                    op.operation_site_fingerprint,
                    op.function_index,
                    op.block_index,
                    op.instruction_index,
                    plan_op.requirement_index,
                    requirement.label,
                    op.op_index,
                    plan_op.op_name,
                    op.mode,
                    op.payload_ref,
                    payload_value_fingerprint,
                    op.resume_ref,
                    op.result_ref,
                    op.has_after,
                ),
            };
        }

        fn writePending(writer: *DurableWriter, context: *DurableValueImageContext, self: *const Self) anyerror!void {
            try writer.writeBool(self.pending != null);
            if (self.pending == null) return;
            switch (self.pending.?) {
                .op => |op| {
                    const snapshot = try self.operationPendingSnapshot(op);
                    try writer.writeU8(0);
                    try writer.writeUsize(op.function_index);
                    try writer.writeUsize(op.block_index);
                    try writer.writeUsize(op.instruction_index);
                    try writer.writeU16(op.dst);
                    try writer.writeU16(op.op_index);
                    try writer.writeUsize(op.operation_site_index);
                    if (!writer.canonical_values) try writer.writeU64(op.operation_site_fingerprint);
                    try writer.writeUsize(op.turn_index);
                    try writeValueRef(writer, op.payload_ref);
                    try writer.writeU16(op.payload_local_id);
                    try writeExecutableImageValueForRef(writer, context, op.payload_ref, snapshot.payload, self.scratch.locals.items);
                    try writer.writeU64(snapshot.payload_value_fingerprint);
                    if (!writer.canonical_values) try writer.writeU64(snapshot.request_fingerprint);
                    try writeControlMode(writer, op.mode);
                    try writeValueRef(writer, op.resume_ref);
                    try writeValueRef(writer, op.result_ref);
                    try writer.writeBool(op.has_after);
                    try writeSessionAfterEntry(writer, op.after_stack_entry);
                },
                .after => |after| {
                    try writer.writeU8(1);
                    try writer.writeUsize(after.function_index);
                    try writer.writeUsize(after.block_index);
                    try writer.writeUsize(after.instruction_index);
                    try writer.writeU16(after.op_index);
                    try writer.writeUsize(after.after_site_index);
                    if (!writer.canonical_values) try writer.writeU64(after.after_site_fingerprint);
                    try writer.writeUsize(after.source_operation_site_index);
                    if (!writer.canonical_values) try writer.writeU64(after.source_operation_site_fingerprint);
                    try writer.writeUsize(after.turn_index);
                    try writeValueRef(writer, after.value_ref);
                    try writeExecutableImageValueForRef(writer, context, after.value_ref, after.value, self.scratch.locals.items);
                    try writer.writeU64(after.value_fingerprint);
                    if (!writer.canonical_values) try writer.writeU64(after.request_fingerprint);
                    try writeValueRef(writer, after.output_ref);
                    try writeValueRef(writer, after.result_ref);
                    try writer.writeUsize(after.remaining);
                },
            }
        }

        fn readPending(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            frames: *const ActiveFrameStack,
            session_id: usize,
        ) anyerror!?Pending {
            if (!try reader.readBool()) return null;
            return switch (try reader.readU8()) {
                0 => blk: {
                    const function_index = try reader.readUsize();
                    const block_index = try reader.readUsize();
                    const instruction_index = try reader.readUsize();
                    const dst = try reader.readU16();
                    const op_index = try reader.readU16();
                    const operation_site_index = try reader.readUsize();
                    const stored_operation_fp = if (reader.canonical_values) null else try reader.readU64();
                    const turn_index = try reader.readUsize();
                    const payload_ref = try readValueRef(reader);
                    const payload_local_id = try reader.readU16();
                    var payload = try readExecutableImageValueForRef(reader, scratch, context, payload_ref, scratch.locals.items);
                    const stored_payload_fp = try reader.readU64();
                    const stored_request_fingerprint = if (reader.canonical_values) null else try reader.readU64();
                    const mode = try readControlMode(reader);
                    const resume_ref = try readValueRef(reader);
                    const result_ref = try readValueRef(reader);
                    const has_after = try reader.readBool();
                    const after_stack_entry = try readSessionAfterEntry(reader);
                    if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
                    if (instruction_index >= compiled_plan.instructions.len) return error.ProgramContractViolation;
                    const function = compiled_plan.functions[function_index];
                    const instruction = compiled_plan.instructions[instruction_index];
                    if (instruction.kind != .call_op or
                        instruction.operand != op_index or
                        instruction.dst != dst or
                        (dst != std.math.maxInt(u16) and dst >= function.local_count))
                    {
                        return error.ProgramContractViolation;
                    }
                    inline for (compiled_plan.ops, 0..) |op, index| {
                        if (op_index == index) {
                            const expected_payload_local_id = if (op.payload_codec == .unit) std.math.maxInt(u16) else instruction.aux;
                            const expected_payload_ref: program_plan.ValueRef = .{
                                .codec = op.payload_codec,
                                .schema_index = op.payload_schema_index,
                            };
                            const expected_resume_ref: program_plan.ValueRef = .{
                                .codec = op.resume_codec,
                                .schema_index = op.resume_schema_index,
                            };
                            if (!payload_ref.eql(expected_payload_ref) or
                                !resume_ref.eql(expected_resume_ref) or
                                mode != op.mode or
                                has_after != op.has_after or
                                payload_local_id != expected_payload_local_id or
                                !result_ref.eql(program_plan.functionResultRef(compiled_plan.functions[function_index])))
                            {
                                return error.ProgramContractViolation;
                            }
                            if (operation_site_index >= operation_yield_sites.len) return error.ProgramContractViolation;
                            const operation_site = operation_yield_sites[operation_site_index];
                            const operation_site_fingerprint = if (canonical_request_identity)
                                operation_site.canonical_fingerprint
                            else
                                operation_site.fingerprint;
                            if (operation_site.index != operation_site_index or
                                operation_site.function_index != function_index or
                                operation_site.block_index != block_index or
                                operation_site.instruction_index != instruction_index or
                                operation_site.op_index != op_index)
                            {
                                return error.ProgramContractViolation;
                            }
                            if (stored_operation_fp) |stored| {
                                if (stored != operation_site_fingerprint) return error.ProgramContractViolation;
                            }
                            const decoded_payload_fingerprint = try Self.fingerprintExecutableValueForRef(payload_ref, payload);
                            if (stored_payload_fp != decoded_payload_fingerprint) return error.ProgramContractViolation;
                            if (payload_local_id != std.math.maxInt(u16)) {
                                if (frames.len() == 0) return error.ProgramContractViolation;
                                const active_frame = frames.at(frames.len() - 1) orelse return error.ProgramContractViolation;
                                if (active_frame.function_index != function_index) return error.ProgramContractViolation;
                                const locals = scratch.frameLocals(active_frame.frame);
                                if (payload_local_id >= locals.len) return error.ProgramContractViolation;
                                const local_payload = locals[payload_local_id];
                                if (!(try Self.executableValuesEqualForRef(payload_ref, local_payload, payload))) {
                                    return error.ProgramContractViolation;
                                }
                                payload = local_payload;
                            }
                            const payload_value_fingerprint = decoded_payload_fingerprint;
                            const requirement = compiled_plan.requirements[op.requirement_index];
                            const request_fingerprint = Self.operationRequestFingerprint(
                                canonical_request_identity,
                                turn_index,
                                operation_site_index,
                                operation_site_fingerprint,
                                function_index,
                                block_index,
                                instruction_index,
                                op.requirement_index,
                                requirement.label,
                                op_index,
                                op.op_name,
                                mode,
                                payload_ref,
                                payload_value_fingerprint,
                                resume_ref,
                                result_ref,
                                has_after,
                            );
                            if (stored_request_fingerprint) |stored| {
                                if (stored != request_fingerprint) return error.ProgramContractViolation;
                            }
                            if (has_after) {
                                try validateSessionAfterEntryForOperationSite(after_stack_entry, op_index, operation_site_index);
                            } else if (after_stack_entry.op_index != op_index or
                                after_stack_entry.operation_site_index != 0 or
                                after_stack_entry.after_site_index != 0)
                            {
                                return error.ProgramContractViolation;
                            }
                            break :blk .{ .op = .{
                                .session_id = session_id,
                                .token = 0,
                                .function_index = function_index,
                                .block_index = block_index,
                                .instruction_index = instruction_index,
                                .dst = dst,
                                .op_index = op_index,
                                .operation_site_index = operation_site_index,
                                .operation_site_fingerprint = operation_site_fingerprint,
                                .turn_index = turn_index,
                                .payload_ref = payload_ref,
                                .payload_local_id = payload_local_id,
                                .payload = payload,
                                .payload_value_fingerprint = payload_value_fingerprint,
                                .request_fingerprint = request_fingerprint,
                                .mode = mode,
                                .resume_ref = resume_ref,
                                .result_ref = result_ref,
                                .has_after = has_after,
                                .after_stack_entry = after_stack_entry,
                            } };
                        }
                    }
                    return error.ProgramContractViolation;
                },
                1 => blk: {
                    const function_index = try reader.readUsize();
                    const block_index = try reader.readUsize();
                    const instruction_index = try reader.readUsize();
                    const op_index = try reader.readU16();
                    const after_site_index = try reader.readUsize();
                    const stored_after_site_fingerprint = if (reader.canonical_values) null else try reader.readU64();
                    const source_operation_site_index = try reader.readUsize();
                    const stored_source_site_fp = if (reader.canonical_values) null else try reader.readU64();
                    const turn_index = try reader.readUsize();
                    const value_ref = try readValueRef(reader);
                    const value = try readExecutableImageValueForRef(reader, scratch, context, value_ref, scratch.locals.items);
                    const stored_value_fingerprint = try reader.readU64();
                    const stored_request_fingerprint = if (reader.canonical_values) null else try reader.readU64();
                    const output_ref = try readValueRef(reader);
                    const result_ref = try readValueRef(reader);
                    const remaining = try reader.readUsize();
                    if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
                    inline for (compiled_plan.ops, 0..) |op, index| {
                        if (op_index == index) {
                            if (!op.has_after) return error.ProgramContractViolation;
                            if (after_site_index >= after_yield_sites.len) return error.ProgramContractViolation;
                            const after_site = after_yield_sites[after_site_index];
                            const after_site_fingerprint = if (canonical_request_identity)
                                after_site.canonical_fingerprint
                            else
                                after_site.fingerprint;
                            const source_op_site_fingerprint = if (canonical_request_identity)
                                after_site.source_operation_site_canonical_fingerprint
                            else
                                after_site.source_operation_site_fingerprint;
                            if (after_site.index != after_site_index or
                                after_site.source_operation_site_index != source_operation_site_index or
                                after_site.source_function_index != function_index or
                                after_site.source_block_index != block_index or
                                after_site.source_instruction_index != instruction_index or
                                after_site.original_op_index != op_index)
                            {
                                return error.ProgramContractViolation;
                            }
                            if (stored_after_site_fingerprint) |stored| {
                                if (stored != after_site_fingerprint) return error.ProgramContractViolation;
                            }
                            if (stored_source_site_fp) |stored| {
                                if (stored != source_op_site_fingerprint) return error.ProgramContractViolation;
                            }
                            if (remaining == 0) return error.ProgramContractViolation;
                            const expected_output_ref = try sessionAfterOutputRefByIndex(
                                compiled_plan,
                                schema_types,
                                HandlersType,
                                canonical_request_identity,
                                op_index,
                                value_ref,
                                remaining,
                                result_ref,
                            );
                            if (!output_ref.eql(expected_output_ref)) return error.ProgramContractViolation;
                            const value_fingerprint = try Self.fingerprintExecutableValueForRef(value_ref, value);
                            if (stored_value_fingerprint != value_fingerprint) return error.ProgramContractViolation;
                            const requirement = compiled_plan.requirements[op.requirement_index];
                            const request_fingerprint = Self.afterRequestFingerprint(
                                canonical_request_identity,
                                turn_index,
                                after_site_index,
                                after_site_fingerprint,
                                source_operation_site_index,
                                source_op_site_fingerprint,
                                function_index,
                                block_index,
                                instruction_index,
                                op.requirement_index,
                                requirement.label,
                                op_index,
                                op.op_name,
                                value_ref,
                                value_fingerprint,
                                output_ref,
                                result_ref,
                                remaining,
                            );
                            if (stored_request_fingerprint) |stored| {
                                if (stored != request_fingerprint) return error.ProgramContractViolation;
                            }
                            break :blk .{ .after = .{
                                .session_id = session_id,
                                .token = 0,
                                .function_index = function_index,
                                .block_index = block_index,
                                .instruction_index = instruction_index,
                                .op_index = op_index,
                                .after_site_index = after_site_index,
                                .after_site_fingerprint = after_site_fingerprint,
                                .source_operation_site_index = source_operation_site_index,
                                .source_operation_site_fingerprint = source_op_site_fingerprint,
                                .turn_index = turn_index,
                                .value = value,
                                .value_fingerprint = value_fingerprint,
                                .request_fingerprint = request_fingerprint,
                                .value_ref = value_ref,
                                .output_ref = output_ref,
                                .result_ref = result_ref,
                                .remaining = remaining,
                            } };
                        }
                    }
                    return error.ProgramContractViolation;
                },
                else => error.ProgramContractViolation,
            };
        }

        fn writeFrameLastReturn(
            writer: *DurableWriter,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            locals: []const ExecutableValue,
            value: ExecutableValue,
        ) anyerror!void {
            if (!valueMatchesRef(ref, value)) {
                if (value != .none) return error.ProgramContractViolation;
                try writer.writeU8(0);
                return;
            }
            if (!writer.canonical_values) {
                for (locals, 0..) |local, local_index| {
                    if (executableValuesShareIdentity(local, value)) {
                        try writer.writeU8(2);
                        try writer.writeUsize(local_index);
                        return;
                    }
                }
            }
            try writer.writeU8(1);
            try writeExecutableValueForRef(writer, context, ref, value);
        }

        fn readFrameLastReturn(
            reader: *DurableReader,
            scratch: *Scratch,
            context: *DurableValueImageContext,
            ref: program_plan.ValueRef,
            locals: []const ExecutableValue,
        ) anyerror!ExecutableValue {
            return switch (try reader.readU8()) {
                0 => blk: {
                    if (reader.canonical_values and ref.codec == .unit) return error.ProgramContractViolation;
                    break :blk .none;
                },
                1 => try readExecutableValueForRef(reader, scratch, context, ref),
                2 => blk: {
                    if (reader.canonical_values) return error.ProgramContractViolation;
                    const local_index = try reader.readUsize();
                    if (local_index >= locals.len) return error.ProgramContractViolation;
                    const value = locals[local_index];
                    if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
                    break :blk value;
                },
                else => error.ProgramContractViolation,
            };
        }

        fn writeCoreImage(writer: *DurableWriter, self: *const Self) anyerror!void {
            if (writer.canonical_values != canonical_request_identity) return error.ProgramContractViolation;
            var context = DurableValueImageContext.init(writer.allocator);
            defer context.deinit();

            try writer.writeUsize(self.remaining_steps);
            try writer.writeUsize(self.next_turn_index);
            try writer.writeBool(self.done_consumed);
            const after_entries = self.scratch.afterEntries();
            try writer.writeUsize(after_entries.len);
            for (after_entries) |entry_value| {
                try writeSessionAfterEntry(writer, entry_value);
            }

            try writer.writeUsize(self.frames.len());
            var frame_index: usize = 0;
            while (frame_index < self.frames.len()) : (frame_index += 1) {
                const frame = self.frames.at(frame_index) orelse return error.ProgramContractViolation;
                try writer.writeUsize(frame.function_index);
                try writer.writeUsize(frame.block_index);
                try writer.writeUsize(frame.instruction_index);
                try writer.writeUsize(frame.instruction_end);
                try writer.writeUsize(frame.frame.call_args_start);
                try writer.writeUsize(frame.frame.after_start);
                try writer.writeBool(frame.last_condition);
                try writer.writeBool(frame.waiting_helper_dst != null);
                if (frame.waiting_helper_dst) |dst| try writer.writeU16(dst);
                const function = compiled_plan.functions[frame.function_index];
                const last_return_ref = if (writer.canonical_values)
                    functionValueRef(function)
                else
                    program_plan.functionResultRef(function);
                const locals = self.scratch.frameLocalsConst(frame.frame);
                try writer.writeUsize(locals.len);
                for (locals, 0..) |value, local_index| {
                    const local_ref = localRefForFunctionIndex(compiled_plan, frame.function_index, @intCast(local_index)) orelse
                        return error.ProgramContractViolation;
                    try writeValueRef(writer, local_ref);
                    try writeMaybeExecutableImageValueForRef(
                        writer,
                        &context,
                        local_ref,
                        value,
                        self.scratch.locals.items[0 .. frame.frame.locals_start + local_index],
                    );
                }
                try writeFrameLastReturn(writer, &context, last_return_ref, locals, frame.last_return);
            }

            try writePending(writer, &context, self);
            try writer.writeBool(self.unwinding_after != null);
            if (self.unwinding_after) |unwind| {
                try writer.writeUsize(unwind.function_index);
                try writeValueRef(writer, unwind.current_ref);
                try writeExecutableImageValueForRef(writer, &context, unwind.current_ref, unwind.value, self.scratch.locals.items);
                try writeValueRef(writer, unwind.final_ref);
                try writer.writeUsize(unwind.remaining);
            }
        }

        fn readCoreImage(allocator: std.mem.Allocator, reader: *DurableReader) anyerror!Self {
            if (reader.canonical_values != canonical_request_identity) return error.ProgramContractViolation;
            var scratch = try Scratch.init(
                allocator,
                analysis.max_active_local_slots,
                analysis.max_active_call_arg_slots,
            );
            errdefer scratch.deinit();

            var frames = try ActiveFrameStack.init(allocator, analysis.max_active_frame_depth);
            errdefer frames.deinit(allocator);

            const remaining_steps = try reader.readUsize();
            if (remaining_steps > max_interpreter_steps) return error.ProgramContractViolation;

            var core: Self = .{
                .allocator = allocator,
                .scratch = scratch,
                .frames = frames,
                .session_id = try nextSessionId(),
                .remaining_steps = remaining_steps,
                .next_turn_index = try reader.readUsize(),
                .done_consumed = try reader.readBool(),
            };
            if (core.done_consumed) return error.ProgramContractViolation;
            scratch = .{ .allocator = allocator };
            frames = .{};
            errdefer core.deinit();

            var context = DurableValueImageContext.init(allocator);
            defer context.deinit();

            const after_stack_len = try reader.readUsize();
            if (after_stack_len > session_after_stack_capacity) return error.ProgramContractViolation;
            const after_stack_bytes = std.math.mul(usize, after_stack_len, 3 * @sizeOf(u16)) catch
                return error.ProgramContractViolation;
            if (reader.remaining() < after_stack_bytes) return error.ProgramContractViolation;
            const after_entries = try core.scratch.prepareAfterEntries(after_stack_len);
            for (after_entries) |*entry_value| {
                entry_value.* = try readSessionAfterEntry(reader);
                try validateSessionAfterEntry(entry_value.*);
            }

            const frame_count = try reader.readUsize();
            if (frame_count == 0 or frame_count > analysis.max_active_frame_depth) return error.ProgramContractViolation;
            for (0..frame_count) |_| {
                const function_index = try reader.readUsize();
                const block_index = try reader.readUsize();
                const instruction_index = try reader.readUsize();
                const instruction_end = try reader.readUsize();
                const call_args_start = try reader.readUsize();
                const after_start = try reader.readUsize();
                const last_condition = try reader.readBool();
                const waiting_helper_dst = if (try reader.readBool()) try reader.readU16() else null;
                if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
                const function = compiled_plan.functions[function_index];
                const expected_local_count: usize = function.local_count;
                if (block_index < function.first_block or block_index >= @as(usize, function.first_block) + function.block_count) return error.ProgramContractViolation;
                const bounds = try blockInstructionBounds(compiled_plan, function_index, block_index);
                if (instruction_end != bounds.end or instruction_index < bounds.first or instruction_index > instruction_end) return error.ProgramContractViolation;
                if (call_args_start > core.scratch.call_args.items.len) return error.ProgramContractViolation;
                if (after_start > core.scratch.afterEntries().len) return error.ProgramContractViolation;
                if (waiting_helper_dst) |dst| {
                    if (dst != std.math.maxInt(u16) and dst >= expected_local_count) return error.ProgramContractViolation;
                }
                const local_count = try reader.readUsize();
                if (local_count != expected_local_count) return error.ProgramContractViolation;
                const locals_start = core.scratch.locals.items.len;
                try core.scratch.locals.resize(core.scratch.allocator, locals_start + local_count);
                const locals = core.scratch.locals.items[locals_start..][0..local_count];
                for (locals, 0..) |*slot, local_index| {
                    const local_ref = localRefForFunctionIndex(compiled_plan, function_index, @intCast(local_index)) orelse
                        return error.ProgramContractViolation;
                    if (!(try readValueRef(reader)).eql(local_ref)) return error.ProgramContractViolation;
                    slot.* = try readMaybeExecutableImageValueForRef(
                        reader,
                        &core.scratch,
                        &context,
                        local_ref,
                        core.scratch.locals.items[0 .. locals_start + local_index],
                    );
                }
                const last_return_ref = if (reader.canonical_values)
                    functionValueRef(function)
                else
                    program_plan.functionResultRef(function);
                const last_return = try readFrameLastReturn(reader, &core.scratch, &context, last_return_ref, locals);
                try core.frames.append(core.allocator, .{
                    .function_index = function_index,
                    .frame = .{
                        .locals_start = locals_start,
                        .locals_len = local_count,
                        .call_args_start = call_args_start,
                        .after_start = after_start,
                    },
                    .block_index = block_index,
                    .instruction_index = instruction_index,
                    .instruction_end = instruction_end,
                    .last_return = last_return,
                    .last_condition = last_condition,
                    .waiting_helper_dst = waiting_helper_dst,
                });
            }
            try core.validateDecodedFrameStack();

            core.pending = try readPending(reader, &core.scratch, &context, &core.frames, core.session_id);
            if (try reader.readBool()) {
                const unwind_ownership_checkpoint = core.scratch.ownershipCheckpoint();
                const function_index = try reader.readUsize();
                const current_ref = try readValueRef(reader);
                const value = try readExecutableImageValueForRef(reader, &core.scratch, &context, current_ref, core.scratch.locals.items);
                core.unwinding_after = .{
                    .function_index = function_index,
                    .value = value,
                    .current_ref = current_ref,
                    .final_ref = try readValueRef(reader),
                    .remaining = try reader.readUsize(),
                };
                if (comptime !canonical_request_identity) {
                    // Legacy v1 preserves string/list roots through the value-image context, but has
                    // no schema-root backreference for the pending/unwind copies of one product or sum.
                    if (core.pending) |pending| switch (pending) {
                        .op => {},
                        .after => |pending_after| if (core.unwinding_after) |*unwind| {
                            if ((pending_after.value_ref.codec == .product or pending_after.value_ref.codec == .sum) and
                                unwind.current_ref.eql(pending_after.value_ref))
                            {
                                if (try Self.executableValuesEqualForRef(
                                    pending_after.value_ref,
                                    pending_after.value,
                                    unwind.value,
                                )) {
                                    core.scratch.rollbackOwned(unwind_ownership_checkpoint);
                                    unwind.value = pending_after.value;
                                }
                            }
                        },
                    };
                }
            }
            if (comptime !canonical_request_identity) try core.validateDecodedPendingState();

            return core;
        }

        fn validateDecodedFrameStack(self: *const Self) error{ProgramContractViolation}!void {
            const frame_count = self.frames.len();
            if (frame_count == 0 or frame_count > analysis.max_active_frame_depth) return error.ProgramContractViolation;
            var expected_locals_start: usize = 0;
            var frame_index: usize = 0;
            while (frame_index < frame_count) : (frame_index += 1) {
                const frame = self.frames.at(frame_index) orelse return error.ProgramContractViolation;
                if (frame.function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
                const function = compiled_plan.functions[frame.function_index];
                if (frame.frame.locals_start != expected_locals_start) return error.ProgramContractViolation;
                if (frame.frame.locals_len != function.local_count) return error.ProgramContractViolation;
                expected_locals_start = std.math.add(usize, expected_locals_start, frame.frame.locals_len) catch
                    return error.ProgramContractViolation;
                if (expected_locals_start > self.scratch.locals.items.len) return error.ProgramContractViolation;
                if (frame.frame.call_args_start > self.scratch.call_args.items.len) return error.ProgramContractViolation;
                if (frame.frame.after_start > self.scratch.afterEntries().len) return error.ProgramContractViolation;

                if (frame_index == 0) {
                    if (frame.function_index != compiled_plan.entry_index or frame.frame.after_start != 0) {
                        return error.ProgramContractViolation;
                    }
                } else {
                    const parent = self.frames.at(frame_index - 1) orelse return error.ProgramContractViolation;
                    if (frame.frame.call_args_start != parent.frame.call_args_start) return error.ProgramContractViolation;
                    if (frame.frame.after_start < parent.frame.after_start) return error.ProgramContractViolation;
                    try self.validateDecodedChildFrame(parent, frame);
                }
                if (comptime canonical_request_identity) try self.validateDecodedDerivedFrameCaches(frame);
            }
            if (expected_locals_start != self.scratch.locals.items.len) return error.ProgramContractViolation;
            const active = self.frames.at(frame_count - 1) orelse return error.ProgramContractViolation;
            if (active.waiting_helper_dst != null) return error.ProgramContractViolation;
        }

        fn validateDecodedDerivedFrameCaches(
            self: *const Self,
            frame: ActiveInterpreterFrame,
        ) error{ProgramContractViolation}!void {
            if (comptime compiled_plan.instructions.len == 0) return;
            const bounds = try blockInstructionBounds(compiled_plan, frame.function_index, frame.block_index);
            if (frame.instruction_index != bounds.end) return;
            const block = compiled_plan.blocks[frame.block_index];
            const terminator = compiled_plan.terminators[block.terminator_index];
            const locals = self.scratch.frameLocalsConst(frame.frame);

            switch (terminator.kind) {
                .branch_if => {
                    if (bounds.end == bounds.first) return error.ProgramContractViolation;
                    const instruction = compiled_plan.instructions[bounds.end - 1];
                    if (instruction.operand >= locals.len or instruction.dst >= locals.len) {
                        return error.ProgramContractViolation;
                    }
                    const stored = switch (locals[instruction.dst]) {
                        .bool => |value| value,
                        else => return error.ProgramContractViolation,
                    };
                    const expected = switch (instruction.kind) {
                        .compare_eq_zero => blk: {
                            if (instruction.dst == instruction.operand) break :blk frame.last_condition;
                            const operand_ref = localRefForFunctionIndex(
                                compiled_plan,
                                frame.function_index,
                                instruction.operand,
                            ) orelse return error.ProgramContractViolation;
                            break :blk switch (operand_ref.codec) {
                                .bool => switch (locals[instruction.operand]) {
                                    .bool => |value| !value,
                                    else => return error.ProgramContractViolation,
                                },
                                .i32 => switch (locals[instruction.operand]) {
                                    .i32 => |value| value == 0,
                                    else => return error.ProgramContractViolation,
                                },
                                .usize => (try executableWordU64(locals[instruction.operand])) == 0,
                                else => return error.ProgramContractViolation,
                            };
                        },
                        .sum_variant_is => (try activeVariantOrdinalForExecutable(
                            schema_types,
                            locals[instruction.operand],
                        )) == instruction.aux,
                        else => return error.ProgramContractViolation,
                    };
                    if (stored != expected or frame.last_condition != expected) {
                        return error.ProgramContractViolation;
                    }
                },
                .return_value => {
                    if (bounds.end == bounds.first) return error.ProgramContractViolation;
                    const instruction = compiled_plan.instructions[bounds.end - 1];
                    if (instruction.kind != .return_value or instruction.operand >= locals.len) {
                        return error.ProgramContractViolation;
                    }
                    const value_ref = functionValueRef(compiled_plan.functions[frame.function_index]);
                    if (!(try Self.executableValuesEqualForRef(
                        value_ref,
                        locals[instruction.operand],
                        frame.last_return,
                    ))) return error.ProgramContractViolation;
                },
                .jump, .return_unit => {},
            }
        }

        fn validateDecodedChildFrame(self: *const Self, parent: ActiveInterpreterFrame, child: ActiveInterpreterFrame) error{ProgramContractViolation}!void {
            if (comptime compiled_plan.instructions.len == 0) return error.ProgramContractViolation;
            const dst = parent.waiting_helper_dst orelse return error.ProgramContractViolation;
            const parent_bounds = try blockInstructionBounds(compiled_plan, parent.function_index, parent.block_index);
            if (parent.instruction_index <= parent_bounds.first or parent.instruction_index > parent_bounds.end) return error.ProgramContractViolation;
            const call_instruction_index = parent.instruction_index - 1;
            const instruction = compiled_plan.instructions[call_instruction_index];
            if (instruction.dst != dst) return error.ProgramContractViolation;
            switch (instruction.kind) {
                .call_helper => {
                    if (instruction.operand >= compiled_plan.functions.len) return error.ProgramContractViolation;
                    if (child.function_index != instruction.operand) return error.ProgramContractViolation;
                    const callee = compiled_plan.functions[instruction.operand];
                    if (callee.parameter_count > child.frame.locals_len) return error.ProgramContractViolation;
                    if (callee.parameter_count != 0) {
                        if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                        const parent_function = compiled_plan.functions[parent.function_index];
                        const parent_locals = self.scratch.frameLocalsConst(parent.frame);
                        const child_locals = self.scratch.frameLocalsConst(child.frame);
                        var arg_index: usize = 0;
                        while (arg_index < callee.parameter_count) : (arg_index += 1) {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (local_id >= parent_function.local_count) return error.ProgramContractViolation;
                            const parent_ref = localRefForFunctionIndex(compiled_plan, parent.function_index, local_id) orelse
                                return error.ProgramContractViolation;
                            const child_ref = localRefForFunctionIndex(compiled_plan, child.function_index, @intCast(arg_index)) orelse
                                return error.ProgramContractViolation;
                            if (!parent_ref.eql(child_ref)) return error.ProgramContractViolation;
                            if (local_id >= parent_locals.len or arg_index >= child_locals.len) return error.ProgramContractViolation;
                            try validateDecodedArgumentValue(
                                parent_ref,
                                parent_locals[local_id],
                                child_locals[arg_index],
                            );
                        }
                    }
                },
                .call_nested_with => {
                    const target_index = nestedTargetIndexForInstruction(call_instruction_index) orelse
                        return error.ProgramContractViolation;
                    if (child.function_index != target_index) return error.ProgramContractViolation;
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) return error.ProgramContractViolation;
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch return error.ProgramContractViolation;
                    if (result_codec != .unit and dst == std.math.maxInt(u16)) return error.ProgramContractViolation;
                },
                else => return error.ProgramContractViolation,
            }
        }

        fn nestedTargetIndexForInstruction(instruction_index: usize) ?usize {
            if (instruction_index >= compiled_plan.instructions.len) return null;
            if (comptime canonical_request_identity) {
                if (instruction_index >= control_instruction_metadata.len) return null;
                const encoded_target_index =
                    control_instruction_metadata[instruction_index].nested_target_index;
                if (encoded_target_index == invalid_control_metadata_index) return null;
                const target_index: usize = encoded_target_index;
                if (target_index >= compiled_plan.functions.len) return null;
                return target_index;
            }
            const instruction = compiled_plan.instructions[instruction_index];
            if (instruction.kind != .call_nested_with) return null;
            return nestedWithTargetIndexForMetadata(
                compiled_plan,
                nested_with_targets,
                instruction.string_literal,
            );
        }

        fn controlNodeForBlockStart(block_index: usize) error{ProgramContractViolation}!usize {
            if (block_index >= compiled_plan.blocks.len) return error.ProgramContractViolation;
            const block = compiled_plan.blocks[block_index];
            return if (block.instruction_count == 0)
                compiled_plan.instructions.len + block_index
            else
                block.first_instruction;
        }

        fn controlNodeForCursor(
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
        ) error{ProgramContractViolation}!usize {
            const bounds = try blockInstructionBounds(compiled_plan, function_index, block_index);
            if (instruction_index < bounds.first or instruction_index > bounds.end) {
                return error.ProgramContractViolation;
            }
            return if (instruction_index == bounds.end)
                compiled_plan.instructions.len + block_index
            else
                instruction_index;
        }

        fn blockIndexForInstruction(function_index: usize, instruction_index: usize) ?usize {
            if (function_index >= compiled_plan.functions.len or
                instruction_index >= control_instruction_metadata.len)
            {
                return null;
            }
            const function = compiled_plan.functions[function_index];
            const block_end = @as(usize, function.first_block) + function.block_count;
            const encoded_block_index = control_instruction_metadata[instruction_index].block_index;
            if (encoded_block_index == invalid_control_metadata_index) return null;
            const block_index: usize = encoded_block_index;
            if (block_index < function.first_block or block_index >= block_end) return null;
            return block_index;
        }

        fn instructionForRuntimeIndex(instruction_index: usize) ?program_plan.Instruction {
            inline for (compiled_plan.instructions, 0..) |instruction, candidate_index| {
                if (instruction_index == candidate_index) return instruction;
            }
            return null;
        }

        fn enqueueControlPathState(
            queue: *[control_path_state_capacity]ControlPathStateIndex,
            queue_len: *usize,
            visited: *ControlPathVisited,
            state: ControlPathState,
        ) error{ProgramContractViolation}!void {
            if (state.node >= control_node_count or
                state.predicate_slot >= control_predicate_slot_count or
                (condition_validity_count == 1 and state.source_valid))
            {
                return error.ProgramContractViolation;
            }
            const authority_index =
                (state.predicate_slot * 2 + @intFromBool(state.condition_matches_reference)) *
                condition_validity_count +
                @intFromBool(state.source_valid);
            const state_index =
                (state.node * 2 + @intFromBool(state.traversed_allowed_suspension)) *
                condition_authority_count +
                authority_index;
            if (visited.isSet(state_index)) return;
            if (queue_len.* >= queue.len) return error.ProgramContractViolation;
            visited.set(state_index);
            queue[queue_len.*] = @intCast(state_index);
            queue_len.* += 1;
        }

        fn conditionAuthorityIndex(
            predicate_slot: usize,
            condition_matches_reference: bool,
            source_valid: bool,
        ) error{ProgramContractViolation}!usize {
            if (predicate_slot >= control_predicate_slot_count or
                (condition_validity_count == 1 and source_valid))
            {
                return error.ProgramContractViolation;
            }
            return (predicate_slot * 2 + @intFromBool(condition_matches_reference)) *
                condition_validity_count +
                @intFromBool(source_valid);
        }

        fn conditionAuthorityContainsReference(
            authority: ControlConditionAuthority,
        ) bool {
            var predicate_slot: usize = 0;
            while (predicate_slot < control_predicate_slot_count) : (predicate_slot += 1) {
                var validity_index: usize = 0;
                while (validity_index < condition_validity_count) : (validity_index += 1) {
                    const authority_index =
                        (predicate_slot * 2 + 1) * condition_validity_count +
                        validity_index;
                    if (authority.isSet(authority_index)) return true;
                }
            }
            return false;
        }

        fn advanceConditionAuthority(
            function_index: usize,
            instruction: program_plan.Instruction,
            authority: ControlConditionAuthority,
        ) error{ProgramContractViolation}!ControlConditionAuthority {
            if (comptime !canonical_request_identity) return authority;
            var result = ControlConditionAuthority.initEmpty();
            var authority_index: usize = 0;
            while (authority_index < condition_authority_count) : (authority_index += 1) {
                if (!authority.isSet(authority_index)) continue;
                var encoded_authority = authority_index;
                var source_valid = encoded_authority % condition_validity_count != 0;
                encoded_authority /= condition_validity_count;
                const condition_matches_reference = encoded_authority % 2 != 0;
                const predicate_slot = encoded_authority / 2;
                if (predicate_slot != 0 and source_valid) {
                    const predicate = staticMachineConditionPredicateForRuntimeFunctionIndex(
                        compiled_plan,
                        function_index,
                        predicate_slot - 1,
                    ) orelse return error.ProgramContractViolation;
                    if (staticMachineInstructionMayWriteLocal(instruction, predicate.operand)) {
                        source_valid = false;
                    }
                }
                result.set(try conditionAuthorityIndex(
                    predicate_slot,
                    condition_matches_reference,
                    source_valid,
                ));
            }
            return result;
        }

        fn controlPathExistsWithoutUnrecordedAfter(
            budget: *ControlValidationBudget,
            function_index: usize,
            start_node: usize,
            target_node: usize,
            allowed_suspended_instruction: ?usize,
            condition_reference: bool,
            initial_condition_authority: ControlConditionAuthority,
        ) error{ProgramContractViolation}!ControlConditionAuthority {
            if (control_node_count == 0 or start_node >= control_node_count or target_node >= control_node_count) {
                return error.ProgramContractViolation;
            }
            if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
            const function = compiled_plan.functions[function_index];
            const function_block_end = @as(usize, function.first_block) + function.block_count;

            var queue: [control_path_state_capacity]ControlPathStateIndex = undefined;
            var visited = ControlPathVisited.initEmpty();
            var queue_len: usize = 0;
            var queue_index: usize = 0;
            var authority_index: usize = 0;
            while (authority_index < condition_authority_count) : (authority_index += 1) {
                if (!initial_condition_authority.isSet(authority_index)) continue;
                var encoded_authority = authority_index;
                const source_valid = if (condition_validity_count == 1)
                    false
                else blk: {
                    const valid = encoded_authority % condition_validity_count != 0;
                    encoded_authority /= condition_validity_count;
                    break :blk valid;
                };
                const condition_matches_reference = encoded_authority % 2 != 0;
                const predicate_slot = encoded_authority / 2;
                try enqueueControlPathState(&queue, &queue_len, &visited, .{
                    .node = start_node,
                    .traversed_allowed_suspension = allowed_suspended_instruction == null,
                    .predicate_slot = predicate_slot,
                    .condition_matches_reference = condition_matches_reference,
                    .source_valid = source_valid,
                });
            }

            var result_condition_authority = ControlConditionAuthority.initEmpty();

            while (queue_index < queue_len) : (queue_index += 1) {
                try budget.consume();
                var encoded_state: usize = @intCast(queue[queue_index]);
                var encoded_authority = encoded_state % condition_authority_count;
                encoded_state /= condition_authority_count;
                const source_valid = if (condition_validity_count == 1)
                    false
                else blk: {
                    const valid = encoded_authority % condition_validity_count != 0;
                    encoded_authority /= condition_validity_count;
                    break :blk valid;
                };
                const state: ControlPathState = .{
                    .node = encoded_state / 2,
                    .traversed_allowed_suspension = encoded_state % 2 != 0,
                    .predicate_slot = encoded_authority / 2,
                    .condition_matches_reference = encoded_authority % 2 != 0,
                    .source_valid = source_valid,
                };
                const node = state.node;
                if (node == target_node) {
                    if (state.traversed_allowed_suspension) {
                        result_condition_authority.set(try conditionAuthorityIndex(
                            state.predicate_slot,
                            state.condition_matches_reference,
                            state.source_valid,
                        ));
                    }
                    continue;
                }

                if (node < compiled_plan.instructions.len) {
                    const block_index = blockIndexForInstruction(function_index, node) orelse
                        return error.ProgramContractViolation;
                    const instruction = compiled_plan.instructions[node];
                    const is_allowed_suspension = allowed_suspended_instruction != null and
                        allowed_suspended_instruction.? == node;
                    switch (instruction.kind) {
                        .return_error => continue,
                        .call_helper => {
                            if (instruction.operand >= compiled_plan.functions.len) return error.ProgramContractViolation;
                            if (!is_allowed_suspension and !analysis.completion_functions[instruction.operand]) continue;
                        },
                        .call_nested_with => {
                            const target_index = nestedTargetIndexForInstruction(node) orelse
                                return error.ProgramContractViolation;
                            if (!is_allowed_suspension and !analysis.completion_functions[target_index]) continue;
                        },
                        .call_op => {
                            if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                            const op = compiled_plan.ops[instruction.operand];
                            if (!is_allowed_suspension and (op.has_after or op.mode == .abort)) continue;
                        },
                        else => {},
                    }
                    const block = compiled_plan.blocks[block_index];
                    const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
                    const next_node = if (node + 1 == instruction_end)
                        compiled_plan.instructions.len + block_index
                    else
                        node + 1;
                    const traversed_allowed_suspension = state.traversed_allowed_suspension or is_allowed_suspension;
                    if (comptime canonical_request_identity) {
                        if (staticMachineConditionPredicateForInstruction(instruction)) |predicate| {
                            const predicate_index = staticMachineConditionPredicateIndexForRuntimeFunction(
                                compiled_plan,
                                function_index,
                                predicate,
                            ) orelse return error.ProgramContractViolation;
                            const predicate_source_valid = !staticMachineInstructionMayWriteLocal(
                                instruction,
                                predicate.operand,
                            );
                            if (state.predicate_slot == predicate_index + 1 and state.source_valid) {
                                try enqueueControlPathState(&queue, &queue_len, &visited, .{
                                    .node = next_node,
                                    .traversed_allowed_suspension = traversed_allowed_suspension,
                                    .predicate_slot = predicate_index + 1,
                                    .condition_matches_reference = state.condition_matches_reference,
                                    .source_valid = predicate_source_valid,
                                });
                            } else {
                                try enqueueControlPathState(&queue, &queue_len, &visited, .{
                                    .node = next_node,
                                    .traversed_allowed_suspension = traversed_allowed_suspension,
                                    .predicate_slot = predicate_index + 1,
                                    .condition_matches_reference = false,
                                    .source_valid = predicate_source_valid,
                                });
                                try enqueueControlPathState(&queue, &queue_len, &visited, .{
                                    .node = next_node,
                                    .traversed_allowed_suspension = traversed_allowed_suspension,
                                    .predicate_slot = predicate_index + 1,
                                    .condition_matches_reference = true,
                                    .source_valid = predicate_source_valid,
                                });
                            }
                        } else {
                            var next_state = state;
                            next_state.node = next_node;
                            next_state.traversed_allowed_suspension = traversed_allowed_suspension;
                            if (state.predicate_slot != 0) {
                                const predicate = staticMachineConditionPredicateForRuntimeFunctionIndex(
                                    compiled_plan,
                                    function_index,
                                    state.predicate_slot - 1,
                                ) orelse return error.ProgramContractViolation;
                                if (staticMachineInstructionMayWriteLocal(instruction, predicate.operand)) {
                                    next_state.source_valid = false;
                                }
                            }
                            try enqueueControlPathState(&queue, &queue_len, &visited, next_state);
                        }
                    } else switch (instruction.kind) {
                        .compare_eq_zero, .sum_variant_is => {
                            try enqueueControlPathState(&queue, &queue_len, &visited, .{
                                .node = next_node,
                                .traversed_allowed_suspension = traversed_allowed_suspension,
                                .predicate_slot = 0,
                                .condition_matches_reference = false,
                                .source_valid = false,
                            });
                            try enqueueControlPathState(&queue, &queue_len, &visited, .{
                                .node = next_node,
                                .traversed_allowed_suspension = traversed_allowed_suspension,
                                .predicate_slot = 0,
                                .condition_matches_reference = true,
                                .source_valid = false,
                            });
                        },
                        else => try enqueueControlPathState(&queue, &queue_len, &visited, .{
                            .node = next_node,
                            .traversed_allowed_suspension = traversed_allowed_suspension,
                            .predicate_slot = 0,
                            .condition_matches_reference = state.condition_matches_reference,
                            .source_valid = false,
                        }),
                    }
                    continue;
                }

                const block_index = node - compiled_plan.instructions.len;
                if (block_index < function.first_block or block_index >= function_block_end) {
                    return error.ProgramContractViolation;
                }
                const block = compiled_plan.blocks[block_index];
                const terminator = compiled_plan.terminators[block.terminator_index];
                switch (terminator.kind) {
                    .branch_if => {
                        const condition = if (state.condition_matches_reference)
                            condition_reference
                        else
                            !condition_reference;
                        try enqueueControlPathState(
                            &queue,
                            &queue_len,
                            &visited,
                            .{
                                .node = try controlNodeForBlockStart(
                                    if (condition) terminator.primary else terminator.secondary,
                                ),
                                .traversed_allowed_suspension = state.traversed_allowed_suspension,
                                .predicate_slot = state.predicate_slot,
                                .condition_matches_reference = state.condition_matches_reference,
                                .source_valid = state.source_valid,
                            },
                        );
                    },
                    .jump => try enqueueControlPathState(
                        &queue,
                        &queue_len,
                        &visited,
                        .{
                            .node = try controlNodeForBlockStart(terminator.primary),
                            .traversed_allowed_suspension = state.traversed_allowed_suspension,
                            .predicate_slot = state.predicate_slot,
                            .condition_matches_reference = state.condition_matches_reference,
                            .source_valid = state.source_valid,
                        },
                    ),
                    .return_unit, .return_value => {},
                }
            }
            return result_condition_authority;
        }

        fn validateControlPathWithoutUnrecordedAfter(
            budget: *ControlValidationBudget,
            function_index: usize,
            start_node: usize,
            target_node: usize,
            allowed_suspended_instruction: ?usize,
        ) error{ProgramContractViolation}!void {
            const condition_reference = false;
            const condition_matches_reference = true;
            const source_valid = false;
            var initial_condition_authority = ControlConditionAuthority.initEmpty();
            initial_condition_authority.set(try conditionAuthorityIndex(
                0,
                condition_matches_reference,
                source_valid,
            ));
            const final_condition_authority = try controlPathExistsWithoutUnrecordedAfter(
                budget,
                function_index,
                start_node,
                target_node,
                allowed_suspended_instruction,
                condition_reference,
                initial_condition_authority,
            );
            if (final_condition_authority.count() == 0) return error.ProgramContractViolation;
        }

        fn instructionReadsLocal(
            function_index: usize,
            instruction_index: usize,
            local_index: u16,
        ) error{ProgramContractViolation}!bool {
            if (instruction_index >= compiled_plan.instructions.len or
                function_index >= compiled_plan.functions.len)
            {
                return error.ProgramContractViolation;
            }
            const instruction = compiled_plan.instructions[instruction_index];
            return switch (instruction.kind) {
                .add_const_i32,
                .compare_eq_zero,
                .product_extract_field,
                .sub_one,
                .sum_extract_payload,
                .sum_variant_is,
                .return_value,
                => instruction.operand == local_index,
                .add_i32 => instruction.operand == local_index or instruction.aux == local_index,
                .call_helper => blk: {
                    if (instruction.operand >= compiled_plan.functions.len) return error.ProgramContractViolation;
                    const callee = compiled_plan.functions[instruction.operand];
                    if (callee.parameter_count == 0) break :blk false;
                    if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                    for (0..callee.parameter_count) |arg_index| {
                        const call_arg_index = std.math.add(usize, instruction.aux, arg_index) catch
                            return error.ProgramContractViolation;
                        if (planCallArgAt(compiled_plan, call_arg_index) == local_index) break :blk true;
                    }
                    break :blk false;
                },
                .call_op => blk: {
                    if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                    const op = compiled_plan.ops[instruction.operand];
                    break :blk op.payload_codec != .unit and instruction.aux == local_index;
                },
                .call_nested_with,
                .const_i32,
                .const_string,
                .const_usize,
                .return_error,
                => false,
            };
        }

        fn instructionDefinesLocalOnFutureContinuation(
            function_index: usize,
            instruction_index: usize,
            local_index: u16,
        ) error{ProgramContractViolation}!bool {
            if (instruction_index >= compiled_plan.instructions.len or
                function_index >= compiled_plan.functions.len)
            {
                return error.ProgramContractViolation;
            }
            const instruction = compiled_plan.instructions[instruction_index];
            if (instruction.dst != local_index or instruction.dst == std.math.maxInt(u16)) return false;
            return switch (instruction.kind) {
                .add_const_i32,
                .add_i32,
                .compare_eq_zero,
                .const_i32,
                .const_string,
                .const_usize,
                .product_extract_field,
                .sub_one,
                .sum_extract_payload,
                .sum_variant_is,
                => true,
                .call_helper => blk: {
                    if (instruction.operand >= effective_completion_refs.len) return error.ProgramContractViolation;
                    break :blk effective_completion_refs[instruction.operand].codec != .unit;
                },
                .call_nested_with => blk: {
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch
                        return error.ProgramContractViolation;
                    break :blk result_codec != .unit;
                },
                .call_op => blk: {
                    if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                    const op = compiled_plan.ops[instruction.operand];
                    break :blk op.mode != .abort and op.resume_codec != .unit;
                },
                .return_error, .return_value => false,
            };
        }

        fn enqueueControlNode(
            queue: *[control_node_capacity]ControlNodeIndex,
            queue_len: *usize,
            visited: *ControlNodeVisited,
            node: usize,
        ) error{ProgramContractViolation}!void {
            if (node >= control_node_count) return error.ProgramContractViolation;
            if (visited.isSet(node)) return;
            if (queue_len.* >= queue.len) return error.ProgramContractViolation;
            visited.set(node);
            queue[queue_len.*] = @intCast(node);
            queue_len.* += 1;
        }

        fn pendingSecuresLocal(
            self: *const Self,
            frame_index: usize,
            local_index: u16,
        ) error{ProgramContractViolation}!bool {
            const frame = self.frames.at(frame_index) orelse return error.ProgramContractViolation;
            if (frame_index + 1 < self.frames.len()) {
                const child = self.frames.at(frame_index + 1) orelse return error.ProgramContractViolation;
                if (child.function_index >= analysis.completion_functions.len) {
                    return error.ProgramContractViolation;
                }
                if (!analysis.completion_functions[child.function_index]) return true;
                if (frame.waiting_helper_dst == null or frame.waiting_helper_dst.? != local_index) return false;
                if (frame.instruction_index == 0) return error.ProgramContractViolation;
                return instructionDefinesLocalOnFutureContinuation(
                    frame.function_index,
                    frame.instruction_index - 1,
                    local_index,
                );
            }
            const pending = self.pending orelse return false;
            return switch (pending) {
                .op => |pending_op| pending_op.function_index == frame.function_index and
                    (pending_op.mode == .abort or
                        (pending_op.dst == local_index and pending_op.resume_ref.codec != .unit)),
                .after => false,
            };
        }

        fn validateAbsentLocalBeforeUse(
            self: *const Self,
            budget: *ControlValidationBudget,
            frame_index: usize,
            local_index: u16,
        ) error{ProgramContractViolation}!void {
            if (try self.pendingSecuresLocal(frame_index, local_index)) return;
            const frame = self.frames.at(frame_index) orelse return error.ProgramContractViolation;
            if (frame.function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
            const function = compiled_plan.functions[frame.function_index];
            const function_block_end = @as(usize, function.first_block) + function.block_count;
            const cursor_node = try controlNodeForCursor(
                frame.function_index,
                frame.block_index,
                frame.instruction_index,
            );

            var queue: [control_node_capacity]ControlNodeIndex = undefined;
            var visited = ControlNodeVisited.initEmpty();
            var queue_len: usize = 0;
            var queue_index: usize = 0;
            if (cursor_node < compiled_plan.instructions.len) {
                try enqueueControlNode(&queue, &queue_len, &visited, cursor_node);
            } else {
                const block_index = cursor_node - compiled_plan.instructions.len;
                if (block_index < function.first_block or block_index >= function_block_end) {
                    return error.ProgramContractViolation;
                }
                const terminator = compiled_plan.terminators[compiled_plan.blocks[block_index].terminator_index];
                switch (terminator.kind) {
                    .branch_if => try enqueueControlNode(
                        &queue,
                        &queue_len,
                        &visited,
                        try controlNodeForBlockStart(
                            if (frame.last_condition) terminator.primary else terminator.secondary,
                        ),
                    ),
                    .jump => try enqueueControlNode(
                        &queue,
                        &queue_len,
                        &visited,
                        try controlNodeForBlockStart(terminator.primary),
                    ),
                    .return_unit, .return_value => return,
                }
            }

            while (queue_index < queue_len) : (queue_index += 1) {
                try budget.consume();
                const node: usize = @intCast(queue[queue_index]);
                if (node < compiled_plan.instructions.len) {
                    const block_index = blockIndexForInstruction(frame.function_index, node) orelse
                        return error.ProgramContractViolation;
                    const instruction = compiled_plan.instructions[node];
                    if (try instructionReadsLocal(frame.function_index, node, local_index)) {
                        return error.ProgramContractViolation;
                    }
                    switch (instruction.kind) {
                        .call_helper => {
                            if (instruction.operand >= compiled_plan.functions.len) return error.ProgramContractViolation;
                            if (!analysis.completion_functions[instruction.operand]) continue;
                        },
                        .call_nested_with => {
                            const target_index = nestedTargetIndexForInstruction(node) orelse
                                return error.ProgramContractViolation;
                            if (!analysis.completion_functions[target_index]) continue;
                        },
                        .call_op => continue,
                        else => {},
                    }
                    if (try instructionDefinesLocalOnFutureContinuation(
                        frame.function_index,
                        node,
                        local_index,
                    )) continue;
                    switch (instruction.kind) {
                        .return_error => continue,
                        else => {},
                    }
                    const block = compiled_plan.blocks[block_index];
                    const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
                    try enqueueControlNode(
                        &queue,
                        &queue_len,
                        &visited,
                        if (node + 1 == instruction_end)
                            compiled_plan.instructions.len + block_index
                        else
                            node + 1,
                    );
                    continue;
                }

                const block_index = node - compiled_plan.instructions.len;
                if (block_index < function.first_block or block_index >= function_block_end) {
                    return error.ProgramContractViolation;
                }
                const terminator = compiled_plan.terminators[compiled_plan.blocks[block_index].terminator_index];
                switch (terminator.kind) {
                    .branch_if => {
                        try enqueueControlNode(
                            &queue,
                            &queue_len,
                            &visited,
                            try controlNodeForBlockStart(terminator.primary),
                        );
                        try enqueueControlNode(
                            &queue,
                            &queue_len,
                            &visited,
                            try controlNodeForBlockStart(terminator.secondary),
                        );
                    },
                    .jump => try enqueueControlNode(
                        &queue,
                        &queue_len,
                        &visited,
                        try controlNodeForBlockStart(terminator.primary),
                    ),
                    .return_unit, .return_value => {},
                }
            }
        }

        fn validateDecodedFrameControlPath(
            self: *Self,
            budget: *ControlValidationBudget,
            frame_index: usize,
        ) error{ProgramContractViolation}!void {
            const frame = self.frames.at(frame_index) orelse return error.ProgramContractViolation;
            const function = compiled_plan.functions[frame.function_index];
            const entry_block = @as(usize, function.first_block) + function.entry_block;
            var segment_start = try controlNodeForBlockStart(entry_block);
            const source_valid = false;
            var condition_authority = ControlConditionAuthority.initEmpty();
            condition_authority.set(try conditionAuthorityIndex(
                0,
                !frame.last_condition,
                source_valid,
            ));

            const after_end = if (frame_index + 1 < self.frames.len()) blk: {
                const child = self.frames.at(frame_index + 1) orelse return error.ProgramContractViolation;
                break :blk child.frame.after_start;
            } else self.scratch.afterEntries().len;
            if (frame.frame.after_start > after_end or after_end > self.scratch.afterEntries().len) {
                return error.ProgramContractViolation;
            }
            const entries = self.scratch.afterEntries()[frame.frame.after_start..after_end];
            for (entries) |entry_value| {
                try validateSessionAfterEntry(entry_value);
                const after_site = afterSiteAt(entry_value.after_site_index) orelse
                    return error.ProgramContractViolation;
                if (after_site.source_function_index != frame.function_index) {
                    return error.ProgramContractViolation;
                }
                const site_node = try controlNodeForCursor(
                    frame.function_index,
                    after_site.source_block_index,
                    after_site.source_instruction_index,
                );
                condition_authority = try controlPathExistsWithoutUnrecordedAfter(
                    budget,
                    frame.function_index,
                    segment_start,
                    site_node,
                    null,
                    frame.last_condition,
                    condition_authority,
                );
                if (condition_authority.count() == 0) return error.ProgramContractViolation;
                const site_instruction = instructionForRuntimeIndex(
                    after_site.source_instruction_index,
                ) orelse return error.ProgramContractViolation;
                condition_authority = try advanceConditionAuthority(
                    frame.function_index,
                    site_instruction,
                    condition_authority,
                );
                segment_start = site_node + 1;
                const site_block = compiled_plan.blocks[after_site.source_block_index];
                const site_instruction_end = @as(usize, site_block.first_instruction) + site_block.instruction_count;
                if (segment_start == site_instruction_end) {
                    segment_start = compiled_plan.instructions.len + after_site.source_block_index;
                }
            }

            const is_active_frame = frame_index + 1 == self.frames.len();
            var allowed_suspended_instruction: ?usize = null;
            if (!is_active_frame) {
                if (frame.instruction_index == 0 or frame.waiting_helper_dst == null) {
                    return error.ProgramContractViolation;
                }
                allowed_suspended_instruction = frame.instruction_index - 1;
            } else if (self.pending) |pending| switch (pending) {
                .op => |pending_op| allowed_suspended_instruction = pending_op.instruction_index,
                .after => {},
            };
            const cursor_node = try controlNodeForCursor(
                frame.function_index,
                frame.block_index,
                frame.instruction_index,
            );
            condition_authority = try controlPathExistsWithoutUnrecordedAfter(
                budget,
                frame.function_index,
                segment_start,
                cursor_node,
                allowed_suspended_instruction,
                frame.last_condition,
                condition_authority,
            );
            if (!conditionAuthorityContainsReference(condition_authority)) {
                return error.ProgramContractViolation;
            }
        }

        fn validateDecodedAfterStackReachability(
            self: *Self,
            budget: *ControlValidationBudget,
        ) error{ProgramContractViolation}!void {
            var frame_index: usize = 0;
            while (frame_index < self.frames.len()) : (frame_index += 1) {
                try self.validateDecodedFrameControlPath(budget, frame_index);
            }
        }

        fn validateDecodedLocalPresence(
            self: *Self,
            budget: *ControlValidationBudget,
        ) error{ProgramContractViolation}!void {
            var frame_index: usize = 0;
            while (frame_index < self.frames.len()) : (frame_index += 1) {
                const frame = self.frames.at(frame_index) orelse return error.ProgramContractViolation;
                const function = compiled_plan.functions[frame.function_index];
                const locals = self.scratch.frameLocalsConst(frame.frame);
                local_presence: for (locals, 0..) |value, local_index| {
                    if (value != .none) continue :local_presence;
                    const local_ref = localRefForFunctionIndex(
                        compiled_plan,
                        frame.function_index,
                        @intCast(local_index),
                    ) orelse return error.ProgramContractViolation;
                    if (local_ref.codec == .unit) continue :local_presence;
                    if (local_index < function.parameter_count) return error.ProgramContractViolation;
                    try self.validateAbsentLocalBeforeUse(
                        budget,
                        frame_index,
                        @intCast(local_index),
                    );
                }
            }
        }

        fn validateDecodedArgumentValue(
            ref: program_plan.ValueRef,
            parent_value: ExecutableValue,
            child_value: ExecutableValue,
        ) error{ProgramContractViolation}!void {
            if (comptime canonical_request_identity) {
                if (!(try Self.executableValuesEqualForRef(ref, parent_value, child_value))) {
                    return error.ProgramContractViolation;
                }
                return;
            }
            const parent_fingerprint = try Self.fingerprintExecutableValueForRef(ref, parent_value);
            const child_fingerprint = try Self.fingerprintExecutableValueForRef(ref, child_value);
            if (parent_fingerprint != child_fingerprint) return error.ProgramContractViolation;
            if (comptime !canonical_request_identity) {
                switch (ref.codec) {
                    .unit, .bool, .i32, .usize => {},
                    .string, .string_list, .product, .sum => {
                        if (!executableValuesShareIdentity(parent_value, child_value)) {
                            return error.ProgramContractViolation;
                        }
                    },
                }
            }
        }

        fn validateDecodedPendingState(self: *Self) error{ProgramContractViolation}!void {
            var control_validation_budget: ControlValidationBudget = .{};
            if (comptime canonical_request_identity) {
                if (self.pending) |pending| switch (pending) {
                    .op => |pending_op| if (pending_op.has_after and
                        self.scratch.afterEntries().len >= session_after_stack_capacity)
                    {
                        return error.ProgramContractViolation;
                    },
                    .after => {},
                };
                try self.validateDecodedAfterStackReachability(&control_validation_budget);
                try self.validateDecodedLocalPresence(&control_validation_budget);
                try self.validateDecodedPendingAuthority();
            }
            const pending = switch (self.pending orelse {
                if (self.unwinding_after != null) {
                    try self.validateDecodedAfterUnwind(
                        if (comptime canonical_request_identity) &control_validation_budget else null,
                    );
                }
                return;
            }) {
                .op => |pending_op| {
                    if (self.unwinding_after != null) return error.ProgramContractViolation;
                    try self.validateDecodedPendingTurnIndex(pending_op.turn_index);
                    try self.validateDecodedOperationPendingState(pending_op);
                    return;
                },
                .after => |pending_after| pending_after,
            };
            try self.validateDecodedPendingTurnIndex(pending.turn_index);
            if (pending.remaining == 0) return error.ProgramContractViolation;
            try self.validateDecodedAfterUnwind(
                if (comptime canonical_request_identity) &control_validation_budget else null,
            );
            const unwind = self.unwinding_after orelse return error.ProgramContractViolation;
            if (unwind.function_index != pending.function_index or
                unwind.remaining != pending.remaining or
                !unwind.current_ref.eql(pending.value_ref) or
                !unwind.final_ref.eql(pending.result_ref))
            {
                return error.ProgramContractViolation;
            }
            try validateDecodedArgumentValue(pending.value_ref, pending.value, unwind.value);
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            if (active.function_index != pending.function_index or active.waiting_helper_dst != null) return error.ProgramContractViolation;
            const after_stack = self.scratch.frameAfterStack(active.frame);
            if (pending.remaining > after_stack.len) return error.ProgramContractViolation;
            const after_entry = after_stack[pending.remaining - 1];
            if (after_entry.op_index != pending.op_index or
                @as(usize, after_entry.operation_site_index) != pending.source_operation_site_index or
                @as(usize, after_entry.after_site_index) != pending.after_site_index)
            {
                return error.ProgramContractViolation;
            }
        }

        fn validateDecodedAfterUnwind(
            self: *Self,
            control_validation_budget: ?*ControlValidationBudget,
        ) error{ProgramContractViolation}!void {
            const unwind = self.unwinding_after orelse return error.ProgramContractViolation;
            if (!valueMatchesRef(unwind.current_ref, unwind.value)) return error.ProgramContractViolation;
            if (unwind.function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
            const function = compiled_plan.functions[unwind.function_index];
            if (!unwind.final_ref.eql(program_plan.functionResultRef(function))) return error.ProgramContractViolation;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            if (active.function_index != unwind.function_index or active.waiting_helper_dst != null) {
                return error.ProgramContractViolation;
            }
            const after_stack = self.scratch.frameAfterStack(active.frame);
            if (unwind.remaining > after_stack.len) return error.ProgramContractViolation;
            if (comptime canonical_request_identity) {
                if (after_stack.len == 0) return error.ProgramContractViolation;
                var expected_current_ref = functionValueRef(function);
                var remaining_before_step = after_stack.len;
                const validate_final_input_contract = true;
                while (remaining_before_step > unwind.remaining) : (remaining_before_step -= 1) {
                    const budget = control_validation_budget orelse
                        return error.ProgramContractViolation;
                    try budget.consume();
                    const consumed_entry = after_stack[remaining_before_step - 1];
                    expected_current_ref = sessionAfterOutputRefByIndex(
                        compiled_plan,
                        schema_types,
                        HandlersType,
                        validate_final_input_contract,
                        consumed_entry.op_index,
                        expected_current_ref,
                        remaining_before_step,
                        unwind.final_ref,
                    ) catch return error.ProgramContractViolation;
                }
                if (!unwind.current_ref.eql(expected_current_ref)) return error.ProgramContractViolation;
                if (unwind.remaining == after_stack.len) {
                    try validateDecodedArgumentValue(unwind.current_ref, active.last_return, unwind.value);
                }
                const bounds = try blockInstructionBounds(compiled_plan, active.function_index, active.block_index);
                if (active.instruction_index != bounds.end or active.instruction_end != bounds.end) {
                    return error.ProgramContractViolation;
                }
                const block = compiled_plan.blocks[active.block_index];
                switch (compiled_plan.terminators[block.terminator_index].kind) {
                    .return_unit, .return_value => {},
                    .jump, .branch_if => return error.ProgramContractViolation,
                }
            }
            if (unwind.remaining == 0) {
                if (comptime canonical_request_identity) {
                    if (!unwind.current_ref.eql(unwind.final_ref)) return error.ProgramContractViolation;
                }
            } else {
                const entry_value = after_stack[unwind.remaining - 1];
                if (entry_value.after_site_index >= after_yield_sites.len) return error.ProgramContractViolation;
                const site = after_yield_sites[entry_value.after_site_index];
                if (site.source_function_index != unwind.function_index or
                    site.source_operation_site_index != entry_value.operation_site_index or
                    site.original_op_index != entry_value.op_index)
                {
                    return error.ProgramContractViolation;
                }
                _ = sessionAfterOutputRefByIndex(
                    compiled_plan,
                    schema_types,
                    HandlersType,
                    canonical_request_identity,
                    entry_value.op_index,
                    unwind.current_ref,
                    unwind.remaining,
                    unwind.final_ref,
                ) catch return error.ProgramContractViolation;
            }
        }

        fn validateDecodedPendingTurnIndex(self: *const Self, turn_index: usize) error{ProgramContractViolation}!void {
            if (self.next_turn_index > maximum_turn_count) return error.ProgramContractViolation;
            if (turn_index == std.math.maxInt(usize)) return error.ProgramContractViolation;
            if (self.next_turn_index != turn_index + 1) return error.ProgramContractViolation;
        }

        fn validateDecodedPendingAuthority(self: *const Self) error{ProgramContractViolation}!void {
            const pending = self.pending orelse return;
            switch (pending) {
                .op => |request| {
                    if (request.session_id != self.session_id or
                        request.token == 0 or
                        request.token >= self.next_token)
                    {
                        return error.ProgramContractViolation;
                    }
                },
                .after => |request| {
                    if (request.session_id != self.session_id or
                        request.token == 0 or
                        request.token >= self.next_token)
                    {
                        return error.ProgramContractViolation;
                    }
                },
            }
        }

        fn validateDecodedOperationPendingState(self: *Self, pending: PendingRequest) error{ProgramContractViolation}!void {
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            try validateActiveOperationFrame(active.*, pending);
            if (pending.has_after and self.scratch.afterEntries().len >= session_after_stack_capacity) {
                return error.ProgramContractViolation;
            }
        }

        fn validateActiveOperationFrame(active: ActiveInterpreterFrame, pending: PendingRequest) error{ProgramContractViolation}!void {
            if (active.function_index != pending.function_index or
                active.block_index != pending.block_index or
                active.waiting_helper_dst != null)
            {
                return error.ProgramContractViolation;
            }
            const expected_next_instruction = std.math.add(usize, pending.instruction_index, 1) catch
                return error.ProgramContractViolation;
            if (active.instruction_index != expected_next_instruction) return error.ProgramContractViolation;
        }

        fn operationSiteForInstruction(instruction_index: usize) ?SessionOperationYieldSite {
            inline for (operation_yield_sites) |site| {
                if (site.instruction_index == instruction_index) return site;
            }
            return null;
        }

        fn afterSiteForOperationSite(operation_site_index: usize) ?SessionAfterYieldSite {
            inline for (after_yield_sites) |site| {
                if (site.source_operation_site_index == operation_site_index) return site;
            }
            return null;
        }

        fn afterSiteAt(after_site_index: usize) ?SessionAfterYieldSite {
            if (after_site_index >= after_yield_sites.len) return null;
            const site = after_yield_sites[after_site_index];
            if (site.index != after_site_index) return null;
            return site;
        }

        fn nextTurnIndex(self: *Self) error{ProgramContractViolation}!usize {
            if (self.next_turn_index >= maximum_turn_count) return error.ProgramContractViolation;
            const turn_index = self.next_turn_index;
            self.next_turn_index = std.math.add(usize, self.next_turn_index, 1) catch
                return error.ProgramContractViolation;
            return turn_index;
        }

        fn traceHashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
            traceHashUsize(hasher, value.len);
            hasher.update(value);
        }

        fn traceHashBool(hasher: *std.hash.Wyhash, value: bool) void {
            hasher.update(&[_]u8{@intFromBool(value)});
        }

        fn traceHashU8(hasher: *std.hash.Wyhash, value: u8) void {
            hasher.update(&[_]u8{value});
        }

        fn traceHashU16(hasher: *std.hash.Wyhash, value: u16) void {
            var bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn traceHashU32(hasher: *std.hash.Wyhash, value: u32) void {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn traceHashI32(hasher: *std.hash.Wyhash, value: i32) void {
            traceHashU32(hasher, @bitCast(value));
        }

        fn traceHashU64(hasher: *std.hash.Wyhash, value: u64) void {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn traceHashUsize(hasher: *std.hash.Wyhash, value: usize) void {
            traceHashU64(hasher, @intCast(value));
        }

        fn traceHashOptionalU16(hasher: *std.hash.Wyhash, value: ?u16) void {
            traceHashBool(hasher, value != null);
            if (value) |actual| traceHashU16(hasher, actual);
        }

        fn traceHashCodec(hasher: *std.hash.Wyhash, codec: program_plan.ValueCodec) void {
            traceHashU8(hasher, @intFromEnum(codec));
        }

        fn traceHashMode(hasher: *std.hash.Wyhash, mode: program_plan.ControlMode) void {
            traceHashBytes(hasher, @tagName(mode));
        }

        fn traceHashRequestKind(hasher: *std.hash.Wyhash, kind: Trace.RequestKind) void {
            traceHashBytes(hasher, @tagName(kind));
        }

        fn traceHashResponseKind(hasher: *std.hash.Wyhash, kind: Trace.ResponseKind) void {
            traceHashBytes(hasher, @tagName(kind));
        }

        fn traceHashValueRef(hasher: *std.hash.Wyhash, ref: program_plan.ValueRef) void {
            traceHashCodec(hasher, ref.codec);
            traceHashOptionalU16(hasher, ref.schema_index);
        }

        fn traceHashCommonRequestPrefix(
            hasher: *std.hash.Wyhash,
            turn_index: usize,
            kind: Trace.RequestKind,
            comptime canonical_identity: bool,
        ) void {
            traceHashBytes(
                hasher,
                if (canonical_identity) "boundary.static-machine.request.v1" else "boundary.session.request",
            );
            traceHashU32(hasher, trace_fingerprint_version);
            traceHashBytes(hasher, program_label);
            traceHashBytes(hasher, compiled_plan.label);
            traceHashU64(hasher, if (canonical_identity) contract_fingerprint else plan_hash);
            traceHashUsize(hasher, turn_index);
            traceHashRequestKind(hasher, kind);
        }

        fn operationRequestFingerprint(
            comptime canonical_identity: bool,
            turn_index: usize,
            operation_site_index: usize,
            operation_site_fingerprint: u64,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            mode: program_plan.ControlMode,
            payload_ref: program_plan.ValueRef,
            payload_fingerprint: u64,
            resume_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            has_after: bool,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            traceHashCommonRequestPrefix(&hasher, turn_index, .operation, canonical_identity);
            traceHashUsize(&hasher, operation_site_index);
            traceHashU64(&hasher, operation_site_fingerprint);
            traceHashUsize(&hasher, function_index);
            traceHashUsize(&hasher, block_index);
            traceHashUsize(&hasher, instruction_index);
            traceHashU16(&hasher, requirement_index);
            traceHashBytes(&hasher, requirement_label);
            traceHashU16(&hasher, op_index);
            traceHashBytes(&hasher, op_name);
            traceHashMode(&hasher, mode);
            traceHashValueRef(&hasher, payload_ref);
            traceHashU64(&hasher, payload_fingerprint);
            traceHashValueRef(&hasher, resume_ref);
            traceHashValueRef(&hasher, result_ref);
            traceHashBool(&hasher, has_after);
            return hasher.final();
        }

        fn afterRequestFingerprint(
            comptime canonical_identity: bool,
            turn_index: usize,
            after_site_index: usize,
            after_site_fingerprint: u64,
            source_operation_site_index: usize,
            source_operation_site_fingerprint: u64,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            value_ref: program_plan.ValueRef,
            value_fingerprint: u64,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            remaining: usize,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            traceHashCommonRequestPrefix(&hasher, turn_index, .after, canonical_identity);
            traceHashUsize(&hasher, after_site_index);
            traceHashU64(&hasher, after_site_fingerprint);
            traceHashUsize(&hasher, source_operation_site_index);
            traceHashU64(&hasher, source_operation_site_fingerprint);
            traceHashUsize(&hasher, function_index);
            traceHashUsize(&hasher, block_index);
            traceHashUsize(&hasher, instruction_index);
            traceHashU16(&hasher, requirement_index);
            traceHashBytes(&hasher, requirement_label);
            traceHashU16(&hasher, op_index);
            traceHashBytes(&hasher, op_name);
            traceHashValueRef(&hasher, value_ref);
            traceHashU64(&hasher, value_fingerprint);
            traceHashValueRef(&hasher, output_ref);
            traceHashValueRef(&hasher, result_ref);
            if (canonical_identity) traceHashUsize(&hasher, remaining);
            return hasher.final();
        }

        fn responseTraceFor(
            request_fingerprint: u64,
            kind: Trace.ResponseKind,
            response_ref: program_plan.ValueRef,
            response_value_fingerprint: u64,
        ) Trace.Response {
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "boundary.session.response");
            traceHashU32(&hasher, trace_fingerprint_version);
            traceHashU64(&hasher, request_fingerprint);
            traceHashResponseKind(&hasher, kind);
            traceHashValueRef(&hasher, response_ref);
            traceHashU64(&hasher, response_value_fingerprint);
            return .{
                .request_fingerprint = request_fingerprint,
                .kind = kind,
                .response_ref = response_ref,
                .response_value_fingerprint = response_value_fingerprint,
                .fingerprint = hasher.final(),
            };
        }

        fn fingerprintTypedValueForRef(ref: program_plan.ValueRef, value: anytype) error{ProgramContractViolation}!u64 {
            return fingerprintTypedValueForRefMode(ref, value, .strict);
        }

        fn fingerprintSchemaFieldTypedValueForRef(ref: program_plan.ValueRef, value: anytype) error{ProgramContractViolation}!u64 {
            return fingerprintTypedValueForRefMode(ref, value, .schema_field);
        }

        fn fingerprintTypedValueForRefMode(
            ref: program_plan.ValueRef,
            value: anytype,
            comptime match_mode: RuntimeRefMatchMode,
        ) error{ProgramContractViolation}!u64 {
            const Value = @TypeOf(value);
            const matches_ref = switch (match_mode) {
                .strict => typeMatchesRuntimeRef(schema_types, ref, Value),
                .schema_field => typeMatchesSchemaFieldRuntimeRef(schema_types, ref, Value),
            };
            if (!matches_ref) return error.ProgramContractViolation;
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "boundary.session.value");
            traceHashU32(&hasher, trace_fingerprint_version);
            traceHashValueRef(&hasher, ref);
            try traceHashTypedValuePayload(&hasher, ref, value, match_mode);
            return hasher.final();
        }

        fn fingerprintExecutableValueForRef(ref: program_plan.ValueRef, value: ExecutableValue) error{ProgramContractViolation}!u64 {
            if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "boundary.session.value");
            traceHashU32(&hasher, trace_fingerprint_version);
            traceHashValueRef(&hasher, ref);
            try traceHashExecutableValuePayload(&hasher, ref, value);
            return hasher.final();
        }

        fn executableValuesEqualForRef(
            ref: program_plan.ValueRef,
            left: ExecutableValue,
            right: ExecutableValue,
        ) error{ProgramContractViolation}!bool {
            if (!valueMatchesRef(ref, left) or !valueMatchesRef(ref, right)) {
                return error.ProgramContractViolation;
            }
            return switch (ref.codec) {
                .unit => true,
                .bool => (try decodeArg(.bool, left)) == (try decodeArg(.bool, right)),
                .i32 => (try decodeArg(.i32, left)) == (try decodeArg(.i32, right)),
                .usize => blk: {
                    const left_word = try executableWordU64(left);
                    const right_word = try executableWordU64(right);
                    if (comptime canonical_request_identity) {
                        if (left_word > static_usize_max or right_word > static_usize_max) {
                            return error.ProgramContractViolation;
                        }
                    }
                    break :blk left_word == right_word;
                },
                .string => std.mem.eql(u8, try decodeArg(.string, left), try decodeArg(.string, right)),
                .string_list => blk: {
                    const left_items = try decodeArg(.string_list, left);
                    const right_items = try decodeArg(.string_list, right);
                    if (left_items.len != right_items.len) break :blk false;
                    for (left_items, right_items) |left_item, right_item| {
                        if (!std.mem.eql(u8, left_item, right_item)) break :blk false;
                    }
                    break :blk true;
                },
                .product, .sum => switch (left) {
                    .schema => |left_schema| switch (right) {
                        .schema => |right_schema| blk: {
                            const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                            if (left_schema.schema_index != schema_index or right_schema.schema_index != schema_index) {
                                return error.ProgramContractViolation;
                            }
                            inline for (schema_types, 0..) |SchemaType, index| {
                                if (schema_index == index) {
                                    const left_typed: *const SchemaType = @ptrCast(@alignCast(left_schema.ptr));
                                    const right_typed: *const SchemaType = @ptrCast(@alignCast(right_schema.ptr));
                                    break :blk try typedValuesEqualForRef(
                                        ref,
                                        SchemaType,
                                        left_typed.*,
                                        right_typed.*,
                                        .strict,
                                    );
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        else => return error.ProgramContractViolation,
                    },
                    else => return error.ProgramContractViolation,
                },
            };
        }

        fn typedValuesEqualForRef(
            ref: program_plan.ValueRef,
            comptime T: type,
            left: T,
            right: T,
            comptime match_mode: RuntimeRefMatchMode,
        ) error{ProgramContractViolation}!bool {
            const matches_ref = switch (match_mode) {
                .strict => typeMatchesRuntimeRef(schema_types, ref, T),
                .schema_field => typeMatchesSchemaFieldRuntimeRef(schema_types, ref, T),
            };
            if (!matches_ref) return error.ProgramContractViolation;

            if (comptime isStringListCarrier(T)) {
                if (left.len != right.len) return false;
                for (left, right) |left_item, right_item| {
                    if (!std.mem.eql(u8, left_item, right_item)) return false;
                }
                return true;
            }
            if (T == void) return true;
            if (T == bool or T == i32 or T == u64) return left == right;
            if (T == usize) {
                if (comptime canonical_request_identity) {
                    if (@as(u64, @intCast(left)) > static_usize_max or
                        @as(u64, @intCast(right)) > static_usize_max)
                    {
                        return error.ProgramContractViolation;
                    }
                }
                return left == right;
            }
            if (T == []const u8) return std.mem.eql(u8, left, right);

            const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
            inline for (schema_types, 0..) |SchemaType, index| {
                if (schema_index == index) {
                    if (SchemaType != T) return error.ProgramContractViolation;
                    const schema = compiled_plan.value_schemas[index];
                    if (schema.codec != ref.codec) return error.ProgramContractViolation;
                    return switch (schema.codec) {
                        .product => typedProductValuesEqual(index, T, left, right),
                        .sum => typedSumValuesEqual(index, T, left, right),
                        else => error.ProgramContractViolation,
                    };
                }
            }
            return error.ProgramContractViolation;
        }

        fn typedProductValuesEqual(
            comptime schema_index: usize,
            comptime T: type,
            left: T,
            right: T,
        ) error{ProgramContractViolation}!bool {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .product) return error.ProgramContractViolation;
            const fields = std.meta.fields(T);
            if (fields.len != schema.field_count) return error.ProgramContractViolation;
            inline for (0..schema.field_count) |field_offset| {
                const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                const typed_field = fields[field_offset];
                if (!std.mem.eql(u8, typed_field.name, field.name)) return error.ProgramContractViolation;
                const field_ref: program_plan.ValueRef = .{
                    .codec = field.codec,
                    .schema_index = field.schema_index,
                };
                if (!(try typedValuesEqualForRef(
                    field_ref,
                    typed_field.type,
                    @field(left, field.name),
                    @field(right, field.name),
                    .schema_field,
                ))) return false;
            }
            return true;
        }

        fn typedSumValuesEqual(
            comptime schema_index: usize,
            comptime T: type,
            left: T,
            right: T,
        ) error{ProgramContractViolation}!bool {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .sum) return error.ProgramContractViolation;
            const left_active = try activeVariantOrdinalForTyped(T, left);
            const right_active = try activeVariantOrdinalForTyped(T, right);
            if (left_active != right_active) return false;
            if (left_active >= schema.variant_count) return error.ProgramContractViolation;

            inline for (0..schema.variant_count) |variant_offset| {
                if (left_active == variant_offset) {
                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + variant_offset];
                    const variant_ref: program_plan.ValueRef = .{
                        .codec = variant.codec,
                        .schema_index = variant.schema_index,
                    };
                    return switch (@typeInfo(T)) {
                        .@"enum" => true,
                        .optional => if (variant_offset == 0)
                            true
                        else blk: {
                            break :blk try typedValuesEqualForRef(
                                variant_ref,
                                @TypeOf(left.?),
                                left.?,
                                right.?,
                                .schema_field,
                            );
                        },
                        .@"union" => |union_info| blk: {
                            const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
                            const left_tag = std.meta.activeTag(left);
                            const right_tag = std.meta.activeTag(right);
                            if (left_tag != right_tag) break :blk false;
                            inline for (union_info.fields, 0..) |field, field_index| {
                                if (variant_offset == field_index and left_tag == @field(Tag, field.name)) {
                                    if (field.type == void) break :blk true;
                                    break :blk try typedValuesEqualForRef(
                                        variant_ref,
                                        field.type,
                                        @field(left, field.name),
                                        @field(right, field.name),
                                        .schema_field,
                                    );
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        else => error.ProgramContractViolation,
                    };
                }
            }
            return error.ProgramContractViolation;
        }

        fn traceHashExecutableValuePayload(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
        ) error{ProgramContractViolation}!void {
            switch (ref.codec) {
                .unit => switch (value) {
                    .none => {},
                    else => return error.ProgramContractViolation,
                },
                .bool => switch (value) {
                    .bool => |typed| traceHashBool(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .i32 => switch (value) {
                    .i32 => |typed| traceHashI32(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .usize => switch (value) {
                    .usize => |typed| {
                        if (comptime canonical_request_identity) {
                            if (@as(u64, @intCast(typed)) > static_usize_max) return error.ProgramContractViolation;
                        }
                        traceHashUsize(hasher, typed);
                    },
                    .word_u64 => |typed| {
                        if (comptime canonical_request_identity) {
                            if (typed > static_usize_max) return error.ProgramContractViolation;
                        }
                        traceHashU64(hasher, typed);
                    },
                    else => return error.ProgramContractViolation,
                },
                .string => switch (value) {
                    .string => |typed| traceHashBytes(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .string_list => switch (value) {
                    .string_list => |typed| {
                        traceHashUsize(hasher, typed.len);
                        for (typed) |item| traceHashBytes(hasher, item);
                    },
                    else => return error.ProgramContractViolation,
                },
                .product, .sum => switch (value) {
                    .schema => |schema| {
                        const expected_schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                        if (schema.schema_index != expected_schema_index) {
                            return error.ProgramContractViolation;
                        }
                        inline for (schema_types, 0..) |SchemaType, schema_index| {
                            if (schema.schema_index == schema_index) {
                                const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                                return traceHashStructuredTypedValuePayload(hasher, ref, SchemaType, typed.*);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                    else => return error.ProgramContractViolation,
                },
            }
        }

        fn traceHashTypedValuePayload(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            value: anytype,
            comptime match_mode: RuntimeRefMatchMode,
        ) error{ProgramContractViolation}!void {
            const Value = @TypeOf(value);
            const matches_ref = switch (match_mode) {
                .strict => typeMatchesRuntimeRef(schema_types, ref, Value),
                .schema_field => typeMatchesSchemaFieldRuntimeRef(schema_types, ref, Value),
            };
            if (!matches_ref) return error.ProgramContractViolation;
            if (comptime isStringListCarrier(@TypeOf(value))) {
                if (!ref.eql(.{ .codec = .string_list })) return error.ProgramContractViolation;
                traceHashUsize(hasher, value.len);
                for (value) |item| traceHashBytes(hasher, item);
                return;
            }
            switch (@TypeOf(value)) {
                void => {
                    if (!ref.eql(.{ .codec = .unit })) return error.ProgramContractViolation;
                },
                bool => {
                    if (!ref.eql(.{ .codec = .bool })) return error.ProgramContractViolation;
                    traceHashBool(hasher, value);
                },
                i32 => {
                    if (!ref.eql(.{ .codec = .i32 })) return error.ProgramContractViolation;
                    traceHashI32(hasher, value);
                },
                u64 => {
                    if (!ref.eql(.{ .codec = .usize })) return error.ProgramContractViolation;
                    traceHashU64(hasher, value);
                },
                usize => {
                    if (!ref.eql(.{ .codec = .usize })) return error.ProgramContractViolation;
                    if (comptime canonical_request_identity) {
                        if (@as(u64, @intCast(value)) > static_usize_max) return error.ProgramContractViolation;
                    }
                    traceHashUsize(hasher, value);
                },
                []const u8 => {
                    if (!ref.eql(.{ .codec = .string })) return error.ProgramContractViolation;
                    traceHashBytes(hasher, value);
                },
                else => try traceHashStructuredTypedValuePayload(hasher, ref, @TypeOf(value), value),
            }
        }

        fn traceHashStructuredTypedValuePayload(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!void {
            const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
            inline for (schema_types, 0..) |SchemaType, index| {
                if (schema_index == index) {
                    if (SchemaType != T) return error.ProgramContractViolation;
                    const schema = compiled_plan.value_schemas[index];
                    if (schema.codec != ref.codec) return error.ProgramContractViolation;
                    traceHashU16(hasher, @intCast(index));
                    if (comptime !canonical_request_identity) traceHashBytes(hasher, schema.label);
                    traceHashCodec(hasher, schema.codec);
                    return switch (schema.codec) {
                        .product => traceHashProductValuePayload(hasher, index, T, value),
                        .sum => traceHashSumValuePayload(hasher, index, T, value),
                        else => error.ProgramContractViolation,
                    };
                }
            }
            return error.ProgramContractViolation;
        }

        fn traceHashProductValuePayload(
            hasher: *std.hash.Wyhash,
            comptime schema_index: usize,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!void {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .product) return error.ProgramContractViolation;
            const fields = std.meta.fields(T);
            if (fields.len != schema.field_count) return error.ProgramContractViolation;
            traceHashU16(hasher, schema.first_field);
            traceHashU16(hasher, schema.field_count);
            inline for (0..schema.field_count) |field_offset| {
                const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                const field_ref: program_plan.ValueRef = .{
                    .codec = field.codec,
                    .schema_index = field.schema_index,
                };
                traceHashU16(hasher, @intCast(field_offset));
                traceHashBytes(hasher, field.name);
                traceHashValueRef(hasher, field_ref);
                const field_fingerprint = try fingerprintSchemaFieldTypedValueForRef(field_ref, @field(value, field.name));
                traceHashU64(hasher, field_fingerprint);
            }
        }

        fn traceHashSumValuePayload(
            hasher: *std.hash.Wyhash,
            comptime schema_index: usize,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!void {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .sum) return error.ProgramContractViolation;
            const active = try activeVariantOrdinalForTyped(T, value);
            if (active >= schema.variant_count) return error.ProgramContractViolation;
            traceHashU16(hasher, schema.first_variant);
            traceHashU16(hasher, schema.variant_count);
            traceHashU16(hasher, active);
            inline for (0..schema.variant_count) |variant_offset| {
                if (active == variant_offset) {
                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + variant_offset];
                    const variant_ref: program_plan.ValueRef = .{
                        .codec = variant.codec,
                        .schema_index = variant.schema_index,
                    };
                    traceHashBytes(hasher, variant.name);
                    traceHashValueRef(hasher, variant_ref);
                    const payload_fingerprint = try sumVariantPayloadFingerprint(variant_offset, variant_ref, T, value);
                    traceHashU64(hasher, payload_fingerprint);
                    return;
                }
            }
            return error.ProgramContractViolation;
        }

        fn sumVariantPayloadFingerprint(
            comptime variant_offset: usize,
            variant_ref: program_plan.ValueRef,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!u64 {
            return switch (@typeInfo(T)) {
                .@"enum" => fingerprintSchemaFieldTypedValueForRef(variant_ref, {}),
                .optional => if (variant_offset == 0)
                    fingerprintSchemaFieldTypedValueForRef(variant_ref, {})
                else
                    fingerprintSchemaFieldTypedValueForRef(variant_ref, value.?),
                .@"union" => |union_info| blk: {
                    inline for (union_info.fields, 0..) |field, field_index| {
                        if (variant_offset == field_index) {
                            if (field.type == void) break :blk fingerprintSchemaFieldTypedValueForRef(variant_ref, {});
                            break :blk fingerprintSchemaFieldTypedValueForRef(variant_ref, @field(value, field.name));
                        }
                    }
                    return error.ProgramContractViolation;
                },
                else => error.ProgramContractViolation,
            };
        }

        fn runtimeRefForExecutableValue(value: ExecutableValue) error{ProgramContractViolation}!program_plan.ValueRef {
            return switch (value) {
                .none => .{ .codec = .unit },
                .bool => .{ .codec = .bool },
                .i32 => .{ .codec = .i32 },
                .usize => .{ .codec = .usize },
                .word_u64 => .{ .codec = .usize },
                .string => .{ .codec = .string },
                .string_list => .{ .codec = .string_list },
                .schema => |schema| blk: {
                    if (schema.schema_index >= compiled_plan.value_schemas.len) return error.ProgramContractViolation;
                    const value_schema = compiled_plan.value_schemas[schema.schema_index];
                    if (value_schema.codec != .product and value_schema.codec != .sum) return error.ProgramContractViolation;
                    break :blk .{
                        .codec = value_schema.codec,
                        .schema_index = schema.schema_index,
                    };
                },
            };
        }

        fn traceHashExecutableValueIdentity(hasher: *std.hash.Wyhash, value: ExecutableValue) error{ProgramContractViolation}!void {
            const ref = try runtimeRefForExecutableValue(value);
            traceHashValueRef(hasher, ref);
            traceHashU64(hasher, try fingerprintExecutableValueForRef(ref, value));
        }

        const ClonedString = struct {
            original: []const u8,
            cloned: []const u8,
        };

        const ClonedStringList = struct {
            original: []const []const u8,
            cloned: []const []const u8,
        };

        const CloneContext = struct {
            scratch: *Scratch,
            strings: std.ArrayList(ClonedString) = .empty,
            string_lists: std.ArrayList(ClonedStringList) = .empty,

            fn init(scratch: *Scratch) @This() {
                return .{ .scratch = scratch };
            }

            fn deinit(self: *@This()) void {
                self.string_lists.deinit(self.scratch.allocator);
                self.strings.deinit(self.scratch.allocator);
            }

            fn sameString(left: []const u8, right: []const u8) bool {
                return left.ptr == right.ptr and left.len == right.len;
            }

            fn sameStringList(left: []const []const u8, right: []const []const u8) bool {
                return left.ptr == right.ptr and left.len == right.len;
            }

            fn cloneString(self: *@This(), value: []const u8) std.mem.Allocator.Error![]const u8 {
                for (self.strings.items) |cloned_entry| {
                    if (sameString(cloned_entry.original, value)) return cloned_entry.cloned;
                }
                const cloned = try self.scratch.storeOwnedString(value);
                try self.strings.append(self.scratch.allocator, .{
                    .original = value,
                    .cloned = cloned,
                });
                return cloned;
            }

            fn cloneStringList(self: *@This(), value: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
                for (self.string_lists.items) |cloned_entry| {
                    if (sameStringList(cloned_entry.original, value)) return cloned_entry.cloned;
                }
                try self.scratch.owned_string_lists.ensureUnusedCapacity(self.scratch.allocator, 1);
                try self.string_lists.ensureUnusedCapacity(self.scratch.allocator, 1);
                const cloned = try self.scratch.allocator.alloc([]const u8, value.len);
                errdefer self.scratch.allocator.free(cloned);
                for (value, 0..) |item, index| {
                    cloned[index] = try self.cloneString(item);
                }
                self.scratch.owned_string_lists.appendAssumeCapacity(cloned);
                self.string_lists.appendAssumeCapacity(.{
                    .original = value,
                    .cloned = cloned,
                });
                return cloned;
            }

            fn cloneMutableStringList(self: *@This(), value: []const []const u8) std.mem.Allocator.Error![][]const u8 {
                return @constCast(try self.cloneStringList(value));
            }
        };

        fn cloneTypedRuntimeValueForRef(
            ref: program_plan.ValueRef,
            clone_context: *CloneContext,
            value: anytype,
        ) anyerror!@TypeOf(value) {
            return cloneTypedRuntimeValueForRefMode(ref, clone_context, value, .strict);
        }

        fn cloneSchemaFieldTypedRuntimeValueForRef(
            ref: program_plan.ValueRef,
            clone_context: *CloneContext,
            value: anytype,
        ) anyerror!@TypeOf(value) {
            return cloneTypedRuntimeValueForRefMode(ref, clone_context, value, .schema_field);
        }

        fn cloneTypedRuntimeValueForRefMode(
            ref: program_plan.ValueRef,
            clone_context: *CloneContext,
            value: anytype,
            comptime match_mode: RuntimeRefMatchMode,
        ) anyerror!@TypeOf(value) {
            const ValueT = @TypeOf(value);
            const matches_ref = switch (match_mode) {
                .strict => typeMatchesRuntimeRef(schema_types, ref, ValueT),
                .schema_field => typeMatchesSchemaFieldRuntimeRef(schema_types, ref, ValueT),
            };
            if (!matches_ref) return error.ProgramContractViolation;
            if (ValueT == void or ValueT == bool or ValueT == i32 or ValueT == u64 or ValueT == usize) return value;
            if (ValueT == []const u8) return try clone_context.cloneString(value);
            if (ValueT == []const []const u8) return try clone_context.cloneStringList(value);
            if (ValueT == [][]const u8) return try clone_context.cloneMutableStringList(value);
            const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
            inline for (schema_types, 0..) |SchemaType, index| {
                if (schema_index == index) {
                    if (SchemaType != ValueT) return error.ProgramContractViolation;
                    const schema = compiled_plan.value_schemas[index];
                    if (schema.codec != ref.codec) return error.ProgramContractViolation;
                    return switch (schema.codec) {
                        .product => cloneProductTypedValue(index, ValueT, clone_context, value),
                        .sum => cloneSumTypedValue(index, ValueT, clone_context, value),
                        else => error.ProgramContractViolation,
                    };
                }
            }
            return error.ProgramContractViolation;
        }

        fn cloneProductTypedValue(
            comptime schema_index: usize,
            comptime T: type,
            clone_context: *CloneContext,
            value: T,
        ) anyerror!T {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .product) return error.ProgramContractViolation;
            const fields = std.meta.fields(T);
            if (fields.len != schema.field_count) return error.ProgramContractViolation;
            var cloned: T = undefined;
            inline for (0..schema.field_count) |field_offset| {
                const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                const field_ref: program_plan.ValueRef = .{
                    .codec = field.codec,
                    .schema_index = field.schema_index,
                };
                @field(cloned, field.name) = try cloneSchemaFieldTypedRuntimeValueForRef(
                    field_ref,
                    clone_context,
                    @field(value, field.name),
                );
            }
            return cloned;
        }

        fn cloneSumTypedValue(
            comptime schema_index: usize,
            comptime T: type,
            clone_context: *CloneContext,
            value: T,
        ) anyerror!T {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .sum) return error.ProgramContractViolation;
            const active = try activeVariantOrdinalForTyped(T, value);
            if (active >= schema.variant_count) return error.ProgramContractViolation;
            return switch (@typeInfo(T)) {
                .@"enum" => value,
                .optional => |optional_info| blk: {
                    _ = optional_info;
                    if (active == 0) break :blk null;
                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + active];
                    const variant_ref: program_plan.ValueRef = .{
                        .codec = variant.codec,
                        .schema_index = variant.schema_index,
                    };
                    break :blk try cloneSchemaFieldTypedRuntimeValueForRef(variant_ref, clone_context, value.?);
                },
                .@"union" => |union_info| blk: {
                    const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
                    const active_tag = std.meta.activeTag(value);
                    inline for (union_info.fields, 0..) |field, field_index| {
                        if (active == field_index and active_tag == @field(Tag, field.name)) {
                            if (field.type == void) break :blk @unionInit(T, field.name, {});
                            const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + field_index];
                            const variant_ref: program_plan.ValueRef = .{
                                .codec = variant.codec,
                                .schema_index = variant.schema_index,
                            };
                            break :blk @unionInit(
                                T,
                                field.name,
                                try cloneSchemaFieldTypedRuntimeValueForRef(variant_ref, clone_context, @field(value, field.name)),
                            );
                        }
                    }
                    return error.ProgramContractViolation;
                },
                else => error.ProgramContractViolation,
            };
        }

        fn cloneExecutableValueForRefWithContext(
            ref: program_plan.ValueRef,
            clone_context: *CloneContext,
            value: ExecutableValue,
        ) anyerror!ExecutableValue {
            if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
            return switch (ref.codec) {
                .unit => .none,
                .bool => .{ .bool = try decodeArg(.bool, value) },
                .i32 => .{ .i32 = try decodeArg(.i32, value) },
                .usize => switch (value) {
                    .usize => |typed| .{ .usize = typed },
                    .word_u64 => |typed| .{ .word_u64 = typed },
                    else => error.ProgramContractViolation,
                },
                .string => .{ .string = try clone_context.cloneString(try decodeArg(.string, value)) },
                .string_list => .{ .string_list = try clone_context.cloneStringList(try decodeArg(.string_list, value)) },
                .product, .sum => switch (value) {
                    .schema => |schema| blk: {
                        const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                        if (schema.schema_index != schema_index) return error.ProgramContractViolation;
                        inline for (schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                                const cloned = try cloneTypedRuntimeValueForRef(ref, clone_context, typed.*);
                                break :blk try clone_context.scratch.storeSchemaValue(SchemaType, schema.schema_index, cloned);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                    else => return error.ProgramContractViolation,
                },
            };
        }

        fn cloneExecutableValueForRef(
            ref: program_plan.ValueRef,
            scratch: *Scratch,
            value: ExecutableValue,
        ) anyerror!ExecutableValue {
            var clone_context = CloneContext.init(scratch);
            defer clone_context.deinit();
            return cloneExecutableValueForRefWithContext(ref, &clone_context, value);
        }

        fn encodeResponseRuntimeValueForRef(
            self: *Self,
            ref: program_plan.ValueRef,
            value: anytype,
        ) anyerror!ExecutableValue {
            if (comptime !canonical_request_identity) {
                return encodeRuntimeValueForRuntimeRef(schema_types, ref, &self.scratch, value);
            }
            _ = try fingerprintTypedValueForRef(ref, value);
            const ownership_checkpoint = self.scratch.ownershipCheckpoint();
            errdefer self.scratch.rollbackOwned(ownership_checkpoint);
            var clone_context = CloneContext.init(&self.scratch);
            defer clone_context.deinit();
            const cloned = try cloneTypedRuntimeValueForRef(ref, &clone_context, value);
            return encodeRuntimeValueForRuntimeRef(schema_types, ref, &self.scratch, cloned);
        }

        fn cloneExecutableValueByIdentityWithContext(
            clone_context: *CloneContext,
            value: ExecutableValue,
        ) anyerror!ExecutableValue {
            return switch (value) {
                .none => .none,
                else => cloneExecutableValueForRefWithContext(try runtimeRefForExecutableValue(value), clone_context, value),
            };
        }

        fn cloneExecutableValueByIdentity(
            scratch: *Scratch,
            value: ExecutableValue,
        ) anyerror!ExecutableValue {
            var clone_context = CloneContext.init(scratch);
            defer clone_context.deinit();
            return cloneExecutableValueByIdentityWithContext(&clone_context, value);
        }

        fn cloneEntryArgs(
            scratch: *Scratch,
            values: []ExecutableValue,
        ) anyerror!void {
            if (comptime entry.parameter_count == 0) return;
            if (comptime compiled_plan.locals.len == 0) return error.ProgramContractViolation;
            var clone_context = CloneContext.init(scratch);
            defer clone_context.deinit();
            for (values, 0..) |value, index| {
                const local = compiled_plan.locals[entry.first_local + index];
                const ref: program_plan.ValueRef = .{ .codec = local.codec, .schema_index = local.schema_index };
                values[index] = try cloneExecutableValueForRefWithContext(ref, &clone_context, value);
            }
        }

        const session_id_source = struct {
            var next: usize = 1;
        };

        fn nextSessionId() error{ProgramContractViolation}!usize {
            while (true) {
                const candidate = @atomicLoad(usize, &session_id_source.next, .monotonic);
                if (candidate == 0 or candidate == std.math.maxInt(usize)) return error.ProgramContractViolation;
                if (@cmpxchgWeak(
                    usize,
                    &session_id_source.next,
                    candidate,
                    candidate + 1,
                    .monotonic,
                    .monotonic,
                ) == null) return candidate;
            }
        }

        fn takeNextToken(self: *Self) error{ProgramContractViolation}!u64 {
            const token = self.next_token;
            if (token == 0 or token == std.math.maxInt(u64)) return error.ProgramContractViolation;
            self.next_token = token + 1;
            return token;
        }

        fn activateDecodedPending(self: *Self) error{ProgramContractViolation}!void {
            if (self.pending) |*pending_union| {
                const token = try self.takeNextToken();
                switch (pending_union.*) {
                    .op => |*pending| {
                        pending.session_id = self.session_id;
                        pending.token = token;
                    },
                    .after => |*pending| {
                        pending.session_id = self.session_id;
                        pending.token = token;
                    },
                }
            }
        }

        pub fn start(allocator: std.mem.Allocator, args: anytype) anyerror!Self {
            if (comptime !canonical_request_identity) {
                comptime validateTypedExecutablePlanSupportWithIdentity(
                    compiled_plan,
                    schema_types,
                    nested_with_targets,
                    .legacy_session,
                ) catch |err|
                    @compileError("Program.Session.start failed executable support validation: " ++ @errorName(err));
                comptime validateSessionPlanSupportWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
                    @compileError("Program.Session.start unsupported: " ++ @errorName(err));
            }
            var scratch = try Scratch.init(
                allocator,
                analysis.max_active_local_slots,
                analysis.max_active_call_arg_slots,
            );
            errdefer scratch.deinit();

            var frames = try ActiveFrameStack.init(allocator, analysis.max_active_frame_depth);
            errdefer frames.deinit(allocator);

            var self: Self = .{
                .allocator = allocator,
                .scratch = scratch,
                .frames = frames,
                .session_id = try nextSessionId(),
            };
            scratch = .{ .allocator = allocator };
            frames = .{};
            errdefer self.deinit();

            var entry_args: [entry.parameter_count]ExecutableValue = undefined;
            try encodeEntryArgs(compiled_plan, schema_types, &self.scratch, entry_args[0..], args);
            if (comptime canonical_request_identity) {
                for (entry_args, 0..) |value, index| {
                    const local = compiled_plan.locals[entry.first_local + index];
                    const ref: program_plan.ValueRef = .{ .codec = local.codec, .schema_index = local.schema_index };
                    _ = try fingerprintExecutableValueForRef(ref, value);
                }
            }
            try cloneEntryArgs(&self.scratch, entry_args[0..]);
            try pushActiveInterpreterFrame(allocator, compiled_plan, &self.scratch, &self.frames, compiled_plan.entry_index, entry_args[0..]);
            return self;
        }

        pub fn deinit(self: *Self) void {
            while (self.frames.len() != 0) {
                const active = self.frames.pop().?;
                self.scratch.popFrame(active.frame);
            }
            self.frames.deinit(self.allocator);
            self.scratch.deinit();
            self.pending = null;
            self.unwinding_after = null;
            self.terminal_runtime_failure = null;
            self.completed = null;
        }

        pub fn hasPendingRequest(self: *const Self) bool {
            return self.pending != null;
        }

        pub fn current(self: *Self) error{ProgramContractViolation}!Current {
            return switch (self.pending orelse return .none) {
                .op => |pending| .{ .request = try self.requestFromPending(pending) },
                .after => |pending| .{ .after = try self.afterFromPending(pending) },
            };
        }

        pub fn capture(self: *Self, allocator: std.mem.Allocator) anyerror!Capsule {
            var metadata_value = try self.capsuleMetadata();
            metadata_value.continuation_fingerprint = try self.continuationFingerprint();
            var core = try self.cloneState(allocator);
            errdefer core.deinit();
            return .{
                .core = core,
                .metadata_value = metadata_value,
            };
        }

        pub fn restore(allocator: std.mem.Allocator, capsule: *const Capsule) anyerror!Self {
            if (capsule.deinitialized) return error.ProgramContractViolation;
            try validateCapsuleMetadata(capsule.metadata_value);
            var core = try capsule.core.cloneState(allocator);
            errdefer core.deinit();
            try core.validateCapsuleShape(capsule.metadata_value);
            try core.retokenizePending();
            try core.validateCapsuleShape(capsule.metadata_value);
            return core;
        }

        pub fn next(self: *Self) anyerror!Step {
            if (self.terminal_runtime_failure) |err| return err;
            if (self.terminal_failure_instruction_index) |instruction_index| {
                return mappedReturnErrorForInstruction(ErrorSet, compiled_plan, instruction_index);
            }
            if (self.pending != null) return error.ProgramContractViolation;
            if (self.unwinding_after != null) {
                if (try self.continueAfterUnwind()) |step| return step;
            }
            if (self.completed != null) return self.consumeCompleted();
            if (self.done_consumed) return error.ProgramContractViolation;

            while (self.frames.len() != 0) {
                try consumeInterpreterStep(&self.remaining_steps);
                if (self.unwinding_after != null) {
                    if (try self.continueAfterUnwind()) |step| return step;
                    continue;
                }
                const active = self.frames.top();
                if (active.waiting_helper_dst != null) return error.ProgramContractViolation;

                if (active.instruction_index < active.instruction_end) {
                    if (comptime compiled_plan.instructions.len == 0) return error.ProgramContractViolation;
                    const instruction_index = active.instruction_index;
                    active.instruction_index += 1;
                    const instruction = compiled_plan.instructions[instruction_index];
                    const function = compiled_plan.functions[active.function_index];
                    var locals = self.scratch.frameLocals(active.frame);
                    switch (instruction.kind) {
                        .add_const_i32 => {
                            const operand = try decodeArg(.i32, locals[instruction.operand]);
                            locals[instruction.dst] = .{
                                .i32 = std.math.add(i32, operand, @as(i32, @intCast(instruction.aux))) catch return error.ProgramContractViolation,
                            };
                        },
                        .add_i32 => {
                            const lhs = try decodeArg(.i32, locals[instruction.operand]);
                            const rhs = try decodeArg(.i32, locals[instruction.aux]);
                            locals[instruction.dst] = .{
                                .i32 = std.math.add(i32, lhs, rhs) catch return error.ProgramContractViolation,
                            };
                        },
                        .call_helper => {
                            const callee = compiled_plan.functions[instruction.operand];
                            const buffer = try self.scratch.pushCallArgs(callee.parameter_count);
                            var args_popped = false;
                            errdefer if (!args_popped) self.scratch.popCallArgs(buffer[0..callee.parameter_count]);
                            if (callee.parameter_count != 0) {
                                if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                                for (0..callee.parameter_count) |arg_index| {
                                    const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                                    if (local_id >= locals.len) return error.ProgramContractViolation;
                                    buffer[arg_index] = locals[local_id];
                                }
                            }
                            active.waiting_helper_dst = instruction.dst;
                            try pushActiveInterpreterFrame(
                                self.allocator,
                                compiled_plan,
                                &self.scratch,
                                &self.frames,
                                instruction.operand,
                                buffer[0..callee.parameter_count],
                            );
                            self.frames.top().frame.call_args_start -= callee.parameter_count;
                            self.scratch.popCallArgs(buffer[0..callee.parameter_count]);
                            args_popped = true;
                        },
                        .call_nested_with => {
                            const target_index = nestedTargetIndexForInstruction(instruction_index) orelse
                                return error.ProgramContractViolation;
                            const target = compiled_plan.functions[target_index];
                            if (target.parameter_count != 0) return error.ProgramContractViolation;
                            const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch return error.ProgramContractViolation;
                            if (result_codec != .unit and instruction.dst == std.math.maxInt(u16)) return error.ProgramContractViolation;
                            active.waiting_helper_dst = instruction.dst;
                            try pushActiveInterpreterFrame(
                                self.allocator,
                                compiled_plan,
                                &self.scratch,
                                &self.frames,
                                target_index,
                                &.{},
                            );
                        },
                        .call_op => {
                            if (comptime compiled_plan.ops.len == 0) return error.ProgramContractViolation;
                            if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                            const op = compiled_plan.ops[instruction.operand];
                            const payload_ref: program_plan.ValueRef = .{
                                .codec = op.payload_codec,
                                .schema_index = op.payload_schema_index,
                            };
                            const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                            const payload_local_id = if (op.payload_codec == .unit) std.math.maxInt(u16) else instruction.aux;
                            if (!valueMatchesRef(payload_ref, payload)) return error.ProgramContractViolation;
                            const result_ref = program_plan.functionResultRef(function);
                            const operation_site = operationSiteForInstruction(instruction_index) orelse return error.ProgramContractViolation;
                            const request = try self.makeRequest(
                                active.function_index,
                                active.block_index,
                                instruction_index,
                                operation_site,
                                instruction.dst,
                                instruction.operand,
                                result_ref,
                                payload_local_id,
                                payload,
                            );
                            return .{ .request = request };
                        },
                        .compare_eq_zero => {
                            const operand_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.operand) orelse return error.ProgramContractViolation;
                            const is_zero = switch (operand_ref.codec) {
                                .bool => !(try decodeArg(.bool, locals[instruction.operand])),
                                .i32 => (try decodeArg(.i32, locals[instruction.operand])) == 0,
                                .usize => (try executableWordU64(locals[instruction.operand])) == 0,
                                else => return error.ProgramContractViolation,
                            };
                            locals[instruction.dst] = .{ .bool = is_zero };
                            active.last_condition = is_zero;
                        },
                        .sum_variant_is => {
                            const is_variant = (try activeVariantOrdinalForExecutable(schema_types, locals[instruction.operand])) == instruction.aux;
                            locals[instruction.dst] = .{ .bool = is_variant };
                            active.last_condition = is_variant;
                        },
                        .sum_extract_payload => {
                            const dst_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.dst) orelse return error.ProgramContractViolation;
                            const extracted = try extractVariantPayloadForExecutable(schema_types, dst_ref, &self.scratch, locals[instruction.operand], instruction.aux);
                            if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                            if (comptime canonical_request_identity) _ = try fingerprintExecutableValueForRef(dst_ref, extracted.value);
                            locals[instruction.dst] = extracted.value;
                        },
                        .product_extract_field => {
                            const dst_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.dst) orelse return error.ProgramContractViolation;
                            const extracted = try extractProductFieldForExecutable(schema_types, dst_ref, &self.scratch, locals[instruction.operand], instruction.aux);
                            if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                            if (comptime canonical_request_identity) _ = try fingerprintExecutableValueForRef(dst_ref, extracted.value);
                            locals[instruction.dst] = extracted.value;
                        },
                        .const_i32 => locals[instruction.dst] = .{ .i32 = try constI32Value(instruction) },
                        .const_string => locals[instruction.dst] = .{ .string = instruction.string_literal },
                        .const_usize => {
                            const word = std.fmt.parseUnsigned(u64, instruction.string_literal, 0) catch return error.ProgramContractViolation;
                            if (comptime canonical_request_identity) {
                                if (word > static_usize_max) return error.ProgramContractViolation;
                            }
                            locals[instruction.dst] = .{ .word_u64 = word };
                        },
                        .return_error => {
                            self.terminal_failure_instruction_index = instruction_index;
                            return mappedReturnErrorForInstruction(ErrorSet, compiled_plan, instruction_index);
                        },
                        .return_value => active.last_return = locals[instruction.operand],
                        .sub_one => {
                            const operand_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.operand) orelse return error.ProgramContractViolation;
                            locals[instruction.dst] = switch (operand_ref.codec) {
                                .i32 => .{ .i32 = std.math.sub(i32, try decodeArg(.i32, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                                .usize => .{ .word_u64 = std.math.sub(u64, try executableWordU64(locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                                else => return error.ProgramContractViolation,
                            };
                        },
                    }
                    continue;
                }

                const block = compiled_plan.blocks[active.block_index];
                const terminator = compiled_plan.terminators[block.terminator_index];
                const function = compiled_plan.functions[active.function_index];
                switch (terminator.kind) {
                    .branch_if => {
                        const next_block = if (active.last_condition) terminator.primary else terminator.secondary;
                        const bounds = try blockInstructionBounds(compiled_plan, active.function_index, next_block);
                        active.block_index = next_block;
                        active.instruction_index = bounds.first;
                        active.instruction_end = bounds.end;
                    },
                    .jump => {
                        const bounds = try blockInstructionBounds(compiled_plan, active.function_index, terminator.primary);
                        active.block_index = terminator.primary;
                        active.instruction_index = bounds.first;
                        active.instruction_end = bounds.end;
                    },
                    .return_unit => {
                        const completion: CompletionValue = .{
                            .value = if (function.value_codec == .unit) .none else active.last_return,
                            .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                            .after_stack = self.scratch.frameAfterStack(active.frame),
                            .kind = .normal,
                        };
                        if (try self.beginOrCompleteSessionReturn(active.function_index, completion)) |step| return step;
                    },
                    .return_value => {
                        const completion: CompletionValue = .{
                            .value = active.last_return,
                            .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                            .after_stack = self.scratch.frameAfterStack(active.frame),
                            .kind = .normal,
                        };
                        if (try self.beginOrCompleteSessionReturn(active.function_index, completion)) |step| return step;
                    },
                }
            }
            return error.ProgramContractViolation;
        }

        /// Advance with a caller-owned deterministic fuel allowance.
        pub fn nextWithFuel(self: *Self, fuel: *u64) anyerror!FuelStep {
            if (self.terminal_runtime_failure) |err| return err;
            if (self.pending != null or self.done_consumed) return error.ProgramContractViolation;
            const cumulative_remaining = self.remaining_steps;
            const requested: usize = if (fuel.* > std.math.maxInt(usize)) std.math.maxInt(usize) else @intCast(fuel.*);
            const allowance = @min(cumulative_remaining, requested);
            self.remaining_steps = allowance;

            const step = self.next() catch |err| {
                const exhausted_temporary_allowance = self.remaining_steps == 0 and allowance < cumulative_remaining;
                const consumed = allowance - self.remaining_steps;
                self.remaining_steps = cumulative_remaining - consumed;
                fuel.* -= consumed;
                if (err == error.ExecutionBudgetExceeded and
                    self.terminal_failure_instruction_index == null and
                    exhausted_temporary_allowance)
                {
                    return .yielded_fuel;
                }
                const retryable_completed_detach = err == error.OutOfMemory and self.completed != null;
                if (self.terminal_failure_instruction_index == null and !retryable_completed_detach) {
                    self.terminal_runtime_failure = err;
                }
                return err;
            };
            const consumed = allowance - self.remaining_steps;
            self.remaining_steps = cumulative_remaining - consumed;
            fuel.* -= consumed;
            return .{ .step = step };
        }

        pub fn @"resume"(self: *Self, request: Request, value: anytype) anyerror!void {
            const pending = try self.checkedPending(request);
            if (pending.mode == .abort) return error.ProgramContractViolation;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            try validateActiveOperationFrame(active.*, pending);
            if (pending.has_after) try self.scratch.reserveAfterSlot();
            const encoded = try self.encodeResponseRuntimeValueForRef(pending.resume_ref, value);
            if (!valueMatchesRef(pending.resume_ref, encoded)) return error.ProgramContractViolation;
            var locals = self.scratch.frameLocals(active.frame);
            if (pending.has_after) self.scratch.appendReservedAfter(pending.after_stack_entry);
            if (pending.resume_ref.codec == .unit) {
                active.last_return = encoded;
            } else if (pending.dst != std.math.maxInt(u16)) {
                locals[pending.dst] = encoded;
            } else {
                active.last_return = encoded;
            }
            self.pending = null;
        }

        pub fn resumeAfter(self: *Self, request: AfterRequest, value: anytype) anyerror!void {
            const pending = try self.checkedPendingAfter(request);
            if (self.unwinding_after) |*unwind| {
                if (unwind.function_index != pending.function_index or
                    unwind.remaining != pending.remaining or
                    !unwind.current_ref.eql(pending.value_ref) or
                    !unwind.final_ref.eql(pending.result_ref))
                {
                    return error.ProgramContractViolation;
                }
                const encoded = try self.encodeResponseRuntimeValueForRef(pending.output_ref, value);
                if (!valueMatchesRef(pending.output_ref, encoded)) return error.ProgramContractViolation;
                unwind.value = encoded;
                unwind.current_ref = pending.output_ref;
                unwind.remaining -= 1;
            } else return error.ProgramContractViolation;
            self.pending = null;
        }

        pub fn returnNow(self: *Self, request: Request, value: anytype) anyerror!void {
            const pending = try self.checkedPending(request);
            if (pending.mode == .transform) return error.ProgramContractViolation;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            try validateActiveOperationFrame(active.*, pending);
            const encoded = try self.encodeResponseRuntimeValueForRef(pending.result_ref, value);
            if (!valueMatchesRef(pending.result_ref, encoded)) return error.ProgramContractViolation;
            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                active.function_index,
                .{
                    .value = encoded,
                    .initial_ref = pending.result_ref,
                    .after_stack = self.scratch.frameAfterStack(active.frame),
                    .kind = .terminal,
                },
            );
            try validateSessionTerminalPropagation(compiled_plan, &self.scratch, &self.frames, completed);
            const result = (try returnFromSessionFrame(compiled_plan, &self.scratch, &self.frames, .{ .value = completed, .terminal = true })) orelse
                return error.ProgramContractViolation;
            self.completed = result;
            self.pending = null;
        }

        fn beginOrCompleteSessionReturn(
            self: *Self,
            function_index: usize,
            completion: CompletionValue,
        ) anyerror!?Step {
            if (completion.kind == .normal and completion.after_stack.len != 0) {
                const function = compiled_plan.functions[function_index];
                self.unwinding_after = .{
                    .function_index = function_index,
                    .value = completion.value,
                    .current_ref = completion.initial_ref,
                    .final_ref = program_plan.functionResultRef(function),
                    .remaining = completion.after_stack.len,
                };
                return self.continueAfterUnwind();
            }

            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                function_index,
                completion,
            );
            if (try returnFromSessionFrame(compiled_plan, &self.scratch, &self.frames, .{ .value = completed, .terminal = false })) |result| {
                self.completed = result;
                return @as(?Step, try self.consumeCompleted());
            }
            return null;
        }

        fn continueAfterUnwind(self: *Self) anyerror!?Step {
            const unwind = self.unwinding_after orelse return null;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            if (active.function_index != unwind.function_index or active.waiting_helper_dst != null) return error.ProgramContractViolation;

            if (unwind.remaining == 0) {
                return self.completeUnwoundFunction(unwind);
            }

            const after_stack = self.scratch.frameAfterStack(active.frame);
            if (unwind.remaining > after_stack.len) return error.ProgramContractViolation;
            const after_index = unwind.remaining - 1;
            const after_entry = after_stack[after_index];
            const op_index = after_entry.op_index;
            if (after_entry.after_site_index >= after_yield_sites.len) return error.ProgramContractViolation;
            const after_site = after_yield_sites[after_entry.after_site_index];
            if (after_site.index != after_entry.after_site_index or
                after_site.source_operation_site_index != after_entry.operation_site_index or
                after_site.original_op_index != op_index)
            {
                return error.ProgramContractViolation;
            }
            const output_ref = try sessionAfterOutputRefByIndex(
                compiled_plan,
                schema_types,
                HandlersType,
                canonical_request_identity,
                op_index,
                unwind.current_ref,
                unwind.remaining,
                unwind.final_ref,
            );
            const request = try self.makeAfterRequest(
                unwind.function_index,
                after_site,
                op_index,
                unwind.current_ref,
                output_ref,
                unwind.final_ref,
                unwind.remaining,
                unwind.value,
            );
            return .{ .after = request };
        }

        fn completeUnwoundFunction(self: *Self, unwind: AfterUnwind) anyerror!?Step {
            self.unwinding_after = null;
            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                unwind.function_index,
                .{
                    .value = unwind.value,
                    .initial_ref = unwind.final_ref,
                    .after_stack = &.{},
                    .kind = .normal,
                },
            );
            if (try returnFromSessionFrame(compiled_plan, &self.scratch, &self.frames, .{ .value = completed, .terminal = false })) |result| {
                self.completed = result;
                return @as(?Step, try self.consumeCompleted());
            }
            return null;
        }

        fn makeRequest(
            self: *Self,
            function_index: usize,
            block_index: usize,
            instruction_index: usize,
            operation_site: SessionOperationYieldSite,
            dst: u16,
            op_index: u16,
            result_ref: program_plan.ValueRef,
            payload_local_id: u16,
            payload: ExecutableValue,
        ) error{ProgramContractViolation}!Request {
            inline for (compiled_plan.ops, 0..) |op, index| {
                if (op_index == index) {
                    if (operation_site.op_index != op_index or
                        operation_site.function_index != function_index or
                        operation_site.block_index != block_index or
                        operation_site.instruction_index != instruction_index)
                    {
                        return error.ProgramContractViolation;
                    }
                    const requirement = compiled_plan.requirements[op.requirement_index];
                    const resume_ref: program_plan.ValueRef = .{
                        .codec = op.resume_codec,
                        .schema_index = op.resume_schema_index,
                    };
                    const payload_ref: program_plan.ValueRef = .{
                        .codec = op.payload_codec,
                        .schema_index = op.payload_schema_index,
                    };
                    const turn_index = try self.nextTurnIndex();
                    const payload_fingerprint = try Self.fingerprintExecutableValueForRef(payload_ref, payload);
                    const operation_site_fingerprint = if (canonical_request_identity)
                        operation_site.canonical_fingerprint
                    else
                        operation_site.fingerprint;
                    const request_fingerprint = Self.operationRequestFingerprint(
                        canonical_request_identity,
                        turn_index,
                        operation_site.index,
                        operation_site_fingerprint,
                        function_index,
                        block_index,
                        instruction_index,
                        op.requirement_index,
                        requirement.label,
                        op_index,
                        op.op_name,
                        op.mode,
                        payload_ref,
                        payload_fingerprint,
                        resume_ref,
                        result_ref,
                        op.has_after,
                    );
                    const token = try self.takeNextToken();
                    const after_site: ?SessionAfterYieldSite = if (op.has_after) afterSiteForOperationSite(operation_site.index) orelse return error.ProgramContractViolation else null;
                    self.pending = .{ .op = .{
                        .session_id = self.session_id,
                        .token = token,
                        .function_index = function_index,
                        .block_index = block_index,
                        .instruction_index = instruction_index,
                        .dst = dst,
                        .op_index = op_index,
                        .operation_site_index = operation_site.index,
                        .operation_site_fingerprint = operation_site_fingerprint,
                        .turn_index = turn_index,
                        .payload_ref = payload_ref,
                        .payload_local_id = payload_local_id,
                        .payload = payload,
                        .payload_value_fingerprint = payload_fingerprint,
                        .request_fingerprint = request_fingerprint,
                        .mode = op.mode,
                        .resume_ref = resume_ref,
                        .result_ref = result_ref,
                        .has_after = op.has_after,
                        .after_stack_entry = if (after_site) |site| .{
                            .op_index = op_index,
                            .operation_site_index = @intCast(operation_site.index),
                            .after_site_index = @intCast(site.index),
                        } else .{ .op_index = op_index },
                    } };
                    var request: Request = .{
                        ._session_id = self.session_id,
                        .token = token,
                        .operation_site_index = operation_site.index,
                        .operation_site_fingerprint = operation_site_fingerprint,
                        .canonical_operation_site_fingerprint = operation_site.canonical_fingerprint,
                        .semantic_label = operation_site.semantic_label,
                        .function_index = function_index,
                        .block_index = block_index,
                        .instruction_index = instruction_index,
                        .requirement_index = op.requirement_index,
                        .requirement_label = requirement.label,
                        .op_index = op_index,
                        .op_name = op.op_name,
                        .mode = op.mode,
                        .payload_ref = payload_ref,
                        .has_payload = op.payload_codec != .unit,
                        .resume_ref = resume_ref,
                        .result_ref = result_ref,
                        .has_after = op.has_after,
                        ._payload = .none,
                        ._turn_index = turn_index,
                        ._payload_value_fingerprint = payload_fingerprint,
                        ._fingerprint = request_fingerprint,
                        ._plan_fingerprint = if (canonical_request_identity) contract_fingerprint else plan_hash,
                    };
                    try request.setPayload(payload);
                    return request;
                }
            }
            unreachable;
        }

        fn makeAfterRequest(
            self: *Self,
            function_index: usize,
            after_site: SessionAfterYieldSite,
            op_index: u16,
            value_ref: program_plan.ValueRef,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            remaining: usize,
            value: ExecutableValue,
        ) error{ProgramContractViolation}!AfterRequest {
            inline for (compiled_plan.ops, 0..) |op, index| {
                if (op_index == index) {
                    if (!op.has_after) return error.ProgramContractViolation;
                    if (after_site.original_op_index != op_index or after_site.source_function_index != function_index) {
                        return error.ProgramContractViolation;
                    }
                    if (!valueMatchesRef(value_ref, value)) return error.ProgramContractViolation;
                    const requirement = compiled_plan.requirements[op.requirement_index];
                    const turn_index = try self.nextTurnIndex();
                    const value_fingerprint = try Self.fingerprintExecutableValueForRef(value_ref, value);
                    const after_site_fingerprint = if (canonical_request_identity)
                        after_site.canonical_fingerprint
                    else
                        after_site.fingerprint;
                    const source_site_fingerprint = if (canonical_request_identity)
                        after_site.source_operation_site_canonical_fingerprint
                    else
                        after_site.source_operation_site_fingerprint;
                    const request_fingerprint = Self.afterRequestFingerprint(
                        canonical_request_identity,
                        turn_index,
                        after_site.index,
                        after_site_fingerprint,
                        after_site.source_operation_site_index,
                        source_site_fingerprint,
                        after_site.source_function_index,
                        after_site.source_block_index,
                        after_site.source_instruction_index,
                        op.requirement_index,
                        requirement.label,
                        op_index,
                        op.op_name,
                        value_ref,
                        value_fingerprint,
                        output_ref,
                        result_ref,
                        remaining,
                    );
                    const token = try self.takeNextToken();
                    self.pending = .{ .after = .{
                        .session_id = self.session_id,
                        .token = token,
                        .function_index = function_index,
                        .block_index = after_site.source_block_index,
                        .instruction_index = after_site.source_instruction_index,
                        .op_index = op_index,
                        .after_site_index = after_site.index,
                        .after_site_fingerprint = after_site_fingerprint,
                        .source_operation_site_index = after_site.source_operation_site_index,
                        .source_operation_site_fingerprint = source_site_fingerprint,
                        .turn_index = turn_index,
                        .value = value,
                        .value_fingerprint = value_fingerprint,
                        .request_fingerprint = request_fingerprint,
                        .value_ref = value_ref,
                        .output_ref = output_ref,
                        .result_ref = result_ref,
                        .remaining = remaining,
                    } };
                    var request: AfterRequest = .{
                        ._session_id = self.session_id,
                        .token = token,
                        .after_site_index = after_site.index,
                        .after_site_fingerprint = after_site_fingerprint,
                        .canonical_after_site_fingerprint = after_site.canonical_fingerprint,
                        .semantic_label = after_site.semantic_label,
                        .source_operation_site_index = after_site.source_operation_site_index,
                        .source_operation_site_fingerprint = source_site_fingerprint,
                        .source_operation_site_canonical_fingerprint = after_site.source_operation_site_canonical_fingerprint,
                        .function_index = function_index,
                        .block_index = after_site.source_block_index,
                        .instruction_index = after_site.source_instruction_index,
                        .requirement_index = op.requirement_index,
                        .requirement_label = requirement.label,
                        .op_index = op_index,
                        .op_name = op.op_name,
                        .value_ref = value_ref,
                        .has_value = value_ref.codec != .unit,
                        .output_ref = output_ref,
                        .result_ref = result_ref,
                        ._remaining = remaining,
                        ._value = .none,
                        ._turn_index = turn_index,
                        ._value_fingerprint = value_fingerprint,
                        ._fingerprint = request_fingerprint,
                        ._plan_fingerprint = if (canonical_request_identity) contract_fingerprint else plan_hash,
                    };
                    try request.setValue(value);
                    return request;
                }
            }
            return error.ProgramContractViolation;
        }

        fn checkedPending(self: *Self, request: Request) error{ProgramContractViolation}!PendingRequest {
            const pending = switch (self.pending orelse return error.ProgramContractViolation) {
                .op => |pending_op| pending_op,
                .after => return error.ProgramContractViolation,
            };
            if (pending.session_id != request._session_id or
                pending.token != request.token or
                pending.operation_site_index != request.operation_site_index or
                pending.operation_site_fingerprint != request.operation_site_fingerprint or
                pending.function_index != request.function_index or
                pending.block_index != request.block_index or
                pending.instruction_index != request.instruction_index or
                pending.op_index != request.op_index or
                pending.mode != request.mode or
                pending.turn_index != request._turn_index or
                !pending.payload_ref.eql(request.payload_ref) or
                pending.payload_value_fingerprint != request._payload_value_fingerprint or
                pending.request_fingerprint != request._fingerprint or
                pending.has_after != request.has_after or
                request._plan_fingerprint != (if (canonical_request_identity) contract_fingerprint else plan_hash) or
                !pending.resume_ref.eql(request.resume_ref) or
                !pending.result_ref.eql(request.result_ref))
            {
                return error.ProgramContractViolation;
            }
            return pending;
        }

        fn checkedPendingAfter(self: *Self, request: AfterRequest) error{ProgramContractViolation}!PendingAfter {
            const pending = switch (self.pending orelse return error.ProgramContractViolation) {
                .op => return error.ProgramContractViolation,
                .after => |pending_after| pending_after,
            };
            if (pending.session_id != request._session_id or
                pending.token != request.token or
                pending.after_site_index != request.after_site_index or
                pending.after_site_fingerprint != request.after_site_fingerprint or
                pending.source_operation_site_index != request.source_operation_site_index or
                pending.source_operation_site_fingerprint != request.source_operation_site_fingerprint or
                pending.function_index != request.function_index or
                pending.block_index != request.block_index or
                pending.instruction_index != request.instruction_index or
                pending.op_index != request.op_index or
                pending.turn_index != request._turn_index or
                pending.value_fingerprint != request._value_fingerprint or
                pending.request_fingerprint != request._fingerprint or
                request._plan_fingerprint != (if (canonical_request_identity) contract_fingerprint else plan_hash) or
                pending.remaining != request._remaining or
                !pending.value_ref.eql(request.value_ref) or
                !pending.output_ref.eql(request.output_ref) or
                !pending.result_ref.eql(request.result_ref))
            {
                return error.ProgramContractViolation;
            }
            return pending;
        }

        fn consumeCompleted(self: *Self) anyerror!Step {
            const result = self.completed orelse return error.ProgramContractViolation;
            const detached = try self.detachExecutionResult(result);
            self.completed = null;
            self.done_consumed = true;
            return .{ .done = detached };
        }

        pub fn takeCompleted(self: *Self) anyerror!?RawResult {
            if (self.completed == null) return null;
            return switch (try self.consumeCompleted()) {
                .done => |done| done,
                .request => unreachable,
                .after => unreachable,
            };
        }

        fn executableValueMayBorrowRuntimeStorage(
            ref: program_plan.ValueRef,
            value: ExecutableValue,
        ) error{ProgramContractViolation}!bool {
            if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
            return switch (ref.codec) {
                .unit, .bool, .i32, .usize => false,
                .string, .string_list => true,
                .product, .sum => switch (value) {
                    .schema => |schema| blk: {
                        const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                        if (schema.schema_index != schema_index) return error.ProgramContractViolation;
                        inline for (schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                                break :blk typedValueMayBorrowRuntimeStorage(typed.*);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                    else => error.ProgramContractViolation,
                },
            };
        }

        fn detachExecutionResult(self: *Self, result: ExecutionResult) anyerror!RawResult {
            var detached = try self.detachExecutionResultValue(result);
            if (comptime canonical_request_identity) {
                errdefer detached.deinit();
                const owner = try self.allocator.create(OpaqueResultOwner);
                owner.* = .{
                    .allocator = self.allocator,
                    .detached = detached,
                };
                return @ptrCast(owner);
            }
            return detached;
        }

        fn detachExecutionResultValue(self: *Self, result: ExecutionResult) anyerror!DetachedResult {
            const result_ref = comptime program_plan.functionResultRef(entry);
            if (comptime canonical_request_identity) {
                _ = try fingerprintExecutableValueForRef(result_ref, result.value);
            }
            if (comptime !typeMayBorrowRuntimeStorage(ResultValue)) {
                return .{
                    .value = try decodeTypedValue(compiled_plan, schema_types, result_ref, result.value),
                };
            }
            if (!(try executableValueMayBorrowRuntimeStorage(result_ref, result.value))) {
                return .{
                    .value = try decodeTypedValue(compiled_plan, schema_types, result_ref, result.value),
                };
            }
            var scratch = try Scratch.init(self.allocator, 0, 0);
            errdefer scratch.deinit();
            const cloned = try cloneExecutableValueForRef(result_ref, &scratch, result.value);
            const decoded = try decodeTypedValue(compiled_plan, schema_types, result_ref, cloned);
            return .{
                .value = decoded,
                ._storage = .{ .scratch = scratch },
            };
        }

        fn executableValuesShareIdentity(left: ExecutableValue, right: ExecutableValue) bool {
            return switch (left) {
                .schema => |left_schema| switch (right) {
                    .schema => |right_schema| left_schema.schema_index == right_schema.schema_index and left_schema.ptr == right_schema.ptr,
                    else => false,
                },
                .string => |left_string| switch (right) {
                    .string => |right_string| left_string.ptr == right_string.ptr and left_string.len == right_string.len,
                    else => false,
                },
                .string_list => |left_list| switch (right) {
                    .string_list => |right_list| left_list.ptr == right_list.ptr and left_list.len == right_list.len,
                    else => false,
                },
                else => false,
            };
        }

        fn clonedLocalForPendingPayload(
            self: *const Self,
            scratch: *Scratch,
            op: PendingRequest,
        ) ?ExecutableValue {
            if (op.payload_local_id == std.math.maxInt(u16)) return null;
            if (self.frames.len() == 0) return null;
            const frame = self.frames.at(self.frames.len() - 1) orelse return null;
            if (frame.function_index != op.function_index) return null;
            const original_locals = self.scratch.frameLocalsConst(frame.frame);
            if (op.payload_local_id >= original_locals.len) return null;
            const original_payload_local = original_locals[op.payload_local_id];
            if (!executableValuesShareIdentity(original_payload_local, op.payload)) return null;
            const cloned_locals = scratch.frameLocals(frame.frame);
            return cloned_locals[op.payload_local_id];
        }

        fn clonedScratchValueForOriginalIdentity(
            self: *const Self,
            scratch: *Scratch,
            original: ExecutableValue,
        ) ?ExecutableValue {
            for (self.scratch.locals.items, 0..) |value, index| {
                if (executableValuesShareIdentity(value, original)) return scratch.locals.items[index];
            }
            for (self.scratch.call_args.items, 0..) |value, index| {
                if (executableValuesShareIdentity(value, original)) return scratch.call_args.items[index];
            }
            return null;
        }

        fn clonedPriorScratchValueForOriginalIdentity(
            self: *const Self,
            scratch: *Scratch,
            original: ExecutableValue,
            local_limit: usize,
            call_arg_limit: usize,
        ) ?ExecutableValue {
            for (self.scratch.locals.items[0..local_limit], 0..) |value, index| {
                if (executableValuesShareIdentity(value, original)) return scratch.locals.items[index];
            }
            for (self.scratch.call_args.items[0..call_arg_limit], 0..) |value, index| {
                if (executableValuesShareIdentity(value, original)) return scratch.call_args.items[index];
            }
            return null;
        }

        fn cloneExecutableValuePreservingScratchIdentity(
            self: *const Self,
            ref: program_plan.ValueRef,
            clone_context: *CloneContext,
            value: ExecutableValue,
        ) anyerror!ExecutableValue {
            if (self.clonedScratchValueForOriginalIdentity(clone_context.scratch, value)) |cloned| return cloned;
            return cloneExecutableValueForRefWithContext(ref, clone_context, value);
        }

        fn clonePending(
            self: *const Self,
            clone_context: *CloneContext,
            pending: Pending,
        ) anyerror!Pending {
            return switch (pending) {
                .op => |op| blk: {
                    var cloned = op;
                    cloned.payload = self.clonedLocalForPendingPayload(clone_context.scratch, op) orelse
                        try cloneExecutableValueForRefWithContext(op.payload_ref, clone_context, op.payload);
                    break :blk .{ .op = cloned };
                },
                .after => |after| blk: {
                    var cloned = after;
                    cloned.value = try self.cloneExecutableValuePreservingScratchIdentity(after.value_ref, clone_context, after.value);
                    break :blk .{ .after = cloned };
                },
            };
        }

        fn cloneScratchInto(
            self: *const Self,
            clone_context: *CloneContext,
        ) anyerror!void {
            const scratch = clone_context.scratch;

            try scratch.locals.resize(scratch.allocator, self.scratch.locals.items.len);
            for (self.scratch.locals.items, 0..) |value, index| {
                scratch.locals.items[index] = self.clonedPriorScratchValueForOriginalIdentity(scratch, value, index, 0) orelse
                    try cloneExecutableValueByIdentityWithContext(clone_context, value);
            }

            try scratch.call_args.resize(scratch.allocator, self.scratch.call_args.items.len);
            for (self.scratch.call_args.items, 0..) |value, index| {
                scratch.call_args.items[index] = self.clonedPriorScratchValueForOriginalIdentity(scratch, value, self.scratch.locals.items.len, index) orelse
                    try cloneExecutableValueByIdentityWithContext(clone_context, value);
            }

            try scratch.copyAfterEntries(self.scratch.afterEntries());
        }

        fn cloneFrames(
            self: *const Self,
            allocator: std.mem.Allocator,
            clone_context: *CloneContext,
        ) anyerror!ActiveFrameStack {
            var frames = try ActiveFrameStack.init(allocator, self.frames.len());
            errdefer frames.deinit(allocator);
            var index: usize = 0;
            while (index < self.frames.len()) : (index += 1) {
                var frame = self.frames.at(index) orelse return error.ProgramContractViolation;
                frame.last_return = self.clonedScratchValueForOriginalIdentity(clone_context.scratch, frame.last_return) orelse
                    try cloneExecutableValueByIdentityWithContext(clone_context, frame.last_return);
                try frames.append(allocator, frame);
            }
            return frames;
        }

        fn cloneState(self: *const Self, allocator: std.mem.Allocator) anyerror!Self {
            var scratch = try Scratch.init(
                allocator,
                self.scratch.locals.items.len,
                self.scratch.call_args.items.len,
            );
            errdefer scratch.deinit();
            var clone_context = CloneContext.init(&scratch);
            defer clone_context.deinit();
            try self.cloneScratchInto(&clone_context);
            var frames = try self.cloneFrames(allocator, &clone_context);
            errdefer frames.deinit(allocator);

            var core: Self = .{
                .allocator = allocator,
                .scratch = scratch,
                .frames = frames,
                .session_id = self.session_id,
                .remaining_steps = self.remaining_steps,
                .next_token = self.next_token,
                .next_turn_index = self.next_turn_index,
                .terminal_failure_instruction_index = self.terminal_failure_instruction_index,
                .terminal_runtime_failure = self.terminal_runtime_failure,
                .done_consumed = self.done_consumed,
            };
            scratch = .{ .allocator = allocator };
            frames = .{};
            errdefer core.deinit();
            clone_context.scratch = &core.scratch;

            if (self.pending) |pending| {
                core.pending = try self.clonePending(&clone_context, pending);
            }

            if (self.unwinding_after) |unwind| {
                core.unwinding_after = .{
                    .function_index = unwind.function_index,
                    .value = try self.cloneExecutableValuePreservingScratchIdentity(unwind.current_ref, &clone_context, unwind.value),
                    .current_ref = unwind.current_ref,
                    .final_ref = unwind.final_ref,
                    .remaining = unwind.remaining,
                };
            }
            if (self.completed) |completed| {
                core.completed = .{
                    .value = try self.cloneExecutableValuePreservingScratchIdentity(program_plan.functionResultRef(entry), &clone_context, completed.value),
                    .terminal = completed.terminal,
                };
            }

            return core;
        }

        fn reidentifyClone(self: *Self) error{ProgramContractViolation}!void {
            const token = self.next_token;
            if (token == 0 or token == std.math.maxInt(u64)) return error.ProgramContractViolation;
            const session_id = try nextSessionId();
            self.next_token = token + 1;
            self.session_id = session_id;
            if (self.pending) |*pending_union| {
                switch (pending_union.*) {
                    .op => |*pending| {
                        pending.session_id = self.session_id;
                        pending.token = token;
                    },
                    .after => |*pending| {
                        pending.session_id = self.session_id;
                        pending.token = token;
                    },
                }
            }
        }

        fn retokenizePending(self: *Self) error{ProgramContractViolation}!void {
            if (self.pending == null) return error.ProgramContractViolation;
            try self.reidentifyClone();
        }

        fn activeLocalSliceConst(self: *const Self, frame: InterpreterFrame) error{ProgramContractViolation}![]const ExecutableValue {
            const end = frame.locals_start + frame.locals_len;
            if (end > self.scratch.locals.items.len) return error.ProgramContractViolation;
            return self.scratch.locals.items[frame.locals_start..end];
        }

        fn requestPayloadForPending(self: *Self, pending: PendingRequest) error{ProgramContractViolation}!ExecutableValue {
            if (pending.payload_ref.codec == .unit) return .none;
            if (pending.payload_local_id != std.math.maxInt(u16)) {
                if (self.frames.len() == 0) return error.ProgramContractViolation;
                const active_frame = self.frames.top();
                if (active_frame.function_index != pending.function_index) return error.ProgramContractViolation;
                const locals = self.scratch.frameLocals(active_frame.frame);
                if (pending.payload_local_id >= locals.len) return error.ProgramContractViolation;
                const local_payload = locals[pending.payload_local_id];
                if (!valueMatchesRef(pending.payload_ref, local_payload)) return error.ProgramContractViolation;
                return local_payload;
            }
            if (!valueMatchesRef(pending.payload_ref, pending.payload)) return error.ProgramContractViolation;
            return pending.payload;
        }

        fn requestFromPending(self: *Self, pending: PendingRequest) error{ProgramContractViolation}!Request {
            inline for (compiled_plan.ops, 0..) |op, index| {
                if (pending.op_index == index) {
                    if (pending.payload_ref.codec != op.payload_codec or pending.payload_ref.schema_index != op.payload_schema_index) {
                        return error.ProgramContractViolation;
                    }
                    if (pending.operation_site_index >= operation_yield_sites.len) return error.ProgramContractViolation;
                    const operation_site = operation_yield_sites[pending.operation_site_index];
                    const expected_operation_fingerprint = if (canonical_request_identity)
                        operation_site.canonical_fingerprint
                    else
                        operation_site.fingerprint;
                    if (operation_site.index != pending.operation_site_index or
                        expected_operation_fingerprint != pending.operation_site_fingerprint)
                    {
                        return error.ProgramContractViolation;
                    }
                    const requirement = compiled_plan.requirements[op.requirement_index];
                    const snapshot = try self.operationPendingSnapshot(pending);
                    var request: Request = .{
                        ._session_id = pending.session_id,
                        .token = pending.token,
                        .operation_site_index = pending.operation_site_index,
                        .operation_site_fingerprint = pending.operation_site_fingerprint,
                        .canonical_operation_site_fingerprint = operation_site.canonical_fingerprint,
                        .semantic_label = operation_site.semantic_label,
                        .function_index = pending.function_index,
                        .block_index = pending.block_index,
                        .instruction_index = pending.instruction_index,
                        .requirement_index = op.requirement_index,
                        .requirement_label = requirement.label,
                        .op_index = pending.op_index,
                        .op_name = op.op_name,
                        .mode = pending.mode,
                        .payload_ref = pending.payload_ref,
                        .has_payload = pending.payload_ref.codec != .unit,
                        .resume_ref = pending.resume_ref,
                        .result_ref = pending.result_ref,
                        .has_after = pending.has_after,
                        ._payload = .none,
                        ._turn_index = pending.turn_index,
                        ._payload_value_fingerprint = snapshot.payload_value_fingerprint,
                        ._fingerprint = snapshot.request_fingerprint,
                        ._plan_fingerprint = if (canonical_request_identity) contract_fingerprint else plan_hash,
                    };
                    try request.setPayload(snapshot.payload);
                    return request;
                }
            }
            return error.ProgramContractViolation;
        }

        fn afterFromPending(self: *Self, pending: PendingAfter) error{ProgramContractViolation}!AfterRequest {
            const unwind = self.unwinding_after orelse return error.ProgramContractViolation;
            if (unwind.function_index != pending.function_index or
                unwind.remaining != pending.remaining or
                !unwind.current_ref.eql(pending.value_ref) or
                !unwind.final_ref.eql(pending.result_ref))
            {
                return error.ProgramContractViolation;
            }
            inline for (compiled_plan.ops, 0..) |op, index| {
                if (pending.op_index == index) {
                    if (!op.has_after) return error.ProgramContractViolation;
                    if (pending.after_site_index >= after_yield_sites.len) return error.ProgramContractViolation;
                    const after_site = after_yield_sites[pending.after_site_index];
                    const expected_after_fingerprint = if (canonical_request_identity)
                        after_site.canonical_fingerprint
                    else
                        after_site.fingerprint;
                    const expected_source_fingerprint = if (canonical_request_identity)
                        after_site.source_operation_site_canonical_fingerprint
                    else
                        after_site.source_operation_site_fingerprint;
                    if (after_site.index != pending.after_site_index or
                        expected_after_fingerprint != pending.after_site_fingerprint or
                        after_site.source_operation_site_index != pending.source_operation_site_index or
                        expected_source_fingerprint != pending.source_operation_site_fingerprint)
                    {
                        return error.ProgramContractViolation;
                    }
                    const requirement = compiled_plan.requirements[op.requirement_index];
                    var request: AfterRequest = .{
                        ._session_id = pending.session_id,
                        .token = pending.token,
                        .after_site_index = pending.after_site_index,
                        .after_site_fingerprint = pending.after_site_fingerprint,
                        .canonical_after_site_fingerprint = after_site.canonical_fingerprint,
                        .semantic_label = after_site.semantic_label,
                        .source_operation_site_index = pending.source_operation_site_index,
                        .source_operation_site_fingerprint = pending.source_operation_site_fingerprint,
                        .source_operation_site_canonical_fingerprint = after_site.source_operation_site_canonical_fingerprint,
                        .function_index = pending.function_index,
                        .block_index = pending.block_index,
                        .instruction_index = pending.instruction_index,
                        .requirement_index = op.requirement_index,
                        .requirement_label = requirement.label,
                        .op_index = pending.op_index,
                        .op_name = op.op_name,
                        .value_ref = pending.value_ref,
                        .has_value = pending.value_ref.codec != .unit,
                        .output_ref = pending.output_ref,
                        .result_ref = pending.result_ref,
                        ._remaining = pending.remaining,
                        ._value = .none,
                        ._turn_index = pending.turn_index,
                        ._value_fingerprint = pending.value_fingerprint,
                        ._fingerprint = pending.request_fingerprint,
                        ._plan_fingerprint = if (canonical_request_identity) contract_fingerprint else plan_hash,
                    };
                    if (!valueMatchesRef(pending.value_ref, pending.value)) return error.ProgramContractViolation;
                    try request.setValue(pending.value);
                    return request;
                }
            }
            return error.ProgramContractViolation;
        }

        fn capsuleMetadata(self: *const Self) error{ProgramContractViolation}!CapsuleMetadata {
            const frame_count = self.frames.len();
            return switch (self.pending orelse return error.ProgramContractViolation) {
                .op => |pending| blk: {
                    const snapshot = try self.operationPendingSnapshot(pending);
                    break :blk .{
                        .parked_kind = .operation,
                        .current_turn_index = pending.turn_index,
                        .current_request_fingerprint = snapshot.request_fingerprint,
                        .current_operation_site_index = pending.operation_site_index,
                        .result_ref = pending.result_ref,
                        .frame_count = frame_count,
                        .pending_after_count = self.scratch.afterEntries().len,
                        .function_index = pending.function_index,
                        .block_index = pending.block_index,
                        .instruction_index = pending.instruction_index,
                        .continuation_fingerprint = 0,
                    };
                },
                .after => |pending| .{
                    .parked_kind = .after,
                    .current_turn_index = pending.turn_index,
                    .current_request_fingerprint = pending.request_fingerprint,
                    .current_after_site_index = pending.after_site_index,
                    .source_operation_site_index = pending.source_operation_site_index,
                    .result_ref = pending.result_ref,
                    .frame_count = frame_count,
                    .pending_after_count = self.scratch.afterEntries().len,
                    .function_index = pending.function_index,
                    .block_index = pending.block_index,
                    .instruction_index = pending.instruction_index,
                    .continuation_fingerprint = 0,
                },
            };
        }

        fn validateCapsuleMetadata(metadata: CapsuleMetadata) error{ProgramContractViolation}!void {
            if (metadata.version != capsule_version) return error.ProgramContractViolation;
            if (metadata.continuation_fingerprint_version != continuation_fingerprint_version) return error.ProgramContractViolation;
            if (metadata.trace_fingerprint_version != trace_fingerprint_version) return error.ProgramContractViolation;
            if (!std.mem.eql(u8, metadata.program_label, program_label)) return error.ProgramContractViolation;
            if (!std.mem.eql(u8, metadata.plan_label, compiled_plan.label)) return error.ProgramContractViolation;
            if (metadata.plan_hash != plan_hash) return error.ProgramContractViolation;
            if (!metadata.owns_copied_values or !metadata.reusable) return error.ProgramContractViolation;
        }

        fn validateCapsuleShape(self: *const Self, metadata: CapsuleMetadata) error{ProgramContractViolation}!void {
            try validateCapsuleMetadata(metadata);
            var actual = try self.capsuleMetadata();
            actual.continuation_fingerprint = try self.continuationFingerprint();
            if (actual.parked_kind != metadata.parked_kind or
                actual.current_turn_index != metadata.current_turn_index or
                actual.current_request_fingerprint != metadata.current_request_fingerprint or
                actual.current_operation_site_index != metadata.current_operation_site_index or
                actual.current_after_site_index != metadata.current_after_site_index or
                actual.source_operation_site_index != metadata.source_operation_site_index or
                !actual.result_ref.eql(metadata.result_ref) or
                actual.frame_count != metadata.frame_count or
                actual.pending_after_count != metadata.pending_after_count or
                actual.function_index != metadata.function_index or
                actual.block_index != metadata.block_index or
                actual.instruction_index != metadata.instruction_index or
                actual.continuation_fingerprint != metadata.continuation_fingerprint)
            {
                return error.ProgramContractViolation;
            }
        }

        fn traceHashMaybeExecutableValueForRef(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
        ) error{ProgramContractViolation}!void {
            traceHashValueRef(hasher, ref);
            if (!valueMatchesRef(ref, value)) {
                switch (value) {
                    .none => {
                        const value_present = false;
                        traceHashBool(hasher, value_present);
                        return;
                    },
                    else => return error.ProgramContractViolation,
                }
            }
            const value_present = true;
            traceHashBool(hasher, value_present);
            traceHashU64(hasher, try fingerprintExecutableValueForRef(ref, value));
        }

        fn traceHashFrame(hasher: *std.hash.Wyhash, self: *const Self, frame: ActiveInterpreterFrame) error{ProgramContractViolation}!void {
            traceHashUsize(hasher, frame.function_index);
            traceHashUsize(hasher, frame.block_index);
            traceHashUsize(hasher, frame.instruction_index);
            traceHashUsize(hasher, frame.instruction_end);
            traceHashBool(hasher, frame.last_condition);
            traceHashOptionalU16(hasher, frame.waiting_helper_dst);
            traceHashExecutableValueIdentity(hasher, frame.last_return) catch |err| switch (err) {
                error.ProgramContractViolation => {
                    traceHashValueRef(hasher, .{ .codec = .unit });
                    const value_present = false;
                    traceHashBool(hasher, value_present);
                },
            };

            const locals = try self.activeLocalSliceConst(frame.frame);
            traceHashUsize(hasher, locals.len);
            for (locals, 0..) |value, local_index| {
                const local_ref = localRefForFunctionIndex(compiled_plan, frame.function_index, @intCast(local_index)) orelse
                    return error.ProgramContractViolation;
                traceHashUsize(hasher, local_index);
                try traceHashMaybeExecutableValueForRef(hasher, local_ref, value);
            }

            const after_stack = self.scratch.afterEntries()[frame.frame.after_start..];
            traceHashUsize(hasher, after_stack.len);
            for (after_stack) |after_entry| {
                traceHashU16(hasher, after_entry.op_index);
                traceHashU16(hasher, after_entry.operation_site_index);
                traceHashU16(hasher, after_entry.after_site_index);
            }
        }

        fn traceHashPending(self: *const Self, hasher: *std.hash.Wyhash, pending: Pending) error{ProgramContractViolation}!void {
            switch (pending) {
                .op => |op| {
                    const snapshot = try self.operationPendingSnapshot(op);
                    traceHashBytes(hasher, "operation");
                    traceHashUsize(hasher, op.turn_index);
                    traceHashU64(hasher, snapshot.request_fingerprint);
                    traceHashUsize(hasher, op.function_index);
                    traceHashUsize(hasher, op.block_index);
                    traceHashUsize(hasher, op.instruction_index);
                    traceHashU16(hasher, op.dst);
                    traceHashU16(hasher, op.op_index);
                    traceHashUsize(hasher, op.operation_site_index);
                    traceHashU64(hasher, op.operation_site_fingerprint);
                    traceHashMode(hasher, op.mode);
                    traceHashValueRef(hasher, op.payload_ref);
                    traceHashU64(hasher, snapshot.payload_value_fingerprint);
                    traceHashValueRef(hasher, op.resume_ref);
                    traceHashValueRef(hasher, op.result_ref);
                    traceHashBool(hasher, op.has_after);
                    traceHashU16(hasher, op.after_stack_entry.op_index);
                    traceHashU16(hasher, op.after_stack_entry.operation_site_index);
                    traceHashU16(hasher, op.after_stack_entry.after_site_index);
                },
                .after => |after| {
                    traceHashBytes(hasher, "after");
                    traceHashUsize(hasher, after.turn_index);
                    traceHashU64(hasher, after.request_fingerprint);
                    traceHashUsize(hasher, after.function_index);
                    traceHashUsize(hasher, after.block_index);
                    traceHashUsize(hasher, after.instruction_index);
                    traceHashU16(hasher, after.op_index);
                    traceHashUsize(hasher, after.after_site_index);
                    traceHashU64(hasher, after.after_site_fingerprint);
                    traceHashUsize(hasher, after.source_operation_site_index);
                    traceHashU64(hasher, after.source_operation_site_fingerprint);
                    traceHashValueRef(hasher, after.value_ref);
                    traceHashU64(hasher, try fingerprintExecutableValueForRef(after.value_ref, after.value));
                    traceHashValueRef(hasher, after.output_ref);
                    traceHashValueRef(hasher, after.result_ref);
                    traceHashUsize(hasher, after.remaining);
                },
            }
        }

        fn continuationFingerprint(self: *const Self) error{ProgramContractViolation}!u64 {
            const pending = self.pending orelse return error.ProgramContractViolation;
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "boundary.session.continuation");
            traceHashU32(&hasher, capsule_version);
            traceHashU32(&hasher, continuation_fingerprint_version);
            traceHashBytes(&hasher, program_label);
            traceHashBytes(&hasher, compiled_plan.label);
            traceHashU64(&hasher, plan_hash);
            traceHashUsize(&hasher, self.next_turn_index);
            traceHashUsize(&hasher, self.remaining_steps);
            traceHashBool(&hasher, self.done_consumed);
            try self.traceHashPending(&hasher, pending);

            traceHashUsize(&hasher, self.frames.len());
            var frame_index: usize = 0;
            while (frame_index < self.frames.len()) : (frame_index += 1) {
                traceHashUsize(&hasher, frame_index);
                try traceHashFrame(&hasher, self, self.frames.at(frame_index) orelse return error.ProgramContractViolation);
            }

            const after_entries = self.scratch.afterEntries();
            traceHashUsize(&hasher, after_entries.len);
            for (after_entries) |after_entry| {
                traceHashU16(&hasher, after_entry.op_index);
                traceHashU16(&hasher, after_entry.operation_site_index);
                traceHashU16(&hasher, after_entry.after_site_index);
            }

            traceHashBool(&hasher, self.unwinding_after != null);
            if (self.unwinding_after) |unwind| {
                traceHashUsize(&hasher, unwind.function_index);
                traceHashValueRef(&hasher, unwind.current_ref);
                traceHashValueRef(&hasher, unwind.final_ref);
                traceHashUsize(&hasher, unwind.remaining);
                traceHashU64(&hasher, try fingerprintExecutableValueForRef(unwind.current_ref, unwind.value));
            }
            return hasher.final();
        }
    };
}

pub fn runExecutablePlanWithArgsForErrorSet(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try validateExecutablePlanSupport(compiled_plan);
    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);
    return runExecutablePlanWithArgsForErrorSetUnchecked(ErrorSet, runtime, compiled_plan, handlers, args);
}

/// Interpret an executable plan after the caller has already entered runtime execution.
pub fn runExecutablePlanWithArgsForErrorSetInRuntimeExecution(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try validateExecutablePlanSupport(compiled_plan);
    return runExecutablePlanWithArgsForErrorSetUnchecked(ErrorSet, runtime, compiled_plan, handlers, args);
}

fn runExecutablePlanWithArgsForErrorSetUnchecked(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    if (args.len != entry.parameter_count) return error.ProgramContractViolation;
    const analysis = comptime program_plan.entryExecutionAnalysis(compiled_plan) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const after_stack_capacity = if (analysis.reachable_after_count == 0) 0 else max_interpreter_steps;
    var remaining_steps: usize = max_interpreter_steps;
    var scratch = try InterpreterScratch(after_stack_capacity, .embedded).init(
        lowered_machine.runtimeAllocator(runtime),
        analysis.max_active_local_slots,
        analysis.max_active_call_arg_slots,
    );
    defer scratch.deinit();
    var entry_args: [entry.parameter_count]ExecutableValue = undefined;
    try encodePublicEntryArgs(compiled_plan, entry_args[0..], args);
    const raw = try executeFunctionWithFrameStack(ErrorSet, runtime, compiled_plan, &.{}, &.{}, handlers, &scratch, compiled_plan.entry_index, entry_args[0..], &remaining_steps);
    return .{ .value = try decodeArg(program_plan.functionResultCodec(entry), raw.value) };
}

fn encodePublicEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    out: []ExecutableValue,
    args: []const lowered_machine.ProgramValue,
) error{ProgramContractViolation}!void {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    if (args.len != entry.parameter_count or out.len != entry.parameter_count) return error.ProgramContractViolation;
    if (comptime entry.parameter_count == 0) return;
    for (args, 0..) |arg, index| {
        const encoded = executableValueFromPublic(arg);
        const local = compiled_plan.locals[entry.first_local + index];
        if (!valueMatchesRef(.{ .codec = local.codec, .schema_index = local.schema_index }, encoded)) return error.ProgramContractViolation;
        out[index] = encoded;
    }
}

fn encodeTypedTupleEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    scratch: anytype,
    out: []ExecutableValue,
    args: anytype,
) (std.mem.Allocator.Error || error{ProgramContractViolation})!void {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    const Args = @TypeOf(args);
    const args_info = @typeInfo(Args);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("Body.encodeArgs must return []const boundary.ir.ProgramValue or a tuple matching entry parameters");
    }
    const fields = args_info.@"struct".fields;
    if (fields.len != entry.parameter_count) {
        @compileError("Body.encodeArgs tuple length must match ProgramPlan entry parameter_count");
    }
    if (out.len != entry.parameter_count) return error.ProgramContractViolation;
    inline for (fields, 0..) |field, index| {
        const local = compiled_plan.locals[entry.first_local + index];
        const ref: program_plan.ValueRef = .{ .codec = local.codec, .schema_index = local.schema_index };
        if (comptime !typeMatchesRef(compiled_plan, schema_types, ref, field.type)) {
            @compileError(
                "Body.encodeArgs tuple field type does not match ProgramPlan entry parameter " ++
                    std.fmt.comptimePrint("{d}", .{index}) ++
                    ": expected " ++
                    @typeName(ValueTypeForRef(compiled_plan, schema_types, ref)) ++
                    ", found " ++
                    @typeName(field.type),
            );
        }
        out[index] = encodeRuntimeValueForRef(compiled_plan, schema_types, ref, scratch, @field(args, field.name)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ProgramContractViolation,
        };
    }
}

const PublicProgramValueArgsKind = enum {
    slice,
    array_pointer,
};

fn publicProgramValueArgsKind(comptime Args: type) ?PublicProgramValueArgsKind {
    if (Args == []const lowered_machine.ProgramValue or Args == []lowered_machine.ProgramValue) {
        return .slice;
    }
    return switch (@typeInfo(Args)) {
        .pointer => |pointer| switch (pointer.size) {
            .slice => if (pointer.child == lowered_machine.ProgramValue) .slice else null,
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| if (array.child == lowered_machine.ProgramValue) .array_pointer else null,
                else => null,
            },
            .many, .c => null,
        },
        else => null,
    };
}

fn publicProgramValueArgsSlice(args: anytype, comptime kind: PublicProgramValueArgsKind) []const lowered_machine.ProgramValue {
    return switch (kind) {
        .slice => args,
        .array_pointer => args[0..],
    };
}

fn encodeEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    scratch: anytype,
    out: []ExecutableValue,
    args: anytype,
) (std.mem.Allocator.Error || error{ProgramContractViolation})!void {
    const public_args_kind = comptime publicProgramValueArgsKind(@TypeOf(args));
    if (comptime public_args_kind != null) {
        const public_args = publicProgramValueArgsSlice(args, public_args_kind.?);
        return encodePublicEntryArgs(compiled_plan, out, public_args);
    }
    return encodeTypedTupleEntryArgs(compiled_plan, schema_types, scratch, out, args);
}

pub fn runExecutablePlanWithTypedArgsForErrorSetInRuntimeExecution(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    try validateTypedExecutablePlanSupport(compiled_plan, schema_types);
    return runExecutablePlanWithTypedArgsForErrorSetUnchecked(ErrorSet, runtime, compiled_plan, schema_types, handlers, args);
}

pub fn runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsInRuntimeExecution(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    try validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, nested_with_targets);
    return runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsUnchecked(ErrorSet, runtime, compiled_plan, schema_types, nested_with_targets, handlers, args);
}

fn runExecutablePlanWithTypedArgsForErrorSetUnchecked(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    return runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsUnchecked(ErrorSet, runtime, compiled_plan, schema_types, &.{}, handlers, args);
}

fn runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsUnchecked(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    const analysis = comptime program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const after_stack_capacity = if (analysis.reachable_after_count == 0) 0 else max_interpreter_steps;
    var remaining_steps: usize = max_interpreter_steps;
    var scratch = try InterpreterScratch(after_stack_capacity, .embedded).init(
        lowered_machine.runtimeAllocator(runtime),
        analysis.max_active_local_slots,
        analysis.max_active_call_arg_slots,
    );
    defer scratch.deinit();
    var entry_args: [entry.parameter_count]ExecutableValue = undefined;
    try encodeEntryArgs(compiled_plan, schema_types, &scratch, entry_args[0..], args);
    const raw = try executeFunctionWithFrameStack(ErrorSet, runtime, compiled_plan, schema_types, nested_with_targets, handlers, &scratch, compiled_plan.entry_index, entry_args[0..], &remaining_steps);
    return .{ .value = try decodeTypedValue(compiled_plan, schema_types, program_plan.functionResultRef(entry), raw.value) };
}

pub fn runExecutablePlanWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return runExecutablePlanWithArgsForErrorSet(error{}, runtime, compiled_plan, handlers, args);
}

fn supportPlanError(comptime err: anyerror) noreturn {
    @compileError("invalid executable support test plan: " ++ @errorName(err));
}

fn supportSchemaTables(comptime codec: program_plan.ValueCodec) struct {
    schemas: []const program_plan.ValueSchemaPlan,
    fields: []const program_plan.ValueFieldPlan,
    variants: []const program_plan.ValueVariantPlan,
    schema_index: ?u16,
} {
    if (codec == .product) {
        const schemas = [_]program_plan.ValueSchemaPlan{.{
            .label = "Product",
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
        }};
        const fields = [_]program_plan.ValueFieldPlan{.{ .name = "value", .codec = .i32 }};
        return .{ .schemas = &schemas, .fields = &fields, .variants = &.{}, .schema_index = 0 };
    }
    if (codec == .sum) {
        const schemas = [_]program_plan.ValueSchemaPlan{.{
            .label = "Sum",
            .codec = .sum,
            .first_variant = 0,
            .variant_count = 1,
        }};
        const variants = [_]program_plan.ValueVariantPlan{.{ .name = "value", .codec = .i32 }};
        return .{ .schemas = &schemas, .fields = &.{}, .variants = &variants, .schema_index = 0 };
    }
    return .{ .schemas = &.{}, .fields = &.{}, .variants = &.{}, .schema_index = null };
}

fn supportResultPlan(comptime codec: program_plan.ValueCodec) program_plan.ProgramPlan {
    if (codec == .unit) return supportUnitPlan("unit-result");
    const root = program_plan.program_plan_builder.function(0);
    const value = program_plan.program_plan_builder.local(root, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.returnValue(root, value) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = codec,
        .value_schema_index = supportSchemaTables(codec).schema_index,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};
    const schema = supportSchemaTables(codec);
    return program_plan.program_plan_builder.finish(.{
        .label = "unsupported-result",
        .ir_hash = 101,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .value_variants = schema.variants,
        .locals = &.{.{ .codec = codec, .schema_index = schema.schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportLastReturnAliasedPayloadPlan(comptime Payload: type) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const payload = program_plan.program_plan_builder.local(root, 0);
    const resumed = program_plan.program_plan_builder.local(root, 1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.returnValue(root, payload) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callOp(root, resumed, program_plan.program_plan_builder.op(root, 0), payload) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(root, payload) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 0,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 2,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "mutable", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "payload",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .i32,
    }};
    const value_schemas = [_]program_plan.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]program_plan.ValueFieldPlan{.{ .name = "items", .codec = .string_list }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .return_value },
    };
    return program_plan.program_plan_builder.finish(.{
        .label = "session-last-return-aliased-payload",
        .ir_hash = 121,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportHelperArgumentAliasedPayloadPlan(comptime Payload: type) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_payload = program_plan.program_plan_builder.local(root, 0);
    const root_result = program_plan.program_plan_builder.local(root, 1);
    const helper_payload = program_plan.program_plan_builder.local(helper, 0);
    const helper_result = program_plan.program_plan_builder.local(helper, 1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelper(root, root_result, helper, 0) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(root, root_result) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callOp(
            helper,
            helper_result,
            program_plan.program_plan_builder.op(helper, 0),
            helper_payload,
        ) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(helper, helper_result) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 2,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 2,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "mutable", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "payload",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .i32,
    }};
    const value_schemas = [_]program_plan.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]program_plan.ValueFieldPlan{.{ .name = "items", .codec = .string_list }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return program_plan.program_plan_builder.finish(.{
        .label = "session-helper-argument-aliased-payload",
        .ir_hash = 125,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .i32 },
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .i32 },
        },
        .call_args = &.{root_payload.index},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportLastReturnSumPayloadPlan(comptime Payload: type) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const payload = program_plan.program_plan_builder.local(root, 0);
    const resumed = program_plan.program_plan_builder.local(root, 1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.returnValue(root, payload) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callOp(root, resumed, program_plan.program_plan_builder.op(root, 0), payload) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(root, payload) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .sum,
        .value_schema_index = 0,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 2,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "mutable", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "payload",
        .mode = .transform,
        .payload_codec = .sum,
        .payload_schema_index = 0,
        .resume_codec = .i32,
    }};
    const schema = ValueSchemaRegistryForTypes(.{Payload});
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .return_value },
    };
    return program_plan.program_plan_builder.finish(.{
        .label = "session-last-return-sum-payload",
        .ir_hash = 122,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.value_schemas,
        .value_fields = schema.value_fields,
        .value_variants = schema.value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportSchemaCarrierIdentityPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const value = program_plan.program_plan_builder.local(root, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.returnValue(root, value) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 0,
        .result_codec = .product,
        .result_schema_index = 0,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]program_plan.ValueSchemaPlan{.{
        .label = "word-carrier-v1",
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]program_plan.ValueFieldPlan{.{ .name = "word", .codec = .usize }};
    const blocks = [_]program_plan.BlockPlan{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};
    return program_plan.program_plan_builder.finish(.{
        .label = "static-machine-schema-carrier-identity",
        .ir_hash = 126,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportUnitPlan(comptime label: []const u8) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = label,
        .ir_hash = 100,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch |err| supportPlanError(err);
}

fn supportUsizeLiteralPlan(comptime literal: []const u8) program_plan.ProgramPlan {
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .usize,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 2,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};
    const instructions = [_]program_plan.Instruction{
        .{ .kind = .const_usize, .dst = 0, .string_literal = literal },
        .{ .kind = .return_value, .operand = 0 },
    };
    return program_plan.program_plan_builder.finish(.{
        .label = "usize-literal-support",
        .ir_hash = 101,
        .entry = program_plan.program_plan_builder.function(0),
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportParameterPlan(comptime codec: program_plan.ValueCodec) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const schema = supportSchemaTables(codec);
    return program_plan.program_plan_builder.finish(.{
        .label = "unsupported-parameter",
        .ir_hash = 102,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .value_variants = schema.variants,
        .locals = &.{.{ .codec = codec, .schema_index = schema.schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch |err| supportPlanError(err);
}

fn supportOpPlan(comptime payload_codec: program_plan.ValueCodec, comptime resume_codec: program_plan.ValueCodec) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const local = program_plan.program_plan_builder.local(root, 0);
    const payload_ref = if (payload_codec == .unit) null else local;
    const dst_ref = if (resume_codec == .unit) null else local;
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, dst_ref, program_plan.program_plan_builder.op(root, 0), payload_ref) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const payload_schema = supportSchemaTables(payload_codec);
    const resume_schema = supportSchemaTables(resume_codec);
    const schemas = if (payload_codec == .product or payload_codec == .sum)
        payload_schema.schemas
    else
        resume_schema.schemas;
    const fields = if (payload_codec == .product) payload_schema.fields else resume_schema.fields;
    const variants = if (payload_codec == .sum) payload_schema.variants else resume_schema.variants;
    const local_codec = if (payload_codec == .unit) resume_codec else payload_codec;
    const local_schema_index = if (payload_codec == .unit) resume_schema.schema_index else payload_schema.schema_index;
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = payload_codec,
        .payload_schema_index = payload_schema.schema_index,
        .resume_codec = resume_codec,
        .resume_schema_index = resume_schema.schema_index,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "unsupported-op",
        .ir_hash = 103,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schemas,
        .value_fields = fields,
        .value_variants = variants,
        .locals = &.{.{ .codec = local_codec, .schema_index = local_schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStringResumeResultPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const resumed = program_plan.program_plan_builder.local(root, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, resumed, program_plan.program_plan_builder.op(root, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(root, resumed) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "string", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "string",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};
    return program_plan.program_plan_builder.finish(.{
        .label = "string-resume-result",
        .ir_hash = 127,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStandaloneUsizeOpPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const payload = program_plan.program_plan_builder.local(root, 0);
    const resumed = program_plan.program_plan_builder.local(root, 1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, resumed, program_plan.program_plan_builder.op(root, 0), payload) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 1,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "usize", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "usize",
        .mode = .transform,
        .payload_codec = .usize,
        .resume_codec = .usize,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "standalone-usize-op",
        .ir_hash = 124,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .usize }, .{ .codec = .usize } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const instructions = [_]program_plan.Instruction{.{
        .kind = .call_nested_with,
        .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
    }};
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "nested-with",
        .ir_hash = 104,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithStructuredTargetPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const nested = program_plan.program_plan_builder.function(1);
    const nested_payload = program_plan.program_plan_builder.local(nested, 0);
    const instructions = [_]program_plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(program_plan.ValueCodec.unit),
            .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        },
        program_plan.program_plan_builder.callOp(nested, null, program_plan.program_plan_builder.op(nested, 0), nested_payload) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const schema = supportSchemaTables(.product);
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = schema.schema_index,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{ .{ .kind = .return_unit }, .{ .kind = .return_unit } };
    return program_plan.program_plan_builder.finish(.{
        .label = "nested-with-structured-target",
        .ir_hash = 115,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{.{ .codec = .product, .schema_index = schema.schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithStringListTargetPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const nested = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const nested_value = program_plan.program_plan_builder.local(nested, 0);
    const instructions = [_]program_plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(program_plan.ValueCodec.string_list),
            .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        },
        program_plan.program_plan_builder.returnValue(root, root_value) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callOp(nested, nested_value, program_plan.program_plan_builder.op(nested, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(nested, nested_value) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .string_list,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .string_list,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 2,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string_list,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{ .{ .kind = .return_value }, .{ .kind = .return_value } };
    return program_plan.program_plan_builder.finish(.{
        .label = "nested-with-string-list-target",
        .ir_hash = 117,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string_list }, .{ .codec = .string_list } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithTerminalResultMismatchPlan() program_plan.ProgramPlan {
    const instructions = [_]program_plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(program_plan.ValueCodec.unit),
            .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        },
        .{ .kind = .call_op, .operand = 0 },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .unit,
            .result_codec = .string,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return .{
        .label = "nested-with-terminal-result-mismatch",
        .ir_hash = 116,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
}

fn supportManyNestedWithPlan(comptime count: usize) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const instructions = comptime blk: {
        var rows: [count]program_plan.Instruction = undefined;
        for (0..count) |index| {
            rows[index] = .{
                .kind = .call_nested_with,
                .aux = @intFromEnum(program_plan.ValueCodec.unit),
                .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
            };
        }
        break :blk rows;
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "many-nested-with",
        .ir_hash = 114,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredHelperLocalPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelper(root, root_value, helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-local",
        .ir_hash = 105,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredHelperParameterPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, 0),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .unit,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 0,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-helper-parameter",
        .ir_hash = 108,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .product, .schema_index = 0 },
        },
        .call_args = &.{0},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportUnreachableStructuredHelperPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        },
        .{
            .symbol_name = "dead_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "dead-structured-helper",
        .ir_hash = 107,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportHelperCyclePlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        program_plan.program_plan_builder.callHelperDiscardingResult(helper, std.math.maxInt(u16), root, null),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{ .symbol_name = "run", .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 0, .first_block = 0, .entry_block = 0, .block_count = 1, .first_instruction = 0, .instruction_count = 1 },
        .{ .symbol_name = "helper", .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 0, .first_block = 1, .entry_block = 0, .block_count = 1, .first_instruction = 1, .instruction_count = 1 },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return program_plan.program_plan_builder.finish(.{
        .label = "helper-cycle",
        .ir_hash = 106,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportAbortBeforeStructuredHelperPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, null, program_plan.program_plan_builder.op(root, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callHelper(root, root_value, helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "dead_structured_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "abort-before-structured-helper",
        .ir_hash = 109,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportErrorBeforeStructuredHelperPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const error_helper = program_plan.program_plan_builder.function(1);
    const structured_helper = program_plan.program_plan_builder.function(2);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(structured_helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), error_helper, null),
        program_plan.program_plan_builder.callHelper(root, root_value, structured_helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_error, .string_literal = "Rejected" },
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "error_helper",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "dead_structured_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 3,
            .instruction_count = 1,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "error-before-structured-helper",
        .ir_hash = 113,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportAbortBeforeStructuredSuccessorPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, null, program_plan.program_plan_builder.op(root, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callHelper(root, root_value, helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 2,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "dead_structured_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "abort-before-structured-successor",
        .ir_hash = 110,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredTerminalHelperResultPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        program_plan.program_plan_builder.callOp(helper, null, program_plan.program_plan_builder.op(helper, 0), null) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "structured_terminal_helper",
            .value_codec = .unit,
            .result_codec = .product,
            .result_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-terminal-helper-result",
        .ir_hash = 111,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredAfterHelperResultPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        program_plan.program_plan_builder.callOp(helper, null, program_plan.program_plan_builder.op(helper, 0), null) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "structured_after_helper",
            .value_codec = .unit,
            .result_codec = .product,
            .result_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "after", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "after",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
        .has_after = true,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-after-helper-result",
        .ir_hash = 112,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

test "boundary.program executable support accepts scalar entry codecs" {
    inline for (.{ program_plan.ValueCodec.unit, .bool, .i32, .usize, .string }) |codec| {
        try validateExecutablePlanSupport(supportResultPlan(codec));
    }
}

test "boundary.program executable support gates const_usize to native representation" {
    const max_u64_literal = "18446744073709551615";
    const max_u64_plan = comptime supportUsizeLiteralPlan(max_u64_literal);
    try max_u64_plan.validate();

    if (comptime @bitSizeOf(usize) < 64) {
        try std.testing.expectError(error.UnsupportedNativeUsizeLiteral, validateExecutablePlanSupport(max_u64_plan));
        try std.testing.expectError(error.UnsupportedNativeUsizeLiteral, validateTypedExecutablePlanSupport(max_u64_plan, &.{}));
        const ledger = ExecutableCapabilityLedgerForPlan(max_u64_plan, &.{}, &.{});
        try std.testing.expectEqual(@as(usize, 1), ledger.blockers.len);
        try std.testing.expectEqual(CapabilityBlockerTag.native_usize_literal, ledger.blockers[0].tag);
    } else {
        try validateExecutablePlanSupport(max_u64_plan);
        try validateTypedExecutablePlanSupport(max_u64_plan, &.{});
        const ledger = ExecutableCapabilityLedgerForPlan(max_u64_plan, &.{}, &.{});
        try std.testing.expectEqual(@as(usize, 0), ledger.blockers.len);
    }
}

test "boundary.program executable support rejects structured result codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedResultCodec, validateExecutablePlanSupport(supportResultPlan(codec)));
    }
}

test "boundary.program executable support rejects structured terminal helper result codecs" {
    try std.testing.expectError(error.UnsupportedResultCodec, validateExecutablePlanSupport(supportStructuredTerminalHelperResultPlan()));
}

test "boundary.program executable support rejects structured after helper result codecs" {
    try std.testing.expectError(error.UnsupportedResultCodec, validateExecutablePlanSupport(supportStructuredAfterHelperResultPlan()));
}

test "boundary.program executable support rejects structured entry parameter codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedParameterCodec, validateExecutablePlanSupport(supportParameterPlan(codec)));
    }
}

test "boundary.program executable support rejects structured helper parameter codecs" {
    try std.testing.expectError(error.UnsupportedParameterCodec, validateExecutablePlanSupport(supportStructuredHelperParameterPlan()));
}

test "boundary.program executable support rejects structured op payload codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedPayloadCodec, validateExecutablePlanSupport(supportOpPlan(codec, .unit)));
    }
}

test "boundary.program executable support rejects structured op resume codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedResumeCodec, validateExecutablePlanSupport(supportOpPlan(.unit, codec)));
    }
}

test "boundary.program executable support rejects nested-with, reachable structured locals, and helper cycles" {
    try std.testing.expectError(error.UnsupportedNestedWith, validateExecutablePlanSupport(supportNestedWithPlan()));
    try std.testing.expectError(error.UnsupportedLocalCodec, validateExecutablePlanSupport(supportStructuredHelperLocalPlan()));
    try std.testing.expectError(error.UnsupportedHelperCycle, validateExecutablePlanSupport(supportHelperCyclePlan()));
}

test "boundary.program executable capability ledger records unresolved nested-with blockers" {
    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithPlan(), &.{}, &.{});
    try std.testing.expectEqual(@as(usize, 1), ledger.blockers.len);
    try std.testing.expectEqual(CapabilityBlockerTag.nested_with_unresolved, ledger.blockers[0].tag);
    try std.testing.expectEqual(@as(u16, 0), ledger.blockers[0].function_index);
    try std.testing.expectEqual(@as(u32, 0), ledger.blockers[0].instruction_index);
    try std.testing.expect(!ledger.truncated);
}

test "boundary.program executable capability ledger does not block typed helper recursion" {
    try validateTypedExecutablePlanSupport(supportHelperCyclePlan(), &.{});

    const ledger = ExecutableCapabilityLedgerForPlan(supportHelperCyclePlan(), &.{}, &.{});
    try std.testing.expectEqual(@as(usize, 0), ledger.blockers.len);
    try std.testing.expect(!ledger.truncated);
}

test "boundary.program executable capability ledger caps blocker records" {
    const ledger = ExecutableCapabilityLedgerForPlan(supportManyNestedWithPlan(max_capability_blockers + 1), &.{}, &.{});
    try std.testing.expectEqual(@as(usize, max_capability_blockers), ledger.blockers.len);
    try std.testing.expect(ledger.truncated);
}

test "boundary.program executable support validates resolver-backed nested target bodies" {
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    try std.testing.expectError(
        error.UnsupportedPayloadCodec,
        validateTypedExecutablePlanSupportWithNestedTargets(supportNestedWithStructuredTargetPlan(), &.{}, &targets),
    );
    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithStructuredTargetPlan(), &.{}, &targets);
    try std.testing.expectEqual(CapabilityBlockerTag.payload_codec, ledger.blockers[0].tag);
}

test "boundary.program executable capability ledger accepts string-list nested target results" {
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    try validateTypedExecutablePlanSupportWithNestedTargets(supportNestedWithStringListTargetPlan(), &.{}, &targets);

    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithStringListTargetPlan(), &.{}, &targets);
    try std.testing.expectEqual(@as(usize, 0), ledger.blockers.len);
    try std.testing.expect(!ledger.truncated);
}

test "Program.Session cloneState preserves last_return aliases into cloned scratch" {
    const Payload = struct {
        items: [][]const u8,
    };
    const compiled_plan = supportLastReturnAliasedPayloadPlan(Payload);
    const Core = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-last-return-aliased-payload",
        compiled_plan,
        .{Payload},
        &.{},
        struct {},
        struct {},
    );

    var items = [_][]const u8{ "left", "right" };
    var core = try Core.start(std.testing.allocator, .{Payload{ .items = items[0..] }});
    defer core.deinit();
    _ = switch (try core.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };

    var capsule = try core.capture(std.testing.allocator);
    defer capsule.deinit();
    var restored = try Core.restore(std.testing.allocator, &capsule);
    defer restored.deinit();

    const restored_request = switch (try restored.current()) {
        .request => |request| request,
        .after => return error.UnexpectedAfter,
        .none => return error.ExpectedRequest,
    };
    var restored_payload = try restored_request.payload(Payload);
    restored_payload.items[0] = "restored";

    const frame = restored.frames.at(0) orelse return error.ProgramContractViolation;
    const last_return = try decodeTypedValue(
        compiled_plan,
        .{Payload},
        .{ .codec = .product, .schema_index = 0 },
        frame.last_return,
    );
    try std.testing.expectEqualStrings("restored", last_return.items[0]);
}

test "Program.Session validation rejects equal helper arguments with different identity" {
    const Payload = struct {
        items: [][]const u8,
    };
    const compiled_plan = supportHelperArgumentAliasedPayloadPlan(Payload);
    const Core = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-helper-argument-aliased-payload",
        compiled_plan,
        .{Payload},
        &.{},
        struct {},
        struct {},
    );

    var first_items = [_][]const u8{ "left", "right" };
    var first = try Core.start(std.testing.allocator, .{Payload{ .items = first_items[0..] }});
    defer first.deinit();
    _ = switch (try first.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };

    var second_items = [_][]const u8{ "left", "right" };
    var second = try Core.start(std.testing.allocator, .{Payload{ .items = second_items[0..] }});
    defer second.deinit();
    _ = switch (try second.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };

    const first_child = first.frames.at(1) orelse return error.ProgramContractViolation;
    const second_child = second.frames.at(1) orelse return error.ProgramContractViolation;
    const replacement = second.scratch.frameLocalsConst(second_child.frame)[0];
    first.scratch.frameLocals(first_child.frame)[0] = replacement;

    try std.testing.expectError(error.ProgramContractViolation, first.validateState());
}

test "StaticMachine control-path capacity has a fixed compact scratch bound" {
    try std.testing.expectEqual(
        @as(?usize, 8),
        controlPathCapacityForCounts(0, 0, 0),
    );
    try std.testing.expectEqual(
        @as(?usize, static_max_path_states),
        controlPathCapacityForCounts(static_max_control_nodes, 0, 0),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        controlPathCapacityForCounts(static_max_control_nodes + 1, 0, 0),
    );
    try std.testing.expectEqual(@as(usize, 69_632), static_max_path_scratch_bytes);
    try std.testing.expectEqual(
        @as(usize, 1_048_576),
        static_max_control_work_units,
    );
    try std.testing.expectEqual(
        static_max_control_work_units,
        static_max_path_states * 32,
    );
}

test "StaticMachine validation admission keeps acyclic after capacity structural" {
    const compiled_plan = supportStructuredAfterHelperResultPlan();
    const analysis = comptime program_plan.staticEntryExecutionAnalysisWithNestedTargets(
        compiled_plan,
        &.{},
    ) catch unreachable;
    const path_capacity = staticMachineControlPathStateCapacity(compiled_plan).?;
    try std.testing.expectEqual(@as(usize, 1), staticAfterStackCapacity(compiled_plan, analysis));
    try std.testing.expect(
        staticMachineControlValidationStepBound(
            compiled_plan,
            analysis,
            path_capacity,
        ).? < static_max_control_work_units,
    );
}

test "StaticMachine live ownership identifiers exhaust without wrapping" {
    const Core = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-live-ownership-exhaustion",
        supportStandaloneUsizeOpPlan(),
        .{},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );

    const saved_session_id = @atomicLoad(usize, &Core.session_id_source.next, .monotonic);
    defer @atomicStore(usize, &Core.session_id_source.next, saved_session_id, .monotonic);
    @atomicStore(usize, &Core.session_id_source.next, std.math.maxInt(usize) - 1, .monotonic);
    try std.testing.expectEqual(std.math.maxInt(usize) - 1, try Core.nextSessionId());
    try std.testing.expectError(error.ProgramContractViolation, Core.nextSessionId());
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        @atomicLoad(usize, &Core.session_id_source.next, .monotonic),
    );
    @atomicStore(usize, &Core.session_id_source.next, saved_session_id, .monotonic);

    var core = try Core.start(std.testing.allocator, .{@as(usize, 7)});
    defer core.deinit();
    core.next_token = std.math.maxInt(u64) - 1;
    try std.testing.expectEqual(std.math.maxInt(u64) - 1, try core.takeNextToken());
    try std.testing.expectError(error.ProgramContractViolation, core.takeNextToken());
    try std.testing.expectEqual(std.math.maxInt(u64), core.next_token);
}

test "StaticMachine request identity rejects a simulated owner collision" {
    const Core = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-live-ownership-collision",
        supportStandaloneUsizeOpPlan(),
        .{},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );

    var first = try Core.start(std.testing.allocator, .{@as(usize, 7)});
    defer first.deinit();
    const foreign = switch (try first.next()) {
        .request => |request| request,
        else => return error.ProgramContractViolation,
    };

    var second = try Core.start(std.testing.allocator, .{@as(usize, 8)});
    defer second.deinit();
    _ = switch (try second.next()) {
        .request => |request| request,
        else => return error.ProgramContractViolation,
    };
    second.session_id = first.session_id;
    if (second.pending) |*pending_union| switch (pending_union.*) {
        .op => |*pending| pending.session_id = first.session_id,
        .after => return error.ProgramContractViolation,
    } else return error.ProgramContractViolation;

    const authoritative = switch (try second.current()) {
        .request => |request| request,
        else => return error.ProgramContractViolation,
    };
    try std.testing.expectEqual(foreign._session_id, authoritative._session_id);
    try std.testing.expectEqual(foreign.token, authoritative.token);
    try std.testing.expect(foreign._payload_value_fingerprint != authoritative._payload_value_fingerprint);
    try std.testing.expectError(error.ProgramContractViolation, second.@"resume"(foreign, @as(usize, 11)));
    try second.@"resume"(authoritative, @as(usize, 12));
}

test "StaticMachine control-path searches share one exact work budget" {
    const compiled_plan = supportUsizeLiteralPlan("7");
    const Core = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-control-validation-budget",
        compiled_plan,
        .{},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );
    const terminal_block_node = compiled_plan.instructions.len;

    try std.testing.expectEqual(@as(?usize, 0), Core.blockIndexForInstruction(0, 0));
    try std.testing.expectEqual(@as(?usize, null), Core.blockIndexForInstruction(1, 0));

    var budget: Core.ControlValidationBudget = .{ .remaining = 5 };
    try Core.validateControlPathWithoutUnrecordedAfter(
        &budget,
        0,
        0,
        terminal_block_node,
        null,
    );
    try std.testing.expectEqual(@as(usize, 2), budget.remaining);
    try std.testing.expectError(
        error.ProgramContractViolation,
        Core.validateControlPathWithoutUnrecordedAfter(
            &budget,
            0,
            0,
            terminal_block_node,
            null,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), budget.remaining);
}

test "StaticMachine child-frame validation uses generated nested-target metadata" {
    const compiled_plan = supportNestedWithStringListTargetPlan();
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    const StaticCore = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-nested-target-metadata",
        compiled_plan,
        .{},
        &targets,
        struct {},
        struct {},
        1 << 20,
    );
    const LegacyCore = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "legacy-nested-target-metadata",
        compiled_plan,
        .{},
        &targets,
        struct {},
        struct {},
    );

    try std.testing.expectEqual(@as(?usize, 1), StaticCore.nestedTargetIndexForInstruction(0));
    try std.testing.expectEqual(@as(?usize, null), StaticCore.nestedTargetIndexForInstruction(1));
    try std.testing.expectEqual(@as(?usize, 1), LegacyCore.nestedTargetIndexForInstruction(0));

    var core = try StaticCore.start(std.testing.allocator, &.{});
    defer core.deinit();
    _ = switch (try core.next()) {
        .request => |request| request,
        else => return error.ProgramContractViolation,
    };
    try std.testing.expectEqual(@as(usize, 2), core.frames.len());
    try core.validateState();
}

test "StaticMachine canonical coherence compares exact structured values" {
    const Payload = struct {
        items: []const []const u8,
    };
    const compiled_plan = supportLastReturnAliasedPayloadPlan(Payload);
    const Core = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-last-return-aliased-payload",
        compiled_plan,
        .{Payload},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );
    const ref: program_plan.ValueRef = .{ .codec = .product, .schema_index = 0 };

    const first_items = [_][]const u8{ "left", "right" };
    var first = try Core.start(std.testing.allocator, .{Payload{ .items = &first_items }});
    defer first.deinit();
    const first_frame = first.frames.at(0) orelse return error.ProgramContractViolation;
    const first_value = first.scratch.frameLocalsConst(first_frame.frame)[0];

    const equal_items = [_][]const u8{ "left", "right" };
    var equal = try Core.start(std.testing.allocator, .{Payload{ .items = &equal_items }});
    defer equal.deinit();
    const equal_frame = equal.frames.at(0) orelse return error.ProgramContractViolation;
    const equal_value = equal.scratch.frameLocalsConst(equal_frame.frame)[0];

    const different_items = [_][]const u8{ "left", "different" };
    var different = try Core.start(std.testing.allocator, .{Payload{ .items = &different_items }});
    defer different.deinit();
    const different_frame = different.frames.at(0) orelse return error.ProgramContractViolation;
    const different_value = different.scratch.frameLocalsConst(different_frame.frame)[0];

    try std.testing.expect(try Core.executableValuesEqualForRef(ref, first_value, equal_value));
    try std.testing.expect(!(try Core.executableValuesEqualForRef(ref, first_value, different_value)));
    try std.testing.expect(try Core.executableValuesEqualForRef(
        .{ .codec = .usize },
        .{ .usize = 7 },
        .{ .word_u64 = 7 },
    ));
    try std.testing.expect(!(try Core.executableValuesEqualForRef(
        .{ .codec = .usize },
        .{ .usize = 7 },
        .{ .word_u64 = 8 },
    )));
}

test "StaticMachine contract identity binds concrete schema carriers" {
    const FullWidth = struct { word: u64 };
    const CanonicalWidth = struct { word: usize };
    const EquivalentFullWidth = struct { word: u64 };
    const compiled_plan = supportSchemaCarrierIdentityPlan();
    const FullWidthCore = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-machine-schema-carrier-identity",
        compiled_plan,
        .{FullWidth},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );
    const CanonicalWidthCore = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-machine-schema-carrier-identity",
        compiled_plan,
        .{CanonicalWidth},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );
    const EquivalentFullWidthCore = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "static-machine-schema-carrier-identity",
        compiled_plan,
        .{EquivalentFullWidth},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );

    try std.testing.expectEqual(
        FullWidthCore.canonical_plan_fingerprint,
        CanonicalWidthCore.canonical_plan_fingerprint,
    );
    try std.testing.expect(FullWidthCore.contract_fingerprint != CanonicalWidthCore.contract_fingerprint);
    try std.testing.expectEqual(FullWidthCore.contract_fingerprint, EquivalentFullWidthCore.contract_fingerprint);

    var state = try FullWidthCore.start(std.testing.allocator, .{FullWidth{ .word = std.math.maxInt(u64) }});
    defer state.deinit();
    const encoded = try state.encodeState(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        CanonicalWidthCore.decodeState(std.testing.allocator, encoded),
    );
}

test "StaticMachine canonical coherence compares exact sum variants" {
    const Payload = union(enum) {
        text: []const u8,
        count: u64,
    };
    const compiled_plan = supportLastReturnSumPayloadPlan(Payload);
    const Core = StaticExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-last-return-sum-payload",
        compiled_plan,
        .{Payload},
        &.{},
        struct {},
        struct {},
        1 << 20,
    );
    const ref: program_plan.ValueRef = .{ .codec = .sum, .schema_index = 0 };

    var first = try Core.start(std.testing.allocator, .{Payload{ .text = "same" }});
    defer first.deinit();
    var equal = try Core.start(std.testing.allocator, .{Payload{ .text = "same" }});
    defer equal.deinit();
    var different_payload = try Core.start(std.testing.allocator, .{Payload{ .text = "different" }});
    defer different_payload.deinit();
    var different_variant = try Core.start(std.testing.allocator, .{Payload{ .count = 1 }});
    defer different_variant.deinit();

    const first_frame = first.frames.at(0) orelse return error.ProgramContractViolation;
    const equal_frame = equal.frames.at(0) orelse return error.ProgramContractViolation;
    const different_payload_frame = different_payload.frames.at(0) orelse return error.ProgramContractViolation;
    const different_variant_frame = different_variant.frames.at(0) orelse return error.ProgramContractViolation;
    const first_value = first.scratch.frameLocalsConst(first_frame.frame)[0];
    const equal_value = equal.scratch.frameLocalsConst(equal_frame.frame)[0];
    const different_payload_value = different_payload.scratch.frameLocalsConst(different_payload_frame.frame)[0];
    const different_variant_value = different_variant.scratch.frameLocalsConst(different_variant_frame.frame)[0];

    try std.testing.expect(try Core.executableValuesEqualForRef(ref, first_value, equal_value));
    try std.testing.expect(!(try Core.executableValuesEqualForRef(ref, first_value, different_payload_value)));
    try std.testing.expect(!(try Core.executableValuesEqualForRef(ref, first_value, different_variant_value)));
}

test "Program.Session rejects u64 typed access to standalone usize sites" {
    const compiled_plan = supportStandaloneUsizeOpPlan();
    const Core = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-standalone-usize-u64-boundary",
        compiled_plan,
        .{},
        &.{},
        struct {},
        struct {},
    );

    var core = try Core.start(std.testing.allocator, .{@as(usize, 7)});
    defer core.deinit();

    const request = switch (try core.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };

    try std.testing.expectEqual(@as(usize, 7), try request.payload(usize));
    try std.testing.expectError(error.ProgramContractViolation, request.payload(u64));
    _ = try request.responseTrace(.@"resume", @as(usize, 11));
    try std.testing.expectError(error.ProgramContractViolation, request.responseTrace(.@"resume", @as(u64, 11)));
    try core.@"resume"(request, @as(usize, 11));
}

test "Program.Session string resume preserves legacy borrowed response semantics" {
    const Core = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-string-response-borrowing",
        supportStringResumeResultPlan(),
        .{},
        &.{},
        struct {},
        struct {},
    );
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var core = try Core.start(failing.allocator(), &.{});
    defer core.deinit();
    const request = switch (try core.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };

    var response = "borrowed".*;
    const allocations_before = failing.allocations;
    failing.fail_index = allocations_before;
    try core.@"resume"(request, response[0..]);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(allocations_before, failing.allocations);

    response[0] = 'B';
    failing.fail_index = std.math.maxInt(usize);
    var result = switch (try core.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("Borrowed", result.value);
}

test "Program.Session decoded operation pending requires a resumable active frame" {
    const compiled_plan = supportOpPlan(.unit, .i32);
    const Core = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-op-pending-frame-validation",
        compiled_plan,
        .{},
        &.{},
        struct {},
        struct {},
    );

    var core = try Core.start(std.testing.allocator, &.{});
    defer core.deinit();
    _ = switch (try core.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };

    try core.validateDecodedPendingState();

    {
        const original_next_turn_index = core.next_turn_index;
        core.next_turn_index = std.math.maxInt(usize);
        defer core.next_turn_index = original_next_turn_index;
        try std.testing.expectError(error.ProgramContractViolation, core.validateDecodedPendingState());
    }

    {
        const original_next_turn_index = core.next_turn_index;
        core.next_turn_index += 1;
        defer core.next_turn_index = original_next_turn_index;
        try std.testing.expectError(error.ProgramContractViolation, core.validateDecodedPendingState());
    }

    {
        const top = core.frames.top();
        const original_function_index = top.function_index;
        top.function_index = original_function_index + 1;
        defer top.function_index = original_function_index;
        try std.testing.expectError(error.ProgramContractViolation, core.validateDecodedPendingState());
    }

    {
        const top = core.frames.top();
        top.waiting_helper_dst = 0;
        defer top.waiting_helper_dst = null;
        try std.testing.expectError(error.ProgramContractViolation, core.validateDecodedPendingState());
    }
}

test "Program.Session fuel wrapper keeps cumulative exhaustion terminal" {
    const compiled_plan = supportOpPlan(.unit, .i32);
    const Core = ExecutableSessionForPlan(
        error{ProgramContractViolation},
        "session-cumulative-fuel-classification",
        compiled_plan,
        .{},
        &.{},
        struct {},
        struct {},
    );

    var core = try Core.start(std.testing.allocator, &.{});
    defer core.deinit();
    core.remaining_steps = 0;
    var fuel: u64 = std.math.maxInt(u64);
    try std.testing.expectError(error.ExecutionBudgetExceeded, core.nextWithFuel(&fuel));
}

test "boundary.program executable support rejects terminal nested target result mismatches" {
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    try std.testing.expectError(
        error.UnsupportedResultCodec,
        validateTypedExecutablePlanSupportWithNestedTargets(supportNestedWithTerminalResultMismatchPlan(), &.{}, &targets),
    );
    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithTerminalResultMismatchPlan(), &.{}, &targets);
    try std.testing.expectEqual(CapabilityBlockerTag.nested_with_result_codec, ledger.blockers[0].tag);
}

test "boundary.program executable support ignores unreachable structured helper metadata" {
    try validateExecutablePlanSupport(supportUnreachableStructuredHelperPlan());
}

test "boundary.program executable support ignores post-terminal structured helper metadata" {
    try validateExecutablePlanSupport(supportAbortBeforeStructuredHelperPlan());
    try validateExecutablePlanSupport(supportAbortBeforeStructuredSuccessorPlan());
    try validateExecutablePlanSupport(supportErrorBeforeStructuredHelperPlan());
}

test "Program.Session start failure owns moved scratch and frame buffers once" {
    const owner = struct {};
    const Session = ExecutableSessionForPlan(error{}, "support-parameter", supportParameterPlan(.i32), &.{}, &.{}, struct {}, owner);
    const bad_args = [_]lowered_machine.ProgramValue{.{ .bool = true }};

    try std.testing.expectError(
        error.ProgramContractViolation,
        Session.start(std.testing.allocator, bad_args[0..]),
    );
}

test "Program.Session terminal precheck preserves frames on caller result mismatch" {
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 0,
            .first_instruction = 0,
            .instruction_count = 0,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .unit,
            .result_codec = .string,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 0,
            .first_instruction = 0,
            .instruction_count = 0,
        },
    };
    const plan = program_plan.ProgramPlan{
        .label = "session-terminal-precheck",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{},
        .terminators = &.{},
        .instructions = &.{},
    };

    var scratch = try InterpreterScratch(0, .embedded).init(std.testing.allocator, 0, 0);
    defer scratch.deinit();
    var frames = try ActiveFrameStack.init(std.testing.allocator, 2);
    defer frames.deinit(std.testing.allocator);
    defer while (frames.len() != 0) {
        const active = frames.pop().?;
        scratch.popFrame(active.frame);
    };

    const root_frame = try scratch.pushFrame(0);
    try frames.append(std.testing.allocator, .{
        .function_index = 0,
        .frame = root_frame,
        .block_index = 0,
        .instruction_index = 0,
        .instruction_end = 0,
    });
    const helper_frame = try scratch.pushFrame(0);
    try frames.append(std.testing.allocator, .{
        .function_index = 1,
        .frame = helper_frame,
        .block_index = 0,
        .instruction_index = 0,
        .instruction_end = 0,
    });

    try std.testing.expectError(
        error.ProgramContractViolation,
        validateSessionTerminalPropagation(plan, &scratch, &frames, .{ .string = "terminal" }),
    );
    try std.testing.expectEqual(@as(usize, 2), frames.len());
}

test "Program.Session capsule image rejects product carrier field drift" {
    const StoredPayload = struct {
        items: [][]const u8,
    };
    const DriftedPayload = struct {
        items: [][]const u8,
        extra: i32,
    };
    const plan = supportLastReturnAliasedPayloadPlan(StoredPayload);
    const owner = struct {};
    const StoredSession = ExecutableSessionForPlan(error{}, "capsule-product-field-drift", plan, &.{StoredPayload}, &.{}, struct {}, owner);
    const DriftedSession = ExecutableSessionForPlan(error{}, "capsule-product-field-drift", plan, &.{DriftedPayload}, &.{}, struct {}, owner);

    var items = [_][]const u8{ "left", "right" };
    var session = try StoredSession.start(std.testing.allocator, .{StoredPayload{ .items = items[0..] }});
    defer session.deinit();
    _ = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var capsule = try session.capture(std.testing.allocator);
    defer capsule.deinit();
    const image = try capsule.encode(std.testing.allocator);
    defer std.testing.allocator.free(image);

    try std.testing.expectError(error.ProgramContractViolation, DriftedSession.Capsule.decode(std.testing.allocator, image));
}

test "Program.Session capsule image rejects enum carrier variant drift" {
    const StoredPayload = enum {
        approved,
        denied,
    };
    const DriftedPayload = enum {
        accepted,
        denied,
    };
    const plan = supportLastReturnSumPayloadPlan(StoredPayload);
    const owner = struct {};
    const StoredSession = ExecutableSessionForPlan(error{}, "capsule-enum-variant-drift", plan, &.{StoredPayload}, &.{}, struct {}, owner);
    const DriftedSession = ExecutableSessionForPlan(error{}, "capsule-enum-variant-drift", plan, &.{DriftedPayload}, &.{}, struct {}, owner);

    var session = try StoredSession.start(std.testing.allocator, .{StoredPayload.approved});
    defer session.deinit();
    _ = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var capsule = try session.capture(std.testing.allocator);
    defer capsule.deinit();
    const image = try capsule.encode(std.testing.allocator);
    defer std.testing.allocator.free(image);

    try std.testing.expectError(error.ProgramContractViolation, DriftedSession.Capsule.decode(std.testing.allocator, image));
}

test "Program.Session capsule image rejects union carrier variant drift" {
    const StoredPayload = union(enum) {
        approved: i32,
        denied,
    };
    const DriftedPayload = union(enum) {
        accepted: i32,
        denied,
    };
    const plan = supportLastReturnSumPayloadPlan(StoredPayload);
    const owner = struct {};
    const StoredSession = ExecutableSessionForPlan(error{}, "capsule-union-variant-drift", plan, &.{StoredPayload}, &.{}, struct {}, owner);
    const DriftedSession = ExecutableSessionForPlan(error{}, "capsule-union-variant-drift", plan, &.{DriftedPayload}, &.{}, struct {}, owner);

    var session = try StoredSession.start(std.testing.allocator, .{StoredPayload{ .approved = 7 }});
    defer session.deinit();
    _ = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var capsule = try session.capture(std.testing.allocator);
    defer capsule.deinit();
    const image = try capsule.encode(std.testing.allocator);
    defer std.testing.allocator.free(image);

    try std.testing.expectError(error.ProgramContractViolation, DriftedSession.Capsule.decode(std.testing.allocator, image));
}
