const control_ir = @import("control_ir");
const machine = @import("machine");
const portable_value = @import("portable_value");
const rnf = @import("rnf");
const std = @import("std");

const implementation_limits: control_ir.CompilerLimits = .{
    .maximum_values = 1024,
    .maximum_blocks = 128,
    .maximum_constructors = 256,
    .maximum_environment_fields = 128,
    .maximum_invariant_terms = 64,
    .maximum_generated_operations = 32_768,
};
const compiler_evaluation_branch_quota = 500_000_000;
const dynamic_fuel_quantum_bytes: u64 = 16;
// Advance this domain whenever deterministic segment charging changes.
const segment_fuel_semantic_domain =
    "segment-fuel=preflight-resource-shape-v4";

const ResidualResponseMode = enum {
    single_resume,
};

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn compilerLimitsFor(comptime Body: type) control_ir.CompilerLimits {
    const limits: control_ir.CompilerLimits = if (hasDeclSafe(
        Body,
        "compiler_limits",
    )) blk: {
        if (@TypeOf(Body.compiler_limits) != control_ir.CompilerLimits) {
            @compileError(
                "Body.compiler_limits must be control_ir.CompilerLimits",
            );
        }
        break :blk Body.compiler_limits;
    } else .{};

    inline for (std.meta.fields(control_ir.CompilerLimits)) |field| {
        const value = @field(limits, field.name);
        const implementation_maximum = @field(
            implementation_limits,
            field.name,
        );
        if (value == 0) {
            @compileError(
                "Boundary compiler limits must be positive: " ++ field.name,
            );
        }
        if (value > implementation_maximum) {
            @compileError(
                "Boundary compiler limit exceeds the implementation ceiling: " ++
                    field.name,
            );
        }
    }
    if (limits.maximum_environment_fields > limits.maximum_values) {
        @compileError(
            "maximum_environment_fields cannot exceed maximum_values",
        );
    }
    return limits;
}

fn valueName(comptime value: control_ir.ValueId) [:0]const u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    return std.fmt.comptimePrint("v{d}", .{value});
}

const activation_entry_name: [:0]const u8 = "activation_entry";

fn activationValueName(comptime value: control_ir.ValueId) [:0]const u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    return std.fmt.comptimePrint("a{d}", .{value});
}

fn constructorName(comptime id: usize) [:0]const u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    return std.fmt.comptimePrint("c{d}", .{id});
}

fn siteName(comptime id: usize) [:0]const u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    return std.fmt.comptimePrint("s{d}", .{id});
}

fn functionReturnName(comptime id: usize) [:0]const u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    return std.fmt.comptimePrint("f{d}", .{id});
}

fn typeForValue(comptime Body: type, comptime value_type: control_ir.ValueType) type {
    return switch (value_type) {
        .scalar => |scalar| switch (scalar) {
            .unit => void,
            .boolean => bool,
            .i8 => i8,
            .i16 => i16,
            .i32 => i32,
            .i64 => i64,
            .u8 => u8,
            .u16 => u16,
            .u32 => u32,
            .u64 => u64,
        },
        .schema => |index| Body.schema_types[index],
    };
}

fn invariantConstantValue(comptime T: type, value: T) ?rnf.InvariantValue {
    return switch (@typeInfo(T)) {
        .bool => .{ .boolean = value },
        .int => |info| if (info.signedness == .signed)
            .{ .signed = @intCast(value) }
        else
            .{ .unsigned = @intCast(value) },
        .optional => if (value == null)
            .{ .sum_case = 0 }
        else
            null,
        .@"union" => |info| blk: {
            const Tag = info.tag_type orelse break :blk null;
            const active = std.meta.activeTag(value);
            inline for (info.fields, 0..) |field, index| {
                if (active == @field(Tag, field.name)) {
                    break :blk if (field.type == void)
                        .{ .sum_case = @intCast(index) }
                    else
                        null;
                }
            }
            unreachable;
        },
        else => null,
    };
}

fn invariantConstantValues(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime maximum_values: usize,
) [maximum_values]?rnf.InvariantValue {
    var result = [_]?rnf.InvariantValue{null} ** maximum_values;
    inline for (program.blocks) |block| {
        inline for (block.instructions) |instruction| {
            switch (instruction.operation) {
                .constant => |constant_index| {
                    const value = Body.constants[constant_index];
                    result[@intCast(instruction.result)] =
                        invariantConstantValue(@TypeOf(value), value);
                },
                else => {},
            }
        }
    }
    return result;
}

fn validateValueTypeReference(
    comptime Body: type,
    comptime value_type: control_ir.ValueType,
) void {
    switch (value_type) {
        .scalar => {},
        .schema => |index| {
            if (index >= Body.schema_types.len) {
                @compileError(
                    "Control IR value type schema index is out of bounds",
                );
            }
        },
    }
}

fn validateDeclaredValueTypes(
    comptime Body: type,
    comptime program: control_ir.Program,
) void {
    inline for (program.value_types) |value_type| {
        validateValueTypeReference(Body, value_type);
    }
    validateValueTypeReference(Body, program.result_type);
    inline for (program.functions) |function| {
        validateValueTypeReference(Body, function.result_type);
    }
    inline for (program.blocks) |block| {
        switch (block.terminator) {
            .@"suspend" => |suspension| {
                if (suspension.resume_type) |resume_type| {
                    validateValueTypeReference(Body, resume_type);
                }
            },
            else => {},
        }
    }
}

fn structForValues(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime values: []const rnf.EnvironmentField,
) type {
    var names: [values.len][:0]const u8 = undefined;
    var types: [values.len]type = undefined;
    var attributes = [_]std.builtin.Type.StructField.Attributes{.{}} ** values.len;
    inline for (values, 0..) |field, index| {
        const FieldType = typeForValue(Body, field.value_type);
        names[index] = valueName(field.value);
        types[index] = FieldType;
        attributes[index] = .{ .@"align" = @alignOf(FieldType) };
    }
    _ = program;
    return @Struct(.auto, null, &names, &types, &attributes);
}

fn structForContinuationValues(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime constructor: anytype,
    comptime values: []const rnf.EnvironmentField,
) type {
    const activation_count = if (constructor.has_activation_context)
        constructor.activation_len + 1
    else
        0;
    const field_count = activation_count + values.len;
    var names: [field_count][:0]const u8 = undefined;
    var types: [field_count]type = undefined;
    var attributes = [_]std.builtin.Type.StructField.Attributes{.{}} ** field_count;
    var index: usize = 0;
    if (constructor.has_activation_context) {
        names[index] = activation_entry_name;
        types[index] = u32;
        attributes[index] = .{ .@"align" = @alignOf(u32) };
        index += 1;
        inline for (constructor.activationFields()) |field| {
            const FieldType = typeForValue(Body, field.value_type);
            names[index] = activationValueName(field.value);
            types[index] = FieldType;
            attributes[index] = .{ .@"align" = @alignOf(FieldType) };
            index += 1;
        }
    }
    inline for (values) |field| {
        const FieldType = typeForValue(Body, field.value_type);
        names[index] = valueName(field.value);
        types[index] = FieldType;
        attributes[index] = .{ .@"align" = @alignOf(FieldType) };
        index += 1;
    }
    _ = program;
    return @Struct(.auto, null, &names, &types, &attributes);
}

fn valueCatalogType(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime canonical: anytype,
) type {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    var fields: [canonical.value_count]rnf.EnvironmentField = undefined;
    inline for (0..canonical.value_count) |dense_index| {
        const source_value = canonical.value_dense_to_source[dense_index];
        fields[dense_index] = .{
            .value = source_value,
            .value_type = program.value_types[source_value],
        };
    }
    return structForValues(Body, program, &fields);
}

fn addSegmentEdgeValues(
    comptime program: control_ir.Program,
    comptime edge: control_ir.Edge,
    included: anytype,
) void {
    const target = program.blocks[@intCast(edge.target)];
    inline for (target.parameters) |parameter| {
        included[@intCast(parameter)] = true;
    }
    inline for (edge.arguments) |argument| switch (argument) {
        .value => |value| included[@intCast(value)] = true,
        .@"resume" => {},
    };
}

fn segmentStoreType(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime constructor: anytype,
    comptime canonical: anytype,
) type {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    var included = [_]bool{false} ** program.value_types.len;
    inline for (constructor.environmentFields()) |field| {
        included[@intCast(field.value)] = true;
    }
    inline for (constructor.activationFields()) |field| {
        included[@intCast(field.value)] = true;
    }
    const block = program.blocks[@intCast(constructor.source_block)];
    inline for (block.instructions) |instruction| {
        included[@intCast(instruction.result)] = true;
        inline for (instruction.operands) |operand| {
            included[@intCast(operand)] = true;
        }
    }
    switch (block.terminator) {
        .jump => |edge| addSegmentEdgeValues(program, edge, &included),
        .branch => |branch| {
            included[@intCast(branch.condition)] = true;
            addSegmentEdgeValues(program, branch.then_edge, &included);
            addSegmentEdgeValues(program, branch.else_edge, &included);
        },
        .@"suspend" => |suspension| {
            inline for (suspension.request_values) |value| {
                included[@intCast(value)] = true;
            }
            addSegmentEdgeValues(
                program,
                suspension.continuation,
                &included,
            );
            if (suspension.callee) |callee| {
                addSegmentEdgeValues(program, callee, &included);
            }
        },
        .return_value => |maybe_value| if (maybe_value) |value| {
            included[@intCast(value)] = true;
        },
        .return_to_caller => |value| {
            included[@intCast(value)] = true;
        },
        .fail => {},
        .fail_value => |value| {
            included[@intCast(value)] = true;
        },
    }

    var fields: [canonical.value_count]rnf.EnvironmentField = undefined;
    var field_count: usize = 0;
    inline for (0..canonical.value_count) |dense_index| {
        const source_value = canonical.value_dense_to_source[dense_index];
        if (!included[@intCast(source_value)]) continue;
        fields[field_count] = .{
            .value = source_value,
            .value_type = program.value_types[@intCast(source_value)],
        };
        field_count += 1;
    }
    return structForContinuationValues(
        Body,
        program,
        constructor,
        fields[0..field_count],
    );
}

fn maximumSegmentStoreSize(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime normal_form: anytype,
    comptime canonical: anytype,
) usize {
    var maximum: usize = 0;
    inline for (normal_form.constructorSlice()) |constructor| {
        maximum = @max(
            maximum,
            @sizeOf(segmentStoreType(
                Body,
                program,
                constructor,
                canonical,
            )),
        );
    }
    return maximum;
}

fn frameType(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime normal_form: anytype,
) type {
    const count = normal_form.constructor_count;
    var names: [count][:0]const u8 = undefined;
    var values: [count]u32 = undefined;
    var types: [count]type = undefined;
    var attributes = [_]std.builtin.Type.UnionField.Attributes{.{}} ** count;
    inline for (normal_form.constructorSlice(), 0..) |constructor, index| {
        const Environment = structForContinuationValues(
            Body,
            program,
            constructor,
            constructor.environmentFields(),
        );
        names[index] = constructorName(index);
        values[index] = @intCast(index);
        types[index] = Environment;
        attributes[index] = .{ .@"align" = @alignOf(Environment) };
    }
    const Tag = @Enum(u32, .exhaustive, &names, &values);
    return @Union(.auto, Tag, &names, &types, &attributes);
}

fn ResidualEffectAnalysis(comptime source_site_count: usize) type {
    return struct {
        source_to_residual: [source_site_count]?u32 =
            [_]?u32{null} ** source_site_count,
        residual_to_source: [source_site_count]u32 = undefined,
        residual_count: usize = 0,
    };
}

fn analyzeResidualEffects(
    comptime Body: type,
    program: control_ir.Program,
    reachability: anytype,
) ResidualEffectAnalysis(Body.effect_sites.len) {
    var analysis: ResidualEffectAnalysis(Body.effect_sites.len) = .{};
    var referenced = [_]bool{false} ** Body.effect_sites.len;
    for (program.blocks) |block| {
        if (!reachability.contains(block.id)) continue;
        switch (block.terminator) {
            .@"suspend" => |suspension| {
                if (suspension.kind == .effect) {
                    referenced[@intCast(suspension.site_id.?)] = true;
                }
            },
            else => {},
        }
    }
    for (referenced, 0..) |present, source_ordinal| {
        if (!present) continue;
        analysis.source_to_residual[source_ordinal] =
            @intCast(analysis.residual_count);
        analysis.residual_to_source[analysis.residual_count] =
            @intCast(source_ordinal);
        analysis.residual_count += 1;
    }
    return analysis;
}

fn SemanticCanonicalization(
    comptime maximum_values: usize,
    comptime maximum_blocks: usize,
) type {
    return struct {
        const Self = @This();

        block_source_to_dense: [maximum_blocks]?control_ir.BlockId =
            [_]?control_ir.BlockId{null} ** maximum_blocks,
        block_dense_to_source: [maximum_blocks]control_ir.BlockId = undefined,
        value_source_to_dense: [maximum_values]?control_ir.ValueId =
            [_]?control_ir.ValueId{null} ** maximum_values,
        value_dense_to_source: [maximum_values]control_ir.ValueId = undefined,
        function_source_to_dense: [maximum_blocks]?control_ir.FunctionId =
            [_]?control_ir.FunctionId{null} ** maximum_blocks,
        function_dense_to_source: [maximum_blocks]control_ir.FunctionId =
            undefined,
        block_count: usize = 0,
        value_count: usize = 0,
        function_count: usize = 0,

        fn bindValue(self: *Self, source: control_ir.ValueId) void {
            const source_index: usize = @intCast(source);
            if (self.value_source_to_dense[source_index] != null) return;
            self.value_source_to_dense[source_index] =
                @intCast(self.value_count);
            self.value_dense_to_source[self.value_count] = source;
            self.value_count += 1;
        }

        fn bindFunction(
            self: *Self,
            source: control_ir.FunctionId,
        ) void {
            const source_index: usize = @intCast(source);
            if (self.function_source_to_dense[source_index] != null) return;
            self.function_source_to_dense[source_index] =
                @intCast(self.function_count);
            self.function_dense_to_source[self.function_count] = source;
            self.function_count += 1;
        }

        pub fn analyze(
            program: control_ir.Program,
            reachability: anytype,
        ) Self {
            var result: Self = .{};
            result.block_count = reachability.count;
            for (0..reachability.count) |dense_block_index| {
                const source_block = reachability.sourceId(
                    @intCast(dense_block_index),
                ) orelse unreachable;
                result.block_dense_to_source[dense_block_index] =
                    source_block;
                result.block_source_to_dense[source_block] =
                    @intCast(dense_block_index);

                const block = program.blocks[source_block];
                result.bindFunction(block.function_id);
                for (block.parameters) |parameter| {
                    result.bindValue(parameter);
                }
                for (block.instructions) |instruction| {
                    result.bindValue(instruction.result);
                }
            }
            return result;
        }

        pub fn blockId(
            self: Self,
            source: control_ir.BlockId,
        ) control_ir.BlockId {
            return self.block_source_to_dense[source] orelse unreachable;
        }

        pub fn valueId(
            self: Self,
            source: control_ir.ValueId,
        ) control_ir.ValueId {
            return self.value_source_to_dense[source] orelse unreachable;
        }

        pub fn functionId(
            self: Self,
            source: control_ir.FunctionId,
        ) control_ir.FunctionId {
            return self.function_source_to_dense[source] orelse unreachable;
        }
    };
}

fn requestType(comptime Body: type, comptime residual_effects: anytype) type {
    if (residual_effects.residual_count == 0) return void;
    var names: [residual_effects.residual_count][:0]const u8 = undefined;
    var values: [residual_effects.residual_count]u32 = undefined;
    var types: [residual_effects.residual_count]type = undefined;
    var attributes = [_]std.builtin.Type.UnionField.Attributes{.{}} **
        residual_effects.residual_count;
    inline for (0..residual_effects.residual_count) |residual_ordinal| {
        const source_ordinal = residual_effects.residual_to_source[
            residual_ordinal
        ];
        const Site = effectiveSiteFor(Body, @intCast(source_ordinal));
        names[residual_ordinal] = siteName(residual_ordinal);
        values[residual_ordinal] = @intCast(residual_ordinal);
        types[residual_ordinal] = Site.Payload;
        attributes[residual_ordinal] = .{ .@"align" = @alignOf(Site.Payload) };
    }
    const Tag = @Enum(u32, .exhaustive, &names, &values);
    return @Union(.auto, Tag, &names, &types, &attributes);
}

fn returnValueType(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime semantic_canonicalization: anytype,
) type {
    if (semantic_canonicalization.function_count <= 1) return void;
    const count = semantic_canonicalization.function_count - 1;
    var names: [count][:0]const u8 = undefined;
    var values: [count]u32 = undefined;
    var types: [count]type = undefined;
    var attributes = [_]std.builtin.Type.UnionField.Attributes{.{}} ** count;
    var index: usize = 0;
    inline for (
        semantic_canonicalization.function_dense_to_source[0..semantic_canonicalization.function_count],
    ) |source_function_id| {
        if (source_function_id == 0) continue;
        const function = program.functions[@intCast(source_function_id)];
        const ResultType = typeForValue(Body, function.result_type);
        names[index] = functionReturnName(function.id);
        values[index] = @intCast(index);
        types[index] = ResultType;
        attributes[index] = .{ .@"align" = @alignOf(ResultType) };
        index += 1;
    }
    const Tag = @Enum(u32, .exhaustive, &names, &values);
    return @Union(.auto, Tag, &names, &types, &attributes);
}

fn siteFor(comptime Body: type, comptime id: usize) type {
    if (id >= Body.effect_sites.len) {
        @compileError("Control IR references an unknown effect site");
    }
    return Body.effect_sites[id];
}

fn effectiveSiteFor(comptime Body: type, comptime id: usize) type {
    if (hasDeclSafe(Body, "effect_morphisms")) {
        inline for (Body.effect_morphisms) |Morphism| {
            if (@as(usize, @intCast(Morphism.source_id)) == id) {
                return Morphism.Target;
            }
        }
    }
    return siteFor(Body, id);
}

fn handlerFunctionFor(
    comptime Body: type,
    comptime source_site_id: usize,
) ?control_ir.FunctionId {
    if (hasDeclSafe(Body, "effect_handlers")) {
        inline for (Body.effect_handlers) |Handler| {
            if (@as(usize, @intCast(Handler.source_id)) == source_site_id) {
                return Handler.function_id;
            }
        }
    }
    return null;
}

fn NormalizedProgram(
    comptime Body: type,
    comptime source: control_ir.Program,
) type {
    return struct {
        const callee_arguments = blk: {
            var result: [source.blocks.len][1]control_ir.EdgeArgument =
                undefined;
            for (source.blocks, 0..) |block, block_index| {
                result[block_index][0] = .{ .value = 0 };
                switch (block.terminator) {
                    .@"suspend" => |suspension| {
                        if (suspension.kind != .effect) continue;
                        const site_id = suspension.site_id.?;
                        if (handlerFunctionFor(Body, site_id) == null) continue;
                        result[block_index][0] = .{
                            .value = suspension.request_values[0],
                        };
                    },
                    else => {},
                }
            }
            break :blk result;
        };

        const blocks = blk: {
            var result: [source.blocks.len]control_ir.Block = undefined;
            for (source.blocks, 0..) |block, block_index| {
                result[block_index] = block;
                switch (block.terminator) {
                    .@"suspend" => |suspension| {
                        if (suspension.kind != .effect) continue;
                        const site_id = suspension.site_id.?;
                        const function_id = handlerFunctionFor(
                            Body,
                            site_id,
                        ) orelse continue;
                        const function = source.function(function_id) catch
                            unreachable;
                        result[block_index].terminator = .{ .@"suspend" = .{
                            .kind = .call,
                            .callee_function = function_id,
                            .callee = .{
                                .target = function.entry,
                                .arguments = callee_arguments[block_index][0..],
                            },
                            .continuation = suspension.continuation,
                            .resume_type = suspension.resume_type,
                        } };
                    },
                    else => {},
                }
            }
            break :blk result;
        };

        const instruction_definitions = blk: {
            var result = [_]?control_ir.Instruction{null} **
                source.value_types.len;
            for (blocks) |block| {
                for (block.instructions) |instruction| {
                    result[@intCast(instruction.result)] = instruction;
                }
            }
            break :blk result;
        };

        pub const value: control_ir.Program = .{
            .label = source.label,
            .value_types = source.value_types,
            .blocks = &blocks,
            .entry = source.entry,
            .result_type = source.result_type,
            .functions = source.functions,
            .instruction_definitions = &instruction_definitions,
        };
    };
}

fn isVector(comptime T: type) bool {
    return portable_value.isVectorType(T);
}

fn isText(comptime T: type) bool {
    return portable_value.isTextType(T);
}

fn isBytes(comptime T: type) bool {
    return portable_value.isBytesType(T);
}

fn hasDynamicEncodedSize(comptime T: type) bool {
    return portable_value.hasVariableEncodedSize(T);
}

fn failureNamed(comptime Body: type, comptime name: []const u8) Body.Failure {
    inline for (std.meta.fields(Body.Failure)) |field| {
        if (comptime std.mem.eql(u8, field.name, name)) {
            return @field(Body.Failure, field.name);
        }
    }
    @compileError("Body.Failure must declare " ++ name);
}

fn failureFromTag(comptime Body: type, comptime tag: u16) Body.Failure {
    inline for (std.meta.fields(Body.Failure)) |field| {
        if (field.value == tag) {
            return @field(Body.Failure, field.name);
        }
    }
    unreachable;
}

fn minimumBlockCost(comptime block: control_ir.Block) u64 {
    return @intCast(block.instructions.len + 1);
}

fn minimumSourceBlockCost(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime block_id: control_ir.BlockId,
) u64 {
    if (comptime hasDeclSafe(Body, "block_costs")) {
        return Body.block_costs[block_id];
    }
    return minimumBlockCost(program.blocks[block_id]);
}

fn requireOperandCount(
    comptime instruction: control_ir.Instruction,
    comptime expected: usize,
) void {
    if (instruction.operands.len != expected) {
        @compileError(
            "Control IR operation has the wrong operand count",
        );
    }
}

fn operandType(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime instruction: control_ir.Instruction,
    comptime index: usize,
) type {
    if (index >= instruction.operands.len) {
        @compileError("Control IR operation is missing an operand");
    }
    return typeForValue(
        Body,
        program.value_types[instruction.operands[index]],
    );
}

fn validateEqualIntegerBinary(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime instruction: control_ir.Instruction,
    comptime Result: type,
) void {
    requireOperandCount(instruction, 2);
    const Left = operandType(Body, program, instruction, 0);
    const Right = operandType(Body, program, instruction, 1);
    if (@typeInfo(Result) != .int or Left != Result or Right != Result) {
        @compileError(
            "integer operation requires equal fixed-width integer types",
        );
    }
}

fn validateIntegerComparison(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime instruction: control_ir.Instruction,
    comptime Result: type,
) void {
    requireOperandCount(instruction, 2);
    const Left = operandType(Body, program, instruction, 0);
    const Right = operandType(Body, program, instruction, 1);
    if (@typeInfo(Left) != .int or Left != Right or Result != bool) {
        @compileError(
            "integer comparison requires equal integers and a bool result",
        );
    }
}

fn validateInstruction(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime instruction: control_ir.Instruction,
) void {
    const Result = typeForValue(Body, program.value_types[instruction.result]);
    switch (instruction.operation) {
        .metadata => @compileError(
            "executable Boundary Control IR instructions require normative operations",
        ),
        .constant => |constant_index| {
            requireOperandCount(instruction, 0);
            if (!hasDeclSafe(Body, "constants")) {
                @compileError("constant instructions require Body.constants");
            }
            if (constant_index >= Body.constants.len) {
                @compileError("constant instruction index is out of bounds");
            }
            if (@TypeOf(Body.constants[constant_index]) != Result) {
                @compileError("constant instruction type does not match its result");
            }
            _ = portable_value.encodedSize(
                Result,
                Body.constants[constant_index],
            ) catch @compileError("constant instruction value is not canonical");
        },
        .copy => {
            requireOperandCount(instruction, 1);
            const Operand = operandType(Body, program, instruction, 0);
            if (Operand != Result) @compileError("copy type mismatch");
        },
        .compare_eq_zero => {
            requireOperandCount(instruction, 1);
            const Operand = operandType(Body, program, instruction, 0);
            if (@typeInfo(Operand) != .int or Result != bool) {
                @compileError("compare_eq_zero requires integer -> bool");
            }
        },
        .integer_add => {
            validateEqualIntegerBinary(Body, program, instruction, Result);
            _ = failureNamed(Body, "arithmetic_overflow");
        },
        .integer_subtract, .integer_multiply => {
            validateEqualIntegerBinary(Body, program, instruction, Result);
            _ = failureNamed(Body, "arithmetic_overflow");
        },
        .integer_divide, .integer_remainder => {
            validateEqualIntegerBinary(Body, program, instruction, Result);
            _ = failureNamed(Body, "arithmetic_overflow");
            _ = failureNamed(Body, "division_by_zero");
        },
        .integer_negate => {
            requireOperandCount(instruction, 1);
            const Operand = operandType(Body, program, instruction, 0);
            if (@typeInfo(Result) != .int or
                @typeInfo(Result).int.signedness != .signed or
                Operand != Result)
            {
                @compileError(
                    "integer_negate requires one signed fixed-width integer",
                );
            }
            _ = failureNamed(Body, "arithmetic_overflow");
        },
        .integer_equal,
        .integer_not_equal,
        .integer_less_than,
        .integer_less_equal,
        .integer_greater_than,
        .integer_greater_equal,
        => validateIntegerComparison(Body, program, instruction, Result),
        .integer_bit_not => {
            requireOperandCount(instruction, 1);
            const Operand = operandType(Body, program, instruction, 0);
            if (@typeInfo(Result) != .int or Operand != Result) {
                @compileError(
                    "integer_bit_not requires one fixed-width integer",
                );
            }
        },
        .integer_bit_and, .integer_bit_or, .integer_bit_xor => {
            validateEqualIntegerBinary(Body, program, instruction, Result);
        },
        .integer_convert => {
            requireOperandCount(instruction, 1);
            const Operand = operandType(Body, program, instruction, 0);
            if (@typeInfo(Operand) != .int or @typeInfo(Result) != .int) {
                @compileError(
                    "integer_convert requires fixed-width integer types",
                );
            }
            _ = failureNamed(Body, "arithmetic_overflow");
        },
        .enum_to_u32 => {
            requireOperandCount(instruction, 1);
            const Operand = operandType(Body, program, instruction, 0);
            if (@typeInfo(Operand) != .@"enum" or Result != u32) {
                @compileError("enum_to_u32 requires exhaustive enum -> u32");
            }
            portable_value.assertPortable(Operand);
        },
        .boolean_not => {
            requireOperandCount(instruction, 1);
            if (operandType(Body, program, instruction, 0) != bool or
                Result != bool)
            {
                @compileError("boolean_not requires bool -> bool");
            }
        },
        .boolean_and, .boolean_or => {
            requireOperandCount(instruction, 2);
            if (operandType(Body, program, instruction, 0) != bool or
                operandType(Body, program, instruction, 1) != bool or
                Result != bool)
            {
                @compileError("boolean operation requires bool operands");
            }
        },
        .select => {
            requireOperandCount(instruction, 3);
            if (operandType(Body, program, instruction, 0) != bool or
                operandType(Body, program, instruction, 1) != Result or
                operandType(Body, program, instruction, 2) != Result)
            {
                @compileError(
                    "select requires bool and two equal result values",
                );
            }
        },
        .product_construct => {
            if (portable_value.isBytesType(Result) or
                portable_value.isTextType(Result) or
                portable_value.isVectorType(Result))
            {
                @compileError(
                    "generated bounded values are semantic atoms, not generic products",
                );
            }
            const fields = switch (@typeInfo(Result)) {
                .@"struct" => |info| info.fields,
                else => @compileError("product_construct result must be a struct"),
            };
            if (fields.len != instruction.operands.len) {
                @compileError("product_construct field arity mismatch");
            }
            inline for (fields, instruction.operands) |field, operand| {
                if (field.type != typeForValue(
                    Body,
                    program.value_types[operand],
                )) {
                    @compileError("product_construct field type mismatch");
                }
            }
        },
        .product_extract => |field_index| {
            requireOperandCount(instruction, 1);
            const Product = typeForValue(
                Body,
                program.value_types[instruction.operands[0]],
            );
            if (portable_value.isBytesType(Product) or
                portable_value.isTextType(Product) or
                portable_value.isVectorType(Product))
            {
                @compileError(
                    "generated bounded values are semantic atoms, not generic products",
                );
            }
            const fields = switch (@typeInfo(Product)) {
                .@"struct" => |info| info.fields,
                else => @compileError("product_extract operand must be a struct"),
            };
            if (field_index >= fields.len or fields[field_index].type != Result) {
                @compileError("product_extract field mismatch");
            }
        },
        .product_replace => |field_index| {
            requireOperandCount(instruction, 2);
            const Product = operandType(Body, program, instruction, 0);
            const Replacement = operandType(Body, program, instruction, 1);
            if (portable_value.isBytesType(Product) or
                portable_value.isTextType(Product) or
                portable_value.isVectorType(Product))
            {
                @compileError(
                    "generated bounded values are semantic atoms, not generic products",
                );
            }
            const fields = switch (@typeInfo(Product)) {
                .@"struct" => |info| info.fields,
                else => @compileError("product_replace operand must be a struct"),
            };
            if (Result != Product or field_index >= fields.len or
                fields[field_index].type != Replacement)
            {
                @compileError("product_replace field mismatch");
            }
        },
        .sum_construct => |variant_index| {
            const fields = switch (@typeInfo(Result)) {
                .@"union" => |info| info.fields,
                else => @compileError("sum_construct result must be a tagged union"),
            };
            if (@typeInfo(Result).@"union".tag_type == null or
                variant_index >= fields.len)
            {
                @compileError("sum_construct variant is invalid");
            }
            const Payload = fields[variant_index].type;
            if (Payload == void) {
                requireOperandCount(instruction, 0);
            } else {
                requireOperandCount(instruction, 1);
                if (operandType(Body, program, instruction, 0) != Payload) {
                    @compileError("sum_construct payload type mismatch");
                }
            }
        },
        .sum_tag_is => |variant_index| {
            requireOperandCount(instruction, 1);
            const Sum = operandType(Body, program, instruction, 0);
            const info = switch (@typeInfo(Sum)) {
                .@"union" => |value| value,
                else => @compileError("sum_tag_is operand must be a tagged union"),
            };
            if (info.tag_type == null or variant_index >= info.fields.len or
                Result != bool)
            {
                @compileError("sum_tag_is variant or result is invalid");
            }
        },
        .sum_extract => |variant_index| {
            requireOperandCount(instruction, 1);
            const Sum = operandType(Body, program, instruction, 0);
            const info = switch (@typeInfo(Sum)) {
                .@"union" => |value| value,
                else => @compileError("sum_extract operand must be a tagged union"),
            };
            if (info.tag_type == null or variant_index >= info.fields.len or
                Result != info.fields[variant_index].type or Result == void)
            {
                @compileError("sum_extract variant or result is invalid");
            }
            _ = failureNamed(Body, "invalid_variant");
        },
        .optional_none => {
            requireOperandCount(instruction, 0);
            if (@typeInfo(Result) != .optional) {
                @compileError("optional_none result must be optional");
            }
        },
        .optional_some => {
            requireOperandCount(instruction, 1);
            const child = switch (@typeInfo(Result)) {
                .optional => |info| info.child,
                else => @compileError("optional_some result must be optional"),
            };
            if (operandType(Body, program, instruction, 0) != child) {
                @compileError("optional_some payload type mismatch");
            }
        },
        .optional_is_some => {
            requireOperandCount(instruction, 1);
            if (@typeInfo(operandType(Body, program, instruction, 0)) !=
                .optional or Result != bool)
            {
                @compileError("optional_is_some requires optional -> bool");
            }
        },
        .vector_empty => {
            requireOperandCount(instruction, 0);
            if (!isVector(Result)) @compileError("vector_empty result must be Vector");
        },
        .vector_length => {
            requireOperandCount(instruction, 1);
            const Vector = operandType(Body, program, instruction, 0);
            if (!isVector(Vector) or Result != u32) {
                @compileError("vector_length requires Vector -> u32");
            }
        },
        .vector_get => {
            requireOperandCount(instruction, 2);
            const Vector = operandType(Body, program, instruction, 0);
            const Index = operandType(Body, program, instruction, 1);
            if (!isVector(Vector) or Index != u32 or Result != Vector.ElementType) {
                @compileError("vector_get requires Vector and u32 index");
            }
            _ = failureNamed(Body, "invalid_index");
        },
        .vector_set => {
            requireOperandCount(instruction, 3);
            const Vector = operandType(Body, program, instruction, 0);
            if (!isVector(Vector) or Result != Vector or
                operandType(Body, program, instruction, 1) != u32 or
                operandType(Body, program, instruction, 2) != Vector.ElementType)
            {
                @compileError("vector_set type mismatch");
            }
            _ = failureNamed(Body, "invalid_index");
        },
        .vector_push => {
            requireOperandCount(instruction, 2);
            const Vector = operandType(Body, program, instruction, 0);
            const Element = operandType(Body, program, instruction, 1);
            if (!isVector(Vector) or Result != Vector or
                Element != Vector.ElementType)
            {
                @compileError("vector_push type mismatch");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .vector_pop => {
            requireOperandCount(instruction, 1);
            const Vector = operandType(Body, program, instruction, 0);
            const fields = switch (@typeInfo(Result)) {
                .@"struct" => |info| info.fields,
                else => @compileError("vector_pop result must be a product"),
            };
            if (!isVector(Vector) or fields.len != 2 or
                fields[0].type != Vector or
                fields[1].type != ?Vector.ElementType)
            {
                @compileError(
                    "vector_pop result must contain Vector and optional element",
                );
            }
        },
        .vector_truncate => {
            requireOperandCount(instruction, 2);
            const Vector = operandType(Body, program, instruction, 0);
            if (!isVector(Vector) or Result != Vector or
                operandType(Body, program, instruction, 1) != u32)
            {
                @compileError("vector_truncate type mismatch");
            }
        },
        .vector_clear => {
            requireOperandCount(instruction, 1);
            const Vector = operandType(Body, program, instruction, 0);
            if (!isVector(Vector) or Result != Vector) {
                @compileError("vector_clear type mismatch");
            }
        },
        .text_empty => {
            requireOperandCount(instruction, 0);
            if (!isText(Result)) @compileError("text_empty result must be Text");
        },
        .text_length => {
            requireOperandCount(instruction, 1);
            const Text = operandType(Body, program, instruction, 0);
            if (!isText(Text) or Result != u32) {
                @compileError("text_length requires Text -> u32");
            }
        },
        .text_append => {
            requireOperandCount(instruction, 2);
            const Destination = operandType(Body, program, instruction, 0);
            const Suffix = operandType(Body, program, instruction, 1);
            if (!isText(Destination) or !isText(Suffix) or Result != Destination) {
                @compileError("text_append requires Text destination and suffix");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .text_append_scalar => {
            requireOperandCount(instruction, 2);
            const Destination = operandType(Body, program, instruction, 0);
            if (!isText(Destination) or Result != Destination or
                operandType(Body, program, instruction, 1) != u32)
            {
                @compileError("text_append_scalar requires Text and u32");
            }
            _ = failureNamed(Body, "capacity_exceeded");
            _ = failureNamed(Body, "invalid_utf8");
        },
        .text_append_unsigned => {
            requireOperandCount(instruction, 2);
            const Destination = operandType(Body, program, instruction, 0);
            const Integer = operandType(Body, program, instruction, 1);
            if (!isText(Destination) or @typeInfo(Integer) != .int or
                @typeInfo(Integer).int.signedness != .unsigned or
                Result != Destination)
            {
                @compileError("text_append_unsigned requires Text and unsigned integer");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .text_append_signed => {
            requireOperandCount(instruction, 2);
            const Destination = operandType(Body, program, instruction, 0);
            const Integer = operandType(Body, program, instruction, 1);
            if (!isText(Destination) or @typeInfo(Integer) != .int or
                @typeInfo(Integer).int.signedness != .signed or
                Result != Destination)
            {
                @compileError(
                    "text_append_signed requires Text and signed integer",
                );
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .text_copy => {
            requireOperandCount(instruction, 3);
            if (!isText(operandType(Body, program, instruction, 0)) or
                operandType(Body, program, instruction, 1) != u32 or
                operandType(Body, program, instruction, 2) != u32 or
                !isText(Result))
            {
                @compileError("text_copy requires Text, u32, u32 -> Text");
            }
            _ = failureNamed(Body, "capacity_exceeded");
            _ = failureNamed(Body, "invalid_utf8");
        },
        .text_compare => {
            requireOperandCount(instruction, 2);
            const Left = operandType(Body, program, instruction, 0);
            const Right = operandType(Body, program, instruction, 1);
            if (!isText(Left) or !isText(Right) or Result != i8) {
                @compileError("text_compare requires Text, Text -> i8");
            }
        },
        .text_join => {
            requireOperandCount(instruction, 3);
            const Left = operandType(Body, program, instruction, 0);
            const Separator = operandType(Body, program, instruction, 1);
            const Right = operandType(Body, program, instruction, 2);
            if (!isText(Left) or !isText(Separator) or !isText(Right) or
                Result != Left)
            {
                @compileError("text_join requires three Text operands");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .bytes_empty => {
            requireOperandCount(instruction, 0);
            if (!isBytes(Result)) @compileError("bytes_empty result must be Bytes");
        },
        .bytes_length => {
            requireOperandCount(instruction, 1);
            const Bytes = operandType(Body, program, instruction, 0);
            if (!isBytes(Bytes) or Result != u32) {
                @compileError("bytes_length requires Bytes -> u32");
            }
        },
        .bytes_append => {
            requireOperandCount(instruction, 2);
            const Destination = operandType(Body, program, instruction, 0);
            const Suffix = operandType(Body, program, instruction, 1);
            if (!isBytes(Destination) or !isBytes(Suffix) or
                Result != Destination)
            {
                @compileError("bytes_append requires Bytes operands");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .bytes_append_scalar => {
            requireOperandCount(instruction, 2);
            const Destination = operandType(Body, program, instruction, 0);
            if (!isBytes(Destination) or Result != Destination or
                operandType(Body, program, instruction, 1) != u8)
            {
                @compileError("bytes_append_scalar requires Bytes and u8");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .bytes_copy => {
            requireOperandCount(instruction, 3);
            if (!isBytes(operandType(Body, program, instruction, 0)) or
                operandType(Body, program, instruction, 1) != u32 or
                operandType(Body, program, instruction, 2) != u32 or
                !isBytes(Result))
            {
                @compileError("bytes_copy requires Bytes, u32, u32 -> Bytes");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
        .bytes_compare => {
            requireOperandCount(instruction, 2);
            const Left = operandType(Body, program, instruction, 0);
            const Right = operandType(Body, program, instruction, 1);
            if (!isBytes(Left) or !isBytes(Right) or Result != i8) {
                @compileError("bytes_compare requires Bytes, Bytes -> i8");
            }
        },
        .bytes_join => {
            requireOperandCount(instruction, 3);
            const Left = operandType(Body, program, instruction, 0);
            const Separator = operandType(Body, program, instruction, 1);
            const Right = operandType(Body, program, instruction, 2);
            if (!isBytes(Left) or !isBytes(Separator) or !isBytes(Right) or
                Result != Left)
            {
                @compileError("bytes_join requires three Bytes operands");
            }
            _ = failureNamed(Body, "capacity_exceeded");
        },
    }
}

fn validateBody(
    comptime Body: type,
    comptime program: control_ir.Program,
    comptime limits: control_ir.CompilerLimits,
) void {
    inline for (.{
        "InitialArgs",
        "Result",
        "Failure",
        "effect_sites",
        "schema_types",
    }) |name| {
        if (!hasDeclSafe(Body, name)) {
            @compileError("Boundary source Body is missing " ++ name);
        }
    }
    validateDeclaredValueTypes(Body, program);
    control_ir.validate(
        limits.maximum_values,
        limits.maximum_blocks,
        program,
    ) catch |err|
        @compileError("Boundary source Control IR is invalid: " ++ @errorName(err));
    if (program.functions.len > program.blocks.len) {
        @compileError("Boundary source functions cannot exceed source blocks");
    }
    const entry = program.blocks[program.entry];
    if (entry.parameters.len > 1) {
        @compileError("Boundary compiler currently admits at most one entry value");
    }
    if (entry.parameters.len == 0) {
        if (Body.InitialArgs != void) {
            @compileError("zero-argument Control IR requires InitialArgs = void");
        }
    } else if (typeForValue(
        Body,
        program.value_types[entry.parameters[0]],
    ) != Body.InitialArgs) {
        @compileError("Control IR entry value does not match InitialArgs");
    }
    if (typeForValue(Body, program.result_type) != Body.Result) {
        @compileError("Control IR result type does not match Result");
    }
    switch (@typeInfo(Body.Failure)) {
        .@"enum" => {},
        else => @compileError("Body.Failure must be an exhaustive enum"),
    }
    portable_value.assertPortable(Body.InitialArgs);
    portable_value.assertPortable(Body.Result);
    portable_value.assertPortable(Body.Failure);
    inline for (Body.schema_types) |Schema| {
        portable_value.assertPortable(Schema);
    }
    inline for (Body.effect_sites, 0..) |Site, index| {
        if (!hasDeclSafe(Site, "Payload") or
            !hasDeclSafe(Site, "Resume") or
            !hasDeclSafe(Site, "semantic_identity"))
        {
            @compileError(
                "each effect site must declare Payload, Resume, and semantic_identity",
            );
        }
        if (hasDeclSafe(Site, "id") and
            hasDeclSafe(Site, "site_id") and
            Site.id != Site.site_id)
        {
            @compileError("effect site id and site_id declarations must agree");
        }
        if ((hasDeclSafe(Site, "id") and Site.id != index) or
            (hasDeclSafe(Site, "site_id") and Site.site_id != index))
        {
            @compileError("effect site ids must be dense from zero");
        }
        const semantic_identity: []const u8 = Site.semantic_identity;
        if (semantic_identity.len == 0) {
            @compileError("effect site semantic_identity must be non-empty");
        }
        portable_value.assertPortable(Site.Payload);
        portable_value.assertPortable(Site.Resume);
    }
    if (hasDeclSafe(Body, "effect_morphisms")) {
        var seen = [_]bool{false} ** Body.effect_sites.len;
        inline for (Body.effect_morphisms) |Morphism| {
            if (!hasDeclSafe(Morphism, "source_id") or
                !hasDeclSafe(Morphism, "Target"))
            {
                @compileError(
                    "effect morphisms must declare source_id and Target",
                );
            }
            const source_id: usize = @intCast(Morphism.source_id);
            if (source_id >= Body.effect_sites.len) {
                @compileError("effect morphism source_id is out of bounds");
            }
            if (seen[source_id]) {
                @compileError(
                    "effect morphisms may transform each source site once",
                );
            }
            seen[source_id] = true;
            const Source = Body.effect_sites[source_id];
            const Target = Morphism.Target;
            if (!hasDeclSafe(Target, "Payload") or
                !hasDeclSafe(Target, "Resume") or
                !hasDeclSafe(Target, "semantic_identity"))
            {
                @compileError(
                    "effect morphism Target must be a typed effect site",
                );
            }
            if (Source.Payload != Target.Payload or
                Source.Resume != Target.Resume)
            {
                @compileError(
                    "effect morphisms must preserve Payload and Resume types",
                );
            }
            const target_identity: []const u8 = Target.semantic_identity;
            if (target_identity.len == 0) {
                @compileError(
                    "effect morphism Target semantic_identity must be non-empty",
                );
            }
            portable_value.assertPortable(Target.Payload);
            portable_value.assertPortable(Target.Resume);
        }
    }
    if (hasDeclSafe(Body, "effect_handlers")) {
        var seen = [_]bool{false} ** Body.effect_sites.len;
        inline for (Body.effect_handlers) |Handler| {
            if (!hasDeclSafe(Handler, "source_id") or
                !hasDeclSafe(Handler, "function_id"))
            {
                @compileError(
                    "effect handlers must declare source_id and function_id",
                );
            }
            const source_id: usize = @intCast(Handler.source_id);
            if (source_id >= Body.effect_sites.len) {
                @compileError("effect handler source_id is out of bounds");
            }
            if (seen[source_id]) {
                @compileError(
                    "effect handlers may eliminate each source site once",
                );
            }
            seen[source_id] = true;
            if (Handler.function_id == 0) {
                @compileError(
                    "effect handlers must target a non-root helper function",
                );
            }
            const function = program.function(Handler.function_id) catch
                @compileError("effect handler function_id is out of bounds");
            const handler_entry = program.blocks[function.entry];
            if (handler_entry.parameters.len != 1 or
                typeForValue(
                    Body,
                    program.value_types[handler_entry.parameters[0]],
                ) != Body.effect_sites[source_id].Payload)
            {
                @compileError(
                    "effect handler function input must match source Payload",
                );
            }
            if (typeForValue(Body, function.result_type) !=
                Body.effect_sites[source_id].Resume)
            {
                @compileError(
                    "effect handler function result must match source Resume",
                );
            }
            if (hasDeclSafe(Body, "effect_morphisms")) {
                inline for (Body.effect_morphisms) |Morphism| {
                    if (Morphism.source_id == Handler.source_id) {
                        @compileError(
                            "an effect site cannot have both a handler and morphism",
                        );
                    }
                }
            }
        }
    }
    if (hasDeclSafe(Body, "block_costs") and
        Body.block_costs.len != program.blocks.len)
    {
        @compileError("Body.block_costs must cover every Control IR block");
    }
    if (hasDeclSafe(Body, "block_costs")) {
        inline for (program.blocks) |block| {
            if (Body.block_costs[block.id] < minimumBlockCost(block)) {
                @compileError(
                    "Body.block_costs cannot undercharge Control IR operations",
                );
            }
        }
    }
    for (program.blocks) |block| {
        inline for (block.instructions) |instruction| {
            validateInstruction(Body, program, instruction);
        }
        switch (block.terminator) {
            .@"suspend" => |suspension| {
                switch (suspension.kind) {
                    .effect => {
                        if (suspension.request_values.len != 1) {
                            @compileError(
                                "effect sites currently require one typed payload value",
                            );
                        }
                        const site_id = suspension.site_id orelse
                            @compileError("effect suspension is missing its site id");
                        const Site = siteFor(Body, site_id);
                        const payload_type = typeForValue(
                            Body,
                            program.value_types[suspension.request_values[0]],
                        );
                        if (payload_type != Site.Payload) {
                            @compileError("effect payload type does not match its site");
                        }
                        const resume_type = suspension.resume_type orelse
                            @compileError("effect suspension is missing its resume type");
                        if (typeForValue(Body, resume_type) != Site.Resume) {
                            @compileError("effect resume type does not match its site");
                        }
                    },
                    .call => {
                        if (program.functions.len <= 1) {
                            @compileError(
                                "call suspension requires explicit helper functions",
                            );
                        }
                    },
                    .explicit_yield, .caller_fuel => {},
                }
            },
            .return_to_caller => {},
            .fail => |failure| {
                const failure_fields = @typeInfo(Body.Failure).@"enum".fields;
                var tag_exists = false;
                inline for (failure_fields) |field| {
                    if (field.value == failure) tag_exists = true;
                }
                if (!tag_exists) {
                    @compileError("Control IR failure tag is outside Body.Failure");
                }
            },
            .fail_value => |value| {
                if (typeForValue(Body, program.value_types[value]) != Body.Failure) {
                    @compileError(
                        "Control IR fail_value must reference Body.Failure",
                    );
                }
            },
            else => {},
        }
    }
}

const SemanticHasher = std.crypto.hash.sha2.Sha256;

fn semanticHashU8(hasher: *SemanticHasher, value: u8) void {
    hasher.update(&.{value});
}

fn semanticHashU16(hasher: *SemanticHasher, value: u16) void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    hasher.update(&bytes);
}

fn semanticHashU32(hasher: *SemanticHasher, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn semanticHashU64(hasher: *SemanticHasher, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn semanticHashBool(hasher: *SemanticHasher, value: bool) void {
    semanticHashU8(hasher, @intFromBool(value));
}

fn semanticHashBytes(hasher: *SemanticHasher, value: []const u8) void {
    semanticHashU64(hasher, @intCast(value.len));
    hasher.update(value);
}

fn semanticHashSchema(comptime T: type, hasher: *SemanticHasher) void {
    const digest = portable_value.schemaDigest(T);
    hasher.update(&digest);
}

fn effectSiteContractDigest(
    comptime Site: type,
    comptime ordinal: usize,
) [32]u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    var hasher = SemanticHasher.init(.{});
    semanticHashBytes(&hasher, "boundary-effect-site-contract-v1");
    semanticHashU32(&hasher, @intCast(ordinal));
    semanticHashBytes(&hasher, Site.semantic_identity);
    semanticHashSchema(Site.Payload, &hasher);
    semanticHashSchema(Site.Resume, &hasher);
    semanticHashBytes(&hasher, "single-resume");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn effectSiteSemanticContractDigest(comptime Site: type) [32]u8 {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    var hasher = SemanticHasher.init(.{});
    semanticHashBytes(&hasher, "boundary-effect-site-semantic-contract-v1");
    semanticHashBytes(&hasher, Site.semantic_identity);
    semanticHashSchema(Site.Payload, &hasher);
    semanticHashSchema(Site.Resume, &hasher);
    semanticHashBytes(&hasher, "single-resume");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn semanticHashValueType(
    comptime Body: type,
    hasher: *SemanticHasher,
    value_type: control_ir.ValueType,
) void {
    semanticHashSchema(typeForValue(Body, value_type), hasher);
}

fn semanticHashEdge(
    hasher: *SemanticHasher,
    edge: control_ir.Edge,
    canonical: anytype,
) void {
    semanticHashU16(hasher, canonical.blockId(edge.target));
    semanticHashU32(hasher, @intCast(edge.arguments.len));
    for (edge.arguments) |argument| {
        switch (argument) {
            .value => |value| {
                semanticHashU8(hasher, 0);
                semanticHashU16(hasher, canonical.valueId(value));
            },
            .@"resume" => semanticHashU8(hasher, 1),
        }
    }
}

fn semanticHashConstantAt(
    comptime Body: type,
    hasher: *SemanticHasher,
    comptime index: usize,
) void {
    if (!hasDeclSafe(Body, "constants")) unreachable;
    if (index >= Body.constants.len) unreachable;
    const value = Body.constants[index];
    const Constant = @TypeOf(value);
    semanticHashSchema(Constant, hasher);
    var encoded: [portable_value.maximumEncodedSize(Constant)]u8 = undefined;
    const length = portable_value.encode(
        Constant,
        value,
        &encoded,
    ) catch unreachable;
    semanticHashBytes(hasher, encoded[0..length]);
}

fn semanticHashInstruction(
    comptime Body: type,
    hasher: *SemanticHasher,
    instruction: control_ir.Instruction,
    canonical: anytype,
) void {
    semanticHashU8(hasher, @intCast(@intFromEnum(instruction.kind)));
    semanticHashU16(hasher, canonical.valueId(instruction.result));
    semanticHashU32(hasher, @intCast(instruction.operands.len));
    for (instruction.operands) |operand| {
        semanticHashU16(hasher, canonical.valueId(operand));
    }
    semanticHashU8(
        hasher,
        @intCast(@intFromEnum(std.meta.activeTag(instruction.operation))),
    );
    switch (instruction.operation) {
        .constant => |constant| semanticHashConstantAt(
            Body,
            hasher,
            constant,
        ),
        .product_extract,
        .product_replace,
        .sum_construct,
        .sum_tag_is,
        .sum_extract,
        => |index| semanticHashU16(hasher, index),
        else => {},
    }
}

fn semanticHashTerminator(
    comptime Body: type,
    hasher: *SemanticHasher,
    terminator: control_ir.Terminator,
    comptime residual_effects: anytype,
    canonical: anytype,
) void {
    semanticHashU8(
        hasher,
        @intCast(@intFromEnum(std.meta.activeTag(terminator))),
    );
    switch (terminator) {
        .jump => |edge| semanticHashEdge(hasher, edge, canonical),
        .branch => |branch| {
            semanticHashU16(hasher, canonical.valueId(branch.condition));
            semanticHashEdge(hasher, branch.then_edge, canonical);
            semanticHashEdge(hasher, branch.else_edge, canonical);
        },
        .@"suspend" => |suspension| {
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(suspension.kind)),
            );
            semanticHashBool(hasher, suspension.site_id != null);
            if (suspension.site_id) |site_id| {
                semanticHashU32(
                    hasher,
                    residual_effects.source_to_residual[@intCast(site_id)] orelse
                        unreachable,
                );
            }
            semanticHashBool(hasher, suspension.callee_function != null);
            if (suspension.callee_function) |function_id| {
                semanticHashU16(
                    hasher,
                    canonical.functionId(function_id),
                );
            }
            semanticHashBool(hasher, suspension.callee != null);
            if (suspension.callee) |callee| {
                semanticHashEdge(hasher, callee, canonical);
            }
            semanticHashU32(hasher, @intCast(suspension.request_values.len));
            for (suspension.request_values) |value| {
                semanticHashU16(hasher, canonical.valueId(value));
            }
            semanticHashEdge(
                hasher,
                suspension.continuation,
                canonical,
            );
            semanticHashBool(hasher, suspension.resume_type != null);
            if (suspension.resume_type) |resume_type| {
                semanticHashValueType(Body, hasher, resume_type);
            }
        },
        .return_value => |maybe_value| {
            semanticHashBool(hasher, maybe_value != null);
            if (maybe_value) |value| {
                semanticHashU16(hasher, canonical.valueId(value));
            }
        },
        .return_to_caller => |value| semanticHashU16(
            hasher,
            canonical.valueId(value),
        ),
        .fail => |failure| semanticHashU16(hasher, failure),
        .fail_value => |value| semanticHashU16(
            hasher,
            canonical.valueId(value),
        ),
    }
}

fn semanticHashInvariantValue(
    hasher: *SemanticHasher,
    value: rnf.InvariantValue,
) void {
    semanticHashU8(
        hasher,
        @intCast(@intFromEnum(std.meta.activeTag(value))),
    );
    switch (value) {
        .boolean => |contents| semanticHashBool(hasher, contents),
        .signed => |contents| semanticHashU64(
            hasher,
            @bitCast(contents),
        ),
        .unsigned => |contents| semanticHashU64(hasher, contents),
        .sum_case => |contents| semanticHashU16(hasher, contents),
    }
}

fn semanticHashInvariant(
    hasher: *SemanticHasher,
    invariant: rnf.InvariantTerm,
    canonical: anytype,
) void {
    semanticHashU8(
        hasher,
        @intCast(@intFromEnum(std.meta.activeTag(invariant))),
    );
    switch (invariant) {
        .boolean => |predicate| {
            semanticHashU16(
                hasher,
                canonical.valueId(predicate.value),
            );
            semanticHashBool(hasher, predicate.expected);
        },
        .boolean_copy => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.source));
        },
        .boolean_not => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.operand));
        },
        .boolean_binary => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.left));
            semanticHashU16(hasher, canonical.valueId(definition.right));
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.operation)),
            );
        },
        .boolean_select => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.condition));
            semanticHashU16(hasher, canonical.valueId(definition.then_value));
            semanticHashU16(hasher, canonical.valueId(definition.else_value));
        },
        .value_copy => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.source));
        },
        .value_constant => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashInvariantValue(hasher, definition.contents);
        },
        .value_select => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.condition));
            semanticHashU16(hasher, canonical.valueId(definition.then_value));
            semanticHashU16(hasher, canonical.valueId(definition.else_value));
        },
        .instruction_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.definition));
            semanticHashU16(hasher, definition.operand_count);
            for (definition.operands[0..definition.operand_count]) |operand| {
                semanticHashU16(hasher, canonical.valueId(operand));
            }
        },
        .product_extract_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.product));
            semanticHashU16(hasher, definition.field_index);
        },
        .sum_extract_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.sum));
            semanticHashU16(hasher, definition.case_index);
        },
        .bounded_length_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.bounded));
        },
        .integer_unary_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.operand));
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.operation)),
            );
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.scalar_type)),
            );
        },
        .integer_binary_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.left));
            semanticHashU16(hasher, canonical.valueId(definition.right));
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.operation)),
            );
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.scalar_type)),
            );
        },
        .integer_convert_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.operand));
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.scalar_type)),
            );
        },
        .integer_zero => |predicate| {
            semanticHashU16(
                hasher,
                canonical.valueId(predicate.value),
            );
            semanticHashBool(hasher, predicate.equal);
        },
        .integer_zero_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.value));
        },
        .integer_relation => |predicate| {
            semanticHashU16(hasher, canonical.valueId(predicate.left));
            semanticHashU16(hasher, canonical.valueId(predicate.right));
            semanticHashU8(hasher, @intCast(@intFromEnum(predicate.relation)));
            semanticHashBool(hasher, predicate.expected);
        },
        .integer_relation_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.left));
            semanticHashU16(hasher, canonical.valueId(definition.right));
            semanticHashU8(
                hasher,
                @intCast(@intFromEnum(definition.relation)),
            );
        },
        .sum_case => |predicate| {
            semanticHashU16(
                hasher,
                canonical.valueId(predicate.value),
            );
            semanticHashU16(hasher, predicate.case_index);
            semanticHashBool(hasher, predicate.equal);
        },
        .sum_case_result => |definition| {
            semanticHashU16(hasher, canonical.valueId(definition.result));
            semanticHashU16(hasher, canonical.valueId(definition.value));
            semanticHashU16(hasher, definition.case_index);
        },
    }
}

fn algebraicCaseIndex(value: anytype) u16 {
    const Value = @TypeOf(value);
    return switch (@typeInfo(Value)) {
        .optional => @intFromBool(value != null),
        .@"union" => |info| blk: {
            const Tag = info.tag_type orelse
                @compileError("sum-case invariant requires a tagged union");
            const active = std.meta.activeTag(value);
            inline for (info.fields, 0..) |field, index| {
                if (active == @field(Tag, field.name)) {
                    break :blk @intCast(index);
                }
            }
            unreachable;
        },
        else => @compileError(
            "sum-case invariant requires a tagged union or optional",
        ),
    };
}

fn invariantValueMatches(value: anytype, expected: rnf.InvariantValue) bool {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .bool => switch (expected) {
            .boolean => |contents| value == contents,
            else => false,
        },
        .int => |info| if (info.signedness == .signed)
            switch (expected) {
                .signed => |contents| @as(i64, value) == contents,
                else => false,
            }
        else switch (expected) {
            .unsigned => |contents| @as(u64, value) == contents,
            else => false,
        },
        .optional, .@"union" => switch (expected) {
            .sum_case => |contents| algebraicCaseIndex(value) == contents,
            else => false,
        },
        else => false,
    };
}

fn compilerSemanticDigest(
    comptime Body: type,
    program: control_ir.Program,
    normal_form: anytype,
    comptime residual_effects: anytype,
    reachability: anytype,
    canonical: anytype,
) [32]u8 {
    var hasher = SemanticHasher.init(.{});
    semanticHashBytes(&hasher, "boundary-rnf-compiler-semantics-v4");
    semanticHashBytes(
        &hasher,
        segment_fuel_semantic_domain,
    );
    semanticHashU64(&hasher, dynamic_fuel_quantum_bytes);
    semanticHashSchema(Body.InitialArgs, &hasher);
    semanticHashSchema(Body.Result, &hasher);
    semanticHashSchema(Body.Failure, &hasher);
    semanticHashBytes(&hasher, "failure-name-tag-map-v1");
    const failure_fields = @typeInfo(Body.Failure).@"enum".fields;
    semanticHashU32(&hasher, @intCast(failure_fields.len));
    inline for (failure_fields) |field| {
        semanticHashBytes(&hasher, field.name);
        semanticHashU32(&hasher, @intCast(field.value));
    }

    semanticHashU32(&hasher, @intCast(residual_effects.residual_count));
    inline for (0..residual_effects.residual_count) |residual_ordinal| {
        const source_ordinal = residual_effects.residual_to_source[
            residual_ordinal
        ];
        const Site = effectiveSiteFor(Body, @intCast(source_ordinal));
        hasher.update(&effectSiteContractDigest(Site, residual_ordinal));
    }

    semanticHashU32(&hasher, @intCast(canonical.value_count));
    for (0..canonical.value_count) |dense_value_index| {
        const source_value = canonical.value_dense_to_source[
            dense_value_index
        ];
        semanticHashValueType(
            Body,
            &hasher,
            program.value_types[source_value],
        );
    }
    semanticHashU16(&hasher, canonical.blockId(program.entry));
    semanticHashValueType(Body, &hasher, program.result_type);
    semanticHashU32(&hasher, @intCast(canonical.function_count));
    for (0..canonical.function_count) |dense_function_index| {
        const source_function = canonical.function_dense_to_source[
            dense_function_index
        ];
        const function = program.function(source_function) catch unreachable;
        semanticHashU16(&hasher, @intCast(dense_function_index));
        semanticHashU16(&hasher, canonical.blockId(function.entry));
        semanticHashValueType(Body, &hasher, function.result_type);
    }
    semanticHashU32(&hasher, @intCast(reachability.count));
    for (0..canonical.block_count) |dense_block_index| {
        const source_block = canonical.block_dense_to_source[
            dense_block_index
        ];
        const block = program.blocks[source_block];
        semanticHashU16(&hasher, @intCast(dense_block_index));
        semanticHashU16(
            &hasher,
            canonical.functionId(block.function_id),
        );
        semanticHashU32(&hasher, @intCast(block.parameters.len));
        for (block.parameters) |parameter| {
            semanticHashU16(&hasher, canonical.valueId(parameter));
        }
        semanticHashU32(&hasher, @intCast(block.instructions.len));
        for (block.instructions) |instruction| {
            semanticHashInstruction(
                Body,
                &hasher,
                instruction,
                canonical,
            );
        }
        semanticHashTerminator(
            Body,
            &hasher,
            block.terminator,
            residual_effects,
            canonical,
        );
        const block_cost: u64 = if (comptime hasDeclSafe(Body, "block_costs"))
            Body.block_costs[block.id]
        else
            minimumBlockCost(block);
        semanticHashU64(&hasher, block_cost);
    }
    semanticHashBytes(&hasher, "await-effect-cost");
    semanticHashU64(&hasher, 1);

    semanticHashU32(
        &hasher,
        @intCast(normal_form.constructor_count),
    );
    for (normal_form.constructorSlice()) |constructor| {
        semanticHashU32(&hasher, constructor.id);
        semanticHashU8(
            &hasher,
            @intCast(@intFromEnum(constructor.origin)),
        );
        semanticHashU16(
            &hasher,
            canonical.blockId(constructor.source_block),
        );
        semanticHashBool(&hasher, constructor.resume_target != null);
        if (constructor.resume_target) |target| {
            semanticHashU16(&hasher, canonical.blockId(target));
        }
        semanticHashBool(&hasher, constructor.has_activation_context);
        semanticHashU32(
            &hasher,
            @intCast(constructor.activation_len),
        );
        for (constructor.activationFields()) |field| {
            semanticHashU16(&hasher, canonical.valueId(field.value));
            semanticHashValueType(Body, &hasher, field.value_type);
        }
        semanticHashU32(
            &hasher,
            @intCast(constructor.environment_len),
        );
        for (constructor.environmentFields()) |field| {
            semanticHashU16(&hasher, canonical.valueId(field.value));
            semanticHashValueType(Body, &hasher, field.value_type);
        }
        semanticHashU32(
            &hasher,
            @intCast(constructor.invariant_len),
        );
        for (constructor.invariantTerms()) |invariant| {
            semanticHashInvariant(&hasher, invariant, canonical);
        }
    }
    semanticHashU32(
        &hasher,
        @intCast(normal_form.entry_transition_count),
    );
    for (normal_form.entryTransitionSlice()) |transition| {
        semanticHashU16(
            &hasher,
            canonical.blockId(transition.source_block),
        );
        semanticHashU8(
            &hasher,
            @intCast(@intFromEnum(transition.edge_kind)),
        );
        semanticHashU16(
            &hasher,
            canonical.blockId(transition.target_block),
        );
        semanticHashU32(&hasher, transition.constructor_id);
    }
    semanticHashU32(&hasher, 0);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn generatedReducerOperationCount(
    program: control_ir.Program,
    normal_form: anytype,
    comptime limits: control_ir.CompilerLimits,
) control_ir.CompilerBlocker!usize {
    var total: usize = 0;
    for (normal_form.constructorSlice()) |constructor| {
        const block = program.blocks[constructor.source_block];
        total = std.math.add(
            usize,
            total,
            block.instructions.len + 1,
        ) catch return error.GeneratedReducerLimitExceeded;
        if (total > limits.maximum_generated_operations) {
            return error.GeneratedReducerLimitExceeded;
        }
    }
    return total;
}

/// Generate one program-specific direct reducer from private typed Control IR.
pub fn DefinitionFor(comptime label: []const u8, comptime Body: type) type {
    @setEvalBranchQuota(compiler_evaluation_branch_quota);
    if (label.len == 0) @compileError("Boundary program label must be non-empty");
    const source_program: control_ir.Program = Body.control_ir;
    const limits = comptime compilerLimitsFor(Body);
    comptime validateBody(Body, source_program, limits);
    const program = NormalizedProgram(Body, source_program).value;
    comptime control_ir.validate(
        limits.maximum_values,
        limits.maximum_blocks,
        program,
    ) catch |err| @compileError(
        "Boundary normalized Control IR is invalid: " ++ @errorName(err),
    );
    const reachability = comptime control_ir.Reachability(
        limits.maximum_blocks,
    ).analyze(program) catch |err| @compileError(
        "Boundary reachability analysis failed: " ++ @errorName(err),
    );
    const semantic_canonicalization = comptime SemanticCanonicalization(
        limits.maximum_values,
        limits.maximum_blocks,
    ).analyze(program, reachability);
    const residual_effects = comptime analyzeResidualEffects(
        Body,
        program,
        reachability,
    );
    const invariant_constants = comptime invariantConstantValues(
        Body,
        program,
        limits.maximum_values,
    );
    const normal_form = comptime blk: {
        break :blk rnf.NormalForm(
            limits.maximum_values,
            limits.maximum_blocks,
            limits.maximum_constructors,
            limits.maximum_environment_fields,
            limits.maximum_invariant_terms,
        ).synthesizeReachableWithConstants(
            program,
            reachability,
            &invariant_constants,
        ) catch |err|
            @compileError("Boundary RNF synthesis failed: " ++ @errorName(err));
    };
    const generated_operation_count = comptime generatedReducerOperationCount(
        program,
        normal_form,
        limits,
    ) catch |err| @compileError(
        "Boundary compiler blocked program: " ++ @errorName(err),
    );
    const generated_semantic_digest = comptime compilerSemanticDigest(
        Body,
        program,
        normal_form,
        residual_effects,
        reachability,
        semantic_canonicalization,
    );
    const FrameType = frameType(Body, program, normal_form);
    const initial_constructor_index = comptime blk: {
        for (0..normal_form.constructor_count) |index| {
            const constructor = normal_form.constructors[index];
            if (constructor.source_block == program.entry and
                constructor.resume_target == program.entry and
                constructor.origin == .block_entry and
                constructor.kind != .await_effect and
                constructor.kind != .caller_fuel_yield)
            {
                break :blk index;
            }
        }
        @compileError(
            "RNF is missing a direct constructor for the Control IR entry block",
        );
    };
    const InitialEnvironment = @FieldType(
        FrameType,
        constructorName(initial_constructor_index),
    );
    const ValueCatalog = valueCatalogType(
        Body,
        program,
        semantic_canonicalization,
    );
    comptime {
        if (@typeInfo(ValueCatalog).@"struct".fields.len !=
            semantic_canonicalization.value_count)
        {
            @compileError(
                "compiler value catalog must contain exactly the reachable values",
            );
        }
    }
    const RequestType = requestType(Body, residual_effects);
    const ReturnValueType = returnValueType(
        Body,
        program,
        semantic_canonicalization,
    );

    return struct {
        const Self = @This();

        pub const Frame = FrameType;
        pub const minimum_initial_environment_bytes =
            portable_value.minimumEncodedSize(InitialEnvironment);
        pub const InitialArgs = Body.InitialArgs;
        pub const Result = Body.Result;
        pub const Failure = Body.Failure;
        pub const Request = RequestType;
        pub const ReturnValue = ReturnValueType;
        pub const EffectRow = struct {
            pub const ResponseMode = ResidualResponseMode;
            pub const operation_site_count: usize =
                residual_effects.residual_count;
            pub const after_site_count: usize = 0;

            /// Resolve one compiler-owned residual-site contract by ordinal.
            pub fn site(comptime ordinal: usize) type {
                if (ordinal >= residual_effects.residual_count) {
                    @compileError("residual effect-site ordinal is out of bounds");
                }
                const source_ordinal = residual_effects.residual_to_source[
                    ordinal
                ];
                const ResidualSite = effectiveSiteFor(
                    Body,
                    @intCast(source_ordinal),
                );
                return struct {
                    pub const site_ordinal: u32 = @intCast(ordinal);
                    pub const Payload = ResidualSite.Payload;
                    pub const Resume = ResidualSite.Resume;
                    pub const Result = ResidualSite.Resume;
                    pub const response_mode: ResidualResponseMode =
                        .single_resume;
                    pub const semantic_identity: []const u8 =
                        ResidualSite.semantic_identity;
                    /// Ordinal-independent capability used by local handlers.
                    pub const semantic_contract_digest: [32]u8 =
                        effectSiteSemanticContractDigest(ResidualSite);
                    pub const contract_digest: [32]u8 =
                        effectSiteContractDigest(ResidualSite, ordinal);
                };
            }
        };
        pub const Transition = machine.ReductionWithReturns(
            Frame,
            Request,
            Result,
            Failure,
            ReturnValue,
        );
        pub const Plan = struct {
            cost: u64,
            transition: Transition,
        };
        pub const semantic_digest = generated_semantic_digest;
        pub const contract_bytes = semantic_digest[0..];
        pub const control = program;
        pub const rnf_value = normal_form;
        pub const DebugConstructorMetadata = struct {
            constructor_id: u32,
            name: []const u8,
            kind: []const u8,
            origin: []const u8,
            source_block: control_ir.BlockId,
            source_function: control_ir.FunctionId,
            resume_target: ?control_ir.BlockId,
        };
        pub const DebugEntryTransitionMetadata = struct {
            source_block: control_ir.BlockId,
            edge_kind: rnf.IncomingEdgeKind,
            target_block: control_ir.BlockId,
            constructor_id: u32,
        };
        pub const DebugMetadata = struct {
            program_label: []const u8,
            constructors: [normal_form.constructor_count]DebugConstructorMetadata,
            entry_transitions: [normal_form.entry_transition_count]DebugEntryTransitionMetadata,
        };
        pub const debug_metadata: DebugMetadata = blk: {
            var constructors: [normal_form.constructor_count]DebugConstructorMetadata =
                undefined;
            for (
                normal_form.constructorSlice(),
                0..,
            ) |constructor, index| {
                constructors[index] = .{
                    .constructor_id = constructor.id,
                    .name = constructorName(index),
                    .kind = @tagName(constructor.kind),
                    .origin = @tagName(constructor.origin),
                    .source_block = constructor.source_block,
                    .source_function = program.blocks[
                        constructor.source_block
                    ].function_id,
                    .resume_target = constructor.resume_target,
                };
            }
            var entry_transitions: [normal_form.entry_transition_count]DebugEntryTransitionMetadata =
                undefined;
            for (
                normal_form.entryTransitionSlice(),
                0..,
            ) |transition, index| {
                entry_transitions[index] = .{
                    .source_block = transition.source_block,
                    .edge_kind = transition.edge_kind,
                    .target_block = transition.target_block,
                    .constructor_id = transition.constructor_id,
                };
            }
            break :blk .{
                .program_label = label,
                .constructors = constructors,
                .entry_transitions = entry_transitions,
            };
        };
        pub const reachable_block_count = reachability.count;
        pub const reachable_value_count =
            semantic_canonicalization.value_count;
        pub const reachable_function_count =
            semantic_canonicalization.function_count;
        pub const compiler_limits = limits;
        pub const generated_reducer_operation_count =
            generated_operation_count;
        pub const reachable_value_catalog_bytes = @sizeOf(ValueCatalog);
        pub const maximum_segment_value_bytes =
            maximumSegmentStoreSize(
                Body,
                program,
                normal_form,
                semantic_canonicalization,
            );

        fn SegmentStore(comptime constructor_id: usize) type {
            return segmentStoreType(
                Body,
                program,
                normal_form.constructors[constructor_id],
                semantic_canonicalization,
            );
        }

        fn constructorForBlock(comptime block_id: control_ir.BlockId) usize {
            inline for (0..normal_form.constructor_count) |index| {
                const constructor = comptime normal_form.constructors[index];
                if (constructor.source_block == block_id and
                    constructor.resume_target == block_id and
                    constructor.origin == .block_entry and
                    constructor.kind != .await_effect and
                    constructor.kind != .caller_fuel_yield)
                {
                    return index;
                }
            }
            @compileError("RNF is missing a direct constructor for a Control IR block");
        }

        fn constructorForIncoming(
            comptime source_block: control_ir.BlockId,
            comptime edge_kind: rnf.IncomingEdgeKind,
            comptime target_block: control_ir.BlockId,
        ) usize {
            inline for (normal_form.entryTransitionSlice()) |transition| {
                if (transition.source_block == source_block and
                    transition.edge_kind == edge_kind and
                    transition.target_block == target_block)
                {
                    return transition.constructor_id;
                }
            }
            @compileError("RNF is missing an edge-specific constructor for a Control IR block");
        }

        fn loadEnvironment(
            comptime constructor_id: usize,
            environment: anytype,
            store: anytype,
        ) void {
            const constructor = comptime normal_form.constructors[constructor_id];
            if (comptime constructor.has_activation_context) {
                @field(store, activation_entry_name) =
                    @field(environment, activation_entry_name);
                inline for (0..constructor.activation_len) |field_index| {
                    const field = comptime constructor.activation[field_index];
                    @field(store, activationValueName(field.value)) =
                        @field(environment, activationValueName(field.value));
                    @field(store, valueName(field.value)) =
                        @field(environment, activationValueName(field.value));
                }
            }
            inline for (0..constructor.environment_len) |field_index| {
                const field = comptime constructor.environment[field_index];
                @field(store, valueName(field.value)) =
                    @field(environment, valueName(field.value));
            }
        }

        fn environmentValue(
            comptime constructor_id: usize,
            environment: anytype,
            comptime value: control_ir.ValueId,
        ) @FieldType(ValueCatalog, valueName(value)) {
            const constructor = comptime normal_form.constructors[constructor_id];
            inline for (0..constructor.environment_len) |field_index| {
                const field = comptime constructor.environment[field_index];
                if (field.value == value) {
                    return @field(environment, valueName(value));
                }
            }
            inline for (0..constructor.activation_len) |field_index| {
                const field = comptime constructor.activation[field_index];
                if (field.value == value) {
                    return @field(environment, activationValueName(value));
                }
            }
            unreachable;
        }

        fn frameForBlock(
            comptime block_id: control_ir.BlockId,
            store: anytype,
        ) Frame {
            const constructor_id = comptime constructorForBlock(block_id);
            const constructor = comptime normal_form.constructors[constructor_id];
            const Environment = @FieldType(
                Frame,
                constructorName(constructor_id),
            );
            var environment: Environment = undefined;
            if (comptime constructor.has_activation_context) {
                @field(environment, activation_entry_name) =
                    @field(store, activation_entry_name);
                inline for (0..constructor.activation_len) |field_index| {
                    const field = comptime constructor.activation[field_index];
                    @field(environment, activationValueName(field.value)) =
                        @field(store, activationValueName(field.value));
                }
            }
            inline for (0..constructor.environment_len) |field_index| {
                const field = comptime constructor.environment[field_index];
                @field(environment, valueName(field.value)) =
                    @field(store, valueName(field.value));
            }
            return @unionInit(
                Frame,
                constructorName(constructor_id),
                environment,
            );
        }

        fn frameForIncoming(
            comptime source_block: control_ir.BlockId,
            comptime edge_kind: rnf.IncomingEdgeKind,
            comptime target_block: control_ir.BlockId,
            store: anytype,
        ) Frame {
            const constructor_id = comptime constructorForIncoming(
                source_block,
                edge_kind,
                target_block,
            );
            if (comptime edge_kind != .call) {
                return awaitingFrame(constructor_id, store);
            }
            const constructor = comptime normal_form.constructors[constructor_id];
            if (comptime !constructor.has_activation_context or
                constructor.origin != .call_entry)
            {
                @compileError("call transition must create activation context");
            }
            const Environment = @FieldType(
                Frame,
                constructorName(constructor_id),
            );
            var environment: Environment = undefined;
            @field(environment, activation_entry_name) = constructor.id;
            inline for (0..constructor.activation_len) |field_index| {
                const field = comptime constructor.activation[field_index];
                @field(environment, activationValueName(field.value)) =
                    @field(store, valueName(field.value));
            }
            inline for (0..constructor.environment_len) |field_index| {
                const field = comptime constructor.environment[field_index];
                @field(environment, valueName(field.value)) =
                    @field(store, valueName(field.value));
            }
            return @unionInit(
                Frame,
                constructorName(constructor_id),
                environment,
            );
        }

        fn applyOrdinaryEdge(
            comptime edge: control_ir.Edge,
            store: anytype,
        ) void {
            const source = store.*;
            const target = program.blocks[edge.target];
            inline for (target.parameters, edge.arguments) |parameter, argument| {
                switch (argument) {
                    .value => |value| {
                        @field(store, valueName(parameter)) =
                            @field(source, valueName(value));
                    },
                    .@"resume" => @compileError(
                        "ordinary Control IR edge cannot carry a resume value",
                    ),
                }
            }
        }

        fn applyResumeEdge(
            comptime edge: control_ir.Edge,
            store: anytype,
            response: anytype,
        ) void {
            const source = store.*;
            const target = program.blocks[edge.target];
            inline for (target.parameters, edge.arguments) |parameter, argument| {
                switch (argument) {
                    .value => |value| {
                        @field(store, valueName(parameter)) =
                            @field(source, valueName(value));
                    },
                    .@"resume" => {
                        const Parameter = typeForValue(
                            Body,
                            program.value_types[parameter],
                        );
                        if (@TypeOf(response) != Parameter) {
                            @compileError("resume response does not match continuation parameter");
                        }
                        @field(store, valueName(parameter)) = response;
                    },
                }
            }
        }

        fn awaitingFrame(
            comptime constructor_id: usize,
            store: anytype,
        ) Frame {
            const constructor = comptime normal_form.constructors[constructor_id];
            const Environment = @FieldType(
                Frame,
                constructorName(constructor_id),
            );
            var environment: Environment = undefined;
            if (comptime constructor.has_activation_context) {
                @field(environment, activation_entry_name) =
                    @field(store, activation_entry_name);
                inline for (0..constructor.activation_len) |field_index| {
                    const field = comptime constructor.activation[field_index];
                    @field(environment, activationValueName(field.value)) =
                        @field(store, activationValueName(field.value));
                }
            }
            inline for (0..constructor.environment_len) |field_index| {
                const field = comptime constructor.environment[field_index];
                @field(environment, valueName(field.value)) =
                    @field(store, valueName(field.value));
            }
            return @unionInit(
                Frame,
                constructorName(constructor_id),
                environment,
            );
        }

        fn checkpointFrame(
            comptime source_block: control_ir.BlockId,
            comptime suspension: control_ir.Suspension,
            store: anytype,
        ) Frame {
            var continuation_store = store.*;
            applyOrdinaryEdge(
                suspension.continuation,
                &continuation_store,
            );
            return frameForIncoming(
                source_block,
                .suspension_continuation,
                suspension.continuation.target,
                &continuation_store,
            );
        }

        const PreparedCost = struct {
            value: u64,
            overflowed: bool = false,
        };

        fn addFuelCost(total: *PreparedCost, amount: u64) void {
            total.value = std.math.add(u64, total.value, amount) catch {
                total.overflowed = true;
                total.value = std.math.maxInt(u64);
                return;
            };
        }

        fn encodedBytes(comptime T: type, value: T) u64 {
            const size = portable_value.encodedSize(T, value) catch
                return std.math.maxInt(u64);
            return std.math.cast(u64, size) orelse
                return std.math.maxInt(u64);
        }

        fn maximumEncodedBytes(comptime T: type) u64 {
            return comptime std.math.cast(
                u64,
                portable_value.maximumEncodedSize(T),
            ) orelse std.math.maxInt(u64);
        }

        fn dynamicBytesCost(comptime T: type, canonical_bytes: u64) u64 {
            if (comptime !hasDynamicEncodedSize(T)) return 0;
            return std.math.divCeil(
                u64,
                canonical_bytes,
                dynamic_fuel_quantum_bytes,
            ) catch std.math.maxInt(u64);
        }

        fn boundedBytes(
            comptime T: type,
            candidate: u64,
        ) u64 {
            return @min(maximumEncodedBytes(T), candidate);
        }

        fn combinedSequenceBytes(
            comptime T: type,
            prefix: u64,
            suffixes: []const u64,
        ) u64 {
            var result = prefix;
            for (suffixes) |suffix| {
                result +|= suffix -| 4;
            }
            return boundedBytes(T, result);
        }

        fn definingInstructionInBlock(
            comptime block: control_ir.Block,
            comptime value: control_ir.ValueId,
        ) ?control_ir.Instruction {
            inline for (block.instructions) |instruction| {
                if (instruction.result == value) return instruction;
            }
            return null;
        }

        fn definingInstructionForValue(
            comptime value: control_ir.ValueId,
        ) ?control_ir.Instruction {
            inline for (program.blocks) |block| {
                if (definingInstructionInBlock(block, value)) |instruction| {
                    return instruction;
                }
            }
            return null;
        }

        fn exactVectorElementBytes(
            comptime block: control_ir.Block,
            comptime value: control_ir.ValueId,
            environment: anytype,
            available: *const [limits.maximum_values]bool,
        ) ?u64 {
            const maybe_instruction = comptime definingInstructionInBlock(
                block,
                value,
            );
            if (comptime maybe_instruction == null) return null;
            const instruction = comptime maybe_instruction.?;
            if (instruction.operation != .vector_get or
                instruction.operands.len != 2)
            {
                return null;
            }
            const vector_name = comptime valueName(instruction.operands[0]);
            const index_name = comptime valueName(instruction.operands[1]);
            if (!available[@intCast(instruction.operands[0])] or
                !available[@intCast(instruction.operands[1])])
            {
                return null;
            }
            const vector = @field(environment, vector_name);
            const element = (vector.get(
                @field(environment, index_name),
            ) catch unreachable) orelse return null;
            return encodedBytes(@TypeOf(element), element);
        }

        fn exactProductFieldBytes(
            comptime block: control_ir.Block,
            comptime product_value: control_ir.ValueId,
            comptime field_index: usize,
            environment: anytype,
            sizes: *const [limits.maximum_values]u64,
            available: *const [limits.maximum_values]bool,
        ) ?u64 {
            const product_name = comptime valueName(product_value);
            const Product = @FieldType(ValueCatalog, product_name);
            const field = std.meta.fields(Product)[field_index];
            if (available[@intCast(product_value)]) {
                const product = @field(environment, product_name);
                return encodedBytes(
                    field.type,
                    @field(product, field.name),
                );
            }
            const maybe_instruction = comptime definingInstructionInBlock(
                block,
                product_value,
            );
            if (comptime maybe_instruction == null) return null;
            const instruction = comptime maybe_instruction.?;
            return switch (instruction.operation) {
                .copy => exactProductFieldBytes(
                    block,
                    instruction.operands[0],
                    field_index,
                    environment,
                    sizes,
                    available,
                ),
                .product_construct => sizes[
                    @intCast(instruction.operands[field_index])
                ],
                .product_replace => |replaced_index| if (replaced_index == field_index)
                    sizes[@intCast(instruction.operands[1])]
                else
                    exactProductFieldBytes(
                        block,
                        instruction.operands[0],
                        field_index,
                        environment,
                        sizes,
                        available,
                    ),
                .vector_get => blk: {
                    const vector_name = comptime valueName(
                        instruction.operands[0],
                    );
                    const index_name = comptime valueName(
                        instruction.operands[1],
                    );
                    if (!available[@intCast(instruction.operands[0])] or
                        !available[@intCast(instruction.operands[1])])
                    {
                        break :blk null;
                    }
                    const vector = @field(environment, vector_name);
                    const element = (vector.get(
                        @field(environment, index_name),
                    ) catch unreachable) orelse break :blk null;
                    break :blk encodedBytes(
                        field.type,
                        @field(element, field.name),
                    );
                },
                else => null,
            };
        }

        fn resultEncodedBytes(
            comptime block: control_ir.Block,
            comptime instruction: control_ir.Instruction,
            environment: anytype,
            sizes: *const [limits.maximum_values]u64,
            available: *const [limits.maximum_values]bool,
        ) u64 {
            const result_name = comptime valueName(instruction.result);
            const ResultType = @FieldType(ValueCatalog, result_name);
            const maximum = maximumEncodedBytes(ResultType);
            return switch (instruction.operation) {
                .metadata => unreachable,
                .constant => |constant_index| encodedBytes(
                    ResultType,
                    Body.constants[constant_index],
                ),
                .copy => sizes[@intCast(instruction.operands[0])],
                .product_construct => blk: {
                    var total: u64 = 0;
                    inline for (instruction.operands) |operand| {
                        total +|= sizes[@intCast(operand)];
                    }
                    break :blk boundedBytes(ResultType, total);
                },
                .product_extract => |field_index| exactProductFieldBytes(
                    block,
                    instruction.operands[0],
                    field_index,
                    environment,
                    sizes,
                    available,
                ) orelse maximum,
                .product_replace => maximum,
                .sum_construct => boundedBytes(
                    ResultType,
                    4 +| if (instruction.operands.len == 0)
                        0
                    else
                        sizes[@intCast(instruction.operands[0])],
                ),
                .sum_extract => maximum,
                .optional_none => 1,
                .optional_some => boundedBytes(
                    ResultType,
                    1 +| sizes[@intCast(instruction.operands[0])],
                ),
                .select => @max(
                    sizes[@intCast(instruction.operands[1])],
                    sizes[@intCast(instruction.operands[2])],
                ),
                .vector_empty, .text_empty, .bytes_empty => 4,
                .vector_get => exactVectorElementBytes(
                    block,
                    instruction.result,
                    environment,
                    available,
                ) orelse maximum,
                .vector_set => maximum,
                .vector_push => boundedBytes(
                    ResultType,
                    sizes[@intCast(instruction.operands[0])] +|
                        sizes[@intCast(instruction.operands[1])],
                ),
                .vector_pop => maximum,
                .vector_truncate => @min(
                    maximum,
                    sizes[@intCast(instruction.operands[0])],
                ),
                .vector_clear => 4,
                .text_append, .bytes_append => combinedSequenceBytes(
                    ResultType,
                    sizes[@intCast(instruction.operands[0])],
                    &.{sizes[@intCast(instruction.operands[1])]},
                ),
                .bytes_append_scalar => boundedBytes(
                    ResultType,
                    sizes[@intCast(instruction.operands[0])] +| 1,
                ),
                .text_append_scalar => boundedBytes(
                    ResultType,
                    sizes[@intCast(instruction.operands[0])] +| 4,
                ),
                .text_append_unsigned, .text_append_signed => boundedBytes(
                    ResultType,
                    sizes[@intCast(instruction.operands[0])] +| 20,
                ),
                .text_copy, .bytes_copy => @min(
                    maximum,
                    sizes[@intCast(instruction.operands[0])],
                ),
                .text_join, .bytes_join => combinedSequenceBytes(
                    ResultType,
                    sizes[@intCast(instruction.operands[0])],
                    &.{
                        sizes[@intCast(instruction.operands[1])],
                        sizes[@intCast(instruction.operands[2])],
                    },
                ),
                .compare_eq_zero,
                .integer_add,
                .integer_subtract,
                .integer_multiply,
                .integer_divide,
                .integer_remainder,
                .integer_negate,
                .integer_equal,
                .integer_not_equal,
                .integer_less_than,
                .integer_less_equal,
                .integer_greater_than,
                .integer_greater_equal,
                .integer_bit_not,
                .integer_bit_and,
                .integer_bit_or,
                .integer_bit_xor,
                .integer_convert,
                .enum_to_u32,
                .boolean_not,
                .boolean_and,
                .boolean_or,
                .sum_tag_is,
                .optional_is_some,
                .vector_length,
                .text_length,
                .bytes_length,
                .text_compare,
                .bytes_compare,
                => maximum,
            };
        }

        // Keep each typed Control IR block as one direct code-generation unit.
        // Inlining every block into the constructor dispatcher makes LLVM
        // reconstruct one pathological monolithic reducer.
        noinline fn executeInstructions(
            comptime block: control_ir.Block,
            store: anytype,
        ) ?Failure {
            inline for (block.instructions) |instruction| {
                const result_name = comptime valueName(instruction.result);
                switch (instruction.operation) {
                    .metadata => unreachable,
                    .constant => |constant_index| {
                        const Constant = @TypeOf(Body.constants[constant_index]);
                        const canonical = comptime portable_value.canonicalValue(
                            Constant,
                            Body.constants[constant_index],
                        ) catch unreachable;
                        @field(store, result_name) = canonical;
                    },
                    .copy => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                    },
                    .compare_eq_zero => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) == 0;
                    },
                    .integer_add => {
                        const ResultType = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = std.math.add(
                            ResultType,
                            @field(store, valueName(instruction.operands[0])),
                            @field(store, valueName(instruction.operands[1])),
                        ) catch return failureNamed(Body, "arithmetic_overflow");
                    },
                    .integer_subtract => {
                        const ResultType = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = std.math.sub(
                            ResultType,
                            @field(store, valueName(instruction.operands[0])),
                            @field(store, valueName(instruction.operands[1])),
                        ) catch return failureNamed(Body, "arithmetic_overflow");
                    },
                    .integer_multiply => {
                        const ResultType = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = std.math.mul(
                            ResultType,
                            @field(store, valueName(instruction.operands[0])),
                            @field(store, valueName(instruction.operands[1])),
                        ) catch return failureNamed(Body, "arithmetic_overflow");
                    },
                    .integer_divide => {
                        const ResultType = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = std.math.divTrunc(
                            ResultType,
                            @field(store, valueName(instruction.operands[0])),
                            @field(store, valueName(instruction.operands[1])),
                        ) catch |err| return switch (err) {
                            error.DivisionByZero => failureNamed(
                                Body,
                                "division_by_zero",
                            ),
                            error.Overflow => failureNamed(
                                Body,
                                "arithmetic_overflow",
                            ),
                        };
                    },
                    .integer_remainder => {
                        const ResultType = @FieldType(ValueCatalog, result_name);
                        const left = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const right = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        _ = std.math.divTrunc(
                            ResultType,
                            left,
                            right,
                        ) catch |err| return switch (err) {
                            error.DivisionByZero => failureNamed(
                                Body,
                                "division_by_zero",
                            ),
                            error.Overflow => failureNamed(
                                Body,
                                "arithmetic_overflow",
                            ),
                        };
                        @field(store, result_name) = @rem(left, right);
                    },
                    .integer_negate => {
                        @field(store, result_name) = std.math.negate(@field(
                            store,
                            valueName(instruction.operands[0]),
                        )) catch return failureNamed(
                            Body,
                            "arithmetic_overflow",
                        );
                    },
                    .integer_equal => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) == @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_not_equal => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) != @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_less_than => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) < @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_less_equal => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) <= @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_greater_than => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) > @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_greater_equal => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) >= @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_bit_not => {
                        @field(store, result_name) = ~@field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                    },
                    .integer_bit_and => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) & @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_bit_or => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) | @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_bit_xor => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) ^ @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .integer_convert => {
                        const ResultType = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = std.math.cast(
                            ResultType,
                            @field(store, valueName(instruction.operands[0])),
                        ) orelse return failureNamed(
                            Body,
                            "arithmetic_overflow",
                        );
                    },
                    .enum_to_u32 => {
                        @field(store, result_name) = @intCast(@intFromEnum(@field(
                            store,
                            valueName(instruction.operands[0]),
                        )));
                    },
                    .boolean_not => {
                        @field(store, result_name) = !@field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                    },
                    .boolean_and => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) and @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .boolean_or => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) or @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                    },
                    .select => {
                        @field(store, result_name) = if (@field(
                            store,
                            valueName(instruction.operands[0]),
                        ))
                            @field(
                                store,
                                valueName(instruction.operands[1]),
                            )
                        else
                            @field(
                                store,
                                valueName(instruction.operands[2]),
                            );
                    },
                    .product_construct => {
                        const Product = @FieldType(ValueCatalog, result_name);
                        var product: Product = undefined;
                        inline for (
                            std.meta.fields(Product),
                            instruction.operands,
                        ) |field, operand| {
                            @field(product, field.name) = @field(
                                store,
                                valueName(operand),
                            );
                        }
                        @field(store, result_name) = product;
                    },
                    .product_extract => |field_index| {
                        const Product = @FieldType(
                            ValueCatalog,
                            valueName(instruction.operands[0]),
                        );
                        const field = std.meta.fields(Product)[field_index];
                        @field(store, result_name) = @field(
                            @field(
                                store,
                                valueName(instruction.operands[0]),
                            ),
                            field.name,
                        );
                    },
                    .product_replace => |field_index| {
                        var product = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const Product = @TypeOf(product);
                        const field = std.meta.fields(Product)[field_index];
                        @field(product, field.name) = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        @field(store, result_name) = product;
                    },
                    .sum_construct => |variant_index| {
                        const Sum = @FieldType(ValueCatalog, result_name);
                        const field = std.meta.fields(Sum)[variant_index];
                        @field(store, result_name) = @unionInit(
                            Sum,
                            field.name,
                            if (field.type == void) {} else @field(
                                store,
                                valueName(instruction.operands[0]),
                            ),
                        );
                    },
                    .sum_tag_is => |variant_index| {
                        const Sum = @FieldType(
                            ValueCatalog,
                            valueName(instruction.operands[0]),
                        );
                        const Tag = @typeInfo(Sum).@"union".tag_type.?;
                        const field = std.meta.fields(Sum)[variant_index];
                        @field(store, result_name) = std.meta.activeTag(@field(
                            store,
                            valueName(instruction.operands[0]),
                        )) == @field(Tag, field.name);
                    },
                    .sum_extract => |variant_index| {
                        const sum = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const Sum = @TypeOf(sum);
                        const Tag = @typeInfo(Sum).@"union".tag_type.?;
                        const field = std.meta.fields(Sum)[variant_index];
                        if (std.meta.activeTag(sum) != @field(Tag, field.name)) {
                            return failureNamed(Body, "invalid_variant");
                        }
                        @field(store, result_name) = @field(sum, field.name);
                    },
                    .optional_none => {
                        @field(store, result_name) = null;
                    },
                    .optional_some => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                    },
                    .optional_is_some => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ) != null;
                    },
                    .vector_empty => {
                        const Vector = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = Vector.empty();
                    },
                    .vector_length => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ).len() catch unreachable;
                    },
                    .vector_get => {
                        const observed = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ).get(@field(
                            store,
                            valueName(instruction.operands[1]),
                        )) catch unreachable;
                        @field(store, result_name) = observed orelse
                            return failureNamed(Body, "invalid_index");
                    },
                    .vector_set => {
                        var vector = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        vector.set(
                            @field(
                                store,
                                valueName(instruction.operands[1]),
                            ),
                            @field(
                                store,
                                valueName(instruction.operands[2]),
                            ),
                        ) catch return failureNamed(Body, "invalid_index");
                        @field(store, result_name) = vector;
                    },
                    .vector_push => {
                        var vector = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        vector.push(@field(
                            store,
                            valueName(instruction.operands[1]),
                        )) catch return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = vector;
                    },
                    .vector_pop => {
                        var vector = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const popped = vector.pop() catch unreachable;
                        const Product = @FieldType(ValueCatalog, result_name);
                        const fields = std.meta.fields(Product);
                        var product: Product = undefined;
                        @field(product, fields[0].name) = vector;
                        @field(product, fields[1].name) = popped;
                        @field(store, result_name) = product;
                    },
                    .vector_truncate => {
                        var vector = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        vector.truncate(@field(
                            store,
                            valueName(instruction.operands[1]),
                        ));
                        @field(store, result_name) = vector;
                    },
                    .vector_clear => {
                        var vector = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        vector.clear();
                        @field(store, result_name) = vector;
                    },
                    .text_empty => {
                        const Text = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = Text.empty();
                    },
                    .text_length => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ).len() catch unreachable;
                    },
                    .text_append => {
                        var text = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const suffix = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        text.append(suffix.slice() catch unreachable) catch
                            return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = text;
                    },
                    .text_append_scalar => {
                        var text = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const scalar = std.math.cast(
                            u21,
                            @field(
                                store,
                                valueName(instruction.operands[1]),
                            ),
                        ) orelse return failureNamed(Body, "invalid_utf8");
                        text.appendScalar(scalar) catch |err| return switch (err) {
                            error.InvalidUtf8 => failureNamed(
                                Body,
                                "invalid_utf8",
                            ),
                            error.CapacityExceeded => failureNamed(
                                Body,
                                "capacity_exceeded",
                            ),
                            else => failureNamed(Body, "capacity_exceeded"),
                        };
                        @field(store, result_name) = text;
                    },
                    .text_append_unsigned => {
                        var text = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        text.appendUnsigned(@intCast(@field(
                            store,
                            valueName(instruction.operands[1]),
                        ))) catch return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = text;
                    },
                    .text_append_signed => {
                        var text = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        text.appendSigned(@intCast(@field(
                            store,
                            valueName(instruction.operands[1]),
                        ))) catch return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = text;
                    },
                    .text_copy => {
                        const Source = @FieldType(
                            ValueCatalog,
                            valueName(instruction.operands[0]),
                        );
                        _ = Source;
                        const ResultText = @FieldType(
                            ValueCatalog,
                            result_name,
                        );
                        const source = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        @field(store, result_name) = source.copyRange(
                            ResultText.maximum_length,
                            @field(
                                store,
                                valueName(instruction.operands[1]),
                            ),
                            @field(
                                store,
                                valueName(instruction.operands[2]),
                            ),
                        ) catch |err| return switch (err) {
                            error.InvalidUtf8 => failureNamed(
                                Body,
                                "invalid_utf8",
                            ),
                            error.CapacityExceeded => failureNamed(
                                Body,
                                "capacity_exceeded",
                            ),
                            else => failureNamed(Body, "capacity_exceeded"),
                        };
                    },
                    .text_compare => {
                        const left = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const right = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        @field(store, result_name) = switch (std.mem.order(
                            u8,
                            left.slice() catch unreachable,
                            right.slice() catch unreachable,
                        )) {
                            .lt => -1,
                            .eq => 0,
                            .gt => 1,
                        };
                    },
                    .text_join => {
                        var text = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const separator = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        const right = @field(
                            store,
                            valueName(instruction.operands[2]),
                        );
                        text.append(separator.slice() catch unreachable) catch
                            return failureNamed(Body, "capacity_exceeded");
                        text.append(right.slice() catch unreachable) catch
                            return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = text;
                    },
                    .bytes_empty => {
                        const Bytes = @FieldType(ValueCatalog, result_name);
                        @field(store, result_name) = Bytes.empty();
                    },
                    .bytes_length => {
                        @field(store, result_name) = @field(
                            store,
                            valueName(instruction.operands[0]),
                        ).len() catch unreachable;
                    },
                    .bytes_append => {
                        var bytes = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const suffix = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        bytes.append(suffix.slice() catch unreachable) catch
                            return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = bytes;
                    },
                    .bytes_append_scalar => {
                        var bytes = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const scalar = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        bytes.append(&.{scalar}) catch
                            return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = bytes;
                    },
                    .bytes_copy => {
                        const ResultBytes = @FieldType(
                            ValueCatalog,
                            result_name,
                        );
                        const source = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        @field(store, result_name) = source.copyRange(
                            ResultBytes.maximum_length,
                            @field(
                                store,
                                valueName(instruction.operands[1]),
                            ),
                            @field(
                                store,
                                valueName(instruction.operands[2]),
                            ),
                        ) catch return failureNamed(
                            Body,
                            "capacity_exceeded",
                        );
                    },
                    .bytes_compare => {
                        const left = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const right = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        @field(store, result_name) = switch (std.mem.order(
                            u8,
                            left.slice() catch unreachable,
                            right.slice() catch unreachable,
                        )) {
                            .lt => -1,
                            .eq => 0,
                            .gt => 1,
                        };
                    },
                    .bytes_join => {
                        var bytes = @field(
                            store,
                            valueName(instruction.operands[0]),
                        );
                        const separator = @field(
                            store,
                            valueName(instruction.operands[1]),
                        );
                        const right = @field(
                            store,
                            valueName(instruction.operands[2]),
                        );
                        bytes.append(separator.slice() catch unreachable) catch
                            return failureNamed(Body, "capacity_exceeded");
                        bytes.append(right.slice() catch unreachable) catch
                            return failureNamed(Body, "capacity_exceeded");
                        @field(store, result_name) = bytes;
                    },
                }
            }
            return null;
        }

        fn requestFor(
            comptime source_site_id: usize,
            payload: anytype,
        ) Request {
            if (Request == void) unreachable;
            return @unionInit(
                Request,
                siteName(residualSiteOrdinal(source_site_id)),
                payload,
            );
        }

        fn residualSiteOrdinal(comptime source_site_id: usize) usize {
            return @intCast(
                residual_effects.source_to_residual[source_site_id] orelse
                    unreachable,
            );
        }

        fn returnValueFor(
            comptime function_id: control_ir.FunctionId,
            payload: anytype,
        ) ReturnValue {
            if (ReturnValue == void or function_id == 0) unreachable;
            return @unionInit(
                ReturnValue,
                functionReturnName(function_id),
                payload,
            );
        }

        fn isAwaitCallConstructor(comptime constructor_id: usize) bool {
            const constructor = comptime normal_form.constructors[constructor_id];
            if (constructor.kind != .call_return or
                constructor.origin != .suspension)
            {
                return false;
            }
            return switch (program.blocks[constructor.source_block].terminator) {
                .@"suspend" => |suspension| suspension.kind == .call,
                else => false,
            };
        }

        fn baseCostForConstructor(comptime constructor_id: usize) u64 {
            const constructor = comptime normal_form.constructors[constructor_id];
            if (constructor.kind == .await_effect) return 1;
            return minimumSourceBlockCost(
                Body,
                program,
                constructor.source_block,
            );
        }

        fn preflightCostConstructor(
            comptime constructor_id: usize,
            environment: anytype,
        ) PreparedCost {
            const constructor = comptime normal_form.constructors[constructor_id];
            var fuel_cost: PreparedCost = .{
                .value = baseCostForConstructor(constructor_id),
            };
            var sizes = [_]u64{0} ** limits.maximum_values;
            var available = [_]bool{false} ** limits.maximum_values;
            inline for (0..constructor.activation_len) |field_index| {
                const field = comptime constructor.activation[field_index];
                const name = comptime activationValueName(field.value);
                const Value = @FieldType(@TypeOf(environment), name);
                const size = encodedBytes(Value, @field(environment, name));
                sizes[@intCast(field.value)] = size;
                available[@intCast(field.value)] = true;
                addFuelCost(
                    &fuel_cost,
                    dynamicBytesCost(Value, size),
                );
            }
            if (constructor.kind == .await_effect or
                isAwaitCallConstructor(constructor_id))
            {
                return fuel_cost;
            }
            var store: SegmentStore(constructor_id) = undefined;
            loadEnvironment(constructor_id, environment, &store);
            inline for (0..constructor.environment_len) |field_index| {
                const field = comptime constructor.environment[field_index];
                const name = comptime valueName(field.value);
                const Value = @FieldType(ValueCatalog, name);
                const size = encodedBytes(Value, @field(store, name));
                sizes[@intCast(field.value)] = size;
                available[@intCast(field.value)] = true;
                addFuelCost(
                    &fuel_cost,
                    dynamicBytesCost(Value, size),
                );
            }
            const block = comptime program.blocks[constructor.source_block];
            inline for (block.instructions) |instruction| {
                inline for (instruction.operands) |operand| {
                    const name = comptime valueName(operand);
                    const Operand = @FieldType(ValueCatalog, name);
                    addFuelCost(
                        &fuel_cost,
                        dynamicBytesCost(
                            Operand,
                            sizes[@intCast(operand)],
                        ),
                    );
                }
                const result_name = comptime valueName(instruction.result);
                const ResultType = @FieldType(ValueCatalog, result_name);
                const result_size = resultEncodedBytes(
                    block,
                    instruction,
                    store,
                    &sizes,
                    &available,
                );
                sizes[@intCast(instruction.result)] = result_size;
                addFuelCost(
                    &fuel_cost,
                    dynamicBytesCost(ResultType, result_size),
                );
            }
            return fuel_cost;
        }

        // RNF constructors are the stable direct-reducer specialization seam.
        noinline fn planConstructor(
            comptime constructor_id: usize,
            environment: anytype,
            accepted_cost: u64,
        ) Plan {
            const constructor = comptime normal_form.constructors[constructor_id];
            if (constructor.kind == .await_effect or
                isAwaitCallConstructor(constructor_id))
            {
                unreachable;
            }
            var store: SegmentStore(constructor_id) = undefined;
            loadEnvironment(constructor_id, environment, &store);
            const block = comptime program.blocks[constructor.source_block];
            if (executeInstructions(block, &store)) |failure| {
                return .{
                    .cost = accepted_cost,
                    .transition = .{ .failed = failure },
                };
            }
            const transition: Transition = switch (block.terminator) {
                .jump => |edge| blk: {
                    applyOrdinaryEdge(edge, &store);
                    break :blk .{ .next = frameForIncoming(
                        block.id,
                        .jump,
                        edge.target,
                        &store,
                    ) };
                },
                .branch => |branch| blk: {
                    const condition = @field(
                        store,
                        valueName(branch.condition),
                    );
                    if (condition) {
                        applyOrdinaryEdge(branch.then_edge, &store);
                        break :blk .{
                            .next = frameForIncoming(
                                block.id,
                                .branch_then,
                                branch.then_edge.target,
                                &store,
                            ),
                        };
                    }
                    applyOrdinaryEdge(branch.else_edge, &store);
                    break :blk .{
                        .next = frameForIncoming(
                            block.id,
                            .branch_else,
                            branch.else_edge.target,
                            &store,
                        ),
                    };
                },
                .@"suspend" => |suspension| switch (suspension.kind) {
                    .effect => blk: {
                        const site_id = suspension.site_id.?;
                        const payload_value = suspension.request_values[0];
                        const payload = @field(store, valueName(payload_value));
                        inline for (0..normal_form.constructor_count) |candidate_id| {
                            const candidate = comptime normal_form.constructors[
                                candidate_id
                            ];
                            if (candidate.kind == .await_effect and
                                candidate.source_block == block.id)
                            {
                                break :blk .{ .request = .{
                                    .awaiting = awaitingFrame(
                                        candidate_id,
                                        &store,
                                    ),
                                    .request = requestFor(site_id, payload),
                                } };
                            }
                        }
                        unreachable;
                    },
                    .call => blk: {
                        inline for (0..normal_form.constructor_count) |candidate_id| {
                            const candidate = comptime normal_form.constructors[
                                candidate_id
                            ];
                            if (isAwaitCallConstructor(candidate_id) and
                                candidate.source_block == block.id)
                            {
                                var callee_store = store;
                                const callee = suspension.callee.?;
                                applyOrdinaryEdge(callee, &callee_store);
                                break :blk .{ .call = .{
                                    .return_frame = awaitingFrame(
                                        candidate_id,
                                        &store,
                                    ),
                                    .callee = frameForIncoming(
                                        block.id,
                                        .call,
                                        callee.target,
                                        &callee_store,
                                    ),
                                } };
                            }
                        }
                        unreachable;
                    },
                    .explicit_yield => .{
                        .yielded = checkpointFrame(
                            block.id,
                            suspension,
                            &store,
                        ),
                    },
                    .caller_fuel => .{
                        .next = checkpointFrame(
                            block.id,
                            suspension,
                            &store,
                        ),
                    },
                },
                .return_value => |maybe_value| .{ .done = if (maybe_value) |value|
                    @field(store, valueName(value))
                else {} },
                .return_to_caller => |value| .{ .return_value = returnValueFor(
                    block.function_id,
                    @field(store, valueName(value)),
                ) },
                .fail => |failure| .{
                    .failed = failureFromTag(Body, failure),
                },
                .fail_value => |value| .{
                    .failed = @field(store, valueName(value)),
                },
            };
            return .{ .cost = accepted_cost, .transition = transition };
        }

        pub fn initial(args: InitialArgs) Frame {
            const constructor_id = comptime constructorForBlock(program.entry);
            var store: SegmentStore(constructor_id) = undefined;
            const entry = program.blocks[program.entry];
            if (entry.parameters.len == 1) {
                const argument_name = comptime valueName(entry.parameters[0]);
                if (comptime @hasField(@TypeOf(store), argument_name)) {
                    @field(store, argument_name) = args;
                }
            }
            return frameForBlock(program.entry, &store);
        }

        pub fn minimumCost(frame: Frame) u64 {
            return switch (frame) {
                inline else => |_, tag| {
                    const constructor_id: usize = comptime @intFromEnum(tag);
                    return baseCostForConstructor(constructor_id);
                },
            };
        }

        pub fn cost(frame: Frame) u64 {
            return switch (frame) {
                inline else => |environment, tag| preflightCostConstructor(
                    comptime @intFromEnum(tag),
                    environment,
                ).value,
            };
        }

        pub fn costOverflows(frame: Frame) bool {
            return switch (frame) {
                inline else => |environment, tag| preflightCostConstructor(
                    comptime @intFromEnum(tag),
                    environment,
                ).overflowed,
            };
        }

        pub fn plan(frame: Frame, accepted_cost: u64) Plan {
            return switch (frame) {
                inline else => |environment, tag| planConstructor(
                    comptime @intFromEnum(tag),
                    environment,
                    accepted_cost,
                ),
            };
        }

        pub fn requestSiteDigest(request: Request) [32]u8 {
            if (Request == void) unreachable;
            return switch (request) {
                inline else => |_, tag| EffectRow.site(
                    comptime @intFromEnum(tag),
                ).contract_digest,
            };
        }

        pub fn current(frame: Frame) ?Request {
            if (Request == void) return null;
            return switch (frame) {
                inline else => |environment, tag| blk: {
                    const constructor_id: usize = comptime @intFromEnum(tag);
                    const constructor = comptime normal_form.constructors[constructor_id];
                    if (constructor.kind != .await_effect) break :blk null;
                    const suspension = program.blocks[
                        constructor.source_block
                    ].terminator.@"suspend";
                    const payload_value = suspension.request_values[0];
                    break :blk requestFor(
                        suspension.site_id.?,
                        environmentValue(
                            constructor_id,
                            environment,
                            payload_value,
                        ),
                    );
                },
            };
        }

        pub fn maximumResumeFramePayloadSize(
            frame: Frame,
            request: Request,
        ) error{ProgramContractViolation}!usize {
            if (Request == void) return error.ProgramContractViolation;
            const expected = current(frame) orelse
                return error.ProgramContractViolation;
            if (!requestEql(expected, request)) {
                return error.ProgramContractViolation;
            }
            return switch (frame) {
                inline else => |_, tag| blk: {
                    const constructor_id: usize = comptime @intFromEnum(tag);
                    const constructor = comptime normal_form.constructors[
                        constructor_id
                    ];
                    if (constructor.kind != .await_effect) {
                        break :blk error.ProgramContractViolation;
                    }
                    const suspension = comptime program.blocks[
                        constructor.source_block
                    ].terminator.@"suspend";
                    const target_constructor_id = comptime constructorForIncoming(
                        constructor.source_block,
                        .suspension_continuation,
                        suspension.continuation.target,
                    );
                    const Environment = @FieldType(
                        Frame,
                        constructorName(target_constructor_id),
                    );
                    break :blk comptime portable_value.maximumEncodedSize(
                        Environment,
                    );
                },
            };
        }

        pub fn @"resume"(
            frame: Frame,
            request: Request,
            response: anytype,
        ) error{ProgramContractViolation}!Frame {
            if (Request == void) return error.ProgramContractViolation;
            return switch (frame) {
                inline else => |environment, tag| blk: {
                    const constructor_id: usize = comptime @intFromEnum(tag);
                    const constructor = comptime normal_form.constructors[constructor_id];
                    if (constructor.kind != .await_effect) {
                        break :blk error.ProgramContractViolation;
                    }
                    const suspension = program.blocks[
                        constructor.source_block
                    ].terminator.@"suspend";
                    const site_id = comptime suspension.site_id.?;
                    const residual_site_id = comptime residualSiteOrdinal(site_id);
                    const request_field = comptime siteName(residual_site_id);
                    const Site = siteFor(Body, site_id);
                    if (@TypeOf(response) != Site.Resume) {
                        break :blk error.ProgramContractViolation;
                    }
                    const canonical_response = portable_value.canonicalValue(
                        Site.Resume,
                        response,
                    ) catch break :blk error.ProgramContractViolation;
                    if (std.meta.activeTag(request) !=
                        @field(std.meta.Tag(Request), request_field))
                    {
                        break :blk error.ProgramContractViolation;
                    }
                    const payload_value = suspension.request_values[0];
                    if (!portable_value.eqlValue(
                        @TypeOf(@field(request, request_field)),
                        @field(request, request_field),
                        environmentValue(
                            constructor_id,
                            environment,
                            payload_value,
                        ),
                    )) {
                        break :blk error.ProgramContractViolation;
                    }
                    var store: SegmentStore(constructor_id) = undefined;
                    loadEnvironment(constructor_id, environment, &store);
                    applyResumeEdge(
                        suspension.continuation,
                        &store,
                        canonical_response,
                    );
                    break :blk frameForIncoming(
                        constructor.source_block,
                        .suspension_continuation,
                        suspension.continuation.target,
                        &store,
                    );
                },
            };
        }

        pub fn applyReturn(
            frame: Frame,
            return_value: ReturnValue,
        ) error{ProgramContractViolation}!Frame {
            if (comptime ReturnValue == void) {
                return error.ProgramContractViolation;
            } else {
                return switch (frame) {
                    inline else => |environment, tag| blk: {
                        const constructor_id: usize =
                            comptime @intFromEnum(tag);
                        if (!comptime isAwaitCallConstructor(constructor_id)) {
                            break :blk error.ProgramContractViolation;
                        }
                        const constructor = comptime normal_form.constructors[
                            constructor_id
                        ];
                        const suspension = comptime program.blocks[
                            constructor.source_block
                        ].terminator.@"suspend";
                        const expected_function = suspension.callee_function.?;
                        break :blk switch (return_value) {
                            inline else => |payload, return_tag| return_blk: {
                                const returned_dense_index: usize =
                                    comptime @intFromEnum(return_tag) + 1;
                                const returned_function: control_ir.FunctionId =
                                    comptime semantic_canonicalization
                                        .function_dense_to_source[
                                        returned_dense_index
                                    ];
                                if (comptime returned_function !=
                                    expected_function)
                                {
                                    break :return_blk error.ProgramContractViolation;
                                }
                                var store: SegmentStore(
                                    constructor_id,
                                ) = undefined;
                                loadEnvironment(
                                    constructor_id,
                                    environment,
                                    &store,
                                );
                                applyResumeEdge(
                                    suspension.continuation,
                                    &store,
                                    payload,
                                );
                                break :return_blk frameForIncoming(
                                    constructor.source_block,
                                    .suspension_continuation,
                                    suspension.continuation.target,
                                    &store,
                                );
                            },
                        };
                    },
                };
            }
        }

        fn instructionResultHolds(
            comptime constructor_id: usize,
            environment: anytype,
            comptime result: control_ir.ValueId,
            comptime definition: control_ir.ValueId,
            comptime operand_count: u8,
            comptime operands: [rnf.maximum_executable_definition_operands]control_ir.ValueId,
        ) bool {
            const source_instruction = comptime definingInstructionForValue(
                definition,
            ) orelse @compileError(
                "generated instruction-result invariant has no definition",
            );
            comptime var instruction = source_instruction;
            instruction.result = result;
            instruction.operands = operands[0..operand_count];
            const instructions = [_]control_ir.Instruction{instruction};
            const constructor = comptime normal_form.constructors[
                constructor_id
            ];
            const validation_block: control_ir.Block = .{
                .id = constructor.source_block,
                .function_id = program.blocks[
                    constructor.source_block
                ].function_id,
                .instructions = &instructions,
                .terminator = .{ .fail = 0 },
            };
            var store: SegmentStore(constructor_id) = undefined;
            loadEnvironment(constructor_id, environment, &store);
            const name = comptime valueName(result);
            const actual = environmentValue(
                constructor_id,
                environment,
                result,
            );
            if (executeInstructions(validation_block, &store) != null) {
                return false;
            }
            return portable_value.eqlValue(
                @TypeOf(actual),
                actual,
                @field(store, name),
            );
        }

        pub fn requestEql(left: Request, right: Request) bool {
            return portable_value.eqlValue(Request, left, right);
        }

        fn validateConstructor(
            comptime constructor_id: usize,
            environment: anytype,
        ) error{ProgramContractViolation}!void {
            const constructor = comptime normal_form.constructors[constructor_id];
            var store: SegmentStore(constructor_id) = undefined;
            loadEnvironment(constructor_id, environment, &store);
            inline for (0..constructor.invariant_len) |term_index| {
                const term = comptime constructor.invariants[term_index];
                const accepted = switch (term) {
                    .boolean => |predicate| @field(
                        store,
                        valueName(predicate.value),
                    ) == predicate.expected,
                    .boolean_copy => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == @field(
                        store,
                        valueName(definition.source),
                    ),
                    .boolean_not => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == !@field(
                        store,
                        valueName(definition.operand),
                    ),
                    .boolean_binary => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == (switch (definition.operation) {
                        .@"and" => @field(
                            store,
                            valueName(definition.left),
                        ) and @field(
                            store,
                            valueName(definition.right),
                        ),
                        .@"or" => @field(
                            store,
                            valueName(definition.left),
                        ) or @field(
                            store,
                            valueName(definition.right),
                        ),
                    }),
                    .boolean_select => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == if (@field(
                        store,
                        valueName(definition.condition),
                    ))
                        @field(
                            store,
                            valueName(definition.then_value),
                        )
                    else
                        @field(
                            store,
                            valueName(definition.else_value),
                        ),
                    .value_copy => |definition| portable_value.eqlValue(
                        @TypeOf(@field(
                            store,
                            valueName(definition.result),
                        )),
                        @field(store, valueName(definition.result)),
                        @field(store, valueName(definition.source)),
                    ),
                    .value_constant => |definition| invariantValueMatches(
                        @field(store, valueName(definition.result)),
                        definition.contents,
                    ),
                    .value_select => |definition| portable_value.eqlValue(
                        @TypeOf(@field(
                            store,
                            valueName(definition.result),
                        )),
                        @field(store, valueName(definition.result)),
                        if (@field(
                            store,
                            valueName(definition.condition),
                        ))
                            @field(
                                store,
                                valueName(definition.then_value),
                            )
                        else
                            @field(
                                store,
                                valueName(definition.else_value),
                            ),
                    ),
                    .instruction_result => |definition| instructionResultHolds(
                        constructor_id,
                        environment,
                        definition.result,
                        definition.definition,
                        definition.operand_count,
                        definition.operands,
                    ),
                    .product_extract_result => |definition| blk: {
                        const product = @field(
                            store,
                            valueName(definition.product),
                        );
                        const Product = @TypeOf(product);
                        const field = std.meta.fields(Product)[
                            definition.field_index
                        ];
                        break :blk portable_value.eqlValue(
                            field.type,
                            @field(store, valueName(definition.result)),
                            @field(product, field.name),
                        );
                    },
                    .sum_extract_result => |definition| blk: {
                        const sum = @field(
                            store,
                            valueName(definition.sum),
                        );
                        const Sum = @TypeOf(sum);
                        const Tag = @typeInfo(Sum).@"union".tag_type.?;
                        const field = std.meta.fields(Sum)[
                            definition.case_index
                        ];
                        if (std.meta.activeTag(sum) != @field(Tag, field.name)) {
                            break :blk false;
                        }
                        break :blk portable_value.eqlValue(
                            field.type,
                            @field(store, valueName(definition.result)),
                            @field(sum, field.name),
                        );
                    },
                    .bounded_length_result => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == @field(
                        store,
                        valueName(definition.bounded),
                    ).len() catch unreachable,
                    .integer_unary_result => |definition| rnf.integerUnaryDefinitionHolds(
                        @field(store, valueName(definition.result)),
                        @field(store, valueName(definition.operand)),
                        definition.operation,
                    ),
                    .integer_binary_result => |definition| rnf.integerBinaryDefinitionHolds(
                        @field(store, valueName(definition.result)),
                        @field(store, valueName(definition.left)),
                        @field(store, valueName(definition.right)),
                        definition.operation,
                    ),
                    .integer_convert_result => |definition| rnf.integerConvertDefinitionHolds(
                        @field(store, valueName(definition.result)),
                        @field(store, valueName(definition.operand)),
                    ),
                    .integer_zero => |predicate| (@field(
                        store,
                        valueName(predicate.value),
                    ) == 0) == predicate.equal,
                    .integer_zero_result => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == (@field(
                        store,
                        valueName(definition.value),
                    ) == 0),
                    .integer_relation => |predicate| rnf.integerRelationHolds(
                        @field(store, valueName(predicate.left)),
                        @field(store, valueName(predicate.right)),
                        predicate.relation,
                    ) == predicate.expected,
                    .integer_relation_result => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == rnf.integerRelationHolds(
                        @field(store, valueName(definition.left)),
                        @field(store, valueName(definition.right)),
                        definition.relation,
                    ),
                    .sum_case => |predicate| (algebraicCaseIndex(@field(
                        store,
                        valueName(predicate.value),
                    )) == predicate.case_index) == predicate.equal,
                    .sum_case_result => |definition| @field(
                        store,
                        valueName(definition.result),
                    ) == (algebraicCaseIndex(@field(
                        store,
                        valueName(definition.value),
                    )) == definition.case_index),
                };
                if (!accepted) return error.ProgramContractViolation;
            }
        }

        pub fn validateFrame(
            frame: Frame,
        ) error{ProgramContractViolation}!void {
            return switch (frame) {
                inline else => |environment, tag| validateConstructor(
                    comptime @intFromEnum(tag),
                    environment,
                ),
            };
        }

        fn frameFunctionId(frame: Frame) control_ir.FunctionId {
            return switch (frame) {
                inline else => |_, tag| blk: {
                    const constructor_id: usize =
                        comptime @intFromEnum(tag);
                    const constructor = comptime normal_form.constructors[
                        constructor_id
                    ];
                    break :blk program.blocks[
                        constructor.source_block
                    ].function_id;
                },
            };
        }

        fn frameIsAwaitCall(frame: Frame) bool {
            return switch (frame) {
                inline else => |_, tag| comptime isAwaitCallConstructor(@intFromEnum(tag)),
            };
        }

        fn validateCallCallee(
            comptime suspension: control_ir.Suspension,
            child: Frame,
        ) error{ProgramContractViolation}!void {
            return switch (child) {
                inline else => |_, child_tag| blk: {
                    const child_constructor_id: usize =
                        comptime @intFromEnum(child_tag);
                    const child_constructor = comptime normal_form.constructors[
                        child_constructor_id
                    ];
                    if (program.blocks[
                        child_constructor.source_block
                    ].function_id != suspension.callee_function.?) {
                        break :blk error.ProgramContractViolation;
                    }
                },
            };
        }

        fn constructorRetainsValue(
            comptime constructor_id: usize,
            comptime value: control_ir.ValueId,
        ) bool {
            const constructor = comptime normal_form.constructors[constructor_id];
            inline for (constructor.environmentFields()) |field| {
                if (field.value == value) return true;
            }
            inline for (constructor.activationFields()) |field| {
                if (field.value == value) return true;
            }
            return false;
        }

        fn constructorRetainsActivationValue(
            comptime constructor_id: usize,
            comptime value: control_ir.ValueId,
        ) bool {
            const constructor = comptime normal_form.constructors[constructor_id];
            inline for (0..constructor.activation_len) |field_index| {
                if (constructor.activation[field_index].value == value) {
                    return true;
                }
            }
            return false;
        }

        fn validateCallEntryArguments(
            comptime parent_constructor_id: usize,
            parent_environment: anytype,
            comptime suspension: control_ir.Suspension,
            child: Frame,
        ) error{ProgramContractViolation}!void {
            @setEvalBranchQuota(compiler_evaluation_branch_quota);
            const parent_constructor = comptime normal_form.constructors[
                parent_constructor_id
            ];
            const callee = comptime suspension.callee.?;
            const call_entry_constructor_id = comptime constructorForIncoming(
                parent_constructor.source_block,
                .call,
                callee.target,
            );
            return switch (child) {
                inline else => |child_environment, child_tag| blk: {
                    const child_constructor_id: usize =
                        comptime @intFromEnum(child_tag);
                    const child_constructor = comptime normal_form.constructors[
                        child_constructor_id
                    ];
                    if (comptime child_constructor.has_activation_context) {
                        if (@field(child_environment, activation_entry_name) !=
                            @as(u32, @intCast(call_entry_constructor_id)))
                        {
                            break :blk error.ProgramContractViolation;
                        }
                        const target = comptime program.blocks[@intCast(callee.target)];
                        inline for (
                            target.parameters,
                            callee.arguments,
                        ) |parameter, argument| {
                            if (!comptime constructorRetainsActivationValue(
                                child_constructor_id,
                                parameter,
                            )) continue;
                            switch (argument) {
                                .value => |source| {
                                    if (!comptime constructorRetainsValue(
                                        parent_constructor_id,
                                        source,
                                    )) {
                                        @compileError(
                                            "call return frame must retain every live call argument",
                                        );
                                    }
                                    const Value = typeForValue(
                                        Body,
                                        program.value_types[@intCast(parameter)],
                                    );
                                    const equal = portable_value.eqlValue(
                                        Value,
                                        @field(
                                            child_environment,
                                            activationValueName(parameter),
                                        ),
                                        environmentValue(
                                            parent_constructor_id,
                                            parent_environment,
                                            source,
                                        ),
                                    );
                                    if (!equal) {
                                        break :blk error.ProgramContractViolation;
                                    }
                                },
                                .@"resume" => @compileError(
                                    "call edge cannot carry a resume value",
                                ),
                            }
                        }
                    } else {
                        break :blk error.ProgramContractViolation;
                    }
                },
            };
        }

        fn validateStackPair(
            parent: Frame,
            child: Frame,
        ) error{ProgramContractViolation}!void {
            return switch (parent) {
                inline else => |environment, tag| blk: {
                    const constructor_id: usize =
                        comptime @intFromEnum(tag);
                    if (!comptime isAwaitCallConstructor(constructor_id)) {
                        break :blk error.ProgramContractViolation;
                    }
                    const constructor = comptime normal_form.constructors[
                        constructor_id
                    ];
                    const suspension = comptime program.blocks[
                        constructor.source_block
                    ].terminator.@"suspend";
                    try validateCallCallee(
                        suspension,
                        child,
                    );
                    try validateCallEntryArguments(
                        constructor_id,
                        environment,
                        suspension,
                        child,
                    );
                },
            };
        }

        pub fn validateStack(
            frames: []const Frame,
        ) error{ProgramContractViolation}!void {
            if (frames.len == 0 or frameFunctionId(frames[0]) != 0) {
                return error.ProgramContractViolation;
            }
            if (frames.len == 1) {
                if (frameIsAwaitCall(frames[0])) {
                    return error.ProgramContractViolation;
                }
                return;
            }
            for (frames[0 .. frames.len - 1], frames[1..]) |parent, child| {
                try validateStackPair(parent, child);
            }
            if (frameIsAwaitCall(frames[frames.len - 1])) {
                return error.ProgramContractViolation;
            }
        }

        comptime {
            _ = Self;
        }
    };
}
