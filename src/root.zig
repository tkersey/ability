const agent_profile = @import("agent_profile");
const control_ir = @import("control_ir");
const driver = @import("driver");
const effect_v2 = @import("effect_v2");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");

/// Published Boundary package identity.
pub const package_version = "1.6.1";

/// Public typed residual-effect authoring namespace.
pub const effect = effect_v2;
/// Canonical Boundary Program Image v1 wire format and validation.
pub const image = struct {
    pub const magic = image_v1.magic;
    pub const image_format_version = image_v1.image_format_version;
    pub const evaluator_semantics_version = image_v1.evaluator_semantics_version;
    pub const header_length = image_v1.header_length;
    pub const section_count = image_v1.section_count;
    pub const Error = image_v1.Error;
    pub const SectionKind = image_v1.SectionKind;
    pub const Section = image_v1.Section;
    pub const Header = image_v1.Header;
    pub const ValidatedEnvelope = image_v1.ValidatedEnvelope;
    pub const ValidationWorkspace = image_v1.ValidationWorkspace;
    /// Borrowed validated view. Reusing its ValidationWorkspace invalidates it.
    pub const ValidatedImageView = image_v1.ValidatedImage;
    pub const validateEnvelope = image_v1.validateEnvelope;
    /// Validate one image into a view borrowed from `workspace`.
    pub const validateImageView = image_v1.validateImage;
    /// Re-encode a view before reusing the workspace that backs it.
    pub const reencodeValidatedView = image_v1.reencodeValidated;
};
/// Bounded Machine ABI v2 compatibility surfaces.
pub const machine_v2 = struct {
    pub const Options = machine.Options;
    pub const kernel = struct {
        pub const Error = kernel_v1.Error;
        pub const MachineFailure = kernel_v1.MachineFailure;
        pub const state_magic = kernel_v1.state_magic;
        pub const state_header_length = kernel_v1.state_header_length;
        pub const frame_header_length = kernel_v1.frame_header_length;
        pub const Outcome = kernel_v1.Outcome;
        pub const RequestIdentity = kernel_v1.RequestIdentity;
        pub const RequestView = kernel_v1.RequestView;
        pub const BoundProgram = kernel_v1.BoundProgram;
        pub const bindMachineV2 = kernel_v1.bindMachineV2;
        pub const initial = kernel_v1.initial;
        pub const validateState = kernel_v1.validateState;
        pub const current = kernel_v1.current;
        pub const @"resume" = kernel_v1.@"resume";
        pub const step = kernel_v1.step;
    };
};
/// Public canonical portable-value and codec namespace.
pub const schema = portable_value;
/// Advanced typed source/control authoring namespace.
pub const ir = control_ir;
/// Declare one typed Boundary source program with one Machine meaning.
pub const program = program_v2.program;
/// Local driver over the same compiled Machine used by World.
pub const Driver = driver.Driver;
/// Optional agent profile over the sole Program compiler.
pub const Agent = agent_profile;
/// Canonical bounded byte sequence.
pub const Bytes = portable_value.Bytes;
/// Canonical bounded UTF-8 text.
pub const Text = portable_value.Text;
/// Canonical bounded vector.
pub const Vector = portable_value.Vector;
/// Identity-bearing Machine compiler options.
pub const MachineOptions = machine.Options;

test "Boundary 1.0 root exposes one compiler and no legacy runtime" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "program"));
    try std.testing.expect(@hasDecl(@This(), "Driver"));
    try std.testing.expect(@hasDecl(@This(), "Agent"));
    try std.testing.expect(@hasDecl(@This(), "effect"));
    try std.testing.expect(@hasDecl(@This(), "image"));
    try std.testing.expect(@hasDecl(image, "validateImageView"));
    try std.testing.expect(@hasDecl(image, "reencodeValidatedView"));
    try std.testing.expect(!@hasDecl(image, "ValidatedImage"));
    try std.testing.expect(!@hasDecl(image, "validateImage"));
    try std.testing.expect(!@hasDecl(image, "reencodeValidated"));
    inline for (.{
        "SemanticHasher",
        "semanticHashSchema",
        "hashFailures",
        "hashEffectContracts",
        "hashInstruction",
        "hashTerminator",
        "hashEdge",
        "hashEnvironmentField",
        "hashInvariant",
    }) |internal_decl| {
        try std.testing.expect(!@hasDecl(image, internal_decl));
    }
    try std.testing.expect(!@hasDecl(@This(), "evaluator"));
    try std.testing.expect(!@hasDecl(@This(), "reducer"));
    try std.testing.expect(!@hasDecl(@This(), "clause"));
    try std.testing.expect(!@hasDecl(@This(), "program_evaluator"));
    try std.testing.expect(!@hasDecl(@This(), "internal_evaluator"));
    try std.testing.expect(@hasDecl(@This(), "machine_v2"));
    try std.testing.expect(!@hasDecl(machine_v2, "profile"));
    try std.testing.expect(!@hasDecl(machine_v2.kernel, "preflightStep"));
    try std.testing.expect(!@hasDecl(machine_v2.kernel, "StepAdmission"));
    try std.testing.expect(!@hasDecl(
        machine_v2.kernel,
        "maximumResumeStateSize",
    ));
    try std.testing.expect(!@hasDecl(@This(), "kernel"));
    try std.testing.expect(@hasDecl(@This(), "schema"));
    try std.testing.expect(@hasDecl(@This(), "ir"));
    try std.testing.expect(!@hasDecl(@This(), "Runtime"));
    try std.testing.expect(!@hasDecl(@This(), "staticMachine"));
    try std.testing.expect(!@hasDecl(@This(), "StaticMachineOptions"));
    try std.testing.expect(!@hasDecl(@This(), "Protocol"));
}
