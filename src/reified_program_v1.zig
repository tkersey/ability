/// One canonical post-normalization compiler result shared by specialization
/// and image emission.
pub fn Program(
    comptime label: []const u8,
    comptime SourceBody: type,
    comptime limits_value: anytype,
    comptime control_value: anytype,
    comptime reachability_value: anytype,
    comptime semantic_canonicalization_value: anytype,
    comptime residual_effects_value: anytype,
    comptime invariant_constants_value: anytype,
    comptime normal_form_value: anytype,
    comptime generated_operation_count_value: usize,
    comptime semantic_digest_value: [32]u8,
) type {
    return struct {
        pub const program_label = label;
        pub const Body = SourceBody;
        pub const compiler_limits = limits_value;
        pub const control = control_value;
        pub const reachability = reachability_value;
        pub const semantic_canonicalization =
            semantic_canonicalization_value;
        pub const residual_effects = residual_effects_value;
        pub const invariant_constants = invariant_constants_value;
        pub const rnf_value = normal_form_value;
        pub const generated_reducer_operation_count =
            generated_operation_count_value;
        pub const semantic_digest = semantic_digest_value;
        pub const contract_bytes = semantic_digest[0..];
    };
}

/// Require the complete internal Reified Program contract at specialization
/// boundaries.
pub fn require(comptime Reified: type) void {
    inline for (.{
        "program_label",
        "Body",
        "compiler_limits",
        "control",
        "reachability",
        "semantic_canonicalization",
        "residual_effects",
        "invariant_constants",
        "rnf_value",
        "generated_reducer_operation_count",
        "semantic_digest",
        "contract_bytes",
    }) |name| {
        if (!@hasDecl(Reified, name)) {
            @compileError("Boundary Reified Program is missing " ++ name);
        }
    }
}
