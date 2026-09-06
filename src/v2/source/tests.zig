const std = @import("std");
const source = @import("../source.zig");
const examples = @import("examples.zig");
const data = @import("boundary_data_v2");

test "actual handler installation sites share executable definitions" {
    var functions: ?usize = null;
    var clause_instructions: ?usize = null;
    for ([_]usize{ 1, 8, 64 }) |count| {
        var b = source.Builder.init(std.testing.allocator);
        defer b.deinit();
        var compiled = try source.lower(std.testing.allocator, try examples.installations(&b, count));
        defer compiled.deinit();
        const program = compiled.program;
        try std.testing.expectEqual(@as(usize, 1), program.handlers.len);
        const clause = program.handlers[0].clauses[0];
        try std.testing.expect(clause.direct);
        const code = program.blocks[@intCast(program.functions[@intCast(clause.function)].entry)];
        if (functions == null) {
            functions = program.functions.len;
            clause_instructions = code.instructions.len;
        }
        try std.testing.expectEqual(functions.?, program.functions.len);
        try std.testing.expectEqual(clause_instructions.?, code.instructions.len);
        var installed: usize = 0;
        for (program.blocks) |block| if (block.terminator == .handle) {
            installed += 1;
        };
        try std.testing.expectEqual(count, installed);
    }
}

test "an added pointer-free constant occupies one stored payload" {
    var empty_size: usize = 0;
    for ([_]usize{ 0, 65536 }) |length| {
        var b = source.Builder.init(std.testing.allocator);
        defer b.deinit();
        const bytes_type = try b.schema(.bytes);
        const unit = try b.scalar(void);
        const pair = try b.schema(.{ .product = &.{ bytes_type, bytes_type } });
        var writer: data.wire.Writer = .{};
        try writer.natural(length);
        const bytes = try b.allocator().alloc(u8, writer.position + length);
        @memset(bytes, 0x5a);
        writer = .{ .output = bytes };
        try writer.natural(length);
        const first = try b.literal(.{ .schema = bytes_type, .bytes = bytes });
        const second = try b.literal(.{ .schema = bytes_type, .bytes = bytes });
        const main = try b.declare(&.{}, pair, &.{}, &.{});
        try b.define(main, try b.pure(try b.primitive(pair, .product, &.{ first, second }, 0)));
        var compiled = try source.lower(std.testing.allocator, b.module(main, unit));
        defer compiled.deinit();
        try std.testing.expectEqual(@as(usize, 1), compiled.program.constants.len);
        try std.testing.expectEqual(bytes.len, compiled.program.constants[0].bytes.len);
        const output = try std.testing.allocator.alloc(u8, try data.image.encodedLength(compiled.program));
        defer std.testing.allocator.free(output);
        _ = try compiled.encode(std.testing.allocator, output);
        if (length == 0) empty_size = output.len else {
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, output, bytes[writer.position..]));
            try std.testing.expect(output.len - empty_size >= length);
            // Two nested byte lengths, the constants section length, and the
            // six later directory offsets can each grow by two ULEB bytes.
            try std.testing.expect(output.len - empty_size <= length + 2 * data.image.section_count);
        }
    }
}

test "public staged emit compiles independently and frees every failed allocation" {
    const Application = struct {
        pub fn emit(b: *source.Builder) !source.Module {
            const integer = try b.scalar(u64);
            const unit = try b.scalar(void);
            const main = try b.declare(&.{}, integer, &.{}, &.{});
            try b.define(main, try b.pure(try b.constant(u64, 42)));
            return b.module(main, unit);
        }
        fn attempt(allocator: std.mem.Allocator) !void {
            var compiled = try @import("../root.zig").program.lower(allocator, @This());
            defer compiled.deinit();
            try std.testing.expectEqual(@as(u8, 42), compiled.program.constants[0].bytes[0]);
        }
    };
    try Application.attempt(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Application.attempt, .{});
}

test "lexical lambda conversion derives captures and owns emitted data independently" {
    var builder = source.Builder.init(std.testing.allocator);
    const module = try examples.lexical(&builder);
    var compiled = source.lower(std.testing.allocator, module) catch |err| {
        builder.deinit();
        return err;
    };
    defer compiled.deinit();
    builder.deinit();
    try std.testing.expectEqual(@as(usize, 1), compiled.program.constructors.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.program.scopes.captures[0].fields.len);
    try std.testing.expectEqual(@as(usize, 2), compiled.program.functions[1].parameters.len);
    const output = try std.testing.allocator.alloc(u8, try data.image.encodedLength(compiled.program));
    defer std.testing.allocator.free(output);
    _ = try compiled.encode(std.testing.allocator, output);
    var decoded = try data.image.decode(std.testing.allocator, output);
    defer decoded.deinit();
}

test "deep bind and value syntax lower with bounded host stack and shared pure subexpressions" {
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const zero = try b.constant(u64, 0);
    const empty = try b.constant(void, {});
    const fault = try b.failureLiteral(empty);
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    var value = zero;
    for (0..12_000) |_| value = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ value, value }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }} } } });
    const first = try b.pure(empty);
    var body = try b.pure(value);
    for (0..12_000) |_| body = try b.bind(try b.variable(unit), first, body);
    try b.define(main, body);
    var compiled = try source.lower(std.testing.allocator, b.module(main, unit));
    defer compiled.deinit();
    var additions: usize = 0;
    for (compiled.program.blocks) |block| for (block.instructions) |instruction| if (instruction.opcode == .integer_add) {
        additions += 1;
    };
    try std.testing.expectEqual(@as(usize, 12_000), additions);
}

test "source bind lowers non-tail handlers and mutually recursive functions" {
    inline for (.{ examples.deep, examples.recursive, examples.generator, examples.stateLocal, examples.stateShared, examples.resourceScalar, examples.resourcePair, examples.answers, examples.scopedReader, examples.writerRaise, examples.schedulerFifo, examples.queensDfs, examples.queensBfs, examples.cellOrder, examples.nested, examples.shallow, examples.injection, examples.indexed, examples.abortCustody, examples.unwind, examples.reentrant, examples.cloned, examples.clauseAbort }) |example| {
        var builder = source.Builder.init(std.testing.allocator);
        defer builder.deinit();
        var compiled = try source.lower(std.testing.allocator, try example(&builder));
        defer compiled.deinit();
        try data.admission.program(std.testing.allocator, compiled.program);
        try data.canonical.require(std.testing.allocator, compiled.program);
    }
}

test "direct clauses reject authored failure and hidden effects at pure admission" {
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    var compiled = try source.lower(std.testing.allocator, try examples.answers(&b));
    defer compiled.deinit();
    const clause = compiled.program.handlers[0].clauses[0];
    try std.testing.expect(clause.direct);
    const function = compiled.program.functions[@intCast(clause.function)];
    var bad = compiled.program;
    const blocks = try std.testing.allocator.dupe(data.program.Block, bad.blocks);
    defer std.testing.allocator.free(blocks);
    blocks[@intCast(function.entry)].terminator = .{ .fail = 0 };
    bad.blocks = blocks;
    try std.testing.expectError(error.InvalidProgram, data.admission.program(std.testing.allocator, bad));
    bad = compiled.program;
    const functions = try std.testing.allocator.dupe(data.program.Function, bad.functions);
    defer std.testing.allocator.free(functions);
    functions[@intCast(clause.function)].effects = &.{clause.effect};
    bad.functions = functions;
    try std.testing.expectError(error.InvalidEffect, data.admission.program(std.testing.allocator, bad));
}

test "library specializations share declarations at one eight and sixty-four installations" {
    const choice = @import("../library/choice.zig");
    const state = @import("../library/state.zig");
    const generator = @import("../library/generator.zig");
    const reader = @import("../library/reader.zig");
    const writer = @import("../library/writer.zig");
    const raise = @import("../library/raise.zig");
    const search = @import("../library/search.zig");
    const scheduler = @import("../library/scheduler.zig");
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const region = b.region();
    const choices = try choice.family(&b, "sharing/choice");
    const states = try state.family(&b, "sharing/state", integer);
    const logs = try writer.family(&b, "sharing/log", integer);
    const raises = try raise.family(&b, "sharing/raise", integer);
    const joined = try scheduler.joinType(&b, integer, region);
    var declarations: ?usize = null;
    var handlers: ?usize = null;
    var first_handler: data.program.Id = 0;
    for (0..64) |index| {
        const interpreted = try choice.all(&b, choices, integer, &.{}, .{ .effects = &.{} });
        _ = try state.interpret(&b, states, integer, region, &.{}, .{ .effects = &.{} }, .value);
        const tasks = try generator.define(&b, "sharing/generator", unit, &.{}, &.{}, .{ .effects = &.{} });
        _ = try reader.define(&b, "sharing/reader", integer, integer, integer, .{ .continuation = &.{} }, .{ .effects = &.{} }, &.{});
        _ = try writer.interpret(&b, logs, integer, region, &.{}, .{ .effects = &.{} });
        _ = try raise.catching(&b, raises, integer, &.{}, .{ .effects = &.{} }, &.{});
        _ = try search.define(&b, "sharing/search", integer, &.{}, .{ .effects = &.{} }, &.{}, &.{}, .depth_first);
        _ = try scheduler.fifo(&b, tasks, .{ .effects = &.{} }, &.{});
        _ = try scheduler.awaiting(&b, tasks, joined, integer, &.{region});
        if (index == 0) {
            declarations = b.functions.items.len;
            handlers = b.handlers.items.len;
            first_handler = interpreted.handler;
        }
        if (index == 0 or index == 7 or index == 63) {
            try std.testing.expectEqual(declarations.?, b.functions.items.len);
            try std.testing.expectEqual(handlers.?, b.handlers.items.len);
            try std.testing.expectEqual(first_handler, interpreted.handler);
        }
    }
    const residual = try b.effect(.{ .identity = "sharing/residual", .payload = unit, .result = unit });
    const changed = try choice.all(&b, choices, integer, &.{}, .{ .effects = &.{residual} });
    try std.testing.expect(changed.handler != first_handler);
    try std.testing.expectEqual(declarations.? + 2, b.functions.items.len);
    try std.testing.expectEqual(handlers.? + 1, b.handlers.items.len);
}

test "failure custody does not silently discard an owned value on a normal branch" {
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const module = try examples.abortCustody(&b);
    const first = b.terms.items[@intCast(b.functions.items[@intCast(module.entry)].body.?)].bind;
    const aborted = b.terms.items[@intCast(first.next)].conditional.when_false;
    const failure = b.terms.items[@intCast(aborted)].bind.next;
    const value = b.terms.items[@intCast(failure)].fail;
    b.terms.items[@intCast(failure)] = .{ .value = value };
    try std.testing.expectError(error.InvalidOwnership, source.lower(std.testing.allocator, b.module(module.entry, module.failure)));
}

test "converting an owned capture consumes the original before any template activation" {
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const module = try examples.cloned(&b);
    const clause = b.handlers.items[0].clauses[0].function;
    const conversion = b.terms.items[@intCast(b.functions.items[@intCast(clause)].body.?)].bind;
    const saved = b.terms.items[@intCast(conversion.next)].bind;
    const resumed = b.terms.items[@intCast(saved.next)].bind.value;
    const original = try b.reference(b.parameter(clause, 3));
    b.terms.items[@intCast(resumed)].resume_value.resumption = original;
    try std.testing.expectError(error.InvalidOwnership, source.lower(std.testing.allocator, b.module(module.entry, module.failure)));
}

test "unused binding annotations and undeclared captures still reject" {
    var builder = source.Builder.init(std.testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    const unused = try builder.variable(integer);
    try builder.define(main, try builder.bind(unused, try builder.pure(try builder.constant(bool, true)), try builder.pure(try builder.constant(u64, 42))));
    var diagnostic: source.Diagnostic = .{};
    try std.testing.expectError(error.TypeMismatch, source.lowerObserved(std.testing.allocator, builder.module(main, unit), .{ .diagnostic = &diagnostic }));
    try std.testing.expectEqual(error.TypeMismatch, diagnostic.code.?);
    try std.testing.expectEqual(builder.functions.items[@intCast(main)].body.?, diagnostic.term.?);
}

test "source clients cannot introduce or eliminate a private resource representation" {
    inline for (.{ true, false }) |introduce| {
        var b = source.Builder.init(std.testing.allocator);
        defer b.deinit();
        _ = try examples.resourceScalar(&b);
        const integer = try b.scalar(u64);
        const unit = try b.scalar(void);
        var resource: data.program.Id = undefined;
        for (b.schemas.items, 0..) |schema, id| if (schema == .internal and schema.internal == .abstract_resource) {
            resource = id;
            break;
        };
        const main = try b.declare(&.{}, if (introduce) unit else integer, if (introduce) &.{} else &.{0}, &.{});
        const owned = try b.variable(resource);
        if (introduce) {
            const forged = try b.pure(try b.primitive(resource, .resource_pack, &.{try b.constant(u64, 41)}, 0));
            try b.define(main, try b.bind(owned, forged, try b.term(.{ .fail = try b.constant(void, {}) })));
        } else {
            const acquired = try b.term(.{ .call = .{ .function = b.resources.items[0].introducers[0], .arguments = &.{} } });
            const exposed = try b.pure(try b.primitive(integer, .resource_unpack, &.{try b.reference(owned)}, 0));
            try b.define(main, try b.bind(owned, acquired, exposed));
        }
        try std.testing.expectError(error.InvalidOwnership, source.lower(std.testing.allocator, b.module(main, unit)));
    }
}

test "a resource borrow cannot escape its protected body even when immediately read by the caller" {
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const original = try examples.resourceScalar(&b);
    const main_bind = b.terms.items[@intCast(b.functions.items[@intCast(original.entry)].body.?)].bind;
    const protected = main_bind.next;
    const body_value = b.terms.items[@intCast(protected)].protect.body;
    const body_function = b.values.items[@intCast(body_value)].expression.lambda;
    const parameter = b.parameter(body_function, 0);
    const borrowed = b.variables.items[@intCast(parameter)];
    var signature = b.schemas.items[@intCast(b.values.items[@intCast(body_value)].schema)].internal.computation;
    signature.result = borrowed;
    const schema = try b.schema(.{ .internal = .{ .computation = signature } });
    b.values.items[@intCast(body_value)].schema = schema;
    b.functions.items[@intCast(body_function)].result = borrowed;
    const returned = try b.pure(try b.reference(parameter));
    b.functions.items[@intCast(body_function)].body = returned;
    const escaped = try b.variable(borrowed);
    const read = try b.term(.{ .call = .{ .function = b.resources.items[0].eliminators[0], .arguments = &.{try b.reference(escaped)} } });
    const next = try b.bind(escaped, protected, read);
    const changed = try b.bind(main_bind.variable, main_bind.value, next);
    b.functions.items[@intCast(original.entry)].body = changed;
    try std.testing.expectError(error.InvalidOwnership, source.lower(std.testing.allocator, b.module(original.entry, original.failure)));
}

test "latent multi use rejects an exclusive caller capture but permits capture before acquisition" {
    inline for (.{ true, false }) |acquire_first| {
        var b = source.Builder.init(std.testing.allocator);
        defer b.deinit();
        const original = try examples.resourceScalar(&b);
        const unit = try b.scalar(void);
        const multiple = try b.effect(.{ .identity = "test/latent-multi", .payload = unit, .result = unit, .control_use = .multi });
        const callee = try b.declare(&.{}, unit, &.{multiple}, &.{});
        try b.define(callee, try b.term(.{ .perform = .{ .effect = multiple, .payload = try b.constant(void, {}) } }));
        const call = try b.term(.{ .call = .{ .function = callee, .arguments = &.{} } });
        const old_body = b.functions.items[@intCast(original.entry)].body.?;
        const old_bind = b.terms.items[@intCast(old_body)].bind;
        const ignored = try b.variable(unit);
        const changed = if (acquire_first) try b.bind(old_bind.variable, old_bind.value, try b.bind(ignored, call, old_bind.next)) else try b.bind(ignored, call, old_body);
        b.functions.items[@intCast(original.entry)].body = changed;
        b.functions.items[@intCast(original.entry)].effects = try b.allocator().dupe(data.program.Id, &.{ 0, 1, 2, multiple });
        if (acquire_first) {
            var diagnostic: source.Diagnostic = .{};
            try std.testing.expectError(error.InvalidOwnership, source.lowerObserved(std.testing.allocator, b.module(original.entry, original.failure), .{ .diagnostic = &diagnostic }));
            try std.testing.expectEqual(error.InvalidOwnership, diagnostic.code.?);
            try std.testing.expectEqual(original.entry, diagnostic.function.?);
            try std.testing.expectEqual(callee, diagnostic.target.callee.?);
            try std.testing.expect(diagnostic.target.block != null and diagnostic.target.slot != null);
        } else {
            var compiled = try source.lower(std.testing.allocator, b.module(original.entry, original.failure));
            compiled.deinit();
        }
    }
}

test "installing the same family cannot hide a captured older capability from a caller's effect row" {
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const resource = try b.resource(integer);
    const effect = try b.effect(.{ .identity = "test/older-instance", .payload = unit, .result = unit, .control_use = .multi, .external = false });
    const cap = try b.schema(.{ .internal = .{ .capability = effect } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = unit, .answer = integer, .capture_bound = &.{ unit, integer, cap }, .handled = &.{effect}, .mode = .deep, .use = .multi } } });
    const returns = try b.declare(&.{integer}, integer, &.{}, &.{});
    const clause = try b.declare(&.{ unit, token }, integer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    try b.define(clause, try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 1)), .argument = try b.constant(void, {}) } }));
    const handler = try b.handler(.{ .mode = .deep, .input = integer, .answer = integer, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} });
    const factory = try b.declare(&.{}, resource, &.{}, &.{});
    const release = try b.declare(&.{resource}, integer, &.{}, &.{});
    try b.resourceAuthority(resource, &.{factory}, &.{release});
    try b.define(factory, try b.pure(try b.primitive(resource, .resource_pack, &.{try b.constant(u64, 41)}, 0)));
    try b.define(release, try b.pure(try b.primitive(integer, .resource_unpack, &.{try b.reference(b.parameter(release, 0))}, 0)));
    const hidden = try b.declare(&.{cap}, integer, &.{}, &.{});
    const inner = try b.declare(&.{cap}, integer, &.{effect}, &.{});
    const escaped = try b.term(.{ .perform = .{ .effect = effect, .capability = try b.reference(b.parameter(hidden, 0)), .payload = try b.constant(void, {}) } });
    try b.define(inner, try b.bind(try b.variable(unit), escaped, try b.pure(try b.constant(u64, 0))));
    const inner_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{cap}, .result = integer, .effects = &.{effect}, .capture_bound = &.{cap} } } });
    try b.define(hidden, try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(inner, inner_type) } }));
    const outer = try b.declare(&.{cap}, integer, &.{effect}, &.{});
    const owned = try b.variable(resource);
    const used = try b.term(.{ .call = .{ .function = release, .arguments = &.{try b.reference(owned)} } });
    const call = try b.term(.{ .call = .{ .function = hidden, .arguments = &.{try b.reference(b.parameter(outer, 0))} } });
    try b.define(outer, try b.bind(owned, try b.term(.{ .call = .{ .function = factory, .arguments = &.{} } }), try b.bind(try b.variable(integer), call, used)));
    const outer_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{cap}, .result = integer, .effects = &.{effect} } } });
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    try b.define(main, try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(outer, outer_type) } }));
    try std.testing.expectError(error.InvalidEffect, source.lower(std.testing.allocator, b.module(main, unit)));
}

test "large sparse region names preserve alpha-equivalent canonical images" {
    const Example = struct {
        fn compile(parent: std.mem.Allocator, region_id: data.program.Id) !source.Compiled {
            var b = source.Builder.init(parent);
            defer b.deinit();
            b.region_count = region_id + 1;
            const unit = try b.scalar(void);
            const integer = try b.scalar(u64);
            const region_schema = try b.schema(.{ .internal = .{ .region = region_id } });
            const main = try b.declare(&.{}, integer, &.{}, &.{});
            const body = try b.declare(&.{region_schema}, integer, &.{}, &.{region_id});
            try b.define(body, try b.pure(try b.constant(u64, 42)));
            const signature = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{region_schema}, .result = integer, .regions = &.{region_id} } } });
            try b.define(main, try b.term(.{ .with_region = .{ .region = region_id, .body = try b.lambda(body, signature) } }));
            return source.lower(parent, b.module(main, unit));
        }
    };
    var small = try Example.compile(std.testing.allocator, 0);
    defer small.deinit();
    var large = try Example.compile(std.testing.allocator, std.math.maxInt(data.program.Id) - 1);
    defer large.deinit();
    try std.testing.expectEqual(@as(data.program.Id, 1), large.program.scopes.region_count);
    var small_bytes: [512]u8 = undefined;
    var large_bytes: [512]u8 = undefined;
    try std.testing.expectEqualSlices(u8, try small.encode(std.testing.allocator, &small_bytes), try large.encode(std.testing.allocator, &large_bytes));
}

test "capture diagnostics name the responsible source variable without changing compiled bytes" {
    const Trace = struct {
        stages: std.ArrayList(source.CompileStage) = .empty,
        fn enter(context: *anyopaque, stage: source.CompileStage) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.stages.append(std.testing.allocator, stage) catch @panic("test trace allocation");
        }
    };
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const module = try examples.lexical(&b);
    var original = try source.lower(std.testing.allocator, module);
    defer original.deinit();
    var trace: Trace = .{};
    defer trace.stages.deinit(std.testing.allocator);
    var diagnostic: source.Diagnostic = .{};
    var observed = try source.lowerObserved(std.testing.allocator, module, .{ .diagnostic = &diagnostic, .observer = .{ .context = &trace, .enter = Trace.enter } });
    defer observed.deinit();
    try std.testing.expectEqualSlices(source.CompileStage, &.{ .source_copy, .source_check, .lowering, .target_check, .direct_optimization, .canonicalization, .complete }, trace.stages.items);
    try std.testing.expect(diagnostic.code == null and diagnostic.phase == .complete);
    var a: [1024]u8 = undefined;
    var c: [1024]u8 = undefined;
    try std.testing.expectEqualSlices(u8, try original.encode(std.testing.allocator, &a), try observed.encode(std.testing.allocator, &c));
    for (b.schemas.items) |*schema| if (schema.* == .internal and schema.internal == .computation) {
        schema.internal.computation.capture_bound = &.{};
    };
    try std.testing.expectError(error.InvalidOwnership, source.lowerObserved(std.testing.allocator, b.module(module.entry, module.failure), .{ .diagnostic = &diagnostic }));
    try std.testing.expectEqual(source.CompileStage.target_check, diagnostic.phase);
    try std.testing.expectEqual(@as(data.program.Id, 1), diagnostic.function.?);
    try std.testing.expectEqual(b.parameter(module.entry, 0), diagnostic.variable.?);
    try std.testing.expect(diagnostic.target.capture != null and diagnostic.target.field != null);
}

test "unbound handler captures identify the return or operation clause" {
    inline for (.{ true, false }) |return_clause| {
        var b = source.Builder.init(std.testing.allocator);
        defer b.deinit();
        const module = try examples.deep(&b);
        const handler = b.handlers.items[0];
        const function = if (return_clause) handler.return_function else handler.clauses[0].function;
        const integer = try b.scalar(u64);
        const free = try b.variable(integer);
        // Keep the original function body well typed while introducing a free
        // variable in this specific handler function.
        const unused = try b.variable(integer);
        b.functions.items[@intCast(function)].body = try b.bind(unused, try b.pure(try b.reference(free)), b.functions.items[@intCast(function)].body.?);
        var diagnostic: source.Diagnostic = .{};
        try std.testing.expectError(error.UnboundVariable, source.lowerObserved(std.testing.allocator, b.module(module.entry, module.failure), .{ .diagnostic = &diagnostic }));
        try std.testing.expectEqual(function, diagnostic.function.?);
        try std.testing.expectEqual(free, diagnostic.variable.?);
        try std.testing.expectEqual(b.functions.items[@intCast(function)].body.?, diagnostic.term.?);
    }
}
