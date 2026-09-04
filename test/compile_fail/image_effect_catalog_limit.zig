const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const effect_count = 129;
const block_count = effect_count + 1;
const value_types = [_]cir.ValueType{.{ .scalar = .u32 }} ** block_count;
const parameters = blk: {
    var result: [block_count][1]cir.ValueId = undefined;
    for (&result, 0..) |*parameter, index| parameter.* = .{@intCast(index)};
    break :blk result;
};
const request_values = blk: {
    var result: [effect_count][1]cir.ValueId = undefined;
    for (&result, 0..) |*request, index| request.* = .{@intCast(index)};
    break :blk result;
};
const resume_arguments = [_]cir.EdgeArgument{.@"resume"};

fn Site(comptime index: usize) type {
    return struct {
        pub const Payload = u32;
        pub const Resume = u32;
        pub const site_id: u32 = index;
        pub const semantic_identity = std.fmt.comptimePrint(
            "fixture.effect-{d}.v1",
            .{index},
        );
    };
}

const effect_site_types = blk: {
    var result: [effect_count]type = undefined;
    for (&result, 0..) |*site, index| site.* = Site(index);
    break :blk result;
};
const blocks = blk: {
    var result: [block_count]cir.Block = undefined;
    for (&result, 0..) |*block, index| block.* = if (index == effect_count) .{
        .id = @intCast(index),
        .parameters = &parameters[index],
        .terminator = .{ .return_value = @intCast(index) },
    } else .{
        .id = @intCast(index),
        .parameters = &parameters[index],
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = @intCast(index),
            .request_values = &request_values[index],
            .continuation = .{
                .target = @intCast(index + 1),
                .arguments = &resume_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    };
    break :blk result;
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const constants = .{};
    pub const effect_sites = effect_site_types;
    pub const schema_types = .{};
    pub const compiler_limits: cir.CompilerLimits = .{
        .maximum_values = block_count,
        .maximum_blocks = block_count,
        .maximum_constructors = 256,
        .maximum_environment_fields = 4,
        .maximum_invariant_terms = 4,
        .maximum_generated_operations = 8192,
    };
    pub const control_ir: cir.Program = .{
        .label = "image-effect-catalog-limit",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};

comptime {
    _ = program_v2.program(
        "image-effect-catalog-limit",
        Body,
    ).program_transition_digest;
}
