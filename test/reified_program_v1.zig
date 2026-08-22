const cir = @import("control_ir");
const compiler = @import("compiler");
const machine = @import("machine");
const program_v2 = @import("program_v2");
const std = @import("std");

const u32_type: cir.ValueType = .{ .scalar = .u32 };
const blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .return_value = 0 },
}};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "reified-program-proof",
        .value_types = &.{u32_type},
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Reified = compiler.ReifiedFor("reified-program-proof", Body);
const Direct = compiler.DirectDefinitionFor(Reified);
const CompatibilityDefinition = compiler.DefinitionFor(
    "reified-program-proof",
    Body,
);
const Program = program_v2.program("reified-program-proof", Body);
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
};
const DirectMachine = machine.Machine(Direct, options);
const ProgramMachine = Program.compile(options);

test "direct specialization consumes the exact Reified Program" {
    try std.testing.expect(Direct.reified_program == Reified);
    try std.testing.expect(CompatibilityDefinition.reified_program == Reified);
    try std.testing.expect(DirectMachine == ProgramMachine);
    try std.testing.expectEqualSlices(
        u8,
        &Reified.semantic_digest,
        &Program.semantic_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &DirectMachine.Manifest.machine_contract_digest,
        &ProgramMachine.Manifest.machine_contract_digest,
    );
    try std.testing.expectEqual(
        Reified.rnf_value.constructor_count,
        Program.rnf.constructor_count,
    );
}

test "Reified Program preserves direct canonical State bytes" {
    const direct = try DirectMachine.initialState(std.testing.allocator, 29);
    defer DirectMachine.deinitState(direct);
    const compiled = try ProgramMachine.initialState(std.testing.allocator, 29);
    defer ProgramMachine.deinitState(compiled);

    const direct_bytes = try DirectMachine.encodeState(
        std.testing.allocator,
        direct,
    );
    defer std.testing.allocator.free(direct_bytes);
    const compiled_bytes = try ProgramMachine.encodeState(
        std.testing.allocator,
        compiled,
    );
    defer std.testing.allocator.free(compiled_bytes);
    try std.testing.expectEqualSlices(u8, direct_bytes, compiled_bytes);
}
