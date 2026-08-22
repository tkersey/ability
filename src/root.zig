const agent_profile = @import("agent_profile");
const control_ir = @import("control_ir");
const driver = @import("driver");
const effect_v2 = @import("effect_v2");
const image_v1 = @import("image_v1");
const machine = @import("machine");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");

/// Public typed residual-effect authoring namespace.
pub const effect = effect_v2;
/// Canonical Boundary Executable Image v1 wire format and validation.
pub const image = image_v1;
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
    try std.testing.expect(@hasDecl(@This(), "schema"));
    try std.testing.expect(@hasDecl(@This(), "ir"));
    try std.testing.expect(!@hasDecl(@This(), "Runtime"));
    try std.testing.expect(!@hasDecl(@This(), "staticMachine"));
    try std.testing.expect(!@hasDecl(@This(), "StaticMachineOptions"));
    try std.testing.expect(!@hasDecl(@This(), "Protocol"));
}
