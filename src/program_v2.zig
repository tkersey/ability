const compiler = @import("compiler");
const image_emit_v1 = @import("image_emit_v1");
const kernel_machine_v1 = @import("kernel_machine_v1");
const machine = @import("machine");
const machine_v2_profile_v1 = @import("machine_v2_profile_v1");

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
            Reified.generated_reducer_operation_count;
        /// Largest typed value carrier used by one generated direct segment.
        ///
        /// This excludes compiler- and optimizer-dependent native stack
        /// placement of temporary copies.
        pub const maximum_segment_value_bytes =
            Definition.maximum_segment_value_bytes;
        /// Compile-time-only whole-program value catalog size for proof.
        pub const reachable_value_catalog_bytes =
            Definition.reachable_value_catalog_bytes;

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
            return machine_v2_profile_v1.Profile(
                program_transition_digest,
                machine_v2_semantic_digest,
                DirectMachine.Manifest.machine_contract_digest,
                options,
                &costs,
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
