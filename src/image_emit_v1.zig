const dynamic_value_v1 = @import("dynamic_value_v1");
const image_v1 = @import("image_v1");
const portable_value = @import("portable_value");
const program_semantics_v1 = @import("program_semantics_v1");
const std = @import("std");

const maximum_nodes = 1024;
const schema_bucket_count = maximum_nodes * 2;
const maximum_bytes = 1 << 20;
pub const maximum_image_bytes = 16 << 20;

pub fn assertSchemaMemberCount(comptime count: usize) void {
    if (count > dynamic_value_v1.maximum_schema_members) {
        @compileError("BPI1 schema members exceed validator capacity");
    }
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn residualSite(comptime Reified: type, comptime ordinal: usize) type {
    const source = Reified.residual_effects.residual_to_source[ordinal];
    if (hasDeclSafe(Reified.Body, "effect_morphisms")) {
        inline for (Reified.Body.effect_morphisms) |Morphism| {
            if (Morphism.source_id == source) return Morphism.Target;
        }
    }
    return Reified.Body.effect_sites[source];
}

fn hashBytes(hasher: anytype, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hasher.update(&length);
    hasher.update(bytes);
}

fn effectDigest(
    comptime Site: type,
    comptime ordinal: ?usize,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashBytes(
        &hasher,
        if (ordinal == null)
            "boundary-effect-site-semantic-contract-v1"
        else
            "boundary-effect-site-contract-v1",
    );
    if (ordinal) |value| {
        var encoded: [4]u8 = undefined;
        std.mem.writeInt(u32, &encoded, value, .little);
        hasher.update(&encoded);
    }
    hashBytes(&hasher, Site.semantic_identity);
    hasher.update(&portable_value.schemaDigest(Site.Payload));
    hasher.update(&portable_value.schemaDigest(Site.Resume));
    hashBytes(&hasher, "single-resume");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub const EnvelopeOptions = struct {
    program_transition_digest: [32]u8,
    maximum_kernel_scratch_bytes: u64,
    maximum_single_value_bytes: u32,
};

/// Compose ten canonical section payloads into the exact BPI1 container.
pub fn Envelope(
    comptime options: EnvelopeOptions,
    comptime sections: [image_v1.section_count][]const u8,
) type {
    const total_length = comptime blk: {
        var total: usize = image_v1.header_length;
        for (sections) |section| total += section.len;
        if (total > maximum_image_bytes) {
            @compileError("BPI1 image exceeds the default 16 MiB profile");
        }
        break :blk total;
    };
    const encoded = comptime blk: {
        var bytes: [total_length]u8 = undefined;
        @memset(bytes[0..image_v1.header_length], 0);
        @memcpy(bytes[0..image_v1.magic.len], &image_v1.magic);
        writeAt(u16, &bytes, 8, image_v1.image_format_version);
        writeAt(u16, &bytes, 10, image_v1.evaluator_semantics_version);
        writeAt(u32, &bytes, 16, image_v1.header_length);
        writeAt(u64, &bytes, 24, total_length);
        writeAt(u32, &bytes, 20, image_v1.section_count);
        @memcpy(bytes[32..64], &options.program_transition_digest);
        writeAt(u64, &bytes, 64, options.maximum_kernel_scratch_bytes);
        writeAt(u32, &bytes, 72, options.maximum_single_value_bytes);
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
    bytes: [maximum_bytes]u8 = undefined,
    offsets: [maximum_nodes]u32 = undefined,
    lengths: [maximum_nodes]u32 = undefined,
    hashes: [maximum_nodes]u64 = undefined,
    buckets: [schema_bucket_count]?u32 =
        [_]?u32{null} ** schema_bucket_count,
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
                assertSchemaMemberCount(info.fields.len);
                var words: [1 + info.fields.len]u32 = undefined;
                words[0] = castU32(info.fields.len);
                inline for (info.fields, 0..) |field, index| {
                    words[index + 1] = std.math.cast(u32, field.value) orelse
                        unreachable;
                }
                break :blk self.appendRecord(.@"enum", &words);
            },
            .@"struct" => |info| blk: {
                assertSchemaMemberCount(info.fields.len);
                var words: [1 + info.fields.len]u32 = undefined;
                words[0] = castU32(info.fields.len);
                inline for (info.fields, 0..) |field, index| {
                    words[index + 1] = self.intern(field.type);
                }
                break :blk self.appendRecord(.product, &words);
            },
            .@"union" => |info| blk: {
                assertSchemaMemberCount(info.fields.len);
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

        const record = self.bytes[start..self.length];
        const hash = recordHash(record);
        var bucket: usize = @intCast(hash & (schema_bucket_count - 1));
        while (self.buckets[bucket]) |existing_id| {
            const existing: usize = @intCast(existing_id);
            if (self.hashes[existing] == hash and
                record.len == self.lengths[existing])
            {
                const offset: usize = self.offsets[existing];
                if (std.mem.eql(
                    u8,
                    self.bytes[offset .. offset + self.lengths[existing]],
                    record,
                )) {
                    self.length = start;
                    return existing_id;
                }
            }
            bucket = (bucket + 1) & (schema_bucket_count - 1);
        }
        if (self.node_count == maximum_nodes) {
            @compileError("BPI1 schema node count exceeds implementation limit");
        }
        self.offsets[self.node_count] = @intCast(start);
        self.lengths[self.node_count] = @intCast(record_length);
        self.hashes[self.node_count] = hash;
        self.buckets[bucket] = @intCast(self.node_count);
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
            @compileError("BPI1 schema section exceeds implementation limit");
        }
    }
};

fn recordHash(bytes: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

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

fn maximumSchemaNodeEncodedSize(comptime T: type) usize {
    portable_value.assertPortable(T);
    var maximum = portable_value.maximumEncodedSize(T);
    if (comptime portable_value.isVectorType(T)) {
        return @max(maximum, maximumSchemaNodeEncodedSize(T.ElementType));
    }
    if (comptime portable_value.isBytesType(T) or
        portable_value.isTextType(T))
    {
        return maximum;
    }
    switch (@typeInfo(T)) {
        .array => |info| maximum = @max(
            maximum,
            maximumSchemaNodeEncodedSize(info.child),
        ),
        .optional => |info| maximum = @max(
            maximum,
            maximumSchemaNodeEncodedSize(info.child),
        ),
        .@"struct" => |info| inline for (info.fields) |field| {
            maximum = @max(
                maximum,
                maximumSchemaNodeEncodedSize(field.type),
            );
        },
        .@"union" => |info| {
            maximum = @max(
                maximum,
                maximumSchemaNodeEncodedSize(info.tag_type.?),
            );
            inline for (info.fields) |field| {
                maximum = @max(
                    maximum,
                    maximumSchemaNodeEncodedSize(field.type),
                );
            }
        },
        else => {},
    }
    return maximum;
}

/// Emit all schemas in the normative BPI1 root traversal order for one
/// Reified Program.
pub fn ProgramSchemaSet(comptime Reified: type) type {
    const effect_count = Reified.residual_effects.residual_count;
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
            const Site = residualSite(Reified, ordinal);
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
    const largest_value = comptime blk: {
        var maximum: usize = 0;
        for (roots) |Root| {
            maximum = @max(
                maximum,
                maximumSchemaNodeEncodedSize(Root),
            );
        }
        break :blk maximum;
    };
    return struct {
        pub const bytes = Set.bytes;
        pub const root_ids = Set.root_ids;
        pub const node_count = Set.node_count;
        pub const maximum_single_value_bytes: u32 = castU32(largest_value);
        pub const initial_args_root_index: usize = 0;
        pub const result_root_index: usize = 1;
        pub const failure_root_index: usize = 2;
        pub const effect_root_start: usize = 3;
        pub const value_root_start: usize = effect_root_start + effect_count * 2;
        pub const function_root_start: usize = value_root_start + value_count;

        pub fn schemaIdForValueType(comptime value_type: anytype) u32 {
            for (0..value_count) |dense_value| {
                const source_value = Reified.semantic_canonicalization
                    .value_dense_to_source[dense_value];
                if (Reified.control.value_types[source_value].eql(value_type)) {
                    return root_ids[value_root_start + dense_value];
                }
            }
            @compileError("BPI1 schema roots omit a reachable value type");
        }
    };
}

pub fn ProgramImageParts(
    comptime Reified: type,
) type {
    const Schemas = ProgramSchemaSet(Reified);
    const Roots = ProgramRoots(Reified, Schemas);
    const Failures = ProgramFailures(Reified);
    const Constants = ProgramConstants(Reified, Schemas);
    const Effects = ProgramEffects(Reified, Schemas);
    const Values = ProgramValues(Reified, Schemas);
    const Functions = ProgramFunctions(Reified, Schemas);
    const Segments = ProgramSegments(Reified, Schemas, Constants);
    const Constructors = ProgramConstructors(Reified, Schemas);
    const Transitions = ProgramEntryTransitions(Reified);
    const sections = [image_v1.section_count][]const u8{
        &Roots.bytes,
        &Schemas.bytes,
        &Failures.bytes,
        &Constants.bytes,
        &Effects.bytes,
        &Values.bytes,
        &Functions.bytes,
        &Segments.bytes,
        &Constructors.bytes,
        &Transitions.bytes,
    };
    const scratch = comptime conservativeKernelScratch(Reified, Schemas);
    const total_length = comptime blk: {
        var total: usize = image_v1.header_length;
        for (sections) |section| total += section.len;
        if (total > maximum_image_bytes) {
            @compileError("BPI1 image exceeds the default 16 MiB profile");
        }
        break :blk total;
    };
    return struct {
        pub const section_bytes = sections;
        pub const byte_length: u64 = total_length;
        pub const program_transition_digest = Reified.program_transition_digest;
        pub const maximum_kernel_scratch_bytes = scratch;
        pub const maximum_single_value_bytes = Schemas.maximum_single_value_bytes;
    };
}

pub fn ProgramImage(
    comptime Reified: type,
) type {
    comptime {
        if (!failureCatalogAdmitted(std.meta.fields(Reified.Body.Failure).len)) {
            @compileError("BPI1 failure variants exceed validator capacity");
        }
    }
    const encoded = comptime blk: {
        var storage: [maximum_image_bytes]u8 = undefined;
        const length = encodeProgramImage(Reified, &storage) catch |err| {
            @compileError(
                "canonical BPI1 encoding failed: " ++ @errorName(err),
            );
        };
        break :blk storage[0..length].*;
    };
    const artifact_digest = comptime blk: {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&encoded, &digest, .{});
        break :blk digest;
    };
    return struct {
        pub const format_version = image_v1.image_format_version;
        pub const bytes = encoded;
        pub const byte_length: u64 = encoded.len;
        pub const program_transition_digest = Reified.program_transition_digest;
        pub const artifact_sha256 = artifact_digest;
        pub const maximum_kernel_scratch_bytes = std.mem.readInt(
            u64,
            encoded[64..][0..8],
            .little,
        );
        pub const maximum_single_value_bytes = std.mem.readInt(
            u32,
            encoded[72..][0..4],
            .little,
        );
    };
}

pub const RuntimeError = error{
    OutputCapacity,
    SectionCapacity,
    CatalogLimit,
    ImageLimit,
};

const RuntimeWriter = struct {
    bytes: []u8,
    cursor: usize,

    fn append(
        self: *RuntimeWriter,
        comptime T: type,
        value: anytype,
    ) RuntimeError!void {
        if (self.cursor > self.bytes.len -| @sizeOf(T)) {
            return error.OutputCapacity;
        }
        writeAt(T, self.bytes, self.cursor, value);
        self.cursor += @sizeOf(T);
    }

    fn copy(self: *RuntimeWriter, value: []const u8) RuntimeError!void {
        if (value.len > self.bytes.len -| self.cursor) {
            return error.OutputCapacity;
        }
        @memcpy(self.bytes[self.cursor..][0..value.len], value);
        self.cursor += value.len;
    }

    fn patch(self: *RuntimeWriter, comptime T: type, offset: usize, value: anytype) void {
        writeAt(T, self.bytes, offset, value);
    }
};

fn RuntimeSchemas(comptime Reified: type) type {
    @setEvalBranchQuota(10_000_000);
    const effect_count = Reified.residual_effects.residual_count;
    const value_count = Reified.semantic_canonicalization.value_count;
    const function_count = Reified.semantic_canonicalization.function_count;
    const root_count = 3 + effect_count * 2 + value_count + function_count;
    const RootTypes = comptime blk: {
        var result: [root_count]type = undefined;
        var index: usize = 0;
        result[index] = Reified.Body.InitialArgs;
        index += 1;
        result[index] = Reified.Body.Result;
        index += 1;
        result[index] = Reified.Body.Failure;
        index += 1;
        for (0..effect_count) |ordinal| {
            const Site = residualSite(Reified, ordinal);
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
    return struct {
        const Self = @This();
        pub const initial_args_root_index: usize = 0;
        pub const result_root_index: usize = 1;
        pub const failure_root_index: usize = 2;
        pub const effect_root_start: usize = 3;
        pub const value_root_start: usize = effect_root_start + effect_count * 2;
        pub const function_root_start: usize = value_root_start + value_count;

        root_ids: [root_count]u32,
        offsets: [maximum_nodes]u32,
        lengths: [maximum_nodes]u32,
        hashes: [maximum_nodes]u64,
        buckets: [schema_bucket_count]?u32,
        node_count: usize,

        fn build(writer: *RuntimeWriter) RuntimeError!Self {
            var self: Self = .{
                .root_ids = undefined,
                .offsets = undefined,
                .lengths = undefined,
                .hashes = undefined,
                .buckets = [_]?u32{null} ** schema_bucket_count,
                .node_count = 0,
            };
            const count_offset = writer.cursor;
            try writer.append(u32, 0);
            inline for (RootTypes, 0..) |Root, index| {
                self.root_ids[index] = try self.intern(writer, Root);
            }
            writer.patch(u32, count_offset, self.node_count);
            return self;
        }

        fn intern(
            self: *Self,
            writer: *RuntimeWriter,
            comptime T: type,
        ) RuntimeError!u32 {
            comptime portable_value.assertPortable(T);
            if (comptime portable_value.isVectorType(T)) {
                const child = try self.intern(writer, T.ElementType);
                return self.appendRecord(writer, .vector, &.{
                    castU32(T.maximum_length),
                    child,
                });
            }
            if (comptime portable_value.isBytesType(T)) {
                return self.appendRecord(
                    writer,
                    .bytes,
                    &.{castU32(T.maximum_length)},
                );
            }
            if (comptime portable_value.isTextType(T)) {
                return self.appendRecord(
                    writer,
                    .text,
                    &.{castU32(T.maximum_length)},
                );
            }
            return switch (@typeInfo(T)) {
                .void => self.appendRecord(writer, .unit, &.{}),
                .bool => self.appendRecord(writer, .bool, &.{}),
                .int => self.appendRecord(writer, integerKind(T), &.{}),
                .array => |info| blk: {
                    const child = try self.intern(writer, info.child);
                    break :blk self.appendRecord(writer, .array, &.{
                        castU32(info.len),
                        child,
                    });
                },
                .optional => |info| blk: {
                    const child = try self.intern(writer, info.child);
                    break :blk self.appendRecord(writer, .optional, &.{child});
                },
                .@"enum" => |info| blk: {
                    assertSchemaMemberCount(info.fields.len);
                    var words: [1 + info.fields.len]u32 = undefined;
                    words[0] = castU32(info.fields.len);
                    inline for (info.fields, 0..) |field, index| {
                        words[index + 1] = std.math.cast(u32, field.value) orelse
                            unreachable;
                    }
                    break :blk self.appendRecord(writer, .@"enum", &words);
                },
                .@"struct" => |info| blk: {
                    assertSchemaMemberCount(info.fields.len);
                    var words: [1 + info.fields.len]u32 = undefined;
                    words[0] = castU32(info.fields.len);
                    inline for (info.fields, 0..) |field, index| {
                        words[index + 1] = try self.intern(writer, field.type);
                    }
                    break :blk self.appendRecord(writer, .product, &words);
                },
                .@"union" => |info| blk: {
                    assertSchemaMemberCount(info.fields.len);
                    const Tag = info.tag_type.?;
                    var words: [2 + info.fields.len * 2]u32 = undefined;
                    words[0] = try self.intern(writer, Tag);
                    words[1] = castU32(info.fields.len);
                    inline for (info.fields, 0..) |field, index| {
                        words[2 + index * 2] = @intFromEnum(
                            @field(Tag, field.name),
                        );
                        words[3 + index * 2] = try self.intern(
                            writer,
                            field.type,
                        );
                    }
                    break :blk self.appendRecord(writer, .sum, &words);
                },
                else => unreachable,
            };
        }

        fn appendRecord(
            self: *Self,
            writer: *RuntimeWriter,
            kind: dynamic_value_v1.Kind,
            words: []const u32,
        ) RuntimeError!u32 {
            const record_length = 8 + words.len * 4;
            const maximum_record_length = 8 +
                (2 + dynamic_value_v1.maximum_schema_members * 2) * 4;
            var candidate: [maximum_record_length]u8 = undefined;
            writeAt(u32, &candidate, 0, record_length);
            writeAt(u8, &candidate, 4, @intFromEnum(kind));
            writeAt(u8, &candidate, 5, 0);
            writeAt(u16, &candidate, 6, 0);
            for (words, 0..) |word, index| {
                writeAt(u32, &candidate, 8 + index * 4, word);
            }
            const record = candidate[0..record_length];
            const hash = recordHash(record);
            var bucket: usize = @intCast(hash & (schema_bucket_count - 1));
            while (self.buckets[bucket]) |existing_id| {
                const existing: usize = @intCast(existing_id);
                if (self.hashes[existing] == hash and
                    record.len == self.lengths[existing])
                {
                    const offset: usize = self.offsets[existing];
                    if (std.mem.eql(
                        u8,
                        writer.bytes[offset .. offset + self.lengths[existing]],
                        record,
                    )) {
                        return existing_id;
                    }
                }
                bucket = (bucket + 1) & (schema_bucket_count - 1);
            }
            if (self.node_count == maximum_nodes) return error.SectionCapacity;
            const start = writer.cursor;
            try writer.copy(record);
            self.offsets[self.node_count] = @intCast(start);
            self.lengths[self.node_count] = @intCast(record_length);
            self.hashes[self.node_count] = hash;
            self.buckets[bucket] = @intCast(self.node_count);
            defer self.node_count += 1;
            return @intCast(self.node_count);
        }

        fn schemaIdForValueType(
            self: *const Self,
            comptime value_type: anytype,
        ) u32 {
            inline for (0..value_count) |dense_value| {
                const source_value = Reified.semantic_canonicalization
                    .value_dense_to_source[dense_value];
                if (Reified.control.value_types[source_value].eql(value_type)) {
                    return self.root_ids[value_root_start + dense_value];
                }
            }
            unreachable;
        }
    };
}

fn RuntimeConstants(comptime Reified: type) type {
    const source_count = if (@hasDecl(Reified.Body, "constants"))
        Reified.Body.constants.len
    else
        0;
    return struct {
        const Self = @This();
        source_to_canonical: [source_count]?u32,

        fn build(
            schemas_state: *const RuntimeSchemas(Reified),
            writer: *RuntimeWriter,
        ) RuntimeError!Self {
            var self: Self = .{
                .source_to_canonical = [_]?u32{null} ** source_count,
            };
            var offsets: [Reified.compiler_limits.maximum_values]u32 = undefined;
            var lengths: [Reified.compiler_limits.maximum_values]u32 = undefined;
            var schemas: [Reified.compiler_limits.maximum_values]u32 = undefined;
            var count: usize = 0;
            const count_offset = writer.cursor;
            try writer.append(u32, 0);
            inline for (0..Reified.semantic_canonicalization.block_count) |dense_block| {
                const source_block = Reified.semantic_canonicalization
                    .block_dense_to_source[dense_block];
                const block = comptime Reified.control.blocks[source_block];
                inline for (block.instructions) |instruction| {
                    const constant_index = switch (instruction.operation) {
                        .constant => |index| index,
                        else => continue,
                    };
                    const value = Reified.Body.constants[constant_index];
                    const Value = @TypeOf(value);
                    const Canonical = EncodedPortableValue(Value, value);
                    const value_length = Canonical.bytes.len;
                    const dense_value = Reified.semantic_canonicalization.valueId(
                        instruction.result,
                    );
                    const schema_id = schemas_state.root_ids[
                        RuntimeSchemas(Reified).value_root_start + dense_value
                    ];
                    const canonical = &Canonical.bytes;
                    var canonical_id: ?u32 = null;
                    for (0..count) |existing| {
                        if (schemas[existing] != schema_id or
                            lengths[existing] != value_length)
                        {
                            continue;
                        }
                        const offset: usize = offsets[existing];
                        if (std.mem.eql(
                            u8,
                            writer.bytes[offset .. offset + value_length],
                            canonical,
                        )) {
                            canonical_id = @intCast(existing);
                            break;
                        }
                    }
                    if (canonical_id) |id| {
                        self.source_to_canonical[constant_index] = id;
                    } else {
                        try writer.append(u32, schema_id);
                        try writer.append(u32, value_length);
                        offsets[count] = @intCast(writer.cursor);
                        lengths[count] = @intCast(value_length);
                        schemas[count] = schema_id;
                        self.source_to_canonical[constant_index] = @intCast(count);
                        try writer.copy(canonical);
                        count += 1;
                    }
                }
            }
            writer.patch(u32, count_offset, count);
            return self;
        }
    };
}

fn EncodedPortableValue(comptime T: type, comptime value: T) type {
    const length = portable_value.encodedSize(T, value) catch unreachable;
    const encoded = comptime blk: {
        var bytes: [length]u8 = undefined;
        const written = portable_value.encode(T, value, &bytes) catch unreachable;
        if (written != length) @compileError("portable value encoded length drifted");
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

/// Encode the canonical BPI1 into caller-owned storage without materializing
/// any complete BPI section as a comptime byte array.
pub fn encodeProgramImage(
    comptime Reified: type,
    output: []u8,
) RuntimeError!usize {
    @setEvalBranchQuota(100_000_000);
    const maximum_single_value_bytes = comptime runtimeMaximumSingleValueBytes(Reified);
    if (output.len < image_v1.header_length) return error.OutputCapacity;
    var writer: RuntimeWriter = .{
        .bytes = output,
        .cursor = image_v1.header_length,
    };
    var offsets: [image_v1.section_count]u64 = undefined;
    var lengths: [image_v1.section_count]u64 = undefined;

    offsets[0] = writer.cursor;
    if (writer.cursor > output.len -| 28) return error.OutputCapacity;
    writer.cursor += 28;
    lengths[0] = 28;

    offsets[1] = writer.cursor;
    var schemas = try RuntimeSchemas(Reified).build(&writer);
    lengths[1] = writer.cursor - offsets[1];
    if (lengths[1] > maximum_bytes) return error.SectionCapacity;
    writeProgramRootsRuntime(
        Reified,
        &schemas,
        output[@intCast(offsets[0])..][0..28],
    );

    offsets[2] = writer.cursor;
    try writeProgramFailuresRuntime(Reified, &writer);
    lengths[2] = writer.cursor - offsets[2];

    offsets[3] = writer.cursor;
    var constants = try RuntimeConstants(Reified).build(&schemas, &writer);
    lengths[3] = writer.cursor - offsets[3];
    if (lengths[3] > maximum_bytes) return error.SectionCapacity;

    offsets[4] = writer.cursor;
    try writeProgramEffectsRuntime(Reified, &schemas, &writer);
    lengths[4] = writer.cursor - offsets[4];

    offsets[5] = writer.cursor;
    try writeProgramValuesRuntime(Reified, &schemas, &writer);
    lengths[5] = writer.cursor - offsets[5];

    offsets[6] = writer.cursor;
    try writeProgramFunctionsRuntime(Reified, &schemas, &writer);
    lengths[6] = writer.cursor - offsets[6];

    offsets[7] = writer.cursor;
    try writeProgramSegmentsRuntime(Reified, &schemas, &constants, &writer);
    lengths[7] = writer.cursor - offsets[7];
    if (lengths[7] > maximum_bytes) return error.SectionCapacity;

    offsets[8] = writer.cursor;
    try writeProgramConstructorsRuntime(Reified, &schemas, &writer);
    lengths[8] = writer.cursor - offsets[8];
    if (lengths[8] > maximum_bytes) return error.SectionCapacity;

    offsets[9] = writer.cursor;
    try writeProgramTransitionsRuntime(Reified, &writer);
    lengths[9] = writer.cursor - offsets[9];

    @memset(output[0..image_v1.header_length], 0);
    @memcpy(output[0..image_v1.magic.len], &image_v1.magic);
    writeAt(u16, output, 8, image_v1.image_format_version);
    writeAt(u16, output, 10, image_v1.evaluator_semantics_version);
    writeAt(u32, output, 16, image_v1.header_length);
    writeAt(u32, output, 20, image_v1.section_count);
    writeAt(u64, output, 24, writer.cursor);
    @memcpy(output[32..64], &Reified.program_transition_digest);
    writeAt(
        u64,
        output,
        64,
        conservativeKernelScratchRuntime(
            Reified,
            schemas.node_count,
            maximum_single_value_bytes,
        ),
    );
    writeAt(
        u32,
        output,
        72,
        maximum_single_value_bytes,
    );
    for (offsets, lengths, 0..) |offset, length, index| {
        const descriptor = image_v1.fixed_prefix_length +
            index * image_v1.section_descriptor_length;
        writeAt(u16, output, descriptor, index + 1);
        writeAt(u16, output, descriptor + 2, 1);
        writeAt(u64, output, descriptor + 8, offset);
        writeAt(u64, output, descriptor + 16, length);
    }
    if (writer.cursor > maximum_image_bytes) return error.ImageLimit;
    return writer.cursor;
}

fn writeProgramRootsRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    output: *[28]u8,
) void {
    @memset(output, 0);
    const entry = Reified.control.blocks[Reified.control.entry];
    writeAt(
        u32,
        output,
        0,
        schemas.root_ids[RuntimeSchemas(Reified).initial_args_root_index],
    );
    writeAt(
        u32,
        output,
        4,
        schemas.root_ids[RuntimeSchemas(Reified).result_root_index],
    );
    writeAt(
        u32,
        output,
        8,
        schemas.root_ids[RuntimeSchemas(Reified).failure_root_index],
    );
    writeAt(
        u16,
        output,
        12,
        Reified.semantic_canonicalization.blockId(Reified.control.entry),
    );
    writeAt(u16, output, 14, entry.parameters.len);
    writeAt(u32, output, 16, Reified.initial_constructor_id);
    writeAt(
        u16,
        output,
        24,
        if (entry.parameters.len == 0)
            std.math.maxInt(u16)
        else
            Reified.semantic_canonicalization.valueId(entry.parameters[0]),
    );
}

fn writeProgramFailuresRuntime(
    comptime Reified: type,
    writer: *RuntimeWriter,
) RuntimeError!void {
    const fields = std.meta.fields(Reified.Body.Failure);
    if (!failureCatalogAdmitted(fields.len)) return error.CatalogLimit;
    try writer.append(u32, fields.len);
    inline for (fields) |field| {
        try writer.append(u32, field.value);
        try writer.append(u32, field.name.len);
        try writer.copy(field.name);
    }
}

fn writeProgramEffectsRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    writer: *RuntimeWriter,
) RuntimeError!void {
    const count = Reified.residual_effects.residual_count;
    try writer.append(u32, count);
    inline for (0..count) |ordinal| {
        const Site = residualSite(Reified, ordinal);
        try writer.append(u32, ordinal);
        try writer.append(u32, Site.semantic_identity.len);
        try writer.copy(Site.semantic_identity);
        try writer.append(
            u32,
            schemas.root_ids[
                RuntimeSchemas(Reified).effect_root_start + ordinal * 2
            ],
        );
        try writer.append(
            u32,
            schemas.root_ids[
                RuntimeSchemas(Reified).effect_root_start + ordinal * 2 + 1
            ],
        );
        try writer.append(u8, 0);
        try writer.append(u8, 0);
        try writer.append(u16, 0);
        const semantic_digest = effectDigest(Site, null);
        const ordinal_digest = effectDigest(Site, ordinal);
        try writer.copy(&semantic_digest);
        try writer.copy(&ordinal_digest);
    }
}

fn writeProgramValuesRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    writer: *RuntimeWriter,
) RuntimeError!void {
    const count = Reified.semantic_canonicalization.value_count;
    try writer.append(u32, count);
    inline for (0..count) |dense_value| {
        try writer.append(
            u32,
            schemas.root_ids[
                RuntimeSchemas(Reified).value_root_start + dense_value
            ],
        );
    }
}

fn writeProgramFunctionsRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    writer: *RuntimeWriter,
) RuntimeError!void {
    const count = Reified.semantic_canonicalization.function_count;
    try writer.append(u32, count);
    inline for (0..count) |dense_function| {
        const source_function = Reified.semantic_canonicalization
            .function_dense_to_source[dense_function];
        const entry = if (Reified.control.functions.len == 0)
            Reified.control.entry
        else
            Reified.control.functions[source_function].entry;
        try writer.append(u16, dense_function);
        try writer.append(
            u16,
            Reified.semantic_canonicalization.blockId(entry),
        );
        try writer.append(
            u32,
            schemas.root_ids[
                RuntimeSchemas(Reified).function_root_start + dense_function
            ],
        );
    }
}

fn writeProgramTransitionsRuntime(
    comptime Reified: type,
    writer: *RuntimeWriter,
) RuntimeError!void {
    const count = Reified.rnf_value.entry_transition_count;
    const Record = struct {
        source: u16,
        edge: u8,
        target: u16,
        constructor: u32,
    };
    var records: [count]Record = undefined;
    inline for (0..count) |index| {
        const transition = Reified.rnf_value.entry_transitions[index];
        records[index] = .{
            .source = Reified.semantic_canonicalization.blockId(
                transition.source_block,
            ),
            .edge = @intFromEnum(program_semantics_v1.wireIncomingEdge(
                transition.edge_kind,
            )),
            .target = Reified.semantic_canonicalization.blockId(
                transition.target_block,
            ),
            .constructor = transition.constructor_id,
        };
    }
    if (count > 1) {
        for (1..count) |index| {
            var position = index;
            while (position > 0 and transitionLess(
                records[position],
                records[position - 1],
            )) : (position -= 1) {
                const previous = records[position - 1];
                records[position - 1] = records[position];
                records[position] = previous;
            }
        }
    }
    try writer.append(u32, count);
    for (records) |record| {
        try writer.append(u16, record.source);
        try writer.append(u8, record.edge);
        try writer.append(u8, 0);
        try writer.append(u16, record.target);
        try writer.append(u16, 0);
        try writer.append(u32, record.constructor);
    }
}

fn conservativeKernelScratchRuntime(
    comptime Reified: type,
    schema_node_count: usize,
    maximum_single_value_bytes: u32,
) u64 {
    const value_bytes = comptime blk: {
        var total: u64 = 0;
        for (0..Reified.semantic_canonicalization.value_count) |dense_value| {
            const source_value = Reified.semantic_canonicalization
                .value_dense_to_source[dense_value];
            const Value = Reified.portableType(
                Reified.control.value_types[source_value],
            );
            total = std.math.add(
                u64,
                total,
                portable_value.maximumEncodedSize(Value),
            ) catch @compileError("BPI1 scratch requirement overflows u64");
        }
        break :blk total;
    };
    const value_metadata = std.math.mul(
        u64,
        Reified.semantic_canonicalization.value_count,
        16,
    ) catch unreachable;
    const schema_stack = std.math.mul(u64, schema_node_count, 16) catch
        unreachable;
    const framing = std.math.add(
        u64,
        std.math.mul(u64, maximum_single_value_bytes, 3) catch unreachable,
        176,
    ) catch unreachable;
    return value_bytes +| value_metadata +| schema_stack +| framing;
}

fn writeProgramConstructorsRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    writer: *RuntimeWriter,
) RuntimeError!void {
    try writer.append(u32, Reified.rnf_value.constructor_count);
    inline for (0..Reified.rnf_value.constructor_count) |constructor_index| {
        const constructor = comptime Reified.rnf_value.constructors[constructor_index];
        const start = writer.cursor;
        try writer.append(u32, 0);
        try writer.append(u32, constructor.id);
        try writer.append(
            u8,
            @intFromEnum(imageConstructorKind(constructor.kind)),
        );
        try writer.append(
            u8,
            @intFromEnum(program_semantics_v1.wireConstructorOrigin(
                constructor.origin,
            )),
        );
        try writer.append(
            u16,
            @intFromBool(constructor.has_activation_context),
        );
        try writer.append(
            u16,
            Reified.semantic_canonicalization.blockId(
                constructor.source_block,
            ),
        );
        try writer.append(
            u16,
            if (constructor.resume_target) |target|
                Reified.semantic_canonicalization.blockId(target)
            else
                std.math.maxInt(u16),
        );
        try writer.append(u16, constructor.activation_len);
        try writer.append(u16, constructor.environment_len);
        try writer.append(u16, constructor.invariant_len);
        try writer.append(u16, 0);
        inline for (0..constructor.activation_len) |field_index| {
            const field = constructor.activation[field_index];
            try appendEnvironmentFieldRuntime(
                Reified,
                schemas,
                field,
                writer,
            );
        }
        inline for (0..constructor.environment_len) |field_index| {
            const field = constructor.environment[field_index];
            try appendEnvironmentFieldRuntime(
                Reified,
                schemas,
                field,
                writer,
            );
        }
        inline for (0..constructor.invariant_len) |invariant_index| {
            const invariant = constructor.invariants[invariant_index];
            try appendInvariant(
                Reified,
                invariant,
                writer,
            );
        }
        writer.patch(u32, start, writer.cursor - start);
    }
}

fn appendEnvironmentFieldRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    comptime field: anytype,
    writer: *RuntimeWriter,
) RuntimeError!void {
    const dense_value = Reified.semantic_canonicalization.valueId(field.value);
    try writer.append(u16, dense_value);
    try writer.append(u16, 0);
    try writer.append(
        u32,
        schemas.root_ids[RuntimeSchemas(Reified).value_root_start + dense_value],
    );
}

fn writeProgramSegmentsRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    constants: *const RuntimeConstants(Reified),
    writer: *RuntimeWriter,
) RuntimeError!void {
    try writer.append(u32, Reified.semantic_canonicalization.block_count);
    inline for (0..Reified.semantic_canonicalization.block_count) |dense_block| {
        const source_block_id = Reified.semantic_canonicalization
            .block_dense_to_source[dense_block];
        const block = comptime Reified.control.blocks[source_block_id];
        const record_start = writer.cursor;
        try writer.append(u32, 0);
        try writer.append(u16, dense_block);
        try writer.append(
            u16,
            Reified.semantic_canonicalization.functionId(block.function_id),
        );
        try writer.append(
            u8,
            if (dense_block == Reified.semantic_canonicalization.blockId(
                Reified.control.entry,
            )) 0 else blockRoleTag(block.role),
        );
        try writer.append(u8, 0);
        try writer.append(u16, block.parameters.len);
        try writer.append(u32, block.instructions.len);
        inline for (block.parameters) |parameter| {
            try writer.append(
                u16,
                Reified.semantic_canonicalization.valueId(parameter),
            );
        }
        inline for (block.instructions) |instruction| {
            const instruction_start = writer.cursor;
            try writer.append(u32, 0);
            try writer.append(u8, instructionKindTag(instruction.operation));
            try writer.append(u8, 0);
            try writer.append(
                u16,
                program_semantics_v1.wireTag(instruction.operation),
            );
            try writer.append(
                u16,
                Reified.semantic_canonicalization.valueId(instruction.result),
            );
            try writer.append(u16, instruction.operands.len);
            try writer.append(
                u32,
                instructionImmediateRuntime(instruction.operation, constants),
            );
            inline for (instruction.operands) |operand| {
                try writer.append(
                    u16,
                    Reified.semantic_canonicalization.valueId(operand),
                );
            }
            writer.patch(
                u32,
                instruction_start,
                writer.cursor - instruction_start,
            );
        }
        try appendTerminatorRuntime(
            Reified,
            schemas,
            block.terminator,
            writer,
        );
        writer.patch(u32, record_start, writer.cursor - record_start);
    }
}

fn appendTerminatorRuntime(
    comptime Reified: type,
    schemas: *const RuntimeSchemas(Reified),
    comptime terminator: anytype,
    writer: *RuntimeWriter,
) RuntimeError!void {
    const start = writer.cursor;
    try writer.append(u32, 0);
    try writer.append(
        u8,
        @intFromEnum(program_semantics_v1.wireTerminator(terminator)),
    );
    try writer.append(u8, 0);
    try writer.append(u16, 0);
    switch (terminator) {
        .jump => |edge| try appendEdgeRuntime(Reified, edge, writer),
        .branch => |branch| {
            try writer.append(
                u16,
                Reified.semantic_canonicalization.valueId(branch.condition),
            );
            try writer.append(u16, 0);
            try appendEdgeRuntime(Reified, branch.then_edge, writer);
            try appendEdgeRuntime(Reified, branch.else_edge, writer);
        },
        .@"suspend" => |suspension| {
            try writer.append(
                u8,
                @intFromEnum(imageSuspensionKind(suspension.kind)),
            );
            try writer.append(u8, 0);
            try writer.append(u16, 0);
            try writer.append(
                u32,
                if (suspension.site_id) |site|
                    Reified.residual_effects.source_to_residual[site] orelse
                        std.math.maxInt(u32)
                else
                    std.math.maxInt(u32),
            );
            try writer.append(
                u16,
                if (suspension.callee_function) |function|
                    Reified.semantic_canonicalization.functionId(function)
                else
                    std.math.maxInt(u16),
            );
            try writer.append(u16, suspension.request_values.len);
            inline for (suspension.request_values) |value| {
                try writer.append(
                    u16,
                    Reified.semantic_canonicalization.valueId(value),
                );
            }
            try writer.append(u8, @intFromBool(suspension.callee != null));
            try writer.append(u8, 0);
            try writer.append(u16, 0);
            if (suspension.callee) |edge| {
                try appendEdgeRuntime(Reified, edge, writer);
            }
            try appendEdgeRuntime(Reified, suspension.continuation, writer);
            try writer.append(
                u32,
                if (suspension.resume_type) |resume_type|
                    schemas.schemaIdForValueType(resume_type)
                else
                    std.math.maxInt(u32),
            );
        },
        .return_value => |value| {
            try writer.append(u8, @intFromBool(value != null));
            try writer.append(u8, 0);
            try writer.append(
                u16,
                if (value) |id|
                    Reified.semantic_canonicalization.valueId(id)
                else
                    std.math.maxInt(u16),
            );
        },
        .return_to_caller, .fail_value => |value| {
            try writer.append(
                u16,
                Reified.semantic_canonicalization.valueId(value),
            );
            try writer.append(u16, 0);
        },
        .fail => |failure| try writer.append(u32, failure),
    }
    writer.patch(u32, start, writer.cursor - start);
}

fn appendEdgeRuntime(
    comptime Reified: type,
    comptime edge: anytype,
    writer: *RuntimeWriter,
) RuntimeError!void {
    try writer.append(
        u16,
        Reified.semantic_canonicalization.blockId(edge.target),
    );
    try writer.append(u16, edge.arguments.len);
    inline for (edge.arguments) |argument| {
        switch (argument) {
            .value => |value| {
                try writer.append(u8, 0);
                try writer.append(u8, 0);
                try writer.append(
                    u16,
                    Reified.semantic_canonicalization.valueId(value),
                );
            },
            .@"resume" => {
                try writer.append(u8, 1);
                try writer.append(u8, 0);
                try writer.append(u16, std.math.maxInt(u16));
            },
        }
    }
}

fn instructionImmediateRuntime(
    comptime operation: anytype,
    constants: anytype,
) u32 {
    return switch (operation) {
        .constant => |source| constants.source_to_canonical[source].?,
        .product_extract,
        .product_replace,
        .sum_construct,
        .sum_tag_is,
        .sum_extract,
        => |index| index,
        else => 0,
    };
}

fn runtimeMaximumSingleValueBytes(comptime Reified: type) u32 {
    var maximum: usize = 0;
    maximum = @max(
        maximum,
        maximumSchemaNodeEncodedSize(Reified.Body.InitialArgs),
    );
    maximum = @max(
        maximum,
        maximumSchemaNodeEncodedSize(Reified.Body.Result),
    );
    maximum = @max(
        maximum,
        maximumSchemaNodeEncodedSize(Reified.Body.Failure),
    );
    for (0..Reified.residual_effects.residual_count) |ordinal| {
        const Site = residualSite(Reified, ordinal);
        maximum = @max(maximum, maximumSchemaNodeEncodedSize(Site.Payload));
        maximum = @max(maximum, maximumSchemaNodeEncodedSize(Site.Resume));
    }
    for (0..Reified.semantic_canonicalization.value_count) |dense_value| {
        const source_value = Reified.semantic_canonicalization
            .value_dense_to_source[dense_value];
        maximum = @max(
            maximum,
            maximumSchemaNodeEncodedSize(Reified.portableType(
                Reified.control.value_types[source_value],
            )),
        );
    }
    for (0..Reified.semantic_canonicalization.function_count) |dense_function| {
        const source_function = Reified.semantic_canonicalization
            .function_dense_to_source[dense_function];
        const result_type = if (Reified.control.functions.len == 0)
            Reified.control.result_type
        else
            Reified.control.functions[source_function].result_type;
        maximum = @max(
            maximum,
            maximumSchemaNodeEncodedSize(Reified.portableType(result_type)),
        );
    }
    return castU32(maximum);
}

fn conservativeKernelScratch(comptime Reified: type, comptime Schemas: type) u64 {
    var value_bytes: u64 = 0;
    for (0..Reified.semantic_canonicalization.value_count) |dense_value| {
        const source_value = Reified.semantic_canonicalization
            .value_dense_to_source[dense_value];
        const Value = Reified.portableType(
            Reified.control.value_types[source_value],
        );
        value_bytes = std.math.add(
            u64,
            value_bytes,
            portable_value.maximumEncodedSize(Value),
        ) catch @compileError("BPI1 scratch requirement overflows u64");
    }
    const value_metadata = std.math.mul(
        u64,
        Reified.semantic_canonicalization.value_count,
        16,
    ) catch @compileError("BPI1 scratch requirement overflows u64");
    const schema_stack = std.math.mul(u64, Schemas.node_count, 16) catch
        @compileError("BPI1 scratch requirement overflows u64");
    const framing = std.math.add(
        u64,
        std.math.mul(
            u64,
            Schemas.maximum_single_value_bytes,
            3,
        ) catch @compileError("BPI1 scratch requirement overflows u64"),
        176,
    ) catch @compileError("BPI1 scratch requirement overflows u64");
    return value_bytes +| value_metadata +| schema_stack +| framing;
}

/// Emit the exact BPI1 roots section for one Reified Program.
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
    if (!failureCatalogAdmitted(fields.len)) {
        @compileError("BPI1 failure variants exceed validator capacity");
    }
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

fn failureCatalogAdmitted(count: usize) bool {
    return count <= image_v1.maximum_catalog_entries;
}

pub fn ProgramEffects(
    comptime Reified: type,
    comptime Schemas: type,
) type {
    const count = Reified.residual_effects.residual_count;
    const length = comptime blk: {
        var total: usize = 4;
        for (0..count) |ordinal| {
            total += 84 + residualSite(Reified, ordinal).semantic_identity.len;
        }
        break :blk total;
    };
    const encoded = comptime blk: {
        var bytes: [length]u8 = [_]u8{0} ** length;
        writeAt(u32, &bytes, 0, count);
        var cursor: usize = 4;
        for (0..count) |ordinal| {
            const Site = residualSite(Reified, ordinal);
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
            @memcpy(
                bytes[cursor..][0..32],
                &effectDigest(Site, null),
            );
            cursor += 32;
            @memcpy(
                bytes[cursor..][0..32],
                &effectDigest(Site, ordinal),
            );
            cursor += 32;
        }
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

pub fn ProgramConstants(comptime Reified: type, comptime Schemas: type) type {
    const source_constant_count = if (@hasDecl(Reified.Body, "constants"))
        Reified.Body.constants.len
    else
        0;
    const built = comptime blk: {
        var bytes: [maximum_bytes]u8 = undefined;
        var offsets: [Reified.compiler_limits.maximum_values]u32 = undefined;
        var lengths: [Reified.compiler_limits.maximum_values]u32 = undefined;
        var schemas: [Reified.compiler_limits.maximum_values]u32 = undefined;
        var count: usize = 0;
        var source_to_canonical = [_]?u32{null} ** source_constant_count;
        var cursor: usize = 4;
        for (0..Reified.semantic_canonicalization.block_count) |dense_block| {
            const source_block = Reified.semantic_canonicalization
                .block_dense_to_source[dense_block];
            for (Reified.control.blocks[source_block].instructions) |instruction| {
                const constant_index = switch (instruction.operation) {
                    .constant => |index| index,
                    else => continue,
                };
                const value = Reified.Body.constants[constant_index];
                const Value = @TypeOf(value);
                const value_length = portable_value.encodedSize(
                    Value,
                    value,
                ) catch unreachable;
                const dense_value = Reified.semantic_canonicalization.valueId(
                    instruction.result,
                );
                const schema_id = Schemas.root_ids[
                    Schemas.value_root_start + dense_value
                ];
                var canonical: [portable_value.maximumEncodedSize(Value)]u8 =
                    undefined;
                const encoded_length = portable_value.encode(
                    Value,
                    value,
                    &canonical,
                ) catch unreachable;
                std.debug.assert(encoded_length == value_length);
                var canonical_id: ?u32 = null;
                for (0..count) |existing| {
                    if (schemas[existing] != schema_id or
                        lengths[existing] != value_length)
                    {
                        continue;
                    }
                    const offset: usize = offsets[existing];
                    if (std.mem.eql(
                        u8,
                        bytes[offset .. offset + value_length],
                        canonical[0..value_length],
                    )) {
                        canonical_id = @intCast(existing);
                        break;
                    }
                }
                if (canonical_id) |id| {
                    source_to_canonical[constant_index] = id;
                    continue;
                }
                if (cursor + 8 + value_length > bytes.len) {
                    @compileError("BPI1 constants exceed implementation limit");
                }
                writeAt(u32, &bytes, cursor, schema_id);
                cursor += 4;
                writeAt(u32, &bytes, cursor, value_length);
                cursor += 4;
                offsets[count] = @intCast(cursor);
                lengths[count] = @intCast(value_length);
                schemas[count] = schema_id;
                source_to_canonical[constant_index] = @intCast(count);
                @memcpy(bytes[cursor..][0..value_length], canonical[0..value_length]);
                cursor += value_length;
                count += 1;
            }
        }
        writeAt(u32, &bytes, 0, count);
        break :blk .{
            .bytes = bytes,
            .length = cursor,
            .count = count,
            .source_to_canonical = source_to_canonical,
        };
    };
    const exact = built.bytes[0..built.length].*;
    return struct {
        pub const bytes = exact;
        pub const constant_count: u32 = @intCast(built.count);
        pub const source_to_canonical = built.source_to_canonical;
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

pub fn ProgramSegments(
    comptime Reified: type,
    comptime Schemas: type,
    comptime Constants: type,
) type {
    const built = comptime blk: {
        var bytes: [maximum_bytes]u8 = undefined;
        var cursor: usize = 4;
        writeAt(
            u32,
            &bytes,
            0,
            Reified.semantic_canonicalization.block_count,
        );
        for (0..Reified.semantic_canonicalization.block_count) |dense_block| {
            const source_block_id = Reified.semantic_canonicalization
                .block_dense_to_source[dense_block];
            const block = Reified.control.blocks[source_block_id];
            const record_start = cursor;
            appendInt(u32, &bytes, &cursor, 0);
            appendInt(u16, &bytes, &cursor, dense_block);
            appendInt(
                u16,
                &bytes,
                &cursor,
                Reified.semantic_canonicalization.functionId(block.function_id),
            );
            appendInt(
                u8,
                &bytes,
                &cursor,
                if (dense_block == Reified.semantic_canonicalization.blockId(
                    Reified.control.entry,
                )) 0 else blockRoleTag(block.role),
            );
            appendInt(u8, &bytes, &cursor, 0);
            appendInt(u16, &bytes, &cursor, block.parameters.len);
            appendInt(u32, &bytes, &cursor, block.instructions.len);
            for (block.parameters) |parameter| {
                appendInt(
                    u16,
                    &bytes,
                    &cursor,
                    Reified.semantic_canonicalization.valueId(parameter),
                );
            }
            for (block.instructions) |instruction| {
                const instruction_start = cursor;
                appendInt(u32, &bytes, &cursor, 0);
                appendInt(
                    u8,
                    &bytes,
                    &cursor,
                    instructionKindTag(instruction.operation),
                );
                appendInt(u8, &bytes, &cursor, 0);
                appendInt(
                    u16,
                    &bytes,
                    &cursor,
                    program_semantics_v1.wireTag(instruction.operation),
                );
                appendInt(
                    u16,
                    &bytes,
                    &cursor,
                    Reified.semantic_canonicalization.valueId(instruction.result),
                );
                appendInt(u16, &bytes, &cursor, instruction.operands.len);
                appendInt(
                    u32,
                    &bytes,
                    &cursor,
                    instructionImmediate(instruction.operation, Constants),
                );
                for (instruction.operands) |operand| {
                    appendInt(
                        u16,
                        &bytes,
                        &cursor,
                        Reified.semantic_canonicalization.valueId(operand),
                    );
                }
                writeAt(
                    u32,
                    &bytes,
                    instruction_start,
                    cursor - instruction_start,
                );
            }
            appendTerminator(
                Reified,
                Schemas,
                block.terminator,
                &bytes,
                &cursor,
            );
            writeAt(u32, &bytes, record_start, cursor - record_start);
        }
        break :blk .{ .bytes = bytes, .length = cursor };
    };
    const exact = built.bytes[0..built.length].*;
    return struct {
        pub const bytes = exact;
    };
}

pub fn ProgramEntryTransitions(comptime Reified: type) type {
    const count = Reified.rnf_value.entry_transition_count;
    const Record = struct {
        source: u16,
        edge: u8,
        target: u16,
        constructor: u32,
    };
    const records = comptime blk: {
        var result: [count]Record = undefined;
        for (Reified.rnf_value.entryTransitionSlice(), 0..) |transition, index| {
            result[index] = .{
                .source = Reified.semantic_canonicalization.blockId(
                    transition.source_block,
                ),
                .edge = @intFromEnum(program_semantics_v1.wireIncomingEdge(
                    transition.edge_kind,
                )),
                .target = Reified.semantic_canonicalization.blockId(
                    transition.target_block,
                ),
                .constructor = transition.constructor_id,
            };
        }
        if (count > 1) {
            for (1..count) |index| {
                var position = index;
                while (position > 0 and transitionLess(
                    result[position],
                    result[position - 1],
                )) : (position -= 1) {
                    const previous = result[position - 1];
                    result[position - 1] = result[position];
                    result[position] = previous;
                }
            }
        }
        break :blk result;
    };
    const encoded = comptime blk: {
        var bytes: [4 + count * 12]u8 = [_]u8{0} ** (4 + count * 12);
        writeAt(u32, &bytes, 0, count);
        for (records, 0..) |record, index| {
            const offset = 4 + index * 12;
            writeAt(u16, &bytes, offset, record.source);
            writeAt(u8, &bytes, offset + 2, record.edge);
            writeAt(u16, &bytes, offset + 4, record.target);
            writeAt(u32, &bytes, offset + 8, record.constructor);
        }
        break :blk bytes;
    };
    return struct {
        pub const bytes = encoded;
    };
}

pub fn ProgramConstructors(comptime Reified: type, comptime Schemas: type) type {
    const built = comptime blk: {
        var bytes: [maximum_bytes]u8 = undefined;
        var cursor: usize = 4;
        writeAt(u32, &bytes, 0, Reified.rnf_value.constructor_count);
        for (Reified.rnf_value.constructorSlice()) |constructor| {
            const start = cursor;
            appendInt(u32, &bytes, &cursor, 0);
            appendInt(u32, &bytes, &cursor, constructor.id);
            appendInt(
                u8,
                &bytes,
                &cursor,
                @intFromEnum(imageConstructorKind(constructor.kind)),
            );
            appendInt(
                u8,
                &bytes,
                &cursor,
                @intFromEnum(program_semantics_v1.wireConstructorOrigin(
                    constructor.origin,
                )),
            );
            appendInt(
                u16,
                &bytes,
                &cursor,
                @intFromBool(constructor.has_activation_context),
            );
            appendInt(
                u16,
                &bytes,
                &cursor,
                Reified.semantic_canonicalization.blockId(
                    constructor.source_block,
                ),
            );
            appendInt(
                u16,
                &bytes,
                &cursor,
                if (constructor.resume_target) |target|
                    Reified.semantic_canonicalization.blockId(target)
                else
                    std.math.maxInt(u16),
            );
            appendInt(u16, &bytes, &cursor, constructor.activation_len);
            appendInt(u16, &bytes, &cursor, constructor.environment_len);
            appendInt(u16, &bytes, &cursor, constructor.invariant_len);
            appendInt(u16, &bytes, &cursor, 0);
            for (constructor.activationFields()) |field| {
                appendEnvironmentField(Reified, Schemas, field, &bytes, &cursor);
            }
            for (constructor.environmentFields()) |field| {
                appendEnvironmentField(Reified, Schemas, field, &bytes, &cursor);
            }
            for (constructor.invariantTerms()) |invariant| {
                var writer: RuntimeWriter = .{ .bytes = &bytes, .cursor = cursor };
                appendInvariant(Reified, invariant, &writer) catch unreachable;
                cursor = writer.cursor;
            }
            writeAt(u32, &bytes, start, cursor - start);
        }
        break :blk .{ .bytes = bytes, .length = cursor };
    };
    const exact = built.bytes[0..built.length].*;
    return struct {
        pub const bytes = exact;
    };
}

fn appendEnvironmentField(
    comptime Reified: type,
    comptime Schemas: type,
    comptime field: anytype,
    bytes: []u8,
    cursor: *usize,
) void {
    const dense_value = Reified.semantic_canonicalization.valueId(field.value);
    appendInt(u16, bytes, cursor, dense_value);
    appendInt(u16, bytes, cursor, 0);
    appendInt(
        u32,
        bytes,
        cursor,
        Schemas.root_ids[Schemas.value_root_start + dense_value],
    );
}

fn appendInvariant(
    comptime Reified: type,
    comptime invariant: anytype,
    writer: *RuntimeWriter,
) RuntimeError!void {
    const start = writer.cursor;
    try writer.append(u32, 0);
    try writer.append(
        u8,
        @intFromEnum(program_semantics_v1.wireInvariant(invariant)),
    );
    try writer.append(u8, 0);
    try writer.append(u16, 0);
    switch (invariant) {
        .boolean => |term| {
            try appendValueId(Reified, term.value, writer);
            try writer.append(u8, @intFromBool(term.expected));
            try writer.append(u8, 0);
        },
        .boolean_copy => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.source, writer);
        },
        .value_copy => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.source, writer);
        },
        .boolean_not => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.operand, writer);
        },
        .boolean_binary => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.left, writer);
            try appendValueId(Reified, term.right, writer);
            try writer.append(u8, booleanBinaryTag(term.operation));
            try writer.append(u8, 0);
        },
        .boolean_select => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.condition, writer);
            try appendValueId(Reified, term.then_value, writer);
            try appendValueId(Reified, term.else_value, writer);
        },
        .value_select => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.condition, writer);
            try appendValueId(Reified, term.then_value, writer);
            try appendValueId(Reified, term.else_value, writer);
        },
        .value_constant => |term| {
            try appendValueId(Reified, term.result, writer);
            try writer.append(u16, 0);
            try appendInvariantValue(term.contents, writer);
        },
        .instruction_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.definition, writer);
            try writer.append(u16, term.operand_count);
            try writer.append(u16, 0);
            for (term.operands[0..term.operand_count]) |operand| {
                try appendValueId(Reified, operand, writer);
            }
        },
        .product_extract_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.product, writer);
            try writer.append(u16, term.field_index);
            try writer.append(u16, 0);
        },
        .sum_extract_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.sum, writer);
            try writer.append(u16, term.case_index);
            try writer.append(u16, 0);
        },
        .bounded_length_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.bounded, writer);
        },
        .integer_unary_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.operand, writer);
            try writer.append(u8, integerUnaryTag(term.operation));
            try writer.append(u8, scalarSchemaTag(term.scalar_type));
            try writer.append(u16, 0);
        },
        .integer_binary_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.left, writer);
            try appendValueId(Reified, term.right, writer);
            try writer.append(u8, integerBinaryTag(term.operation));
            try writer.append(u8, scalarSchemaTag(term.scalar_type));
        },
        .integer_convert_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.operand, writer);
            try writer.append(u8, scalarSchemaTag(term.scalar_type));
            try writer.append(u8, 0);
            try writer.append(u16, 0);
        },
        .integer_zero => |term| {
            try appendValueId(Reified, term.value, writer);
            try writer.append(u8, @intFromBool(term.equal));
            try writer.append(u8, 0);
        },
        .integer_zero_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.value, writer);
        },
        .integer_relation => |term| {
            try appendValueId(Reified, term.left, writer);
            try appendValueId(Reified, term.right, writer);
            try writer.append(u8, integerRelationTag(term.relation));
            try writer.append(u8, @intFromBool(term.expected));
            try writer.append(u16, 0);
        },
        .integer_relation_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.left, writer);
            try appendValueId(Reified, term.right, writer);
            try writer.append(u8, integerRelationTag(term.relation));
            try writer.append(u8, 0);
        },
        .sum_case => |term| {
            try appendValueId(Reified, term.value, writer);
            try writer.append(u16, term.case_index);
            try writer.append(u8, @intFromBool(term.equal));
            try writer.append(u8, 0);
            try writer.append(u16, 0);
        },
        .sum_case_result => |term| {
            try appendValueId(Reified, term.result, writer);
            try appendValueId(Reified, term.value, writer);
            try writer.append(u16, term.case_index);
            try writer.append(u16, 0);
        },
    }
    writer.patch(u32, start, writer.cursor - start);
}

fn appendValueId(
    comptime Reified: type,
    value: u16,
    writer: *RuntimeWriter,
) RuntimeError!void {
    try writer.append(
        u16,
        Reified.semantic_canonicalization.valueId(value),
    );
}

fn appendInvariantValue(
    comptime value: anytype,
    writer: *RuntimeWriter,
) RuntimeError!void {
    const payload: u64 = switch (value) {
        .boolean => |item| @intFromBool(item),
        .signed => |item| @bitCast(item),
        .unsigned => |item| item,
        .sum_case => |item| item,
    };
    try writer.append(u8, @intFromEnum(std.meta.activeTag(value)));
    for (0..7) |_| try writer.append(u8, 0);
    try writer.append(u64, payload);
}

fn booleanBinaryTag(comptime operation: anytype) u8 {
    return switch (operation) {
        .@"and" => 0,
        .@"or" => 1,
    };
}

fn integerUnaryTag(comptime operation: anytype) u8 {
    return switch (operation) {
        .negate => 0,
        .bit_not => 1,
    };
}

fn integerBinaryTag(comptime operation: anytype) u8 {
    return switch (operation) {
        .add => 0,
        .subtract => 1,
        .multiply => 2,
        .divide => 3,
        .remainder => 4,
        .bit_and => 5,
        .bit_or => 6,
        .bit_xor => 7,
    };
}

fn integerRelationTag(comptime relation: anytype) u8 {
    return switch (relation) {
        .equal => 0,
        .not_equal => 1,
        .less_than => 2,
        .less_equal => 3,
        .greater_than => 4,
        .greater_equal => 5,
    };
}

fn scalarSchemaTag(comptime scalar: anytype) u8 {
    return switch (scalar) {
        .i8 => 2,
        .i16 => 3,
        .i32 => 4,
        .i64 => 5,
        .u8 => 6,
        .u16 => 7,
        .u32 => 8,
        .u64 => 9,
        .unit, .boolean => unreachable,
    };
}

fn transitionLess(left: anytype, right: @TypeOf(left)) bool {
    if (left.source != right.source) return left.source < right.source;
    if (left.edge != right.edge) return left.edge < right.edge;
    if (left.target != right.target) return left.target < right.target;
    return left.constructor < right.constructor;
}

fn appendTerminator(
    comptime Reified: type,
    comptime Schemas: type,
    comptime terminator: anytype,
    bytes: []u8,
    cursor: *usize,
) void {
    const start = cursor.*;
    appendInt(u32, bytes, cursor, 0);
    appendInt(
        u8,
        bytes,
        cursor,
        @intFromEnum(program_semantics_v1.wireTerminator(terminator)),
    );
    appendInt(u8, bytes, cursor, 0);
    appendInt(u16, bytes, cursor, 0);
    switch (terminator) {
        .jump => |edge| appendEdge(Reified, edge, bytes, cursor),
        .branch => |branch| {
            appendInt(
                u16,
                bytes,
                cursor,
                Reified.semantic_canonicalization.valueId(branch.condition),
            );
            appendInt(u16, bytes, cursor, 0);
            appendEdge(Reified, branch.then_edge, bytes, cursor);
            appendEdge(Reified, branch.else_edge, bytes, cursor);
        },
        .@"suspend" => |suspension| {
            appendInt(
                u8,
                bytes,
                cursor,
                @intFromEnum(imageSuspensionKind(suspension.kind)),
            );
            appendInt(u8, bytes, cursor, 0);
            appendInt(u16, bytes, cursor, 0);
            appendInt(
                u32,
                bytes,
                cursor,
                if (suspension.site_id) |site|
                    Reified.residual_effects.source_to_residual[site] orelse
                        std.math.maxInt(u32)
                else
                    std.math.maxInt(u32),
            );
            appendInt(
                u16,
                bytes,
                cursor,
                if (suspension.callee_function) |function|
                    Reified.semantic_canonicalization.functionId(function)
                else
                    std.math.maxInt(u16),
            );
            appendInt(u16, bytes, cursor, suspension.request_values.len);
            for (suspension.request_values) |value| {
                appendInt(
                    u16,
                    bytes,
                    cursor,
                    Reified.semantic_canonicalization.valueId(value),
                );
            }
            appendInt(u8, bytes, cursor, @intFromBool(suspension.callee != null));
            appendInt(u8, bytes, cursor, 0);
            appendInt(u16, bytes, cursor, 0);
            if (suspension.callee) |edge| {
                appendEdge(Reified, edge, bytes, cursor);
            }
            appendEdge(Reified, suspension.continuation, bytes, cursor);
            appendInt(
                u32,
                bytes,
                cursor,
                if (suspension.resume_type) |resume_type|
                    Schemas.schemaIdForValueType(resume_type)
                else
                    std.math.maxInt(u32),
            );
        },
        .return_value => |value| {
            appendInt(u8, bytes, cursor, @intFromBool(value != null));
            appendInt(u8, bytes, cursor, 0);
            appendInt(
                u16,
                bytes,
                cursor,
                if (value) |id|
                    Reified.semantic_canonicalization.valueId(id)
                else
                    std.math.maxInt(u16),
            );
        },
        .return_to_caller, .fail_value => |value| {
            appendInt(
                u16,
                bytes,
                cursor,
                Reified.semantic_canonicalization.valueId(value),
            );
            appendInt(u16, bytes, cursor, 0);
        },
        .fail => |failure| appendInt(u32, bytes, cursor, failure),
    }
    writeAt(u32, bytes, start, cursor.* - start);
}

fn appendEdge(
    comptime Reified: type,
    comptime edge: anytype,
    bytes: []u8,
    cursor: *usize,
) void {
    appendInt(
        u16,
        bytes,
        cursor,
        Reified.semantic_canonicalization.blockId(edge.target),
    );
    appendInt(u16, bytes, cursor, edge.arguments.len);
    for (edge.arguments) |argument| {
        switch (argument) {
            .value => |value| {
                appendInt(u8, bytes, cursor, 0);
                appendInt(u8, bytes, cursor, 0);
                appendInt(
                    u16,
                    bytes,
                    cursor,
                    Reified.semantic_canonicalization.valueId(value),
                );
            },
            .@"resume" => {
                appendInt(u8, bytes, cursor, 1);
                appendInt(u8, bytes, cursor, 0);
                appendInt(u16, bytes, cursor, std.math.maxInt(u16));
            },
        }
    }
}

fn instructionKindTag(comptime operation: anytype) u8 {
    return switch (program_semantics_v1.canonicalInstructionKind(operation)) {
        .constant => 0,
        .copy => 1,
        .compare_eq_zero => 2,
        .pure => 3,
        .call => 4,
    };
}

fn instructionImmediate(comptime operation: anytype, comptime Constants: type) u32 {
    return switch (operation) {
        .constant => |source| Constants.source_to_canonical[source] orelse
            unreachable,
        .product_extract,
        .product_replace,
        .sum_construct,
        .sum_tag_is,
        .sum_extract,
        => |index| index,
        else => 0,
    };
}

fn blockRoleTag(comptime role: anytype) u8 {
    return switch (role) {
        .segment => 0,
        .loop_header => 1,
        .call_return => 2,
        .after_handler => 3,
        .terminal_handoff => 4,
    };
}

fn imageSuspensionKind(comptime kind: anytype) program_semantics_v1.WireSuspension {
    return switch (kind) {
        .effect => .effect,
        .call => .call,
        .explicit_yield => .explicit_yield,
        else => @compileError("BPI1 excludes synthetic scheduling suspensions"),
    };
}

fn imageConstructorKind(kind: anytype) program_semantics_v1.WireConstructorKind {
    return switch (kind) {
        .entry => .entry,
        .segment_entry => .segment_entry,
        .loop_header => .loop_header,
        .await_effect => .await_effect,
        .call_return => .call_return,
        .after_handler => .after_handler,
        .caller_fuel_yield => .explicit_yield,
        .terminal_handoff => .terminal_handoff,
    };
}

fn appendInt(
    comptime T: type,
    bytes: []u8,
    cursor: *usize,
    value: anytype,
) void {
    std.debug.assert(cursor.* <= bytes.len -| @sizeOf(T));
    writeAt(T, bytes, cursor.*, value);
    cursor.* += @sizeOf(T);
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
    var hash_tasks: [128]dynamic_value_v1.SchemaHashTask = undefined;
    try std.testing.expectEqual(
        portable_value.schemaDigest(Product),
        try dynamic_value_v1.schemaDigest(
            table,
            Schemas.root_ids[0],
            &hash_tasks,
        ),
    );
}

test "BPI1 envelope composition is exact and digest-bound" {
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
        .program_transition_digest = [_]u8{1} ** 32,
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
