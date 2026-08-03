const program_v2 = @import("program_v2");
const std = @import("std");

/// Compile one agent profile through the sole Boundary Program compiler.
pub fn program(comptime label: []const u8, comptime Body: type) type {
    return program_v2.program(label, Body);
}

/// Agent spelling for one ordinary Boundary source program.
pub fn Profile(comptime label: []const u8, comptime Body: type) type {
    return program(label, Body);
}

test "Agent profile owns no second reducer" {
    try std.testing.expect(!@hasDecl(@This(), "Runtime"));
    try std.testing.expect(!@hasDecl(@This(), "Session"));
    try std.testing.expect(!@hasDecl(@This(), "Interpreter"));
}
