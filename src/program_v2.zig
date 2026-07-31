const compiler = @import("compiler");
const machine = @import("machine");

/// Declare one typed Boundary source program with one Machine meaning.
pub fn program(comptime label: []const u8, comptime Body: type) type {
    const Definition = compiler.DefinitionFor(label, Body);
    return struct {
        /// Diagnostic source label excluded from Machine semantic identity.
        pub const program_label = label;
        /// Private typed source/control program.
        pub const control_ir = Definition.control;
        /// Canonical compile-time Resumption Normal Form.
        pub const rnf = Definition.rnf_value;
        /// Source-declared bounded compiler work, excluded from Machine identity.
        pub const compiler_limits = Definition.compiler_limits;
        /// Static size proxy for the generated direct reducer.
        pub const generated_reducer_operation_count =
            Definition.generated_reducer_operation_count;
        /// Maximum stack scratch used by any one generated direct segment.
        pub const maximum_segment_scratch_bytes =
            Definition.maximum_segment_scratch_bytes;
        /// Compile-time-only whole-program value catalog size for proof.
        pub const reachable_value_catalog_bytes =
            Definition.reachable_value_catalog_bytes;

        /// Compile this program to its sole direct Boundary Machine.
        pub fn compile(comptime options: machine.Options) type {
            return machine.Machine(Definition, options);
        }
    };
}
