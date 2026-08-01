const boundary = @import("boundary");
const std = @import("std");

const Lookup = boundary.effect.site(
    0,
    "proof.single-reducer.lookup.v1",
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
    pub const Failure = enum { rejected };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "single-reducer-proof",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Program = boundary.program("single-reducer-proof", Body);
const Machine = Program.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});
const Reducer = fn (Machine.State, *u64) Machine.Error!Machine.Outcome;

fn reducerDeclarationCount(comptime Owner: type) comptime_int {
    var result = 0;
    inline for (@typeInfo(Owner).@"struct".decls) |declaration| {
        if (@TypeOf(@field(Owner, declaration.name)) == Reducer) result += 1;
    }
    return result;
}

fn functionDeclarationCount(comptime Owner: type) comptime_int {
    var result = 0;
    inline for (@typeInfo(Owner).@"struct".decls) |declaration| {
        switch (@typeInfo(@TypeOf(@field(Owner, declaration.name)))) {
            .@"fn" => result += 1,
            else => {},
        }
    }
    return result;
}

comptime {
    if (!@hasDecl(Machine, "step")) {
        @compileError("compiled Boundary Machine has no public step reducer");
    }
    if (@TypeOf(Machine.step) != Reducer) {
        @compileError("compiled Boundary Machine step does not own the Machine ABI reducer signature");
    }
    if (reducerDeclarationCount(Machine) != 1) {
        @compileError("compiled Boundary Machine exposes more than one ABI-shaped reducer");
    }
    if (!@hasDecl(Program, "compile") or functionDeclarationCount(Program) != 1) {
        @compileError("Boundary Program exposes a competing compilation route");
    }
    if (@hasDecl(boundary, "Runtime") or
        @hasDecl(boundary, "staticMachine") or
        @hasDecl(boundary, "StaticMachineOptions"))
    {
        @compileError("Boundary public root exposes a competing runtime");
    }
}

pub fn main(init: std.process.Init) !void {
    const state = try Machine.initialState(std.heap.page_allocator, 21);
    defer Machine.deinitState(state);
    var caller_fuel: u64 = 8;
    switch (try Machine.step(state, &caller_fuel)) {
        .request => {},
        else => return error.ExpectedEffectRequest,
    }

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "single_boundary_reducer={}\n" ++
            "runtime_semantic_module_count={d}\n" ++
            "reducer_public_entry=Program.compile(...).step\n" ++
            "program_compile_surface_count={d}\n",
        .{
            reducerDeclarationCount(Machine) == 1,
            reducerDeclarationCount(Machine),
            functionDeclarationCount(Program),
        },
    );
    try stdout.flush();
}
