const cir = @import("control_ir");
const program_v2 = @import("program_v2");

const count = 1025;
const value_types = [_]cir.ValueType{.{ .scalar = .u32 }} ** count;
const constant_values = blk: {
    @setEvalBranchQuota(10_000);
    var result: [count]u32 = undefined;
    for (&result, 0..) |*value, index| value.* = @intCast(index);
    break :blk result;
};
const instructions = blk: {
    @setEvalBranchQuota(10_000);
    var result: [count]cir.Instruction = undefined;
    for (&result, 0..) |*instruction, index| instruction.* = .{
        .kind = .constant,
        .result = @intCast(index),
        .operation = .{ .constant = @intCast(index) },
    };
    break :blk result;
};
const blocks = [_]cir.Block{.{
    .id = 0,
    .instructions = &instructions,
    .terminator = .{ .return_value = count - 1 },
}};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = constant_values;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const compiler_limits: cir.CompilerLimits = .{
        .maximum_values = count,
        .maximum_blocks = 1,
        .maximum_constructors = 4,
        .maximum_environment_fields = 4,
        .maximum_invariant_terms = 4,
        .maximum_generated_operations = 2048,
    };
    pub const control_ir: cir.Program = .{
        .label = "image-constant-catalog-limit",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

comptime {
    _ = program_v2.program("image-constant-catalog-limit", Body).image().bytes;
}
