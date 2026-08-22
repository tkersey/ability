const std = @import("std");

fn copyPossiblyOverlapping(destination: []u8, source: []const u8) void {
    std.debug.assert(destination.len == source.len);
    if (source.len == 0) return;
    if (@intFromPtr(destination.ptr) <= @intFromPtr(source.ptr)) {
        std.mem.copyForwards(u8, destination, source);
    } else {
        std.mem.copyBackwards(u8, destination, source);
    }
}

/// Portable-value operation and canonical-codec failures.
pub const Error = error{
    CapacityExceeded,
    InvalidUtf8,
    InvalidTag,
    Malformed,
    SizeOverflow,
    TrailingBytes,
};

const PortableKind = enum {
    bytes,
    text,
    vector,
};

const bytes_authenticity = opaque {};
const text_authenticity = opaque {};
const vector_authenticity = opaque {};

fn assertCanonicalCapacity(comptime maximum: usize) void {
    if (maximum > std.math.maxInt(u32)) {
        @compileError("Boundary portable capacities must fit the canonical u32 domain");
    }
}

/// Inline owned bytes with a contract-bearing maximum logical length.
pub fn Bytes(comptime maximum_bytes: usize) type {
    comptime assertCanonicalCapacity(maximum_bytes);
    return struct {
        const Self = @This();

        pub const portable_value_kind = PortableKind.bytes;
        pub const portable_value_authenticity = bytes_authenticity;
        pub const maximum_length = maximum_bytes;

        storage: [maximum_bytes]u8 = [_]u8{0} ** maximum_bytes,
        logical_length: u32 = 0,

        /// Construct an empty value.
        pub fn empty() Self {
            return .{};
        }

        /// Copy one logical byte slice into bounded owned storage.
        pub fn fromSlice(value: []const u8) Error!Self {
            if (value.len > maximum_bytes) return error.CapacityExceeded;
            var result = Self.empty();
            @memcpy(result.storage[0..value.len], value);
            result.logical_length = @intCast(value.len);
            return result;
        }

        /// Return the validated target-neutral logical length.
        pub fn len(self: *const Self) Error!u32 {
            if (self.logical_length > maximum_bytes) return error.Malformed;
            return self.logical_length;
        }

        fn logicalSlice(self: *const Self) []const u8 {
            if (self.logical_length > maximum_bytes) return &.{};
            return self.storage[0..@intCast(self.logical_length)];
        }

        /// Borrow validated initialized logical bytes.
        pub fn slice(self: *const Self) Error![]const u8 {
            _ = try self.len();
            return self.logicalSlice();
        }

        /// Append atomically, failing before mutation on overflow.
        pub fn append(self: *Self, suffix: []const u8) Error!void {
            if (self.logical_length > maximum_bytes) return error.Malformed;
            const start: usize = @intCast(self.logical_length);
            const end = std.math.add(usize, start, suffix.len) catch
                return error.CapacityExceeded;
            if (end > maximum_bytes) return error.CapacityExceeded;
            copyPossiblyOverlapping(self.storage[start..end], suffix);
            self.logical_length = @intCast(end);
        }

        /// Copy a bounded byte range into a possibly different capacity.
        pub fn copyRange(
            self: *const Self,
            comptime result_capacity: usize,
            start: u32,
            end: u32,
        ) Error!Bytes(result_capacity) {
            _ = try self.len();
            if (start > end or end > self.logical_length) {
                return error.CapacityExceeded;
            }
            return Bytes(result_capacity).fromSlice(
                self.storage[@intCast(start)..@intCast(end)],
            );
        }

        /// Replace one logical byte.
        pub fn set(self: *Self, index: u32, value: u8) Error!void {
            if (self.logical_length > maximum_bytes) return error.Malformed;
            if (index >= self.logical_length) return error.CapacityExceeded;
            self.storage[@intCast(index)] = value;
        }

        /// Return one logical byte.
        pub fn get(self: *const Self, index: u32) Error!?u8 {
            _ = try self.len();
            if (index >= self.logical_length) return null;
            return self.storage[@intCast(index)];
        }

        /// Shorten the logical value.
        pub fn truncate(self: *Self, new_length: u32) void {
            if (self.logical_length > maximum_bytes) {
                @memset(&self.storage, 0);
                self.logical_length = 0;
                return;
            }
            if (new_length >= self.logical_length) return;
            const old_length = self.logical_length;
            @memset(self.storage[new_length..old_length], 0);
            self.logical_length = new_length;
        }

        /// Clear the logical value without exposing spare storage.
        pub fn clear(self: *Self) void {
            self.truncate(0);
        }

        /// Compare canonical logical contents.
        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.logical_length > maximum_bytes or
                other.logical_length > maximum_bytes) return false;
            const self_slice = self.slice() catch return false;
            const other_slice = other.slice() catch return false;
            return std.mem.eql(u8, self_slice, other_slice);
        }

        /// Lexicographically compare logical bytes.
        pub fn order(self: *const Self, other: *const Self) Error!std.math.Order {
            if (self.logical_length > maximum_bytes or
                other.logical_length > maximum_bytes)
            {
                return error.Malformed;
            }
            return std.mem.order(u8, try self.slice(), try other.slice());
        }
    };
}

/// Inline owned UTF-8 text with a contract-bearing maximum byte length.
pub fn Text(comptime maximum_bytes: usize) type {
    comptime assertCanonicalCapacity(maximum_bytes);
    return struct {
        const Self = @This();

        pub const portable_value_kind = PortableKind.text;
        pub const portable_value_authenticity = text_authenticity;
        pub const maximum_length = maximum_bytes;

        storage: [maximum_bytes]u8 = [_]u8{0} ** maximum_bytes,
        logical_length: u32 = 0,

        /// Construct empty text.
        pub fn empty() Self {
            return .{};
        }

        /// Copy one valid UTF-8 string into bounded owned storage.
        pub fn fromSlice(value: []const u8) Error!Self {
            if (value.len > maximum_bytes) return error.CapacityExceeded;
            if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
            var result = Self.empty();
            @memcpy(result.storage[0..value.len], value);
            result.logical_length = @intCast(value.len);
            return result;
        }

        /// Return the validated logical UTF-8 byte length.
        pub fn len(self: *const Self) Error!u32 {
            if (self.logical_length > maximum_bytes) return error.Malformed;
            return self.logical_length;
        }

        fn logicalSlice(self: *const Self) []const u8 {
            if (self.logical_length > maximum_bytes) return &.{};
            return self.storage[0..@intCast(self.logical_length)];
        }

        /// Borrow validated logical UTF-8 bytes.
        pub fn slice(self: *const Self) Error![]const u8 {
            if (self.logical_length > maximum_bytes) return error.Malformed;
            const value = self.logicalSlice();
            if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
            return value;
        }

        /// Append valid UTF-8 atomically.
        pub fn append(self: *Self, suffix: []const u8) Error!void {
            if (self.logical_length > maximum_bytes) return error.Malformed;
            const start: usize = @intCast(self.logical_length);
            const end = std.math.add(usize, start, suffix.len) catch
                return error.CapacityExceeded;
            if (end > maximum_bytes) return error.CapacityExceeded;
            _ = try self.slice();
            if (!std.unicode.utf8ValidateSlice(suffix)) return error.InvalidUtf8;
            copyPossiblyOverlapping(self.storage[start..end], suffix);
            self.logical_length = @intCast(end);
        }

        /// Append one Unicode scalar atomically.
        pub fn appendScalar(self: *Self, scalar: u21) Error!void {
            var encoded: [4]u8 = undefined;
            const length = std.unicode.utf8Encode(scalar, &encoded) catch
                return error.InvalidUtf8;
            try self.append(encoded[0..length]);
        }

        /// Append one unsigned decimal integer without locale semantics.
        pub fn appendUnsigned(self: *Self, value: u64) Error!void {
            var buffer: [20]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch
                return error.CapacityExceeded;
            try self.append(formatted);
        }

        /// Append one signed decimal integer without locale semantics.
        pub fn appendSigned(self: *Self, value: i64) Error!void {
            var buffer: [20]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch
                return error.CapacityExceeded;
            try self.append(formatted);
        }

        /// Copy a byte range that must itself be valid UTF-8.
        pub fn copyRange(
            self: *const Self,
            comptime result_capacity: usize,
            start: u32,
            end: u32,
        ) Error!Text(result_capacity) {
            const source = try self.slice();
            if (start > end or end > self.logical_length) return error.CapacityExceeded;
            return Text(result_capacity).fromSlice(
                source[@intCast(start)..@intCast(end)],
            );
        }

        /// Compare canonical logical contents.
        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.logical_length > maximum_bytes or
                other.logical_length > maximum_bytes) return false;
            const self_slice = self.slice() catch return false;
            const other_slice = other.slice() catch return false;
            return std.mem.eql(u8, self_slice, other_slice);
        }

        /// Lexicographically compare UTF-8 bytes without locale semantics.
        pub fn order(self: *const Self, other: *const Self) Error!std.math.Order {
            if (self.logical_length > maximum_bytes or
                other.logical_length > maximum_bytes)
            {
                return error.Malformed;
            }
            return std.mem.order(u8, try self.slice(), try other.slice());
        }
    };
}

/// Inline owned bounded vector whose spare capacity has no semantic identity.
pub fn Vector(comptime Element: type, comptime maximum_items: usize) type {
    comptime assertCanonicalCapacity(maximum_items);
    comptime assertPortable(Element);
    comptime if (!hasCanonicalDefaultValue(Element)) {
        @compileError(
            "Boundary Vector element type must have a canonical default value",
        );
    };
    return struct {
        const Self = @This();

        pub const portable_value_kind = PortableKind.vector;
        pub const portable_value_authenticity = vector_authenticity;
        pub const ElementType = Element;
        pub const maximum_length = maximum_items;

        storage: [maximum_items]Element =
            [_]Element{canonicalDefaultValue(Element)} ** maximum_items,
        logical_length: u32 = 0,

        /// Construct an empty vector.
        pub fn empty() Self {
            return .{};
        }

        fn canonicalElement(item: Element) Error!Element {
            _ = try encodedSize(Element, item);
            return canonicalValue(Element, item);
        }

        fn canonicalElementAt(self: *const Self, index: u32) Error!?Element {
            if (self.logical_length > maximum_items) return error.Malformed;
            if (index >= self.logical_length) return null;
            return try canonicalElement(self.storage[@intCast(index)]);
        }

        /// Copy a logical element slice.
        pub fn fromSlice(items: []const Element) Error!Self {
            if (items.len > maximum_items) return error.CapacityExceeded;
            var result = Self.empty();
            for (items, 0..) |item, index| {
                result.storage[index] = try canonicalElement(item);
            }
            result.logical_length = @intCast(items.len);
            return result;
        }

        /// Return the validated logical element count.
        pub fn len(self: *const Self) Error!u32 {
            if (self.logical_length > maximum_items) return error.Malformed;
            return self.logical_length;
        }

        /// Borrow initialized logical elements only within canonical internals.
        fn logicalSlice(self: *const Self) []const Element {
            if (self.logical_length > maximum_items) return &.{};
            return self.storage[0..@intCast(self.logical_length)];
        }

        /// Return one element by value, never by portable pointer identity.
        pub fn get(self: *const Self, index: u32) Error!?Element {
            return self.canonicalElementAt(index);
        }

        /// Replace one logical element.
        pub fn set(self: *Self, index: u32, item: Element) Error!void {
            if (self.logical_length > maximum_items) return error.Malformed;
            if (index >= self.logical_length) return error.CapacityExceeded;
            const canonical = try canonicalElement(item);
            self.storage[@intCast(index)] = canonical;
        }

        /// Append one element atomically.
        pub fn push(self: *Self, item: Element) Error!void {
            if (self.logical_length > maximum_items) return error.Malformed;
            const index: usize = @intCast(self.logical_length);
            if (index == maximum_items) return error.CapacityExceeded;
            const canonical = try canonicalElement(item);
            self.storage[index] = canonical;
            self.logical_length += 1;
        }

        /// Remove and return the final logical element.
        pub fn pop(self: *Self) Error!?Element {
            if (self.logical_length > maximum_items) return error.Malformed;
            if (self.logical_length == 0) return null;
            const next_length = self.logical_length - 1;
            const item = (try self.canonicalElementAt(next_length)) orelse
                unreachable;
            self.logical_length = next_length;
            const index: usize = @intCast(next_length);
            self.storage[index] = canonicalDefaultValue(Element);
            return item;
        }

        /// Shorten the vector without observing spare storage.
        pub fn truncate(self: *Self, new_length: u32) void {
            if (self.logical_length > maximum_items) {
                if (comptime maximumEncodedSize(Element) != 0) {
                    for (&self.storage) |*item| {
                        item.* = canonicalDefaultValue(Element);
                    }
                }
                self.logical_length = 0;
                return;
            }
            if (new_length >= self.logical_length) return;
            const old_length = self.logical_length;
            if (comptime maximumEncodedSize(Element) != 0) {
                for (self.storage[new_length..old_length]) |*item| {
                    item.* = canonicalDefaultValue(Element);
                }
            }
            self.logical_length = new_length;
        }

        /// Clear all logical elements.
        pub fn clear(self: *Self) void {
            self.truncate(0);
        }

        /// Compare logical elements structurally.
        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.logical_length > maximum_items or
                other.logical_length > maximum_items) return false;
            if (self.logical_length != other.logical_length) return false;
            if (comptime maximumEncodedSize(Element) == 0) return true;
            for (self.logicalSlice(), other.logicalSlice()) |left, right| {
                if (!eqlValue(Element, left, right)) return false;
            }
            return true;
        }
    };
}

/// Whether `T` is Boundary's canonical bounded byte type.
pub fn isBytesType(comptime T: type) bool {
    return isBytes(T);
}

/// Whether `T` is Boundary's canonical bounded UTF-8 text type.
pub fn isTextType(comptime T: type) bool {
    return isText(T);
}

/// Whether `T` is Boundary's canonical bounded vector type.
pub fn isVectorType(comptime T: type) bool {
    return isVector(T);
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn isBytes(comptime T: type) bool {
    if (comptime !hasDeclSafe(T, "portable_value_kind") or
        !hasDeclSafe(T, "portable_value_authenticity") or
        !hasDeclSafe(T, "maximum_length")) return false;
    if (@TypeOf(T.portable_value_kind) != PortableKind or
        @TypeOf(T.portable_value_authenticity) != type or
        @TypeOf(T.maximum_length) != usize) return false;
    return T.portable_value_kind == .bytes and
        T.portable_value_authenticity == bytes_authenticity and
        T == Bytes(T.maximum_length);
}

fn isText(comptime T: type) bool {
    if (comptime !hasDeclSafe(T, "portable_value_kind") or
        !hasDeclSafe(T, "portable_value_authenticity") or
        !hasDeclSafe(T, "maximum_length")) return false;
    if (@TypeOf(T.portable_value_kind) != PortableKind or
        @TypeOf(T.portable_value_authenticity) != type or
        @TypeOf(T.maximum_length) != usize) return false;
    return T.portable_value_kind == .text and
        T.portable_value_authenticity == text_authenticity and
        T == Text(T.maximum_length);
}

fn isVector(comptime T: type) bool {
    if (comptime !hasDeclSafe(T, "portable_value_kind") or
        !hasDeclSafe(T, "portable_value_authenticity") or
        !hasDeclSafe(T, "ElementType") or
        !hasDeclSafe(T, "maximum_length")) return false;
    if (@TypeOf(T.portable_value_kind) != PortableKind or
        @TypeOf(T.portable_value_authenticity) != type or
        @TypeOf(T.ElementType) != type or
        @TypeOf(T.maximum_length) != usize) return false;
    return T.portable_value_kind == .vector and
        T.portable_value_authenticity == vector_authenticity and
        T == Vector(T.ElementType, T.maximum_length);
}

fn isCanonicalInteger(comptime T: type) bool {
    return T == i8 or T == i16 or T == i32 or T == i64 or
        T == u8 or T == u16 or T == u32 or T == u64;
}

fn hasCanonicalDefaultValue(comptime T: type) bool {
    if (isBytes(T) or isText(T) or isVector(T)) return true;
    return switch (@typeInfo(T)) {
        .void, .bool, .int => true,
        .array => |info| info.len == 0 or hasCanonicalDefaultValue(info.child),
        .optional => true,
        .@"enum" => |info| info.fields.len != 0,
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| {
                if (!hasCanonicalDefaultValue(field.type)) break :blk false;
            }
            break :blk true;
        },
        .@"union" => |info| blk: {
            inline for (info.fields) |field| {
                if (hasCanonicalDefaultValue(field.type)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Reject values without explicit first-order portable semantics.
pub fn assertPortable(comptime T: type) void {
    @setEvalBranchQuota(1_000_000);
    if (isBytes(T) or isText(T)) return;
    if (isVector(T)) {
        assertPortable(T.ElementType);
        return;
    }
    switch (@typeInfo(T)) {
        .void, .bool => {},
        .int => {
            if (!isCanonicalInteger(T)) {
                @compileError("Boundary Machine integers must be explicit i8/i16/i32/i64 or u8/u16/u32/u64");
            }
        },
        .array => |info| {
            if (info.sentinel() != null) {
                @compileError("Boundary Machine portable arrays cannot have sentinels");
            }
            assertPortable(info.child);
        },
        .optional => |info| assertPortable(info.child),
        .@"enum" => |info| {
            if (!info.is_exhaustive) {
                @compileError("Boundary Machine enums must be exhaustive");
            }
            inline for (std.meta.fields(T)) |field| {
                _ = std.math.cast(u32, field.value) orelse
                    @compileError("Boundary Machine enum tags must fit canonical u32");
            }
        },
        .@"struct" => |info| inline for (info.fields) |field| {
            if (field.is_comptime) {
                @compileError("Boundary Machine products cannot contain comptime fields");
            }
            assertPortable(field.type);
        },
        .@"union" => |info| {
            const Tag = info.tag_type orelse
                @compileError("Boundary Machine unions must be tagged");
            assertPortable(Tag);
            inline for (info.fields) |field| assertPortable(field.type);
        },
        else => @compileError("unsupported Boundary Machine portable value: " ++ @typeName(T)),
    }
}

test "portable admission owns the comptime quota for deep closed values" {
    const Payload = struct {
        path: Text(256),
        digest: Text(64),
        contents: Text(32 * 1024),
        rationale: Text(4096),
        stdout: Text(32 * 1024),
        stderr: Text(32 * 1024),
        count: u32,
        passed: bool,
    };
    const Observation = union(enum) {
        one: Payload,
        two: Payload,
        three: Payload,
        four: Payload,
        five: Payload,
        six: Payload,
        seven: Payload,
        eight: Payload,
    };
    const State = struct {
        history: Vector(Observation, 12),
        candidate: Observation,
        prior: ?Observation,
    };

    comptime assertPortable(State);
    const maximum = comptime maximumEncodedSize(State);
    try std.testing.expect(maximum > 0);
}

fn canonicalDefaultValue(comptime T: type) T {
    comptime assertPortable(T);
    if (comptime maximumEncodedSize(T) == 0) return std.mem.zeroes(T);
    if (comptime isBytes(T) or isText(T) or isVector(T)) return T.empty();
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => false,
        .int => 0,
        .array => |info| blk: {
            var result: T = undefined;
            inline for (0..info.len) |index| {
                result[index] = canonicalDefaultValue(info.child);
            }
            break :blk result;
        },
        .optional => null,
        .@"enum" => |info| @field(T, info.fields[0].name),
        .@"struct" => |info| blk: {
            var result: T = undefined;
            inline for (info.fields) |field| {
                @field(result, field.name) = canonicalDefaultValue(field.type);
            }
            break :blk result;
        },
        .@"union" => |info| blk: {
            inline for (info.fields) |field| {
                if (hasCanonicalDefaultValue(field.type)) {
                    break :blk @unionInit(
                        T,
                        field.name,
                        canonicalDefaultValue(field.type),
                    );
                }
            }
            unreachable;
        },
        else => unreachable,
    };
}

/// Rebuild one portable value into its unique owned representation.
pub fn canonicalValue(comptime T: type, value: T) Error!T {
    comptime assertPortable(T);
    if (comptime maximumEncodedSize(T) == 0) return std.mem.zeroes(T);
    if (comptime isBytes(T) or isText(T)) {
        if (value.logical_length > T.maximum_length) return error.Malformed;
        return T.fromSlice(value.storage[0..@intCast(value.logical_length)]);
    }
    if (comptime isVector(T)) {
        if (value.logical_length > T.maximum_length) return error.Malformed;
        var result = T.empty();
        if (comptime maximumEncodedSize(T.ElementType) == 0) {
            result.logical_length = value.logical_length;
            return result;
        }
        for (value.logicalSlice(), 0..) |item, index| {
            result.storage[index] = try canonicalValue(T.ElementType, item);
        }
        result.logical_length = value.logical_length;
        return result;
    }
    return switch (@typeInfo(T)) {
        .void => {},
        .bool, .int => value,
        .array => |info| blk: {
            var result: T = undefined;
            for (value, 0..) |item, index| {
                result[index] = try canonicalValue(info.child, item);
            }
            break :blk result;
        },
        .optional => |info| if (value) |payload|
            try canonicalValue(info.child, payload)
        else
            null,
        .@"enum" => |info| blk: {
            const raw = @intFromEnum(value);
            inline for (info.fields) |field| {
                if (raw == field.value) break :blk @field(T, field.name);
            }
            break :blk error.InvalidTag;
        },
        .@"struct" => |info| blk: {
            var result: T = undefined;
            inline for (info.fields) |field| {
                @field(result, field.name) = try canonicalValue(
                    field.type,
                    @field(value, field.name),
                );
            }
            break :blk result;
        },
        .@"union" => |info| blk: {
            const Tag = info.tag_type.?;
            const active_tag = std.meta.activeTag(value);
            inline for (info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    break :blk @unionInit(
                        T,
                        field.name,
                        try canonicalValue(
                            field.type,
                            @field(value, field.name),
                        ),
                    );
                }
            }
            break :blk error.InvalidTag;
        },
        else => unreachable,
    };
}

/// Compare canonical value semantics without observing spare bounded storage.
pub fn eqlValue(comptime T: type, left: T, right: T) bool {
    comptime assertPortable(T);
    if (comptime maximumEncodedSize(T) == 0) return true;
    if (comptime isBytes(T) or isText(T)) return left.eql(&right);
    if (comptime isVector(T)) return left.eql(&right);
    return switch (@typeInfo(T)) {
        .void => true,
        .bool, .int => left == right,
        .@"enum" => blk: {
            validateEnumTag(T, left) catch break :blk false;
            validateEnumTag(T, right) catch break :blk false;
            break :blk left == right;
        },
        .array => |info| blk: {
            for (left, right) |left_item, right_item| {
                if (!eqlValue(info.child, left_item, right_item)) {
                    break :blk false;
                }
            }
            break :blk true;
        },
        .optional => |info| blk: {
            if (left) |left_payload| {
                const right_payload = right orelse break :blk false;
                break :blk eqlValue(info.child, left_payload, right_payload);
            }
            break :blk right == null;
        },
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| {
                if (!eqlValue(
                    field.type,
                    @field(left, field.name),
                    @field(right, field.name),
                )) break :blk false;
            }
            break :blk true;
        },
        .@"union" => |info| blk: {
            const Tag = info.tag_type.?;
            const active = std.meta.activeTag(left);
            if (active != std.meta.activeTag(right)) break :blk false;
            inline for (info.fields) |field| {
                if (active == @field(Tag, field.name)) {
                    break :blk eqlValue(
                        field.type,
                        @field(left, field.name),
                        @field(right, field.name),
                    );
                }
            }
            break :blk false;
        },
        else => unreachable,
    };
}

const SchemaHasher = std.crypto.hash.sha2.Sha256;

fn schemaHashU32(hasher: *SchemaHasher, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn schemaHashU64(hasher: *SchemaHasher, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn schemaHashBytes(hasher: *SchemaHasher, value: []const u8) void {
    schemaHashU64(hasher, @intCast(value.len));
    hasher.update(value);
}

fn hashSchemaInto(comptime T: type, hasher: *SchemaHasher) void {
    comptime assertPortable(T);
    if (comptime isBytes(T)) {
        schemaHashBytes(hasher, "bytes");
        schemaHashU64(hasher, T.maximum_length);
        return;
    }
    if (comptime isText(T)) {
        schemaHashBytes(hasher, "text");
        schemaHashU64(hasher, T.maximum_length);
        return;
    }
    if (comptime isVector(T)) {
        schemaHashBytes(hasher, "vector");
        schemaHashU64(hasher, T.maximum_length);
        hashSchemaInto(T.ElementType, hasher);
        return;
    }
    switch (@typeInfo(T)) {
        .void => schemaHashBytes(hasher, "unit"),
        .bool => schemaHashBytes(hasher, "bool"),
        .int => |info| {
            schemaHashBytes(hasher, "int");
            schemaHashU32(hasher, info.bits);
            schemaHashBytes(hasher, @tagName(info.signedness));
        },
        .array => |info| {
            schemaHashBytes(hasher, "array");
            schemaHashU64(hasher, info.len);
            hashSchemaInto(info.child, hasher);
        },
        .optional => |info| {
            schemaHashBytes(hasher, "optional");
            hashSchemaInto(info.child, hasher);
        },
        .@"enum" => |info| {
            schemaHashBytes(hasher, "enum");
            schemaHashU64(hasher, info.fields.len);
            inline for (info.fields) |field| {
                schemaHashU32(
                    hasher,
                    std.math.cast(u32, field.value) orelse unreachable,
                );
            }
        },
        .@"struct" => |info| {
            schemaHashBytes(hasher, "product");
            schemaHashU64(hasher, info.fields.len);
            inline for (info.fields) |field| {
                hashSchemaInto(field.type, hasher);
            }
        },
        .@"union" => |info| {
            schemaHashBytes(hasher, "sum");
            const Tag = info.tag_type.?;
            hashSchemaInto(Tag, hasher);
            schemaHashU64(hasher, info.fields.len);
            inline for (info.fields) |field| {
                schemaHashU32(
                    hasher,
                    @intFromEnum(@field(Tag, field.name)),
                );
                hashSchemaInto(field.type, hasher);
            }
        },
        else => unreachable,
    }
}

/// Hash one portable schema structurally, excluding Zig nominal type names.
pub fn schemaDigest(comptime T: type) [32]u8 {
    @setEvalBranchQuota(1_000_000);
    var hasher = SchemaHasher.init(.{});
    schemaHashBytes(&hasher, "boundary-portable-schema-v2");
    hashSchemaInto(T, &hasher);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn checkedAdd(left: usize, right: usize) Error!usize {
    return std.math.add(usize, left, right) catch error.SizeOverflow;
}

fn validateEnumTag(comptime T: type, value: T) Error!void {
    const raw = @intFromEnum(value);
    inline for (std.meta.fields(T)) |field| {
        if (raw == field.value) return;
    }
    return error.InvalidTag;
}

fn encodedSizePtr(comptime T: type, value: *const T) Error!usize {
    comptime assertPortable(T);
    if (comptime maximumEncodedSize(T) == 0) return 0;
    if (comptime isBytes(T)) {
        if (value.logical_length > T.maximum_length) return error.Malformed;
        return checkedAdd(4, @intCast(value.logical_length));
    }
    if (comptime isText(T)) {
        if (value.logical_length > T.maximum_length) return error.Malformed;
        _ = try value.slice();
        return checkedAdd(4, @intCast(value.logical_length));
    }
    if (comptime isVector(T)) {
        if (value.logical_length > T.maximum_length) return error.Malformed;
        if (comptime maximumEncodedSize(T.ElementType) == 0) return 4;
        var total: usize = 4;
        for (value.logicalSlice()) |*item| {
            total = try checkedAdd(total, try encodedSizePtr(T.ElementType, item));
        }
        return total;
    }
    return switch (@typeInfo(T)) {
        .void => 0,
        .bool => 1,
        .int => |info| @divExact(info.bits, 8),
        .array => |info| blk: {
            var total: usize = 0;
            for (value) |*item| total = try checkedAdd(
                total,
                try encodedSizePtr(info.child, item),
            );
            break :blk total;
        },
        .optional => |info| if (value.*) |*payload|
            checkedAdd(1, try encodedSizePtr(info.child, payload))
        else
            1,
        .@"enum" => blk: {
            try validateEnumTag(T, value.*);
            break :blk 4;
        },
        .@"struct" => |info| blk: {
            var total: usize = 0;
            inline for (info.fields) |field| {
                total = try checkedAdd(
                    total,
                    try encodedSizePtr(field.type, &@field(value.*, field.name)),
                );
            }
            break :blk total;
        },
        .@"union" => |info| blk: {
            const Tag = info.tag_type.?;
            const active = std.meta.activeTag(value.*);
            inline for (info.fields) |field| {
                if (active == @field(Tag, field.name)) {
                    break :blk try checkedAdd(
                        4,
                        try encodedSizePtr(field.type, &@field(value.*, field.name)),
                    );
                }
            }
            break :blk error.InvalidTag;
        },
        else => unreachable,
    };
}

/// Compute the exact canonical encoded size of one validated value.
pub fn encodedSize(comptime T: type, value: T) Error!usize {
    return encodedSizePtr(T, &value);
}

fn addMaximum(comptime left: usize, comptime right: usize) usize {
    if (right > std.math.maxInt(usize) - left) {
        @compileError("Boundary portable maximum encoded size overflows usize");
    }
    return left + right;
}

fn multiplyMaximum(comptime left: usize, comptime right: usize) usize {
    if (left != 0 and right > std.math.maxInt(usize) / left) {
        @compileError("Boundary portable maximum encoded size overflows usize");
    }
    return left * right;
}

/// Compute the minimum canonical encoded size from portable value semantics.
pub fn minimumEncodedSize(comptime T: type) usize {
    @setEvalBranchQuota(1_000_000);
    comptime assertPortable(T);
    if (comptime isBytes(T) or isText(T) or isVector(T)) return 4;
    return switch (@typeInfo(T)) {
        .void => 0,
        .bool => 1,
        .int => |info| @divExact(info.bits, 8),
        .array => |info| multiplyMaximum(
            info.len,
            minimumEncodedSize(info.child),
        ),
        .optional => 1,
        .@"enum" => 4,
        .@"struct" => |info| blk: {
            comptime var total: usize = 0;
            inline for (info.fields) |field| {
                total = addMaximum(total, minimumEncodedSize(field.type));
            }
            break :blk total;
        },
        .@"union" => |info| blk: {
            comptime var minimum: ?usize = null;
            inline for (info.fields) |field| {
                const field_minimum = comptime minimumEncodedSize(field.type);
                minimum = if (minimum) |current|
                    @min(current, field_minimum)
                else
                    field_minimum;
            }
            break :blk addMaximum(4, minimum orelse 0);
        },
        else => unreachable,
    };
}

/// Compute the maximum canonical encoded size from contract-bearing bounds.
pub fn maximumEncodedSize(comptime T: type) usize {
    @setEvalBranchQuota(1_000_000);
    comptime assertPortable(T);
    if (comptime isBytes(T) or isText(T)) {
        return addMaximum(4, T.maximum_length);
    }
    if (comptime isVector(T)) return addMaximum(
        4,
        multiplyMaximum(
            T.maximum_length,
            maximumEncodedSize(T.ElementType),
        ),
    );
    return switch (@typeInfo(T)) {
        .void => 0,
        .bool => 1,
        .int => |info| @divExact(info.bits, 8),
        .array => |info| multiplyMaximum(
            info.len,
            maximumEncodedSize(info.child),
        ),
        .optional => |info| addMaximum(1, maximumEncodedSize(info.child)),
        .@"enum" => 4,
        .@"struct" => |info| blk: {
            comptime var total: usize = 0;
            inline for (info.fields) |field| {
                total = comptime addMaximum(
                    total,
                    maximumEncodedSize(field.type),
                );
            }
            break :blk total;
        },
        .@"union" => |info| blk: {
            comptime var maximum: usize = 0;
            inline for (info.fields) |field| {
                const field_maximum =
                    comptime maximumEncodedSize(field.type);
                maximum = @max(maximum, field_maximum);
            }
            break :blk addMaximum(4, maximum);
        },
        else => unreachable,
    };
}

/// Report whether logical values of one type can have different encoded sizes.
pub fn hasVariableEncodedSize(comptime T: type) bool {
    return minimumEncodedSize(T) != maximumEncodedSize(T);
}

const Writer = struct {
    bytes: []u8,
    index: usize = 0,

    fn write(self: *Writer, value: []const u8) void {
        @memcpy(self.bytes[self.index..][0..value.len], value);
        self.index += value.len;
    }

    fn writeInt(self: *Writer, comptime T: type, value: T) void {
        var bytes: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        self.write(&bytes);
    }
};

const HashWriter = struct {
    hasher: *std.crypto.hash.sha2.Sha256,

    fn write(self: *HashWriter, value: []const u8) void {
        self.hasher.update(value);
    }

    fn writeInt(self: *HashWriter, comptime T: type, value: T) void {
        var bytes: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        self.write(&bytes);
    }
};

fn enumToU32(value: anytype) Error!u32 {
    try validateEnumTag(@TypeOf(value), value);
    return std.math.cast(u32, @intFromEnum(value)) orelse error.InvalidTag;
}

fn encodeInto(comptime T: type, value: *const T, writer: anytype) Error!void {
    if (comptime maximumEncodedSize(T) == 0) return;
    if (comptime isBytes(T)) {
        writer.writeInt(u32, value.logical_length);
        writer.write(try value.slice());
        return;
    }
    if (comptime isText(T)) {
        writer.writeInt(u32, value.logical_length);
        writer.write(try value.slice());
        return;
    }
    if (comptime isVector(T)) {
        writer.writeInt(u32, value.logical_length);
        if (comptime maximumEncodedSize(T.ElementType) == 0) return;
        for (value.logicalSlice()) |*item| {
            try encodeInto(T.ElementType, item, writer);
        }
        return;
    }
    switch (@typeInfo(T)) {
        .void => {},
        .bool => writer.write(&.{@intFromBool(value.*)}),
        .int => writer.writeInt(T, value.*),
        .array => |info| for (value) |*item| try encodeInto(info.child, item, writer),
        .optional => |info| {
            if (value.*) |*payload| {
                writer.write(&.{1});
                try encodeInto(info.child, payload, writer);
            } else {
                writer.write(&.{0});
            }
        },
        .@"enum" => writer.writeInt(u32, try enumToU32(value.*)),
        .@"struct" => |info| inline for (info.fields) |field| {
            try encodeInto(field.type, &@field(value.*, field.name), writer);
        },
        .@"union" => |info| {
            const Tag = info.tag_type.?;
            const active = std.meta.activeTag(value.*);
            writer.writeInt(u32, try enumToU32(active));
            inline for (info.fields) |field| {
                if (active == @field(Tag, field.name)) {
                    try encodeInto(field.type, &@field(value.*, field.name), writer);
                    return;
                }
            }
            return error.InvalidTag;
        },
        else => unreachable,
    }
}

/// Encode into caller-owned bytes only after exact size and value validation.
pub fn encode(comptime T: type, value: T, output: []u8) Error!usize {
    const required = try encodedSize(T, value);
    if (required > output.len) return error.CapacityExceeded;
    var writer: Writer = .{ .bytes = output[0..required] };
    try encodeInto(T, &value, &writer);
    return writer.index;
}

/// Add one value's exact canonical encoding to a SHA-256 stream.
pub fn updateCanonicalHash(
    comptime T: type,
    value: T,
    hasher: *std.crypto.hash.sha2.Sha256,
) Error!void {
    _ = try encodedSize(T, value);
    var writer: HashWriter = .{ .hasher = hasher };
    try encodeInto(T, &value, &writer);
}

const Reader = struct {
    bytes: []const u8,
    index: usize = 0,

    fn read(self: *Reader, length: usize) Error![]const u8 {
        const end = std.math.add(usize, self.index, length) catch
            return error.Malformed;
        if (end > self.bytes.len) return error.Malformed;
        const result = self.bytes[self.index..end];
        self.index = end;
        return result;
    }

    fn readInt(self: *Reader, comptime T: type) Error!T {
        const length = @divExact(@typeInfo(T).int.bits, 8);
        return std.mem.readInt(T, (try self.read(length))[0..length], .little);
    }
};

fn enumFromU32(comptime T: type, value: u32) Error!T {
    inline for (std.meta.fields(T)) |field| {
        const canonical = std.math.cast(u32, field.value) orelse unreachable;
        if (value == canonical) return @field(T, field.name);
    }
    return error.InvalidTag;
}

fn decodeFrom(comptime T: type, reader: *Reader) Error!T {
    if (comptime maximumEncodedSize(T) == 0) return std.mem.zeroes(T);
    if (comptime isBytes(T)) {
        const length = try reader.readInt(u32);
        if (length > T.maximum_length) return error.CapacityExceeded;
        return T.fromSlice(try reader.read(@intCast(length)));
    }
    if (comptime isText(T)) {
        const length = try reader.readInt(u32);
        if (length > T.maximum_length) return error.CapacityExceeded;
        return T.fromSlice(try reader.read(@intCast(length)));
    }
    if (comptime isVector(T)) {
        const length = try reader.readInt(u32);
        if (length > T.maximum_length) return error.CapacityExceeded;
        var result = T.empty();
        if (comptime maximumEncodedSize(T.ElementType) == 0) {
            result.logical_length = length;
            return result;
        }
        for (0..length) |_| try result.push(try decodeFrom(T.ElementType, reader));
        return result;
    }
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => switch ((try reader.read(1))[0]) {
            0 => false,
            1 => true,
            else => error.Malformed,
        },
        .int => try reader.readInt(T),
        .array => |info| blk: {
            var result: T = undefined;
            for (&result) |*item| item.* = try decodeFrom(info.child, reader);
            break :blk result;
        },
        .optional => |info| switch ((try reader.read(1))[0]) {
            0 => null,
            1 => try decodeFrom(info.child, reader),
            else => error.Malformed,
        },
        .@"enum" => try enumFromU32(T, try reader.readInt(u32)),
        .@"struct" => |info| blk: {
            var result: T = undefined;
            inline for (info.fields) |field| {
                @field(result, field.name) = try decodeFrom(field.type, reader);
            }
            break :blk result;
        },
        .@"union" => |info| blk: {
            const Tag = info.tag_type.?;
            const tag = try enumFromU32(Tag, try reader.readInt(u32));
            inline for (info.fields) |field| {
                if (tag == @field(Tag, field.name)) {
                    break :blk @unionInit(
                        T,
                        field.name,
                        try decodeFrom(field.type, reader),
                    );
                }
            }
            return error.InvalidTag;
        },
        else => unreachable,
    };
}

/// Return the canonical u32 constructor id of one tagged-union value.
pub fn unionTag(comptime T: type, value: T) Error!u32 {
    comptime assertPortable(T);
    const info = @typeInfo(T);
    if (info != .@"union" or info.@"union".tag_type == null) {
        @compileError("unionTag expects a portable tagged union");
    }
    return enumToU32(std.meta.activeTag(value));
}

/// Return the exact encoded size of the active tagged-union payload.
pub fn unionPayloadEncodedSize(comptime T: type, value: T) Error!usize {
    comptime assertPortable(T);
    const info = @typeInfo(T);
    if (info != .@"union" or info.@"union".tag_type == null) {
        @compileError("unionPayloadEncodedSize expects a portable tagged union");
    }
    const Tag = info.@"union".tag_type.?;
    const active = std.meta.activeTag(value);
    inline for (info.@"union".fields) |field| {
        if (active == @field(Tag, field.name)) {
            return encodedSizePtr(field.type, &@field(value, field.name));
        }
    }
    return error.InvalidTag;
}

/// Add only the active tagged-union payload's canonical bytes to a SHA-256
/// stream. The caller owns the separately framed constructor or site tag.
pub fn updateUnionPayloadCanonicalHash(
    comptime T: type,
    value: T,
    hasher: *std.crypto.hash.sha2.Sha256,
) Error!void {
    _ = try unionPayloadEncodedSize(T, value);
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type.?;
    const active = std.meta.activeTag(value);
    inline for (info.fields) |field| {
        if (active == @field(Tag, field.name)) {
            return updateCanonicalHash(
                field.type,
                @field(value, field.name),
                hasher,
            );
        }
    }
    return error.InvalidTag;
}

/// Return the maximum encoded environment bytes of any union constructor.
pub fn maximumUnionPayloadSize(comptime T: type) usize {
    comptime assertPortable(T);
    const info = @typeInfo(T);
    if (info != .@"union" or info.@"union".tag_type == null) {
        @compileError("maximumUnionPayloadSize expects a portable tagged union");
    }
    var maximum: usize = 0;
    inline for (info.@"union".fields) |field| {
        maximum = @max(maximum, maximumEncodedSize(field.type));
    }
    return maximum;
}

/// Encode only the active environment payload after validating its exact size.
pub fn encodeUnionPayload(
    comptime T: type,
    value: T,
    output: []u8,
) Error!usize {
    const required = try unionPayloadEncodedSize(T, value);
    if (required > output.len) return error.CapacityExceeded;
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type.?;
    const active = std.meta.activeTag(value);
    var writer: Writer = .{ .bytes = output[0..required] };
    inline for (info.fields) |field| {
        if (active == @field(Tag, field.name)) {
            try encodeInto(field.type, &@field(value, field.name), &writer);
            return writer.index;
        }
    }
    return error.InvalidTag;
}

/// Decode one constructor-local environment from its canonical constructor id.
pub fn decodeUnionPayload(
    comptime T: type,
    constructor_id: u32,
    bytes: []const u8,
) Error!T {
    comptime assertPortable(T);
    const info = @typeInfo(T);
    if (info != .@"union" or info.@"union".tag_type == null) {
        @compileError("decodeUnionPayload expects a portable tagged union");
    }
    const Tag = info.@"union".tag_type.?;
    const tag = try enumFromU32(Tag, constructor_id);
    var reader: Reader = .{ .bytes = bytes };
    inline for (info.@"union".fields) |field| {
        if (tag == @field(Tag, field.name)) {
            const result = @unionInit(
                T,
                field.name,
                try decodeFrom(field.type, &reader),
            );
            if (reader.index != bytes.len) return error.TrailingBytes;
            return result;
        }
    }
    return error.InvalidTag;
}

/// Decode exactly one canonical value and reject trailing bytes.
pub fn decodeExact(comptime T: type, bytes: []const u8) Error!T {
    comptime assertPortable(T);
    var reader: Reader = .{ .bytes = bytes };
    const result = try decodeFrom(T, &reader);
    if (reader.index != bytes.len) return error.TrailingBytes;
    return result;
}

test "Bytes encoding observes logical bytes and ignores spare capacity" {
    const Value = Bytes(16);
    var first = try Value.fromSlice("abc");
    var second = try Value.fromSlice("abc");
    first.storage[12] = 1;
    second.storage[12] = 255;

    var first_bytes: [maximumEncodedSize(Value)]u8 = undefined;
    var second_bytes: [maximumEncodedSize(Value)]u8 = undefined;
    const first_len = try encode(Value, first, &first_bytes);
    const second_len = try encode(Value, second, &second_bytes);
    try std.testing.expectEqual(first_len, second_len);
    try std.testing.expectEqualSlices(
        u8,
        first_bytes[0..first_len],
        second_bytes[0..second_len],
    );
}

test "canonicalValue recursively removes bounded spare storage" {
    const Item = struct {
        label: Text(4),
    };
    const Items = Vector(Item, 2);

    var label = try Text(4).fromSlice("ok");
    label.storage[3] = 0xff;
    var items = Items.empty();
    items.storage[0] = .{ .label = label };
    items.logical_length = 1;
    items.storage[1].label.storage[0] = 0xee;

    const canonical = try canonicalValue(Items, items);
    try std.testing.expectEqualStrings(
        "ok",
        try canonical.storage[0].label.slice(),
    );
    try std.testing.expectEqual(@as(u8, 0), canonical.storage[0].label.storage[3]);
    try std.testing.expectEqual(@as(u8, 0), canonical.storage[1].label.storage[0]);
}

test "Vector canonicalizes nested elements at every ingress" {
    const Tag = Text(2);
    const Tags = Vector(Tag, 1);
    const Item = struct {
        label: Text(4),
        tags: Tags,
    };
    const Items = Vector(Item, 1);

    var label = try Text(4).fromSlice("ok");
    label.storage[3] = 0xff;
    var tag = try Tag.fromSlice("x");
    tag.storage[1] = 0xee;
    var tags = Tags.empty();
    tags.storage[0] = tag;
    tags.logical_length = 1;
    const dirty: Item = .{ .label = label, .tags = tags };

    const from_slice = try Items.fromSlice(&.{dirty});
    try std.testing.expectEqual(@as(u8, 0), from_slice.storage[0].label.storage[3]);
    try std.testing.expectEqual(
        @as(u8, 0),
        from_slice.storage[0].tags.storage[0].storage[1],
    );

    var set_items = Items.empty();
    try set_items.push(canonicalDefaultValue(Item));
    try set_items.set(0, dirty);
    try std.testing.expectEqual(@as(u8, 0), set_items.storage[0].label.storage[3]);
    try std.testing.expectEqual(
        @as(u8, 0),
        set_items.storage[0].tags.storage[0].storage[1],
    );

    var pushed = Items.empty();
    try pushed.push(dirty);
    try std.testing.expectEqual(@as(u8, 0), pushed.storage[0].label.storage[3]);
    try std.testing.expectEqual(
        @as(u8, 0),
        pushed.storage[0].tags.storage[0].storage[1],
    );
}

test "Vector truncate canonicalizes removed tagged-union integer payloads" {
    const Element = union(enum) {
        count: u32,
        flag: bool,
    };
    const Items = Vector(Element, 2);

    var items = try Items.fromSlice(&.{
        Element{ .count = 42 },
        Element{ .flag = true },
    });
    items.truncate(1);

    try std.testing.expectEqual(@as(u32, 1), try items.len());
    try std.testing.expectEqualDeep(
        canonicalDefaultValue(Element),
        items.storage[1],
    );
}

test "Vector by-value egress rejects malformed nested elements" {
    const Item = Text(2);
    const Items = Vector(Item, 1);

    var malformed = Items.empty();
    malformed.storage[0].storage[0] = 0xff;
    malformed.storage[0].logical_length = 1;
    malformed.logical_length = 1;
    const before = malformed;

    try std.testing.expectError(error.InvalidUtf8, malformed.get(0));
    try std.testing.expectError(error.InvalidUtf8, malformed.pop());
    try std.testing.expectEqualDeep(before, malformed);

    var dirty = Items.empty();
    dirty.storage[0] = try Item.fromSlice("x");
    dirty.storage[0].storage[1] = 0xee;
    dirty.logical_length = 1;

    const observed = (try dirty.get(0)).?;
    try std.testing.expectEqualStrings("x", try observed.slice());
    try std.testing.expectEqual(@as(u8, 0), observed.storage[1]);

    const removed = (try dirty.pop()).?;
    try std.testing.expectEqualStrings("x", try removed.slice());
    try std.testing.expectEqual(@as(u8, 0), removed.storage[1]);
    try std.testing.expectEqualDeep(Items.empty(), dirty);
}

test "Bytes shrinking resets every vacated byte" {
    const Value = Bytes(8);
    var value = try Value.fromSlice("secrets!");

    value.truncate(3);
    try std.testing.expectEqualSlices(u8, "sec", try value.slice());
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 0 },
        value.storage[3..],
    );

    value.clear();
    try std.testing.expectEqual(@as(u32, 0), value.logical_length);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 0, 0, 0, 0 },
        &value.storage,
    );

    @memset(&value.storage, 0xa5);
    value.logical_length = 9;
    value.truncate(0);
    try std.testing.expectEqual(@as(u32, 0), value.logical_length);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 0, 0, 0, 0 },
        &value.storage,
    );
}

test "canonical equality ignores spare storage recursively" {
    const Item = struct {
        title: Text(16),
        count: u32,
    };
    const Items = Vector(Item, 2);

    var left_title = try Text(16).fromSlice("same");
    var right_title = try Text(16).fromSlice("same");
    left_title.storage[15] = 1;
    right_title.storage[15] = 255;

    var left = Items.empty();
    var right = Items.empty();
    try left.push(.{ .title = left_title, .count = 1 });
    try right.push(.{ .title = right_title, .count = 1 });
    left.storage[1] = .{
        .title = try Text(16).fromSlice("unused-left"),
        .count = 99,
    };
    right.storage[1] = .{
        .title = try Text(16).fromSlice("unused-right"),
        .count = 100,
    };

    try std.testing.expect(eqlValue(Items, left, right));
}

test "vector shrinking resets every vacated product slot" {
    const Item = struct {
        secret: u32,
        present: bool,
    };
    const Items = Vector(Item, 3);

    var items = try Items.fromSlice(&.{
        .{ .secret = 11, .present = true },
        .{ .secret = 22, .present = true },
        .{ .secret = 33, .present = true },
    });
    const popped = (try items.pop()).?;
    try std.testing.expectEqual(@as(u32, 33), popped.secret);
    try std.testing.expectEqual(@as(u32, 0), items.storage[2].secret);
    try std.testing.expect(!items.storage[2].present);

    items.truncate(1);
    try std.testing.expectEqual(@as(u32, 0), items.storage[1].secret);
    try std.testing.expect(!items.storage[1].present);

    items.clear();
    try std.testing.expectEqual(@as(u32, 0), items.storage[0].secret);
    try std.testing.expect(!items.storage[0].present);

    items.storage[2] = .{ .secret = 99, .present = true };
    items.logical_length = 4;
    items.truncate(0);
    try std.testing.expectEqual(@as(u32, 0), items.storage[2].secret);
    try std.testing.expect(!items.storage[2].present);
}

test "bounded defaults initialize all storage and malformed lengths stay total" {
    const Item = struct {
        title: Text(4),
        count: u32,
    };
    const Items = Vector(Item, 2);
    const bytes = Bytes(4).empty();
    const text = Text(4).empty();
    const items = Items.empty();

    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &bytes.storage);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &text.storage);
    try std.testing.expectEqual(@as(u32, 0), items.storage[0].count);
    try std.testing.expectEqual(@as(u32, 0), items.storage[1].count);
    try std.testing.expectEqual(
        @as(u32, 0),
        try items.storage[0].title.len(),
    );

    var malformed_bytes = bytes;
    malformed_bytes.logical_length = 5;
    try std.testing.expectError(error.Malformed, malformed_bytes.len());
    try std.testing.expectError(error.Malformed, malformed_bytes.slice());
    try std.testing.expectError(error.Malformed, malformed_bytes.get(0));
    try std.testing.expectError(
        error.Malformed,
        malformed_bytes.copyRange(1, 0, 1),
    );

    const valid_bytes = try Bytes(4).fromSlice("ab");
    try std.testing.expectEqual(@as(?u8, null), try valid_bytes.get(2));
    try std.testing.expectError(
        error.CapacityExceeded,
        valid_bytes.copyRange(1, 0, 3),
    );

    var malformed_text = text;
    malformed_text.logical_length = 5;
    try std.testing.expectError(error.Malformed, malformed_text.len());
    try std.testing.expectError(error.Malformed, malformed_text.slice());
    try std.testing.expectError(error.Malformed, malformed_text.append("x"));

    var malformed_items = items;
    malformed_items.logical_length = 3;
    try std.testing.expectError(error.Malformed, malformed_items.len());
    try std.testing.expectEqual(@as(usize, 0), malformed_items.logicalSlice().len);
    try std.testing.expectError(error.Malformed, malformed_items.get(0));
    try std.testing.expectError(
        error.Malformed,
        malformed_items.push(.{ .title = text, .count = 1 }),
    );
}

test "Text append rejects an invalid current prefix before mutation" {
    const Value = Text(4);
    var value = Value.empty();
    value.storage[0] = 0xff;
    value.logical_length = 1;
    const before = value;

    try std.testing.expectError(error.InvalidUtf8, value.slice());
    try std.testing.expectError(error.InvalidUtf8, value.append("a"));
    try std.testing.expectEqualDeep(before, value);
    try std.testing.expect(!eqlValue(Value, value, value));
}

test "Text copyRange validates the complete source before selecting" {
    const Value = Text(2);
    var malformed = Value.empty();
    malformed.storage = .{ 0xff, 'a' };
    malformed.logical_length = 2;

    try std.testing.expectError(
        error.InvalidUtf8,
        malformed.copyRange(1, 1, 2),
    );
}

test "Bytes and Text append preserve overlapping suffixes in both directions" {
    const TestBytes = Bytes(8);
    const TestText = Text(8);

    var backward_bytes = TestBytes.empty();
    @memcpy(backward_bytes.storage[0..6], "abcdef");
    backward_bytes.logical_length = 2;
    try backward_bytes.append(backward_bytes.storage[0..4]);
    try std.testing.expectEqualStrings("ababcd", try backward_bytes.slice());

    var forward_bytes = TestBytes.empty();
    @memcpy(forward_bytes.storage[0..6], "abcdef");
    forward_bytes.logical_length = 2;
    try forward_bytes.append(forward_bytes.storage[3..6]);
    try std.testing.expectEqualStrings("abdef", try forward_bytes.slice());

    var backward_text = TestText.empty();
    @memcpy(backward_text.storage[0..6], "abcdef");
    backward_text.logical_length = 2;
    try backward_text.append(backward_text.storage[0..4]);
    try std.testing.expectEqualStrings("ababcd", try backward_text.slice());

    var forward_text = TestText.empty();
    @memcpy(forward_text.storage[0..6], "abcdef");
    forward_text.logical_length = 2;
    try forward_text.append(forward_text.storage[3..6]);
    try std.testing.expectEqualStrings("abdef", try forward_text.slice());
}

test "bounded byte and text ordering rejects malformed operands" {
    const ByteValue = Bytes(2);
    const TextValue = Text(2);

    const byte_left = try ByteValue.fromSlice("a");
    const byte_right = try ByteValue.fromSlice("b");
    try std.testing.expectEqual(std.math.Order.lt, try byte_left.order(&byte_right));

    var malformed_bytes = byte_left;
    malformed_bytes.logical_length = 3;
    try std.testing.expectError(
        error.Malformed,
        malformed_bytes.order(&byte_right),
    );

    const text_left = try TextValue.fromSlice("a");
    const text_right = try TextValue.fromSlice("b");
    try std.testing.expectEqual(std.math.Order.lt, try text_left.order(&text_right));

    var malformed_text = text_left;
    malformed_text.logical_length = 3;
    try std.testing.expectError(
        error.Malformed,
        malformed_text.order(&text_right),
    );

    var invalid_utf8 = text_left;
    invalid_utf8.storage[0] = 0xff;
    try std.testing.expectError(
        error.InvalidUtf8,
        invalid_utf8.order(&text_right),
    );
}

test "generic vector equality rejects malformed logical lengths" {
    const Values = Vector(u8, 1);
    var left = Values.empty();
    var right = Values.empty();
    left.logical_length = 2;
    right.logical_length = 2;
    left.storage[0] = 1;
    right.storage[0] = 2;

    try std.testing.expect(!left.eql(&right));
    try std.testing.expect(!eqlValue(Values, left, right));
}

test "vector validates nested bounded values before mutation" {
    const SmallText = Text(1);
    const Values = Vector(SmallText, 1);
    var malformed = SmallText.empty();
    malformed.logical_length = 2;
    var values = Values.empty();

    try std.testing.expectError(error.Malformed, values.push(malformed));
    try std.testing.expectEqual(@as(u32, 0), try values.len());
}

test "portable schema identity is structural and capacity-bearing" {
    const First = struct {
        left: u32,
        right: Text(8),
    };
    const Renamed = struct {
        alpha: u32,
        beta: Text(8),
    };
    const Larger = struct {
        left: u32,
        right: Text(9),
    };

    try std.testing.expectEqualSlices(
        u8,
        &schemaDigest(First),
        &schemaDigest(Renamed),
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &schemaDigest(First),
        &schemaDigest(Larger),
    ));
}

test "all required scalar and algebraic forms round-trip canonically" {
    const Exhaustive = enum(u16) {
        zero = 0,
        high = 513,
    };
    const Sum = union(enum) {
        unit: void,
        signed: i16,
        text: Text(8),
    };
    const Value = struct {
        unit: void,
        boolean: bool,
        i8_value: i8,
        i16_value: i16,
        i32_value: i32,
        i64_value: i64,
        u8_value: u8,
        u16_value: u16,
        u32_value: u32,
        u64_value: u64,
        array: [3]u16,
        enumeration: Exhaustive,
        sum: Sum,
        optional: ?i32,
    };
    const value: Value = .{
        .unit = {},
        .boolean = true,
        .i8_value = -8,
        .i16_value = -16,
        .i32_value = -32,
        .i64_value = -64,
        .u8_value = 8,
        .u16_value = 16,
        .u32_value = 32,
        .u64_value = 64,
        .array = .{ 3, 5, 8 },
        .enumeration = .high,
        .sum = .{ .text = try Text(8).fromSlice("sum") },
        .optional = -7,
    };

    var bytes: [maximumEncodedSize(Value)]u8 = undefined;
    const length = try encode(Value, value, &bytes);
    const decoded = try decodeExact(Value, bytes[0..length]);
    try std.testing.expect(eqlValue(Value, value, decoded));
    try std.testing.expectEqual(@as(u16, 513), @intFromEnum(decoded.enumeration));
    try std.testing.expectEqualStrings("sum", try decoded.sum.text.slice());
}

test "Text mutation is UTF-8 checked and transactional on capacity overflow" {
    const Value = Text(4);
    const oversized_invalid = [_]u8{0xff} ** 5;
    try std.testing.expectError(
        error.CapacityExceeded,
        Value.fromSlice(&oversized_invalid),
    );

    var value = try Value.fromSlice("ab");
    try std.testing.expectError(error.CapacityExceeded, value.append("€"));
    try std.testing.expectEqualStrings("ab", try value.slice());
    const append_oversized_invalid = [_]u8{0xff} ** 3;
    try std.testing.expectError(
        error.CapacityExceeded,
        value.append(&append_oversized_invalid),
    );
    try std.testing.expectEqualStrings("ab", try value.slice());
    try std.testing.expectError(error.InvalidUtf8, value.append("\xff"));
    try std.testing.expectEqualStrings("ab", try value.slice());
    try value.appendScalar('¢');
    try std.testing.expectEqualStrings("ab¢", try value.slice());
}

test "vector of products and tagged sums round-trip canonically" {
    const Item = struct {
        title: Text(16),
        summary: Text(32),
    };
    const Choice = union(enum) {
        none,
        count: u32,
        note: Text(16),
    };
    const Result = struct {
        items: Vector(Item, 8),
        item_count: u32,
        limit: ?u16,
        choice: Choice,
    };

    var items = Vector(Item, 8).empty();
    try items.push(.{
        .title = try Text(16).fromSlice("One"),
        .summary = try Text(32).fromSlice("First summary"),
    });
    try items.push(.{
        .title = try Text(16).fromSlice("Two"),
        .summary = try Text(32).fromSlice("Second summary"),
    });
    const value: Result = .{
        .items = items,
        .item_count = 2,
        .limit = 8,
        .choice = .{ .note = try Text(16).fromSlice("ready") },
    };

    var bytes: [maximumEncodedSize(Result)]u8 = undefined;
    const length = try encode(Result, value, &bytes);
    const decoded = try decodeExact(Result, bytes[0..length]);
    try std.testing.expectEqual(@as(u32, 2), decoded.item_count);
    try std.testing.expectEqual(@as(?u16, 8), decoded.limit);
    try std.testing.expect(decoded.items.eql(&items));
    try std.testing.expectEqualStrings(
        "ready",
        try decoded.choice.note.slice(),
    );
}

test "malformed bounded lengths tags UTF-8 and trailing bytes fail closed" {
    const SmallText = Text(3);
    var excessive_length = [_]u8{ 4, 0, 0, 0, 'a', 'b', 'c', 'd' };
    try std.testing.expectError(
        error.CapacityExceeded,
        decodeExact(SmallText, &excessive_length),
    );

    const invalid_utf8 = [_]u8{ 1, 0, 0, 0, 0xff };
    try std.testing.expectError(
        error.InvalidUtf8,
        decodeExact(SmallText, &invalid_utf8),
    );
    try std.testing.expectError(error.Malformed, decodeExact(bool, &.{2}));
    try std.testing.expectError(
        error.TrailingBytes,
        decodeExact(u8, &.{ 7, 0 }),
    );

    const Exhaustive = enum {
        first,
        second,
    };
    try std.testing.expectError(
        error.InvalidTag,
        decodeExact(Exhaustive, &.{ 2, 0, 0, 0 }),
    );
    const Sum = union(enum) {
        empty: void,
        value: u8,
    };
    try std.testing.expectError(
        error.InvalidTag,
        decodeExact(Sum, &.{ 2, 0, 0, 0 }),
    );
}

test "invalid exhaustive enum tags fail before canonical write or hash" {
    const Exhaustive = enum(u8) {
        first,
        second,
    };
    const InvalidFactory = struct {
        fn make(raw: u8) Exhaustive {
            @setRuntimeSafety(false);
            return @enumFromInt(raw);
        }
    };
    const invalid = InvalidFactory.make(2);

    try std.testing.expect(!eqlValue(Exhaustive, invalid, invalid));
    try std.testing.expect(!eqlValue(
        [1]Exhaustive,
        .{invalid},
        .{invalid},
    ));
    try std.testing.expectError(error.InvalidTag, encodedSize(Exhaustive, invalid));
    var output = [_]u8{0xa5} ** 4;
    try std.testing.expectError(
        error.InvalidTag,
        encode(Exhaustive, invalid, &output),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 4),
        &output,
    );
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try std.testing.expectError(
        error.InvalidTag,
        updateCanonicalHash(Exhaustive, invalid, &hasher),
    );

    const Nested = struct { value: Exhaustive };
    try std.testing.expectError(
        error.InvalidTag,
        encodedSize(Nested, .{ .value = invalid }),
    );
}

test "invalid tagged union tags fail canonical sizing before mutation" {
    const Tag = enum(u8) {
        empty,
        other,
    };
    const Sum = union(Tag) {
        empty: void,
        other: void,
    };
    const InvalidFactory = struct {
        fn make(raw: u8) Sum {
            var value: Sum = .empty;
            @setRuntimeSafety(false);
            const tag: Tag = @enumFromInt(raw);
            const tag_pointer: *Tag = @ptrCast(&value);
            tag_pointer.* = tag;
            return value;
        }
    };
    const invalid = InvalidFactory.make(2);

    try std.testing.expect(!eqlValue(Sum, invalid, invalid));
    try std.testing.expectError(error.InvalidTag, encodedSize(Sum, invalid));
    var output = [_]u8{0xa5} ** maximumEncodedSize(Sum);
    try std.testing.expectError(error.InvalidTag, encode(Sum, invalid, &output));
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** maximumEncodedSize(Sum)),
        &output,
    );

    var values = Vector(Sum, 1).empty();
    try std.testing.expectError(error.InvalidTag, values.push(invalid));
    try std.testing.expectEqual(@as(u32, 0), try values.len());
    values.storage[0] = invalid;
    values.logical_length = 1;
    try std.testing.expect(!values.eql(&values));
}

test "zero-width vector codec and equality are constant in logical length" {
    const Values = Vector(void, 1_000_000);
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, Values.maximum_length, .little);
    const decoded = try decodeExact(Values, &bytes);
    try std.testing.expectEqual(@as(u32, 1_000_000), try decoded.len());
    try std.testing.expectEqual(@as(usize, 4), maximumEncodedSize(Values));
    try std.testing.expectEqual(@as(usize, 4), try encodedSize(Values, decoded));

    var encoded: [4]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try encode(Values, decoded, &encoded),
    );
    try std.testing.expectEqualSlices(u8, &bytes, &encoded);
    try std.testing.expect(decoded.eql(&decoded));
    try std.testing.expect(eqlValue(Values, decoded, decoded));

    const MaximumValues = Vector(void, std.math.maxInt(u32));
    var maximum = MaximumValues.empty();
    maximum.logical_length = std.math.maxInt(u32);
    maximum.truncate(std.math.maxInt(u32) - 1);
    try std.testing.expectEqual(
        @as(u32, std.math.maxInt(u32) - 1),
        try maximum.len(),
    );
    maximum.clear();
    try std.testing.expectEqual(@as(u32, 0), try maximum.len());
}

test "zero-width aggregate defaults are constant in aggregate width" {
    const Element = [10_000]void;
    const Values = Vector(Element, 1);
    var values = Values.empty();

    try values.push(undefined);
    try std.testing.expectEqual(@as(u32, 1), try values.len());
    values.clear();
    try std.testing.expectEqual(@as(u32, 0), try values.len());
}

test "nested zero-width portable values use one canonical constant-time quotient" {
    const EmptyProduct = struct {
        unit: void,
    };
    const Values = [1_000_000]EmptyProduct;
    const value: Values = undefined;

    try std.testing.expectEqual(@as(usize, 0), maximumEncodedSize(Values));
    try std.testing.expectEqual(@as(usize, 0), try encodedSize(Values, value));

    var bytes: [0]u8 = .{};
    try std.testing.expectEqual(
        @as(usize, 0),
        try encode(Values, value, &bytes),
    );
    const decoded = try decodeExact(Values, &bytes);
    try std.testing.expect(eqlValue(Values, value, decoded));
}

test "canonical hashing preserves large bounded aggregate bytes without recursive copies" {
    const Snapshot = struct {
        slot: u8,
        path: Text(256),
        digest: Text(64),
        contents: Text(16 * 1024),
    };
    const WorkingSet = struct {
        documents: Vector(Snapshot, 9),
        latest: ?Snapshot,
        baseline_failed: bool,
        mutation_count: u32,
    };

    var value: WorkingSet = .{
        .documents = Vector(Snapshot, 9).empty(),
        .latest = null,
        .baseline_failed = true,
        .mutation_count = 4,
    };
    try value.documents.push(.{
        .slot = 2,
        .path = try Text(256).fromSlice("src/methods.mjs"),
        .digest = try Text(64).fromSlice(
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        ),
        .contents = try Text(16 * 1024).fromSlice("export const ready = true;\n"),
    });
    value.latest = (try value.documents.get(0)).?;

    const encoded_length = try encodedSize(WorkingSet, value);
    const encoded = try std.testing.allocator.alloc(u8, encoded_length);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqual(encoded_length, try encode(WorkingSet, value, encoded));

    var expected_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    expected_hasher.update(encoded);
    var expected: [32]u8 = undefined;
    expected_hasher.final(&expected);

    var actual_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try updateCanonicalHash(WorkingSet, value, &actual_hasher);
    var actual: [32]u8 = undefined;
    actual_hasher.final(&actual);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "Research Digest bounds are representable without target-width values" {
    const ResearchItem = struct {
        title: Text(256),
        summary: Text(1024),
    };
    const ResearchResponse = struct {
        items: Vector(ResearchItem, 8),
    };
    const DigestResult = struct {
        digest: Text(8192),
        item_count: u32,
    };
    comptime {
        assertPortable(ResearchResponse);
        assertPortable(DigestResult);
        if (maximumEncodedSize(ResearchResponse) == 0) @compileError("invalid bound");
        if (maximumEncodedSize(DigestResult) == 0) @compileError("invalid bound");
    }
}
