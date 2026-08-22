const compiler = @import("compiler");
const image_emit_v1 = @import("image_emit_v1");
const machine = @import("machine");

/// Declare one typed Boundary source program with one Machine meaning.
pub fn program(comptime label: []const u8, comptime Body: type) type {
    const Reified = compiler.ReifiedFor(label, Body);
    const Definition = compiler.DirectDefinitionFor(Reified);
    return struct {
        /// Diagnostic source label excluded from Machine semantic identity.
        pub const program_label = label;
        /// Private typed source/control program.
        pub const control_ir = Reified.control;
        /// Canonical compile-time Resumption Normal Form.
        pub const rnf = Reified.rnf_value;
        /// Source-declared bounded compiler work, excluded from Machine identity.
        pub const compiler_limits = Reified.compiler_limits;
        /// Canonical semantic identity of the Reified Program.
        pub const semantic_digest = Reified.semantic_digest;
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
        pub fn compile(comptime options: machine.Options) type {
            return machine.Machine(Definition, options);
        }

        /// Emit the canonical Boundary Executable Image for this Program.
        pub fn image(comptime options: machine.Options) type {
            const DirectMachine = compile(options);
            const Emitted = image_emit_v1.ProgramImage(
                Reified,
                Definition,
                DirectMachine,
            );
            return struct {
                pub const format_version = Emitted.format_version;
                pub const bytes = Emitted.bytes;
                pub const byte_length = Emitted.byte_length;
                pub const program_semantic_digest = Emitted.program_semantic_digest;
                pub const machine_contract_digest = Emitted.machine_contract_digest;
                pub const artifact_sha256 = Emitted.artifact_sha256;
                pub const maximum_kernel_scratch_bytes =
                    Emitted.maximum_kernel_scratch_bytes;
                pub const maximum_single_value_bytes =
                    Emitted.maximum_single_value_bytes;
                pub const machine_options = options;
                pub const Manifest = Emitted.Manifest;
            };
        }
    };
}
