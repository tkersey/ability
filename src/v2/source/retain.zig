// Copyright (c) 2026 Boundary contributors. MIT license.
//! A statically abrupt branch must still carry lexical custody to its failure.
//! Thread one unused owned value through its local control graph. Calls retain
//! it in their ordinary return frame; failure hands it to World unwinding.
const std = @import("std");
const p = @import("boundary_data_v2").program;
const Error = @import("../source.zig").Error;

pub fn forFailure(allocator: std.mem.Allocator, blocks: *std.ArrayList(p.Block), root: p.Id, schema: p.Id) Error!p.Id {
    var ids: std.AutoHashMapUnmanaged(p.Id, p.Id) = .empty;
    var pending: std.ArrayList(p.Id) = .empty;
    try ids.put(allocator, root, blocks.items.len);
    try pending.append(allocator, root);
    var index: usize = 0;
    while (index < pending.items.len) : (index += 1) {
        const term = blocks.items[@intCast(pending.items[index])].terminator;
        var next: std.ArrayList(p.Id) = .empty;
        switch (term) {
            .fail => {},
            .return_value => return error.InvalidSource,
            .jump, .yield_value => |edge| try next.append(allocator, edge.block),
            .branch => |branch| try next.appendSlice(allocator, &.{ branch.when_true.block, branch.when_false.block }),
            .switch_variant => |selected| for (selected.cases) |edge| try next.append(allocator, edge.block),
            .unpack_product => |unpack| try next.append(allocator, unpack.block),
            inline else => |operation| try next.append(allocator, operation.next.block),
        }
        for (next.items) |id| if (!ids.contains(id)) {
            try ids.put(allocator, id, blocks.items.len + pending.items.len);
            try pending.append(allocator, id);
        };
    }
    const first = blocks.items.len;
    for (pending.items) |id| {
        const original = blocks.items[@intCast(id)];
        const arity = original.parameters.len;
        const parameters = try allocator.alloc(p.Id, arity + 1);
        @memcpy(parameters[0..arity], original.parameters);
        parameters[arity] = schema;
        const instructions = try allocator.dupe(p.Instruction, original.instructions);
        for (instructions) |*operation| operation.operands = try slots(allocator, operation.operands, arity);
        const term = original.terminator;
        const rewritten: p.Terminator = switch (term) {
            .fail => |value| .{ .fail = slot(value, arity) },
            .return_value => unreachable,
            .jump, .yield_value => |target| if (term == .jump) .{ .jump = try rewriteEdge(allocator, target, arity, ids) } else .{ .yield_value = try rewriteEdge(allocator, target, arity, ids) },
            .branch => |branch| .{ .branch = .{ .condition = slot(branch.condition, arity), .when_true = try rewriteEdge(allocator, branch.when_true, arity, ids), .when_false = try rewriteEdge(allocator, branch.when_false, arity, ids) } },
            .switch_variant => |selected| blk: {
                const cases = try allocator.alloc(p.Edge, selected.cases.len);
                for (cases, selected.cases) |*target, from| target.* = try rewriteEdge(allocator, from, arity, ids);
                break :blk .{ .switch_variant = .{ .value = slot(selected.value, arity), .cases = cases } };
            },
            .unpack_product => |unpack| blk: {
                const arguments = try allocator.alloc(p.Id, unpack.arguments.len + 1);
                for (arguments[0..unpack.arguments.len], unpack.arguments) |*to, from| to.* = slot(from, arity);
                arguments[unpack.arguments.len] = arity;
                break :blk .{ .unpack_product = .{ .value = slot(unpack.value, arity), .block = ids.get(unpack.block).?, .arguments = arguments } };
            },
            inline else => |operation, kind| blk: {
                var changed = operation;
                changed.next = try rewriteEdge(allocator, operation.next, arity, ids);
                inline for (@typeInfo(@TypeOf(operation)).@"struct".fields) |field| {
                    if (comptime std.mem.eql(u8, field.name, "next") or std.mem.eql(u8, field.name, "function") or std.mem.eql(u8, field.name, "handler") or std.mem.eql(u8, field.name, "effect") or std.mem.eql(u8, field.name, "region") or std.mem.eql(u8, field.name, "loan_region")) continue;
                    @field(changed, field.name) = switch (field.type) {
                        p.Id => slot(@field(operation, field.name), arity),
                        ?p.Id => if (@field(operation, field.name)) |value| slot(value, arity) else null,
                        []const p.Id => try slots(allocator, @field(operation, field.name), arity),
                        else => @compileError("classify the new terminator field before retaining custody"),
                    };
                }
                break :blk @unionInit(p.Terminator, @tagName(kind), changed);
            },
        };
        try blocks.append(allocator, .{ .function = original.function, .parameters = parameters, .instructions = instructions, .terminator = rewritten });
    }
    return first;
}

fn slot(value: p.Id, arity: usize) p.Id {
    return value + @intFromBool(value >= arity);
}
fn slots(allocator: std.mem.Allocator, values: []const p.Id, arity: usize) Error![]const p.Id {
    const output = try allocator.alloc(p.Id, values.len);
    for (output, values) |*to, from| to.* = slot(from, arity);
    return output;
}
fn rewriteEdge(allocator: std.mem.Allocator, original: p.Edge, arity: usize, ids: std.AutoHashMapUnmanaged(p.Id, p.Id)) Error!p.Edge {
    const arguments = try allocator.alloc(p.Argument, original.arguments.len + 1);
    for (arguments[0..original.arguments.len], original.arguments) |*to, from| to.* = switch (from) {
        .slot => |value| .{ .slot = slot(value, arity) },
        .returned => .returned,
    };
    arguments[original.arguments.len] = .{ .slot = arity };
    return .{ .block = ids.get(original.block).?, .arguments = arguments };
}
