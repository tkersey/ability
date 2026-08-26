const compiler = @import("compiler");
const image_emit_v1 = @import("image_emit_v1");
const kernel_machine_v1 = @import("kernel_machine_v1");
const machine = @import("machine");
const machine_v2_profile_v1 = @import("machine_v2_profile_v1");
const std = @import("std");

fn constructorFieldsEqual(
    left: anytype,
    right: anytype,
) bool {
    if (left.source_block != right.source_block or
        left.resume_target != right.resume_target or
        left.has_activation_context != right.has_activation_context or
        left.activation_len != right.activation_len or
        left.environment_len != right.environment_len or
        left.invariant_len != right.invariant_len)
    {
        return false;
    }
    for (left.activationFields(), right.activationFields()) |a, b| {
        if (a.value != b.value or !a.value_type.eql(b.value_type)) return false;
    }
    for (left.environmentFields(), right.environmentFields()) |a, b| {
        if (a.value != b.value or !a.value_type.eql(b.value_type)) return false;
    }
    for (left.invariantTerms(), right.invariantTerms()) |a, b| {
        if (!std.meta.eql(a, b)) return false;
    }
    return true;
}

/// Declare one typed Boundary source program with one Machine meaning.
pub fn program(comptime label: []const u8, comptime Body: type) type {
    const Reified = compiler.ReifiedFor(label, Body);
    const MachineV2Lowering = compiler.MachineV2LoweringFor(Reified);
    const Definition = compiler.DirectDefinitionFor(MachineV2Lowering);
    return struct {
        /// Diagnostic source label excluded from Machine semantic identity.
        pub const program_label = label;
        /// Private typed source/control program.
        pub const control_ir = Reified.control;
        /// Canonical compile-time Resumption Normal Form.
        pub const rnf = Reified.rnf_value;
        /// Source-declared bounded compiler work, excluded from Machine identity.
        pub const compiler_limits = Reified.compiler_limits;
        /// Canonical transition identity of the defunctionalized Program.
        pub const program_transition_digest =
            Reified.program_transition_digest;
        /// Exact legacy bounded-reducer identity retained by Machine ABI v2.
        pub const machine_v2_semantic_digest =
            MachineV2Lowering.machine_v2_semantic_digest;
        /// Static size proxy for the generated direct reducer.
        pub const generated_reducer_operation_count =
            Definition.generated_reducer_operation_count;
        /// Largest typed value carrier used by one generated direct segment.
        ///
        /// This excludes compiler- and optimizer-dependent native stack
        /// placement of temporary copies.
        pub const maximum_segment_value_bytes =
            Definition.maximum_segment_value_bytes;
        /// Compile-time-only whole-program value catalog size for proof.
        pub const reachable_value_catalog_bytes =
            Definition.reachable_value_catalog_bytes;

        /// Return the exact generic compiler input used by World linking.
        ///
        /// Optional declarations remain optional; this projection deliberately
        /// introduces no second owner that can drift from the source Body.
        pub fn component() type {
            return Body;
        }

        /// Compile this program to its sole direct Boundary Machine.
        pub fn compileV2(comptime options: machine.Options) type {
            return machine.Machine(Definition, options);
        }

        /// Source-compatible alias for the bounded Machine ABI v2 compiler.
        pub fn compile(comptime options: machine.Options) type {
            return compileV2(options);
        }

        /// Emit the profile-independent canonical Boundary Program Image.
        pub fn image() type {
            const Emitted = image_emit_v1.ProgramImage(Reified);
            return struct {
                pub const format_version = Emitted.format_version;
                pub const bytes = Emitted.bytes;
                pub const byte_length = Emitted.byte_length;
                pub const program_transition_digest =
                    Emitted.program_transition_digest;
                pub const artifact_sha256 = Emitted.artifact_sha256;
                pub const maximum_kernel_scratch_bytes =
                    Emitted.maximum_kernel_scratch_bytes;
                pub const maximum_single_value_bytes =
                    Emitted.maximum_single_value_bytes;
            };
        }

        /// Materialize the bounded Machine ABI v2 policy separately from BPI1.
        pub fn machineV2Profile(comptime options: machine.Options) type {
            const DirectMachine = compileV2(options);
            comptime {
                if (MachineV2Lowering.semantic_canonicalization.block_count !=
                    Reified.semantic_canonicalization.block_count)
                {
                    @compileError("Machine v2 segment catalog diverges from BPI1");
                }
                for (0..Reified.semantic_canonicalization.block_count) |dense| {
                    if (MachineV2Lowering.semantic_canonicalization
                        .block_dense_to_source[dense] !=
                        Reified.semantic_canonicalization
                            .block_dense_to_source[dense])
                    {
                        @compileError("Machine v2 segment ids diverge from BPI1");
                    }
                }
                if (MachineV2Lowering.rnf_value.entry_transition_count !=
                    Reified.rnf_value.entry_transition_count)
                {
                    @compileError("Machine v2 transition catalog diverges from BPI1");
                }
            }
            const costs = comptime blk: {
                var values: [MachineV2Lowering.semantic_canonicalization.block_count]u64 =
                    undefined;
                for (0..values.len) |dense_segment| {
                    const source_segment = MachineV2Lowering
                        .semantic_canonicalization
                        .block_dense_to_source[dense_segment];
                    values[dense_segment] =
                        MachineV2Lowering.effective_block_costs[source_segment];
                }
                break :blk values;
            };
            const terminator_overrides = comptime blk: {
                var values: [costs.len]u8 = [_]u8{0} ** costs.len;
                for (0..values.len) |dense_segment| {
                    const source_segment = MachineV2Lowering
                        .semantic_canonicalization
                        .block_dense_to_source[dense_segment];
                    switch (MachineV2Lowering.control.blocks[source_segment].terminator) {
                        .@"suspend" => |suspension| {
                            if (suspension.kind == .caller_fuel) {
                                values[dense_segment] = 1;
                            }
                        },
                        else => {},
                    }
                }
                break :blk values;
            };
            const constructor_origins = comptime blk: {
                var values: [MachineV2Lowering.rnf_value.constructor_count]u8 =
                    undefined;
                for (MachineV2Lowering.rnf_value.constructorSlice(), 0..) |
                    constructor,
                    index,
                | {
                    values[index] = @intFromEnum(constructor.origin);
                }
                break :blk values;
            };
            const constructor_mappings = comptime blk: {
                var values: [MachineV2Lowering.rnf_value.constructor_count]u32 =
                    undefined;
                for (MachineV2Lowering.rnf_value.constructorSlice(), 0..) |
                    v2_constructor,
                    v2_id,
                | {
                    if (MachineV2Lowering.rnf_value.constructor_count ==
                        Reified.rnf_value.constructor_count)
                    {
                        if (!constructorFieldsEqual(
                            &v2_constructor,
                            &Reified.rnf_value.constructors[v2_id],
                        )) {
                            @compileError("Machine v2 constructor layout diverges from BPI1");
                        }
                        values[v2_id] = @intCast(v2_id);
                        continue;
                    }
                    if (v2_id < Reified.rnf_value.constructor_count and
                        constructorFieldsEqual(
                            &v2_constructor,
                            &Reified.rnf_value.constructors[v2_id],
                        ))
                    {
                        values[v2_id] = @intCast(v2_id);
                        continue;
                    }
                    var match: ?u32 = null;
                    for (Reified.rnf_value.constructorSlice(), 0..) |
                        pure_constructor,
                        pure_id,
                    | {
                        if (!constructorFieldsEqual(
                            &v2_constructor,
                            &pure_constructor,
                        )) continue;
                        if (match != null) {
                            @compileError("Machine v2 constructor mapping is ambiguous");
                        }
                        match = @intCast(pure_id);
                    }
                    values[v2_id] = match orelse
                        @compileError("Machine v2 constructor lacks a BPI1 quotient");
                }
                break :blk values;
            };
            const transition_kinds = comptime blk: {
                var values: [MachineV2Lowering.rnf_value.entry_transition_count]u8 =
                    undefined;
                for (MachineV2Lowering.rnf_value.entryTransitionSlice(), 0..) |
                    transition,
                    index,
                | {
                    const pure_transition = Reified.rnf_value
                        .entryTransitionSlice()[index];
                    if (transition.source_block != pure_transition.source_block or
                        transition.target_block != pure_transition.target_block)
                    {
                        @compileError("Machine v2 transition endpoints diverge from BPI1");
                    }
                    if (transition.edge_kind != pure_transition.edge_kind and
                        !(transition.edge_kind == .suspension_continuation and
                            pure_transition.edge_kind == .jump and
                            terminator_overrides[
                                MachineV2Lowering.semantic_canonicalization
                                    .blockId(transition.source_block)
                            ] == 1))
                    {
                        @compileError("Machine v2 transition delta is not profile-owned");
                    }
                    values[index] = @intFromEnum(transition.edge_kind);
                }
                break :blk values;
            };
            const transition_constructors = comptime blk: {
                var values: [MachineV2Lowering.rnf_value.entry_transition_count]u32 =
                    undefined;
                for (MachineV2Lowering.rnf_value.entryTransitionSlice(), 0..) |
                    transition,
                    index,
                | {
                    values[index] = transition.constructor_id;
                }
                break :blk values;
            };
            return machine_v2_profile_v1.Profile(
                program_transition_digest,
                machine_v2_semantic_digest,
                DirectMachine.Manifest.machine_contract_digest,
                options,
                &costs,
                &terminator_overrides,
                &constructor_origins,
                &constructor_mappings,
                &transition_kinds,
                &transition_constructors,
                MachineV2Lowering.initial_constructor_id,
                Reified.rnf_value.constructor_count,
            );
        }

        /// Adapt the fixed byte kernel to the typed Machine ABI v2 surface.
        pub fn kernelMachineV2(comptime options: machine.Options) type {
            const Image = image();
            const Profile = machineV2Profile(options);
            return kernel_machine_v1.Machine(
                Definition,
                Image,
                Profile,
                options,
            );
        }
    };
}
