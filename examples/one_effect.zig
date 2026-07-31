const boundary = @import("boundary");
const std = @import("std");

const Lookup = boundary.effect.site(
    0,
    "example.lookup.v1",
    u32,
    u32,
);

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        rejected,
    };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "one-effect",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Program = boundary.program("one-effect", Body);
const Machine = Program.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

pub fn main() !void {
    var driver = try boundary.Driver(Machine).init(
        std.heap.page_allocator,
        21,
    );
    defer driver.deinit();

    var handlers = struct {
        pub fn handle(
            _: *@This(),
            comptime tag: anytype,
            payload: anytype,
        ) !switch (tag) {
            .s0 => u32,
        } {
            return payload * 2;
        }
    }{};
    var caller_fuel: u64 = 8;
    const result = switch (try driver.run(&handlers, &caller_fuel)) {
        .done => |value| value,
        .yielded => return error.UnexpectedYield,
        .failed => return error.UnexpectedMachineFailure,
        .handler_error => |failure| return failure.err,
    };
    defer result.deinit();

    if (result.value().* != 42) return error.UnexpectedResult;
}
