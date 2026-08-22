const std = @import("std");

pub const Error = error{
    InvalidSchema,
    InvalidUtf8,
    InvalidValue,
    LengthOverflow,
    LimitExceeded,
    TrailingBytes,
};

pub const Kind = enum(u8) {
    unit = 0,
    bool = 1,
    i8 = 2,
    i16 = 3,
    i32 = 4,
    i64 = 5,
    u8 = 6,
    u16 = 7,
    u32 = 8,
    u64 = 9,
    bytes = 10,
    text = 11,
    array = 12,
    vector = 13,
    optional = 14,
    @"enum" = 15,
    product = 16,
    sum = 17,
};

pub const NodeIndex = struct {
    offset: u32,
    length: u32,
    minimum_encoded_size: u64,
    maximum_encoded_size: u64,
};

pub const Table = struct {
    bytes: []const u8,
    nodes: []const NodeIndex,

    pub fn count(self: Table) u32 {
        return @intCast(self.nodes.len);
    }

    pub fn node(self: Table, id: u32) Error!Node {
        if (id >= self.nodes.len) return error.InvalidSchema;
        const entry = self.nodes[id];
        const start: usize = entry.offset;
        const end = start + entry.length;
        const record = self.bytes[start..end];
        return .{
            .id = id,
            .kind = std.enums.fromInt(Kind, record[4]) orelse
                return error.InvalidSchema,
            .payload = record[8..],
            .minimum_encoded_size = entry.minimum_encoded_size,
            .maximum_encoded_size = entry.maximum_encoded_size,
        };
    }
};

pub const Node = struct {
    id: u32,
    kind: Kind,
    payload: []const u8,
    minimum_encoded_size: u64,
    maximum_encoded_size: u64,
};

pub const ValueTask = union(enum) {
    schema: u32,
    repeat: struct {
        schema: u32,
        remaining: u32,
    },
    product: struct {
        schema: u32,
        field_index: u32,
    },
};

/// Validate one complete BEI1 schema-section payload into caller-owned index
/// storage. Children must precede parents, making the structural DAG finite.
pub fn validateSchemaSection(
    bytes: []const u8,
    index_storage: []NodeIndex,
) Error!Table {
    if (bytes.len < 4) return error.InvalidSchema;
    const node_count = readInt(u32, bytes, 0);
    if (node_count > index_storage.len) return error.LimitExceeded;
    var cursor: usize = 4;
    for (0..node_count) |node_id| {
        if (bytes.len - cursor < 8) return error.InvalidSchema;
        const record_length = readInt(u32, bytes, cursor);
        if (record_length < 8) return error.InvalidSchema;
        const record_end = std.math.add(
            usize,
            cursor,
            record_length,
        ) catch return error.LengthOverflow;
        if (record_end > bytes.len) return error.InvalidSchema;
        const kind = std.enums.fromInt(Kind, bytes[cursor + 4]) orelse
            return error.InvalidSchema;
        if (bytes[cursor + 5] != 0 or
            readInt(u16, bytes, cursor + 6) != 0)
        {
            return error.InvalidSchema;
        }
        const payload = bytes[cursor + 8 .. record_end];
        const sizes = try validateNode(
            bytes,
            kind,
            payload,
            index_storage[0..node_id],
        );
        index_storage[node_id] = .{
            .offset = std.math.cast(u32, cursor) orelse
                return error.LengthOverflow,
            .length = record_length,
            .minimum_encoded_size = sizes.minimum,
            .maximum_encoded_size = sizes.maximum,
        };
        cursor = record_end;
    }
    if (cursor != bytes.len) return error.InvalidSchema;
    return .{
        .bytes = bytes,
        .nodes = index_storage[0..node_count],
    };
}

/// Validate one exact canonical value without constructing a Zig type. The
/// caller owns the bounded traversal stack; no semantic cursor is persisted.
pub fn validateValue(
    table: Table,
    schema_id: u32,
    bytes: []const u8,
    task_storage: []ValueTask,
) Error!void {
    if (schema_id >= table.nodes.len) return error.InvalidSchema;
    if (task_storage.len == 0) return error.LimitExceeded;
    var task_count: usize = 1;
    task_storage[0] = .{ .schema = schema_id };
    var cursor: usize = 0;
    while (task_count != 0) {
        task_count -= 1;
        switch (task_storage[task_count]) {
            .schema => |id| {
                const node = try table.node(id);
                switch (node.kind) {
                    .unit => {},
                    .bool => {
                        const value = try takeByte(bytes, &cursor);
                        if (value > 1) return error.InvalidValue;
                    },
                    .i8, .u8 => try take(bytes, &cursor, 1),
                    .i16, .u16 => try take(bytes, &cursor, 2),
                    .i32, .u32, .i64, .u64 => try take(
                        bytes,
                        &cursor,
                        if (node.kind == .i64 or node.kind == .u64) 8 else 4,
                    ),
                    .bytes, .text => {
                        const length = try readValueLength(bytes, &cursor);
                        const maximum = readInt(u32, node.payload, 0);
                        if (length > maximum) return error.InvalidValue;
                        const value = try takeSlice(bytes, &cursor, length);
                        if (node.kind == .text and
                            !std.unicode.utf8ValidateSlice(value))
                        {
                            return error.InvalidUtf8;
                        }
                    },
                    .array => try pushTask(task_storage, &task_count, .{
                        .repeat = .{
                            .schema = readInt(u32, node.payload, 4),
                            .remaining = readInt(u32, node.payload, 0),
                        },
                    }),
                    .vector => {
                        const length = try readValueLength(bytes, &cursor);
                        if (length > readInt(u32, node.payload, 0)) {
                            return error.InvalidValue;
                        }
                        try pushTask(task_storage, &task_count, .{
                            .repeat = .{
                                .schema = readInt(u32, node.payload, 4),
                                .remaining = length,
                            },
                        });
                    },
                    .optional => {
                        const present = try takeByte(bytes, &cursor);
                        if (present > 1) return error.InvalidValue;
                        if (present == 1) {
                            try pushTask(task_storage, &task_count, .{
                                .schema = readInt(u32, node.payload, 0),
                            });
                        }
                    },
                    .@"enum" => {
                        const tag = try readValueInt(u32, bytes, &cursor);
                        if (!tagInEnum(node, tag)) return error.InvalidValue;
                    },
                    .product => try pushTask(task_storage, &task_count, .{
                        .product = .{ .schema = id, .field_index = 0 },
                    }),
                    .sum => {
                        const tag = try readValueInt(u32, bytes, &cursor);
                        const payload_schema = sumPayloadSchema(node, tag) orelse
                            return error.InvalidValue;
                        try pushTask(task_storage, &task_count, .{
                            .schema = payload_schema,
                        });
                    },
                }
            },
            .repeat => |repeat| {
                if (repeat.remaining == 0) continue;
                try pushTask(task_storage, &task_count, .{
                    .repeat = .{
                        .schema = repeat.schema,
                        .remaining = repeat.remaining - 1,
                    },
                });
                try pushTask(task_storage, &task_count, .{
                    .schema = repeat.schema,
                });
            },
            .product => |product| {
                const node = try table.node(product.schema);
                const field_count = readInt(u32, node.payload, 0);
                if (product.field_index >= field_count) continue;
                try pushTask(task_storage, &task_count, .{
                    .product = .{
                        .schema = product.schema,
                        .field_index = product.field_index + 1,
                    },
                });
                try pushTask(task_storage, &task_count, .{
                    .schema = readInt(
                        u32,
                        node.payload,
                        4 + @as(usize, product.field_index) * 4,
                    ),
                });
            },
        }
    }
    if (cursor != bytes.len) return error.TrailingBytes;
}

fn pushTask(
    storage: []ValueTask,
    count: *usize,
    task: ValueTask,
) Error!void {
    if (count.* == storage.len) return error.LimitExceeded;
    storage[count.*] = task;
    count.* += 1;
}

fn readValueLength(bytes: []const u8, cursor: *usize) Error!u32 {
    return readValueInt(u32, bytes, cursor);
}

fn readValueInt(
    comptime T: type,
    bytes: []const u8,
    cursor: *usize,
) Error!T {
    const slice = try takeSlice(bytes, cursor, @sizeOf(T));
    return std.mem.readInt(T, slice[0..@sizeOf(T)], .little);
}

fn takeByte(bytes: []const u8, cursor: *usize) Error!u8 {
    const result = try takeSlice(bytes, cursor, 1);
    return result[0];
}

fn take(bytes: []const u8, cursor: *usize, length: usize) Error!void {
    _ = try takeSlice(bytes, cursor, length);
}

fn takeSlice(
    bytes: []const u8,
    cursor: *usize,
    length: usize,
) Error![]const u8 {
    const end = std.math.add(usize, cursor.*, length) catch
        return error.InvalidValue;
    if (end > bytes.len) return error.InvalidValue;
    defer cursor.* = end;
    return bytes[cursor.*..end];
}

fn tagInEnum(node: Node, tag: u32) bool {
    const count = readInt(u32, node.payload, 0);
    for (0..count) |index| {
        if (readInt(u32, node.payload, 4 + index * 4) == tag) return true;
    }
    return false;
}

fn sumPayloadSchema(node: Node, tag: u32) ?u32 {
    const count = readInt(u32, node.payload, 4);
    for (0..count) |index| {
        const offset = 8 + index * 8;
        if (readInt(u32, node.payload, offset) == tag) {
            return readInt(u32, node.payload, offset + 4);
        }
    }
    return null;
}

const Sizes = struct {
    minimum: u64,
    maximum: u64,
};

fn validateNode(
    section: []const u8,
    kind: Kind,
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    return switch (kind) {
        .unit => fixed(payload, 0),
        .bool, .i8, .u8 => fixed(payload, 1),
        .i16, .u16 => fixed(payload, 2),
        .i32, .u32, .@"enum" => if (kind == .@"enum")
            validateEnum(payload)
        else
            fixed(payload, 4),
        .i64, .u64 => fixed(payload, 8),
        .bytes, .text => validateBoundedBytes(payload),
        .array => validateRepeated(payload, prior, false),
        .vector => validateRepeated(payload, prior, true),
        .optional => validateOptional(payload, prior),
        .product => validateProduct(payload, prior),
        .sum => validateSum(section, payload, prior),
    };
}

fn fixed(payload: []const u8, size: u64) Error!Sizes {
    if (payload.len != 0) return error.InvalidSchema;
    return .{ .minimum = size, .maximum = size };
}

fn validateBoundedBytes(payload: []const u8) Error!Sizes {
    if (payload.len != 4) return error.InvalidSchema;
    return .{
        .minimum = 4,
        .maximum = try add(4, readInt(u32, payload, 0)),
    };
}

fn validateRepeated(
    payload: []const u8,
    prior: []const NodeIndex,
    variable: bool,
) Error!Sizes {
    if (payload.len != 8) return error.InvalidSchema;
    const count = readInt(u32, payload, 0);
    const child = try priorNode(prior, readInt(u32, payload, 4));
    const minimum = try multiply(count, child.minimum_encoded_size);
    const maximum = try multiply(count, child.maximum_encoded_size);
    if (!variable) return .{ .minimum = minimum, .maximum = maximum };
    return .{ .minimum = 4, .maximum = try add(4, maximum) };
}

fn validateOptional(
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    if (payload.len != 4) return error.InvalidSchema;
    const child = try priorNode(prior, readInt(u32, payload, 0));
    return .{ .minimum = 1, .maximum = try add(1, child.maximum_encoded_size) };
}

fn validateEnum(payload: []const u8) Error!Sizes {
    if (payload.len < 4) return error.InvalidSchema;
    const count = readInt(u32, payload, 0);
    if (count == 0 or payload.len != try recordArrayLength(4, count, 4)) {
        return error.InvalidSchema;
    }
    for (0..count) |left| {
        const left_tag = readInt(u32, payload, 4 + left * 4);
        for (0..left) |right| {
            if (left_tag == readInt(u32, payload, 4 + right * 4)) {
                return error.InvalidSchema;
            }
        }
    }
    return .{ .minimum = 4, .maximum = 4 };
}

fn validateProduct(
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    if (payload.len < 4) return error.InvalidSchema;
    const count = readInt(u32, payload, 0);
    if (payload.len != try recordArrayLength(4, count, 4)) {
        return error.InvalidSchema;
    }
    var sizes: Sizes = .{ .minimum = 0, .maximum = 0 };
    for (0..count) |index| {
        const child = try priorNode(
            prior,
            readInt(u32, payload, 4 + index * 4),
        );
        sizes.minimum = try add(sizes.minimum, child.minimum_encoded_size);
        sizes.maximum = try add(sizes.maximum, child.maximum_encoded_size);
    }
    return sizes;
}

fn validateSum(
    section: []const u8,
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    if (payload.len < 8) return error.InvalidSchema;
    const tag_schema = readInt(u32, payload, 0);
    const tag_node = try priorNodeView(section, prior, tag_schema);
    if (tag_node.kind != .@"enum") return error.InvalidSchema;
    const count = readInt(u32, payload, 4);
    if (count == 0 or payload.len != try recordArrayLength(8, count, 8)) {
        return error.InvalidSchema;
    }
    var minimum: u64 = std.math.maxInt(u64);
    var maximum: u64 = 0;
    for (0..count) |index| {
        const tag_offset = 8 + index * 8;
        const tag = readInt(u32, payload, tag_offset);
        if (!tagInEnum(tag_node, tag)) return error.InvalidSchema;
        for (0..index) |prior_index| {
            if (tag == readInt(u32, payload, 8 + prior_index * 8)) {
                return error.InvalidSchema;
            }
        }
        const child = try priorNode(
            prior,
            readInt(u32, payload, tag_offset + 4),
        );
        minimum = @min(minimum, child.minimum_encoded_size);
        maximum = @max(maximum, child.maximum_encoded_size);
    }
    return .{
        .minimum = try add(4, minimum),
        .maximum = try add(4, maximum),
    };
}

fn priorNodeView(
    section: []const u8,
    prior: []const NodeIndex,
    id: u32,
) Error!Node {
    const entry = try priorNode(prior, id);
    const start: usize = entry.offset;
    const record = section[start .. start + entry.length];
    return .{
        .id = id,
        .kind = std.enums.fromInt(Kind, record[4]) orelse
            return error.InvalidSchema,
        .payload = record[8..],
        .minimum_encoded_size = entry.minimum_encoded_size,
        .maximum_encoded_size = entry.maximum_encoded_size,
    };
}

fn recordArrayLength(base: usize, count: u32, stride: usize) Error!usize {
    const entries = std.math.mul(usize, count, stride) catch
        return error.LengthOverflow;
    return std.math.add(usize, base, entries) catch error.LengthOverflow;
}

fn priorNode(prior: []const NodeIndex, id: u32) Error!NodeIndex {
    if (id >= prior.len) return error.InvalidSchema;
    return prior[id];
}

fn add(left: anytype, right: anytype) Error!u64 {
    return std.math.add(u64, @intCast(left), @intCast(right)) catch
        error.LengthOverflow;
}

fn multiply(left: anytype, right: anytype) Error!u64 {
    return std.math.mul(u64, @intCast(left), @intCast(right)) catch
        error.LengthOverflow;
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

test "dynamic schema validation indexes canonical postorder nodes" {
    var bytes = [_]u8{0} ** 32;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 8, .little);
    bytes[8] = @intFromEnum(Kind.u32);
    std.mem.writeInt(u32, bytes[12..16], 16, .little);
    bytes[16] = @intFromEnum(Kind.vector);
    std.mem.writeInt(u32, bytes[20..24], 2, .little);
    std.mem.writeInt(u32, bytes[24..28], 0, .little);
    var storage: [2]NodeIndex = undefined;
    const table = try validateSchemaSection(bytes[0..28], &storage);
    try std.testing.expectEqual(@as(u32, 2), table.count());
    const vector = try table.node(1);
    try std.testing.expectEqual(Kind.vector, vector.kind);
    try std.testing.expectEqual(@as(u64, 4), vector.minimum_encoded_size);
    try std.testing.expectEqual(@as(u64, 12), vector.maximum_encoded_size);

    var value = [_]u8{0} ** 12;
    std.mem.writeInt(u32, value[0..4], 2, .little);
    std.mem.writeInt(u32, value[4..8], 7, .little);
    std.mem.writeInt(u32, value[8..12], 11, .little);
    var tasks: [4]ValueTask = undefined;
    try validateValue(table, 1, &value, &tasks);

    std.mem.writeInt(u32, value[0..4], 3, .little);
    try std.testing.expectError(
        error.InvalidValue,
        validateValue(table, 1, &value, &tasks),
    );
}

test "dynamic schema validation rejects forward references" {
    var bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, bytes[0..4], 1, .little);
    std.mem.writeInt(u32, bytes[4..8], 12, .little);
    bytes[8] = @intFromEnum(Kind.optional);
    std.mem.writeInt(u32, bytes[12..16], 0, .little);
    var storage: [1]NodeIndex = undefined;
    try std.testing.expectError(
        error.InvalidSchema,
        validateSchemaSection(&bytes, &storage),
    );
}

test "dynamic values reject noncanonical booleans and trailing bytes" {
    var schema = [_]u8{0} ** 12;
    std.mem.writeInt(u32, schema[0..4], 1, .little);
    std.mem.writeInt(u32, schema[4..8], 8, .little);
    schema[8] = @intFromEnum(Kind.bool);
    var nodes: [1]NodeIndex = undefined;
    const table = try validateSchemaSection(&schema, &nodes);
    var tasks: [1]ValueTask = undefined;
    try validateValue(table, 0, &.{1}, &tasks);
    try std.testing.expectError(
        error.InvalidValue,
        validateValue(table, 0, &.{2}, &tasks),
    );
    try std.testing.expectError(
        error.TrailingBytes,
        validateValue(table, 0, &.{ 1, 0 }, &tasks),
    );
}
