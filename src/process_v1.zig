pub const capsule = @import("process_capsule_v1");
pub const effect = @import("process_effect_v1");
const semantics = @import("process_advance_v1");
const state_codec = @import("process_state_v1");

pub const advance = semantics.advance;
pub const encodeKernelInput = semantics.encodeKernelInput;
pub const validateState = semantics.validateState;
pub const Buffers = semantics.Buffers;
pub const CapacityRequirement = semantics.CapacityRequirement;
pub const Instance = semantics.Instance;
pub const Outcome = semantics.Outcome;
pub const ProcessState = state_codec.StateView;
pub const EffectRequest = effect.RequestView;
pub const EffectResult = effect.ResultView;
pub const state = struct {
    pub const magic = state_codec.magic;
    pub const format_version = state_codec.format_version;
    pub const Frame = state_codec.Frame;
    pub const StateView = state_codec.StateView;
    pub const encode = semantics.encodeState;
    pub const validateEncoding = state_codec.validate;
    pub const artifactDigest = state_codec.artifactDigest;
};
pub const fixed_kernel_abi = struct {
    pub const version = semantics.kernel_semantic_version;
    pub const input_magic = semantics.kernel_input_magic;
    pub const input_format_version = semantics.kernel_input_format_version;
    pub const input_header_length = semantics.kernel_input_header_length;
    pub const outcome_magic = semantics.outcome_magic;
    pub const outcome_format_version = semantics.outcome_format_version;
    pub const outcome_header_length = semantics.outcome_header_length;
    pub const exports = struct {
        pub const abi_version = "boundary_process_kernel_abi_version";
        pub const reserve = "boundary_process_kernel_reserve";
        pub const input_ptr = "boundary_process_kernel_input_ptr";
        pub const input_capacity = "boundary_process_kernel_input_capacity";
        pub const input_payload_ptr = "boundary_process_kernel_input_payload_ptr";
        pub const prepare_input = "boundary_process_kernel_prepare_input";
        pub const execute = "boundary_process_kernel_execute";
        pub const output_ptr = "boundary_process_kernel_output_ptr";
        pub const output_len = "boundary_process_kernel_output_len";
        pub const error_ptr = "boundary_process_kernel_error_ptr";
        pub const error_len = "boundary_process_kernel_error_len";
    };
};

test {
    _ = semantics;
    _ = capsule;
    _ = state_codec;
    _ = effect;
    _ = fixed_kernel_abi;
}
