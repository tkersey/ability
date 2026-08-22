const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const portable_value = @import("portable_value");
const std = @import("std");

const maximum_nodes = 1024;
const maximum_bytes = 1 << 20;
const maximum_image_bytes = 16 << 20;

pub const EnvelopeOptions = struct {
    program_semantic_digest: [32]u8,
    machine_contract_digest: [32]u8,
    maximum_frames: u32,
    maximum_state_bytes: u32,
    maximum_machine_fuel: u64,
    maximum_kernel_scratch_bytes: u64,
    maximum_single_value_bytes: u32,
};

/// Compose ten canonical section payloads into the exact BEI1 container.
pub fn Envelope(
    comptime options: EnvelopeOptions,
    comptime sections: [image_v1.section_count][]const u8,
) type {
    const total_length = comptime blk: {
        var total: usize = image_v1.header_length;
        for (sections) |section| total += section.len;
        if (total > maximum_image_bytes) {
            @compileError("BEI1 image exceeds the default 16 MiB profile");
        }
        break :blk total;
    };
    const encoded = comptime blk: {
        var bytes: [total_length]u8 = [_]u8{0} ** total_length;
        @memcpy(bytes[0..image_v1.magic.len], &image_v1.magic);
        writeAt(u16, &bytes, 8, image_v1.image_format_version);
        writeAt(u16, &bytes, 10, image_v1.machine_abi_version);
        writeAt(u16, &bytes, 12, image_v1.state_format_version);
        writeAt(u16, &bytes, 14, image_v1.kernel_semantics_version);
        writeAt(u32, &bytes, 20, image_v1.header_length);
        writeAt(u64, &bytes, 24, total_length);
        writeAt(u32, &bytes, 32, image_v1.section_count);
        @memcpy(bytes[40..72], &options.program_semantic_digest);
        @memcpy(bytes[72..104], &options.machine_contract_digest);
        writeAt(u32, &bytes, 104, options.maximum_frames);
        writeAt(u32, &bytes, 108, options.maximum_state_bytes);
        writeAt(u64, &bytes, 112, options.maximum_machine_fuel);
        writeAt(u64, &bytes, 120, options.maximum_kernel_scratch_bytes);
        writeAt(u32, &bytes, 128, options.maximum_single_value_bytes);
        var payload_offset: usize = image_v1.header_length;
        for (sections, 0..) |section, index| {
            const descriptor = image_v1.fixed_prefix_length +
                index * image_v1.section_descriptor_length;
            writeAt(u16, &bytes, descriptor, index + 1);
            writeAt(u16, &bytes, descriptor + 2, 1);
            writeAt(u64, &bytes, descriptor + 8, payload_offset);
            writeAt(u64, &bytes, descriptor + 16, section.len);
            @memcpy(bytes[payload_offset..][0..section.len], section);
            payload_offset += section.len;
        }
        break :blk bytes;
    };
    const sha256 = comptime blk: {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&encoded, &digest, .{});
        break :blk digest;
    };
    return struct {
        pub const bytes = encoded;
        pub const byte_length: u64 = total_length;
        pub const artifact_sha256 = sha256;
    };
}

fn writeAt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    value: anytype,
) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], @intCast(value), .little);
}

const Builder = struct {
    bytes: [maximum_bytes]u8 = [_]u8{0} ** maximum_bytes,
    offsets: [maximum_nodes]u32 = undefined,
    lengths: [maximum_nodes]u32 = undefined,
    node_count: usize = 0,
    length: usize = 4,

    fn intern(self: *Builder, comptime T: type) u32 {
        portable_value.assertPortable(T);
        if (comptime portable_value.isVectorType(T)) {
            const child = self.intern(T.ElementType);
            return self.appendRecord(.vector, &.{
                castU32(T.maximum_length),
                child,
            });
        }
        if (comptime portable_value.isBytesType(T)) {
            return self.appendRecord(.bytes, &.{castU32(T.maximum_length)});
        }
        if (comptime portable_value.isTextType(T)) {
            return self.appendRecord(.text, &.{castU32(T.maximum_length)});
        }
        return switch (@typeInfo(T)) {
            .void => self.appendRecord(.unit, &.{}),
            .bool => self.appendRecord(.bool, &.{}),
            .int => self.appendRecord(integerKind(T), &.{}),
            .array => |info| blk: {
                const child = self.intern(info.child);
                break :blk self.appendRecord(.array, &.{
                    castU32(info.len),
                    child,
                });
            },
            .optional => |info| blk: {
                const child = self.intern(info.child);
                break :blk self.appendRecord(.optional, &.{child});
            },
            .@"enum" => |info| blk: {
                var words: [1 + info.fields.len]u32 = undefined;
                words[0] = castU32(info.fields.len);
                inline for (info.fields, 0..) |field, index| {
                    words[index + 1] = std.math.cast(u32, field.value) orelse
                        unreachable;
                }
                break :blk self.appendRecord(.@"enum", &words);
            },
            .@"struct" => |info| blk: {
                var words: [1 + info.fields.len]u32 = undefined;
                words[0] = castU32(info.fields.len);
                inline for (info.fields, 0..) |field, index| {
                    words[index + 1] = self.intern(field.type);
                }
                break :blk self.appendRecord(.product, &words);
            },
            .@"union" => |info| blk: {
                const Tag = info.tag_type.?;
                var words: [2 + info.fields.len * 2]u32 = undefined;
                words[0] = self.intern(Tag);
                words[1] = castU32(info.fields.len);
                inline for (info.fields, 0..) |field, index| {
                    words[2 + index * 2] = @intFromEnum(
                        @field(Tag, field.name),
                    );
                    words[3 + index * 2] = self.intern(field.type);
                }
                break :blk self.appendRecord(.sum, &words);
            },
            else => unreachable,
        };
    }

    fn appendRecord(
        self: *Builder,
        kind: dynamic_value_v1.Kind,
        words: []const u32,
    ) u32 {
        const start = self.length;
        const record_length = 8 + words.len * 4;
        self.requireBytes(record_length);
        self.writeInt(u32, @intCast(record_length));
        self.bytes[self.length] = @intFromEnum(kind);
        self.length += 1;
        self.bytes[self.length] = 0;
        self.length += 1;
        self.writeInt(u16, 0);
        for (words) |word| self.writeInt(u32, word);

        for (0..self.node_count) |existing| {
            if (self.length - start != self.lengths[existing]) continue;
            const offset: usize = self.offsets[existing];
            if (std.mem.eql(
                u8,
                self.bytes[offset .. offset + self.lengths[existing]],
                self.bytes[start..self.length],
            )) {
                self.length = start;
                return @intCast(existing);
            }
        }
        if (self.node_count == maximum_nodes) {
            @compileError("BEI1 schema node count exceeds implementation limit");
        }
        self.offsets[self.node_count] = @intCast(start);
        self.lengths[self.node_count] = @intCast(record_length);
        defer self.node_count += 1;
        return @intCast(self.node_count);
    }

    fn finish(self: *Builder) void {
        std.mem.writeInt(
            u32,
            self.bytes[0..4],
            @intCast(self.node_count),
            .little,
        );
    }

    fn writeInt(self: *Builder, comptime T: type, value: T) void {
        self.requireBytes(@sizeOf(T));
        std.mem.writeInt(
            T,
            self.bytes[self.length..][0..@sizeOf(T)],
            value,
            .little,
        );
        self.length += @sizeOf(T);
    }

    fn requireBytes(self: Builder, additional: usize) void {
        if (additional > maximum_bytes - self.length) {
            @compileError("BEI1 schema section exceeds implementation limit");
        }
    }
};

/// Produce the canonical structurally interned schema section for one ordered
/// root tuple. Root ids preserve tuple order; schema nodes use DFS postorder.
pub fn SchemaSet(comptime RootTypes: anytype) type {
    const built = comptime blk: {
        var builder: Builder = .{};
        var roots: [RootTypes.len]u32 = undefined;
        for (RootTypes, 0..) |Root, index| {
            roots[index] = builder.intern(Root);
        }
        builder.finish();
        break :blk .{ .builder = builder, .roots = roots };
    };
    const exact_bytes = built.builder.bytes[0..built.builder.length].*;
    return struct {
        pub const bytes = exact_bytes;
        pub const root_ids = built.roots;
        pub const node_count: u32 = @intCast(built.builder.node_count);
    };
}

/// Emit all schemas in the normative BEI1 root traversal order for one
/// Reified Program and its shared direct definition contract.
pub fn ProgramSchemaSet(comptime Reified: type, comptime Definition: type) type {
    const effect_count = Definition.EffectRow.operation_site_count;
    const value_count = Reified.semantic_canonicalization.value_count;
    const function_count = Reified.semantic_canonicalization.function_count;
    const root_count = 3 + effect_count * 2 + value_count + function_count;
    const roots = comptime blk: {
        var result: [root_count]type = undefined;
        var index: usize = 0;
        result[index] = Reified.Body.InitialArgs;
        index += 1;
        result[index] = Reified.Body.Result;
        index += 1;
        result[index] = Reified.Body.Failure;
        index += 1;
        for (0..effect_count) |ordinal| {
            const Site = Definition.EffectRow.site(ordinal);
            result[index] = Site.Payload;
            index += 1;
            result[index] = Site.Resume;
            index += 1;
        }
        for (0..value_count) |dense_value| {
            const source_value = Reified.semantic_canonicalization
                .value_dense_to_source[dense_value];
            result[index] = Reified.portableType(
                Reified.control.value_types[source_value],
            );
            index += 1;
        }
        for (0..function_count) |dense_function| {
            const source_function = Reified.semantic_canonicalization
                .function_dense_to_source[dense_function];
            const result_type = if (Reified.control.functions.len == 0)
                Reified.control.result_type
            else
                Reified.control.functions[source_function].result_type;
            result[index] = Reified.portableType(result_type);
            index += 1;
        }
        break :blk result;
    };
    const Set = SchemaSet(roots);
    return struct {
        pub const bytes = Set.bytes;
        pub const root_ids = Set.root_ids;
        pub const node_count = Set.node_count;
        pub const initial_args_root_index: usize = 0;
        pub const result_root_index: usize = 1;
        pub const failure_root_index: usize = 2;
        pub const effect_root_start: usize = 3;
        pub const value_root_start: usize = effect_root_start + effect_count * 2;
        pub const function_root_start: usize = value_root_start + value_count;
    };
}

/// Emit the exact BEI1 roots section for one Reified Program.
pub fn ProgramRoots(comptime Reified: type, comptime Schemas: type) type {
    const entry = Reified.control.blocks[Reified.control.entry];
    const encoded = comptime blk: {
        var bytes: [28]u8 = [_]u8{0} ** 28;
        writeAt(
            u32,
            &bytes,
            0,
            Schemas.root_ids[Schemas.initial_args_root_index],
        );
        writeAt(
            u32,
            &bytes,
            4,
            Schemas.root_ids[Schemas.result_root_index],
        );
        writeAt(
            u32,
            &bytes,
            8,
            Schemas.root_ids[Schemas.failure_root_index],
        );
        writeAt(
            u16,
            &bytes,
            12,
            Reified.semantic_canonicalization.blockId(Reified.control.entry),
        );
        writeAt(u16, &bytes, 14, entry.parameters.len);
        writeAt(u32, &bytes, 16, Reified.initial_constructor_id);
        writeAt(u16, &bytes, 20, 0);
        writeAt(u16, &bytes, 22, 0);
        writeAt(
            u16,
            &bytes,
            24,
            if (entry.parameters.len == 0)
                std.math.maxInt(u16)
            else
                Reified.semantic_canonicalization.valueId(entry.parameters[0]),
        );
        writeAt(u16, &bytes, 26, 0);
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

pub fn ProgramFailures(comptime Reified: type) type {
    const fields = std.meta.fields(Reified.Body.Failure);
    const length = comptime blk: {
        var total: usize = 4;
        for (fields) |field| total += 8 + field.name.len;
        break :blk total;
    };
    const encoded = comptime blk: {
        var bytes: [length]u8 = undefined;
        writeAt(u32, &bytes, 0, fields.len);
        var cursor: usize = 4;
        for (fields) |field| {
            writeAt(u32, &bytes, cursor, field.value);
            cursor += 4;
            writeAt(u32, &bytes, cursor, field.name.len);
            cursor += 4;
            @memcpy(bytes[cursor..][0..field.name.len], field.name);
            cursor += field.name.len;
        }
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

pub fn ProgramEffects(
    comptime Definition: type,
    comptime Schemas: type,
) type {
    const count = Definition.EffectRow.operation_site_count;
    const length = comptime blk: {
        var total: usize = 4;
        for (0..count) |ordinal| {
            total += 84 + Definition.EffectRow.site(ordinal).semantic_identity.len;
        }
        break :blk total;
    };
    const encoded = comptime blk: {
        var bytes: [length]u8 = [_]u8{0} ** length;
        writeAt(u32, &bytes, 0, count);
        var cursor: usize = 4;
        for (0..count) |ordinal| {
            const Site = Definition.EffectRow.site(ordinal);
            writeAt(u32, &bytes, cursor, ordinal);
            cursor += 4;
            writeAt(u32, &bytes, cursor, Site.semantic_identity.len);
            cursor += 4;
            @memcpy(
                bytes[cursor..][0..Site.semantic_identity.len],
                Site.semantic_identity,
            );
            cursor += Site.semantic_identity.len;
            writeAt(
                u32,
                &bytes,
                cursor,
                Schemas.root_ids[Schemas.effect_root_start + ordinal * 2],
            );
            cursor += 4;
            writeAt(
                u32,
                &bytes,
                cursor,
                Schemas.root_ids[Schemas.effect_root_start + ordinal * 2 + 1],
            );
            cursor += 4;
            bytes[cursor] = 0;
            cursor += 4;
            @memcpy(bytes[cursor..][0..32], &Site.semantic_contract_digest);
            cursor += 32;
            @memcpy(bytes[cursor..][0..32], &Site.contract_digest);
            cursor += 32;
        }
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

pub fn ProgramValues(comptime Reified: type, comptime Schemas: type) type {
    const count = Reified.semantic_canonicalization.value_count;
    const encoded = comptime blk: {
        var bytes: [4 + count * 4]u8 = undefined;
        writeAt(u32, &bytes, 0, count);
        for (0..count) |dense_value| {
            writeAt(
                u32,
                &bytes,
                4 + dense_value * 4,
                Schemas.root_ids[Schemas.value_root_start + dense_value],
            );
        }
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

pub fn ProgramFunctions(comptime Reified: type, comptime Schemas: type) type {
    const count = Reified.semantic_canonicalization.function_count;
    const encoded = comptime blk: {
        var bytes: [4 + count * 8]u8 = undefined;
        writeAt(u32, &bytes, 0, count);
        for (0..count) |dense_function| {
            const source_function = Reified.semantic_canonicalization
                .function_dense_to_source[dense_function];
            const entry = if (Reified.control.functions.len == 0)
                Reified.control.entry
            else
                Reified.control.functions[source_function].entry;
            const offset = 4 + dense_function * 8;
            writeAt(u16, &bytes, offset, dense_function);
            writeAt(
                u16,
                &bytes,
                offset + 2,
                Reified.semantic_canonicalization.blockId(entry),
            );
            writeAt(
                u32,
                &bytes,
                offset + 4,
                Schemas.root_ids[Schemas.function_root_start + dense_function],
            );
        }
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

fn integerKind(comptime T: type) dynamic_value_v1.Kind {
    return if (T == i8)
        .i8
    else if (T == i16)
        .i16
    else if (T == i32)
        .i32
    else if (T == i64)
        .i64
    else if (T == u8)
        .u8
    else if (T == u16)
        .u16
    else if (T == u32)
        .u32
    else if (T == u64)
        .u64
    else
        unreachable;
}

fn castU32(value: anytype) u32 {
    return std.math.cast(u32, value) orelse unreachable;
}

test "schema emission is postorder, structurally interned, and nominally neutral" {
    const Left = struct { value: u32 };
    const Right = struct { renamed: u32 };
    const Schemas = SchemaSet(.{ Left, Right, portable_value.Text(8) });
    try std.testing.expectEqual(@as(u32, 3), Schemas.node_count);
    try std.testing.expectEqual(Schemas.root_ids[0], Schemas.root_ids[1]);
    var nodes: [3]dynamic_value_v1.NodeIndex = undefined;
    const table = try dynamic_value_v1.validateSchemaSection(
        &Schemas.bytes,
        &nodes,
    );
    try std.testing.expectEqual(.u32, (try table.node(0)).kind);
    try std.testing.expectEqual(.product, (try table.node(1)).kind);
    try std.testing.expectEqual(.text, (try table.node(2)).kind);
}

test "typed canonical encoding validates through emitted dynamic schemas" {
    const Choice = enum(u32) { none = 3, count = 9 };
    const Sum = union(Choice) {
        none: void,
        count: u16,
    };
    const Text = portable_value.Text(12);
    const Bytes = portable_value.Bytes(8);
    const Numbers = portable_value.Vector(u32, 3);
    const Product = struct {
        enabled: bool,
        label: Text,
        bytes: Bytes,
        numbers: Numbers,
        fixed: [2]i16,
        maybe: ?u8,
        choice: Sum,
    };
    const Schemas = SchemaSet(.{Product});
    var nodes: [Schemas.node_count]dynamic_value_v1.NodeIndex = undefined;
    const table = try dynamic_value_v1.validateSchemaSection(
        &Schemas.bytes,
        &nodes,
    );
    const value: Product = .{
        .enabled = true,
        .label = try Text.fromSlice("kernel"),
        .bytes = try Bytes.fromSlice(&.{ 1, 2, 3 }),
        .numbers = try Numbers.fromSlice(&.{ 5, 8 }),
        .fixed = .{ -2, 4 },
        .maybe = 7,
        .choice = .{ .count = 21 },
    };
    const maximum_size = comptime portable_value.maximumEncodedSize(Product);
    var encoded: [maximum_size]u8 = undefined;
    const length = try portable_value.encode(Product, value, &encoded);
    var tasks: [32]dynamic_value_v1.ValueTask = undefined;
    try dynamic_value_v1.validateValue(
        table,
        Schemas.root_ids[0],
        encoded[0..length],
        &tasks,
    );
    const root = try table.node(Schemas.root_ids[0]);
    try std.testing.expectEqual(
        @as(u64, maximum_size),
        root.maximum_encoded_size,
    );
}

test "BEI1 envelope composition is exact and digest-bound" {
    const Schemas = SchemaSet(.{u32});
    const empty = "";
    const sections = [image_v1.section_count][]const u8{
        empty,
        &Schemas.bytes,
        empty,
        empty,
        empty,
        empty,
        empty,
        empty,
        empty,
        empty,
    };
    const Image = Envelope(.{
        .program_semantic_digest = [_]u8{1} ** 32,
        .machine_contract_digest = [_]u8{2} ** 32,
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 1000,
        .maximum_kernel_scratch_bytes = 512,
        .maximum_single_value_bytes = 4,
    }, sections);
    const envelope = try image_v1.validateEnvelope(&Image.bytes);
    try std.testing.expectEqual(
        @as(u64, image_v1.header_length + Schemas.bytes.len),
        Image.byte_length,
    );
    try std.testing.expectEqualSlices(
        u8,
        &Schemas.bytes,
        envelope.section(.schemas),
    );
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&Image.bytes, &digest, .{});
    try std.testing.expectEqual(Image.artifact_sha256, digest);
}
