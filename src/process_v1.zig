pub const advance = @import("process_advance_v1");
pub const capsule = @import("process_capsule_v1");
pub const effect = @import("process_effect_v1");
pub const state = @import("process_state_v1");

pub const ProcessState = state.StateView;
pub const EffectRequest = effect.RequestView;
pub const EffectResult = effect.ResultView;
pub const fixed_kernel_abi = struct {
    pub const version = advance.kernel_semantic_version;
    pub const input_magic = advance.kernel_input_magic;
    pub const input_format_version = advance.kernel_input_format_version;
    pub const input_header_length = advance.kernel_input_header_length;
    pub const outcome_magic = advance.outcome_magic;
    pub const outcome_format_version = advance.outcome_format_version;
    pub const outcome_header_length = advance.outcome_header_length;
    pub const exports = struct {
        pub const abi_version = "boundary_process_kernel_abi_version";
        pub const reserve = "boundary_process_kernel_reserve";
        pub const input_ptr = "boundary_process_kernel_input_ptr";
        pub const execute = "boundary_process_kernel_execute";
        pub const output_ptr = "boundary_process_kernel_output_ptr";
        pub const output_len = "boundary_process_kernel_output_len";
        pub const error_ptr = "boundary_process_kernel_error_ptr";
        pub const error_len = "boundary_process_kernel_error_len";
    };
};

test {
    _ = advance;
    _ = capsule;
    _ = state;
    _ = effect;
    _ = fixed_kernel_abi;
}
