const dynamic_value_v1 = @import("dynamic_value_v1");
const portable_value = @import("portable_value");
const std = @import("std");

const maximum_nodes = 1024;
const maximum_bytes = 1 << 20;

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
