const std = @import("std");

/// Dense value identity scoped to one Control IR function.
pub const ValueId = u16;

/// Dense block identity scoped to one Control IR function.
pub const BlockId = u16;

/// Dense function identity scoped to one Control IR program.
pub const FunctionId = u16;

/// Target-neutral scalar kinds admitted by the Boundary 1.0 compiler.
pub const ScalarType = enum {
    unit,
    boolean,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,

    /// Whether this scalar is one of the fixed-width integer kinds.
    pub fn isInteger(self: ScalarType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
            .unit, .boolean => false,
        };
    }
};

/// One lowered portable value type.
///
/// Structured schemas are content-addressed by the later portable-value pass;
/// Control IR needs only their dense compiler-local identity.
pub const ValueType = union(enum) {
    scalar: ScalarType,
    schema: u32,

    /// Compare two lowered types without nominal Zig identity.
    pub fn eql(self: ValueType, other: ValueType) bool {
        return switch (self) {
            .scalar => |scalar| switch (other) {
                .scalar => |other_scalar| scalar == other_scalar,
                .schema => false,
            },
            .schema => |schema| switch (other) {
                .scalar => false,
                .schema => |other_schema| schema == other_schema,
            },
        };
    }

    /// Whether this type is the canonical Boolean scalar.
    pub fn isBoolean(self: ValueType) bool {
        return switch (self) {
            .scalar => |scalar| scalar == .boolean,
            .schema => false,
        };
    }

    /// Whether this type is a fixed-width integer.
    pub fn isInteger(self: ValueType) bool {
        return switch (self) {
            .scalar => |scalar| scalar.isInteger(),
            .schema => false,
        };
    }
};

/// Pure instruction classifications needed by normalization and path analysis.
pub const InstructionKind = enum {
    constant,
    copy,
    compare_eq_zero,
    pure,
    call,
};

/// Normative pure operation carried by one typed Control IR definition.
pub const InstructionOperation = union(enum) {
    /// Analysis-only instruction retained for private compiler tests.
    metadata,
    /// Index into the source Body's heterogeneous canonical constant tuple.
    constant: u16,
    copy,
    compare_eq_zero,
    integer_add,
    integer_subtract,
    integer_multiply,
    integer_divide,
    integer_remainder,
    integer_negate,
    integer_equal,
    integer_not_equal,
    integer_less_than,
    integer_less_equal,
    integer_greater_than,
    integer_greater_equal,
    integer_bit_not,
    integer_bit_and,
    integer_bit_or,
    integer_bit_xor,
    integer_convert,
    boolean_not,
    boolean_and,
    boolean_or,
    select,
    product_construct,
    product_extract: u16,
    product_replace: u16,
    sum_construct: u16,
    sum_tag_is: u16,
    sum_extract: u16,
    optional_none,
    optional_some,
    optional_is_some,
    vector_empty,
    vector_length,
    vector_get,
    vector_set,
    vector_push,
    vector_pop,
    vector_truncate,
    vector_clear,
    text_empty,
    text_append,
    text_append_scalar,
    text_append_unsigned,
    text_append_signed,
    text_copy,
    text_compare,
    text_join,
    bytes_empty,
    bytes_append,
    bytes_copy,
    bytes_compare,
};

/// One explicit typed Control IR value definition.
pub const Instruction = struct {
    kind: InstructionKind,
    result: ValueId,
    operands: []const ValueId = &.{},
    operation: InstructionOperation = .metadata,
};

/// One value supplied to a successor block parameter.
pub const EdgeArgument = union(enum) {
    value: ValueId,
    @"resume",
};

/// One explicit Control IR edge.
pub const Edge = struct {
    target: BlockId,
    arguments: []const EdgeArgument = &.{},
};

/// Suspension classes whose continuations may require portable state.
pub const SuspensionKind = enum {
    effect,
    call,
    explicit_yield,
    caller_fuel,
};

/// One suspension followed by one typed continuation edge.
pub const Suspension = struct {
    kind: SuspensionKind,
    site_id: ?u32 = null,
    request_values: []const ValueId = &.{},
    callee_function: ?FunctionId = null,
    callee: ?Edge = null,
    continuation: Edge,
    resume_type: ?ValueType = null,
};

/// One conditional branch with explicit successor edges.
pub const Branch = struct {
    condition: ValueId,
    then_edge: Edge,
    else_edge: Edge,
};

/// One normalized block terminator.
pub const Terminator = union(enum) {
    jump: Edge,
    branch: Branch,
    @"suspend": Suspension,
    return_value: ?ValueId,
    return_to_caller: ValueId,
    fail: u16,
};

/// Compiler classification for persisted block entries.
pub const BlockRole = enum {
    segment,
    loop_header,
    call_return,
    after_handler,
    terminal_handoff,
};

/// One typed normalized basic block.
pub const Block = struct {
    id: BlockId,
    function_id: FunctionId = 0,
    role: BlockRole = .segment,
    parameters: []const ValueId = &.{},
    instructions: []const Instruction = &.{},
    terminator: Terminator,
};

/// One statically declared Control IR function.
pub const Function = struct {
    id: FunctionId,
    entry: BlockId,
    result_type: ValueType,
};

/// One private typed Control IR function.
pub const Program = struct {
    label: []const u8,
    value_types: []const ValueType,
    blocks: []const Block,
    entry: BlockId,
    result_type: ValueType,
    /// Empty means one implicit root function for source compatibility.
    functions: []const Function = &.{},

    /// Resolve one dense typed value without exposing unchecked table access.
    pub fn valueType(self: Program, value: ValueId) ValidationError!ValueType {
        const index: usize = @intCast(value);
        if (index >= self.value_types.len) return error.InvalidValue;
        return self.value_types[index];
    }

    /// Resolve one dense function, including the implicit single-root form.
    pub fn function(
        self: Program,
        function_id: FunctionId,
    ) ValidationError!Function {
        if (self.functions.len == 0) {
            if (function_id != 0) return error.InvalidFunction;
            return .{
                .id = 0,
                .entry = self.entry,
                .result_type = self.result_type,
            };
        }
        const index: usize = @intCast(function_id);
        if (index >= self.functions.len) return error.InvalidFunction;
        return self.functions[index];
    }
};

/// Bounded compiler-analysis and reducer-generation work.
///
/// A source Body may lower these ceilings with `compiler_limits`. Ceilings are
/// admission policy, not executable Machine semantics, and therefore do not
/// enter the Machine contract digest when the generated RNF is unchanged.
pub const CompilerLimits = struct {
    maximum_values: usize = 64,
    maximum_blocks: usize = 64,
    maximum_constructors: usize = 128,
    maximum_environment_fields: usize = 64,
    maximum_invariant_terms: usize = 16,
    maximum_generated_operations: usize = 8192,
};

/// Bounded compiler work that cannot be represented inside declared ceilings.
pub const CompilerBlocker = error{
    GeneratedReducerLimitExceeded,
};

/// Structural and type failures rejected before RNF synthesis.
pub const ValidationError = error{
    EmptyProgram,
    TooManyBlocks,
    TooManyValues,
    InvalidFunction,
    InvalidBlock,
    InvalidValue,
    DuplicateDefinition,
    MissingDefinition,
    EdgeArityMismatch,
    EdgeTypeMismatch,
    InvalidResume,
    InvalidInstruction,
    InvalidCondition,
    InvalidReturn,
    LivenessDidNotConverge,
};

/// Forward reachability from the root entry over all explicit control edges.
///
/// Calls mark both the callee entry and the caller continuation reachable.
/// Return edges need no dynamic reconstruction because every statically
/// admitted call already owns its typed continuation edge.
pub fn Reachability(comptime maximum_blocks: usize) type {
    return struct {
        const Self = @This();

        reachable: [maximum_blocks]bool =
            [_]bool{false} ** maximum_blocks,
        source_to_dense: [maximum_blocks]?BlockId =
            [_]?BlockId{null} ** maximum_blocks,
        dense_to_source: [maximum_blocks]BlockId = undefined,
        count: usize = 0,

        /// Whether one validated block belongs to the root-reachable graph.
        pub fn contains(self: Self, block: BlockId) bool {
            return self.reachable[@intCast(block)];
        }

        /// Resolve one source block to its deterministic traversal ordinal.
        pub fn denseId(self: Self, block: BlockId) ?BlockId {
            return self.source_to_dense[@intCast(block)];
        }

        /// Resolve one deterministic traversal ordinal to its source block.
        pub fn sourceId(self: Self, dense: BlockId) ?BlockId {
            if (@as(usize, @intCast(dense)) >= self.count) return null;
            return self.dense_to_source[@intCast(dense)];
        }

        fn enqueue(
            self: *Self,
            program: Program,
            queue: *[maximum_blocks]BlockId,
            queue_length: *usize,
            block: BlockId,
        ) ValidationError!void {
            const index: usize = @intCast(block);
            if (index >= program.blocks.len) return error.InvalidBlock;
            if (self.reachable[index]) return;
            self.reachable[index] = true;
            self.source_to_dense[index] = @intCast(self.count);
            self.dense_to_source[self.count] = block;
            self.count += 1;
            queue[queue_length.*] = block;
            queue_length.* += 1;
        }

        fn enqueueEdge(
            self: *Self,
            program: Program,
            queue: *[maximum_blocks]BlockId,
            queue_length: *usize,
            edge: Edge,
        ) ValidationError!void {
            try self.enqueue(program, queue, queue_length, edge.target);
        }

        /// Compute the closed root-reachable block set.
        pub fn analyze(program: Program) ValidationError!Self {
            if (program.blocks.len == 0) return error.EmptyProgram;
            if (program.blocks.len > maximum_blocks) {
                return error.TooManyBlocks;
            }

            var result: Self = .{};
            var queue: [maximum_blocks]BlockId = undefined;
            var queue_length: usize = 0;
            var cursor: usize = 0;
            try result.enqueue(
                program,
                &queue,
                &queue_length,
                program.entry,
            );

            while (cursor < queue_length) : (cursor += 1) {
                const block = program.blocks[@intCast(queue[cursor])];
                switch (block.terminator) {
                    .jump => |edge| try result.enqueueEdge(
                        program,
                        &queue,
                        &queue_length,
                        edge,
                    ),
                    .branch => |branch| {
                        try result.enqueueEdge(
                            program,
                            &queue,
                            &queue_length,
                            branch.then_edge,
                        );
                        try result.enqueueEdge(
                            program,
                            &queue,
                            &queue_length,
                            branch.else_edge,
                        );
                    },
                    .@"suspend" => |suspension| {
                        if (suspension.callee) |callee| {
                            try result.enqueueEdge(
                                program,
                                &queue,
                                &queue_length,
                                callee,
                            );
                        }
                        try result.enqueueEdge(
                            program,
                            &queue,
                            &queue_length,
                            suspension.continuation,
                        );
                    },
                    .return_value, .return_to_caller, .fail => {},
                }
            }
            return result;
        }
    };
}

/// A small allocation-free value set used by compiler analyses.
pub fn ValueSet(comptime maximum_values: usize) type {
    return struct {
        const Self = @This();

        bits: [maximum_values]bool = [_]bool{false} ** maximum_values,

        /// Construct an empty set.
        pub fn empty() Self {
            return .{};
        }

        /// Insert one value, returning whether the set changed.
        pub fn insert(self: *Self, value: ValueId) bool {
            const index: usize = @intCast(value);
            if (self.bits[index]) return false;
            self.bits[index] = true;
            return true;
        }

        /// Remove one value, returning whether the set changed.
        pub fn remove(self: *Self, value: ValueId) bool {
            const index: usize = @intCast(value);
            if (!self.bits[index]) return false;
            self.bits[index] = false;
            return true;
        }

        /// Whether one value belongs to the set.
        pub fn contains(self: Self, value: ValueId) bool {
            return self.bits[@intCast(value)];
        }

        /// Merge another set, returning whether the receiver changed.
        pub fn merge(self: *Self, other: Self) bool {
            var changed = false;
            for (&self.bits, other.bits) |*destination, source| {
                if (source and !destination.*) {
                    destination.* = true;
                    changed = true;
                }
            }
            return changed;
        }

        /// Compare two sets.
        pub fn eql(self: Self, other: Self) bool {
            return std.mem.eql(bool, &self.bits, &other.bits);
        }

        /// Count contained values.
        pub fn count(self: Self) usize {
            var total: usize = 0;
            for (self.bits) |present| {
                if (present) total += 1;
            }
            return total;
        }
    };
}

fn validateValue(program: Program, value: ValueId) ValidationError!void {
    if (@as(usize, @intCast(value)) >= program.value_types.len) {
        return error.InvalidValue;
    }
}

fn validateEdge(
    program: Program,
    edge: Edge,
    allow_resume: bool,
    resume_type: ?ValueType,
) ValidationError!void {
    if (@as(usize, @intCast(edge.target)) >= program.blocks.len) {
        return error.InvalidBlock;
    }
    const target = program.blocks[@intCast(edge.target)];
    if (edge.arguments.len != target.parameters.len) {
        return error.EdgeArityMismatch;
    }

    var saw_resume = false;
    for (edge.arguments, target.parameters) |argument, parameter| {
        try validateValue(program, parameter);
        const parameter_type = program.value_types[@intCast(parameter)];
        switch (argument) {
            .value => |value| {
                try validateValue(program, value);
                if (!program.value_types[@intCast(value)].eql(parameter_type)) {
                    return error.EdgeTypeMismatch;
                }
            },
            .@"resume" => {
                if (!allow_resume or saw_resume) return error.InvalidResume;
                const response_type = resume_type orelse return error.InvalidResume;
                if (!response_type.eql(parameter_type)) return error.EdgeTypeMismatch;
                saw_resume = true;
            },
        }
    }
    if ((resume_type != null) != saw_resume) return error.InvalidResume;
}

/// Validate one Control IR function before data-flow analysis.
pub fn validate(
    comptime maximum_values: usize,
    comptime maximum_blocks: usize,
    program: Program,
) ValidationError!void {
    if (program.blocks.len == 0) return error.EmptyProgram;
    if (program.blocks.len > maximum_blocks) return error.TooManyBlocks;
    if (program.value_types.len > maximum_values) return error.TooManyValues;
    if (@as(usize, @intCast(program.entry)) >= program.blocks.len) {
        return error.InvalidBlock;
    }
    if (program.functions.len != 0) {
        for (program.functions, 0..) |function, function_index| {
            if (function.id != function_index or
                @as(usize, @intCast(function.entry)) >= program.blocks.len or
                program.blocks[@intCast(function.entry)].function_id != function.id)
            {
                return error.InvalidFunction;
            }
        }
        const root = try program.function(0);
        if (root.entry != program.entry or
            !root.result_type.eql(program.result_type))
        {
            return error.InvalidFunction;
        }
    }

    var defined = [_]bool{false} ** maximum_values;
    for (program.blocks, 0..) |block, block_index| {
        if (block.id != block_index) return error.InvalidBlock;
        _ = try program.function(block.function_id);
        for (block.parameters) |parameter| {
            try validateValue(program, parameter);
            const index: usize = @intCast(parameter);
            if (defined[index]) return error.DuplicateDefinition;
            defined[index] = true;
        }
        for (block.instructions) |instruction| {
            try validateValue(program, instruction.result);
            const result_index: usize = @intCast(instruction.result);
            if (defined[result_index]) return error.DuplicateDefinition;
            defined[result_index] = true;
        }
    }
    for (defined[0..program.value_types.len]) |present| {
        if (!present) return error.MissingDefinition;
    }

    for (program.blocks) |block| {
        for (block.instructions) |instruction| {
            for (instruction.operands) |operand| try validateValue(program, operand);
            switch (instruction.operation) {
                .metadata => {},
                .constant => if (instruction.kind != .constant or
                    instruction.operands.len != 0)
                {
                    return error.InvalidInstruction;
                },
                .copy => if (instruction.kind != .copy or
                    instruction.operands.len != 1)
                {
                    return error.InvalidInstruction;
                },
                .compare_eq_zero => if (instruction.kind != .compare_eq_zero or
                    instruction.operands.len != 1)
                {
                    return error.InvalidInstruction;
                },
                .integer_add,
                .integer_subtract,
                .integer_multiply,
                .integer_divide,
                .integer_remainder,
                .integer_equal,
                .integer_not_equal,
                .integer_less_than,
                .integer_less_equal,
                .integer_greater_than,
                .integer_greater_equal,
                .integer_bit_and,
                .integer_bit_or,
                .integer_bit_xor,
                .boolean_and,
                .boolean_or,
                .vector_get,
                .vector_push,
                .vector_truncate,
                .text_append,
                .text_append_scalar,
                .text_append_unsigned,
                .text_append_signed,
                .text_compare,
                .bytes_append,
                .bytes_compare,
                => if (instruction.kind != .pure or instruction.operands.len != 2) {
                    return error.InvalidInstruction;
                },
                .product_construct, .sum_construct => if (instruction.kind != .pure) {
                    return error.InvalidInstruction;
                },
                .integer_negate,
                .integer_bit_not,
                .integer_convert,
                .boolean_not,
                .product_extract,
                .sum_tag_is,
                .sum_extract,
                .optional_some,
                .optional_is_some,
                .vector_length,
                .vector_pop,
                .vector_clear,
                => if (instruction.kind != .pure or
                    instruction.operands.len != 1)
                {
                    return error.InvalidInstruction;
                },
                .select,
                .vector_set,
                .text_copy,
                .text_join,
                .bytes_copy,
                => if (instruction.kind != .pure or
                    instruction.operands.len != 3)
                {
                    return error.InvalidInstruction;
                },
                .product_replace => if (instruction.kind != .pure or
                    instruction.operands.len != 2)
                {
                    return error.InvalidInstruction;
                },
                .optional_none,
                .vector_empty,
                .text_empty,
                .bytes_empty,
                => if (instruction.kind != .pure or
                    instruction.operands.len != 0)
                {
                    return error.InvalidInstruction;
                },
            }
            switch (instruction.kind) {
                .constant => if (instruction.operands.len != 0) return error.InvalidInstruction,
                .copy => {
                    if (instruction.operands.len != 1) return error.InvalidInstruction;
                    if (!program.value_types[@intCast(instruction.result)].eql(
                        program.value_types[@intCast(instruction.operands[0])],
                    )) return error.InvalidInstruction;
                },
                .compare_eq_zero => {
                    if (instruction.operands.len != 1) return error.InvalidInstruction;
                    if (!program.value_types[@intCast(instruction.result)].isBoolean()) {
                        return error.InvalidInstruction;
                    }
                    if (!program.value_types[@intCast(instruction.operands[0])].isInteger()) {
                        return error.InvalidInstruction;
                    }
                },
                .pure, .call => {},
            }
        }

        switch (block.terminator) {
            .jump => |edge| try validateEdge(program, edge, false, null),
            .branch => |branch| {
                try validateValue(program, branch.condition);
                if (!program.value_types[@intCast(branch.condition)].isBoolean()) {
                    return error.InvalidCondition;
                }
                try validateEdge(program, branch.then_edge, false, null);
                try validateEdge(program, branch.else_edge, false, null);
            },
            .@"suspend" => |suspension| {
                for (suspension.request_values) |value| try validateValue(program, value);
                switch (suspension.kind) {
                    .effect => {
                        if (suspension.site_id == null or
                            suspension.callee_function != null or
                            suspension.callee != null)
                        {
                            return error.InvalidInstruction;
                        }
                        try validateEdge(
                            program,
                            suspension.continuation,
                            true,
                            suspension.resume_type,
                        );
                    },
                    .call => {
                        if (suspension.site_id != null or
                            suspension.request_values.len != 0)
                        {
                            return error.InvalidInstruction;
                        }
                        const callee_function_id = suspension.callee_function orelse
                            return error.InvalidInstruction;
                        const callee = suspension.callee orelse
                            return error.InvalidInstruction;
                        const function = try program.function(callee_function_id);
                        if (callee.target != function.entry) {
                            return error.InvalidFunction;
                        }
                        try validateEdge(program, callee, false, null);
                        const resume_type = suspension.resume_type orelse
                            return error.InvalidResume;
                        if (!resume_type.eql(function.result_type)) {
                            return error.EdgeTypeMismatch;
                        }
                        try validateEdge(
                            program,
                            suspension.continuation,
                            true,
                            suspension.resume_type,
                        );
                    },
                    .explicit_yield, .caller_fuel => {
                        if (suspension.site_id != null or
                            suspension.request_values.len != 0 or
                            suspension.callee_function != null or
                            suspension.callee != null or
                            suspension.resume_type != null)
                        {
                            return error.InvalidInstruction;
                        }
                        try validateEdge(
                            program,
                            suspension.continuation,
                            false,
                            null,
                        );
                    },
                }
            },
            .return_value => |maybe_value| {
                if (block.function_id != 0) return error.InvalidReturn;
                if (maybe_value) |value| {
                    try validateValue(program, value);
                    if (!program.value_types[@intCast(value)].eql(program.result_type)) {
                        return error.InvalidReturn;
                    }
                } else if (!program.result_type.eql(.{ .scalar = .unit })) {
                    return error.InvalidReturn;
                }
            },
            .return_to_caller => |value| {
                if (block.function_id == 0) return error.InvalidReturn;
                try validateValue(program, value);
                const function = try program.function(block.function_id);
                if (!program.value_types[@intCast(value)].eql(
                    function.result_type,
                )) {
                    return error.InvalidReturn;
                }
            },
            .fail => {},
        }
    }
}

/// Allocation-free exact liveness over one bounded Control IR function.
pub fn Liveness(
    comptime maximum_values: usize,
    comptime maximum_blocks: usize,
) type {
    const Set = ValueSet(maximum_values);
    return struct {
        const Self = @This();

        live_in: [maximum_blocks]Set = [_]Set{Set.empty()} ** maximum_blocks,
        entry_live: [maximum_blocks]Set = [_]Set{Set.empty()} ** maximum_blocks,
        live_out: [maximum_blocks]Set = [_]Set{Set.empty()} ** maximum_blocks,
        iteration_count: usize = 0,

        fn transferEdge(
            self: Self,
            program: Program,
            edge: Edge,
            destination: *Set,
        ) void {
            const target_index: usize = @intCast(edge.target);
            _ = destination.merge(self.live_in[target_index]);
            const target = program.blocks[target_index];
            for (target.parameters, edge.arguments) |parameter, argument| {
                if (!self.entry_live[target_index].contains(parameter)) continue;
                switch (argument) {
                    .value => |value| _ = destination.insert(value),
                    .@"resume" => {},
                }
            }
        }

        fn blockOut(self: Self, program: Program, block: Block) Set {
            var result = Set.empty();
            switch (block.terminator) {
                .jump => |edge| self.transferEdge(program, edge, &result),
                .branch => |branch| {
                    self.transferEdge(program, branch.then_edge, &result);
                    self.transferEdge(program, branch.else_edge, &result);
                },
                .@"suspend" => |suspension| {
                    self.transferEdge(program, suspension.continuation, &result);
                },
                .return_value, .return_to_caller, .fail => {},
            }
            return result;
        }

        fn addTerminatorUses(block: Block, set: *Set) void {
            switch (block.terminator) {
                .branch => |branch| _ = set.insert(branch.condition),
                .@"suspend" => |suspension| {
                    for (suspension.request_values) |value| _ = set.insert(value);
                    if (suspension.callee) |callee| {
                        for (callee.arguments) |argument| switch (argument) {
                            .value => |value| _ = set.insert(value),
                            .@"resume" => {},
                        };
                    }
                },
                .return_value => |maybe_value| {
                    if (maybe_value) |value| _ = set.insert(value);
                },
                .return_to_caller => |value| _ = set.insert(value),
                .jump, .fail => {},
            }
        }

        /// Compute the fixed point after validating the function.
        pub fn analyze(program: Program) ValidationError!Self {
            try validate(maximum_values, maximum_blocks, program);
            var analysis: Self = .{};
            const maximum_iterations = program.blocks.len * (program.value_types.len + 1) + 1;

            while (analysis.iteration_count < maximum_iterations) {
                analysis.iteration_count += 1;
                var changed = false;
                var remaining = program.blocks.len;
                while (remaining > 0) {
                    remaining -= 1;
                    const block = program.blocks[remaining];
                    const outgoing = analysis.blockOut(program, block);
                    var live = outgoing;
                    addTerminatorUses(block, &live);

                    var instruction_index = block.instructions.len;
                    while (instruction_index > 0) {
                        instruction_index -= 1;
                        const instruction = block.instructions[instruction_index];
                        _ = live.remove(instruction.result);
                        for (instruction.operands) |operand| _ = live.insert(operand);
                    }

                    const entry_live = live;
                    for (block.parameters) |parameter| _ = live.remove(parameter);

                    if (!analysis.live_out[remaining].eql(outgoing)) {
                        analysis.live_out[remaining] = outgoing;
                        changed = true;
                    }
                    if (!analysis.entry_live[remaining].eql(entry_live)) {
                        analysis.entry_live[remaining] = entry_live;
                        changed = true;
                    }
                    if (!analysis.live_in[remaining].eql(live)) {
                        analysis.live_in[remaining] = live;
                        changed = true;
                    }
                }
                if (!changed) return analysis;
            }
            return error.LivenessDidNotConverge;
        }

        /// Values that must cross one explicit edge, excluding a resume value
        /// produced by the boundary itself.
        pub fn edgeEnvironment(self: Self, program: Program, edge: Edge) Set {
            var result = Set.empty();
            self.transferEdge(program, edge, &result);
            return result;
        }
    };
}

test "liveness retains exact effect continuation values and omits dead definitions" {
    const i32_type: ValueType = .{ .scalar = .i32 };
    const bool_type: ValueType = .{ .scalar = .boolean };
    const value_types = [_]ValueType{
        i32_type,
        i32_type,
        bool_type,
        i32_type,
        i32_type,
        i32_type,
    };
    const entry_instructions = [_]Instruction{
        .{ .kind = .constant, .result = 1 },
        .{ .kind = .compare_eq_zero, .result = 2, .operands = &.{0} },
    };
    const finish_instructions = [_]Instruction{
        .{ .kind = .pure, .result = 5, .operands = &.{ 3, 4 } },
    };
    const continuation_arguments = [_]EdgeArgument{ .@"resume", .{ .value = 0 } };
    const blocks = [_]Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .instructions = &entry_instructions,
            .terminator = .{ .branch = .{
                .condition = 2,
                .then_edge = .{ .target = 1 },
                .else_edge = .{ .target = 2 },
            } },
        },
        .{
            .id = 1,
            .terminator = .{ .@"suspend" = .{
                .kind = .effect,
                .site_id = 7,
                .request_values = &.{0},
                .continuation = .{ .target = 3, .arguments = &continuation_arguments },
                .resume_type = i32_type,
            } },
        },
        .{
            .id = 2,
            .terminator = .{ .@"suspend" = .{
                .kind = .effect,
                .site_id = 8,
                .request_values = &.{0},
                .continuation = .{ .target = 3, .arguments = &continuation_arguments },
                .resume_type = i32_type,
            } },
        },
        .{
            .id = 3,
            .parameters = &.{ 3, 4 },
            .instructions = &finish_instructions,
            .terminator = .{ .return_value = 5 },
        },
    };
    const program: Program = .{
        .label = "correlated-effect",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = i32_type,
    };

    const analysis = try Liveness(16, 8).analyze(program);
    const then_environment = analysis.edgeEnvironment(
        program,
        blocks[1].terminator.@"suspend".continuation,
    );
    try std.testing.expect(then_environment.contains(0));
    try std.testing.expect(!then_environment.contains(1));
    try std.testing.expectEqual(@as(usize, 1), then_environment.count());
}

test "validation rejects resume placeholders on ordinary edges" {
    const i32_type: ValueType = .{ .scalar = .i32 };
    const value_types = [_]ValueType{ i32_type, i32_type };
    const invalid_arguments = [_]EdgeArgument{.@"resume"};
    const blocks = [_]Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .jump = .{
                .target = 1,
                .arguments = &invalid_arguments,
            } },
        },
        .{
            .id = 1,
            .parameters = &.{1},
            .terminator = .{ .return_value = 1 },
        },
    };
    const program: Program = .{
        .label = "invalid-resume",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = i32_type,
    };

    try std.testing.expectError(error.InvalidResume, validate(8, 4, program));
}
