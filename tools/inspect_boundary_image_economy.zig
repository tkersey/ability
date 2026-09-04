const image_v1 = @import("image_v1");
const program_semantics_v1 = @import("program_semantics_v1");
const std = @import("std");

const maximum_image_bytes = 64 * 1024 * 1024;
const top_entry_count = 20;

const ConstantEntry = struct {
    id: u32,
    schema_id: u32,
    record_bytes: u32,
    payload_bytes: u32,
    payload_sha256: [32]u8,
};

const SegmentEntry = struct {
    id: u16,
    function_id: u16,
    bytes: u32,
    instructions: u32,
    operands: u32,
    parameters: u16,
    sha256: [32]u8,
};

const ConstructorEntry = struct {
    id: u32,
    source_segment_id: u16,
    bytes: u32,
    activation_fields: u16,
    environment_fields: u16,
    invariant_terms: u16,
    sha256: [32]u8,
};

const Counts = struct {
    schema_records: u32,
    failure_records: u32,
    constant_records: u32,
    constant_payload_bytes: u64,
    effect_records: u32,
    value_records: u32,
    function_records: u32,
    segment_records: u32,
    instructions: u64,
    operands: u64,
    parameters: u64,
    constructor_records: u32,
    activation_fields: u64,
    environment_fields: u64,
    invariant_terms: u64,
    entry_transition_records: u32,
    framing_bytes: u64,
};

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    defer arguments.deinit();
    _ = arguments.skip();
    const path = arguments.next() orelse return error.MissingImagePath;
    if (arguments.next() != null) return error.UnexpectedArgument;

    const file = try std.Io.Dir.openFile(.cwd(), init.io, path, .{});
    defer file.close(init.io);
    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(init.io, &read_buffer);
    const bytes = try reader.interface.allocRemaining(
        init.gpa,
        .limited(maximum_image_bytes),
    );
    defer init.gpa.free(bytes);

    const workspace = try init.gpa.create(image_v1.ValidationWorkspace);
    defer init.gpa.destroy(workspace);
    const image = try image_v1.validateImage(bytes, workspace);

    var constants: std.ArrayList(ConstantEntry) = .empty;
    defer constants.deinit(init.gpa);
    var segments: std.ArrayList(SegmentEntry) = .empty;
    defer segments.deinit(init.gpa);
    var constructors: std.ArrayList(ConstructorEntry) = .empty;
    defer constructors.deinit(init.gpa);

    const counts = try inspect(
        image,
        init.gpa,
        &constants,
        &segments,
        &constructors,
    );
    std.mem.sort(ConstantEntry, constants.items, {}, constantLessThan);
    std.mem.sort(SegmentEntry, segments.items, {}, segmentLessThan);
    std.mem.sort(ConstructorEntry, constructors.items, {}, constructorLessThan);

    var output_buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &output_buffer);
    try writeReport(
        &stdout.interface,
        image,
        counts,
        constants.items,
        segments.items,
        constructors.items,
    );
    try stdout.interface.flush();
}

fn inspect(
    image: image_v1.ValidatedImage,
    allocator: std.mem.Allocator,
    constants: *std.ArrayList(ConstantEntry),
    segments: *std.ArrayList(SegmentEntry),
    constructors: *std.ArrayList(ConstructorEntry),
) !Counts {
    const envelope = &image.catalogs.envelope;
    var counts: Counts = .{
        .schema_records = readInt(u32, envelope.section(.schemas), 0),
        .failure_records = readInt(u32, envelope.section(.failures), 0),
        .constant_records = readInt(u32, envelope.section(.constants), 0),
        .constant_payload_bytes = 0,
        .effect_records = readInt(u32, envelope.section(.effects), 0),
        .value_records = readInt(u32, envelope.section(.values), 0),
        .function_records = readInt(u32, envelope.section(.functions), 0),
        .segment_records = image.segment_count,
        .instructions = 0,
        .operands = 0,
        .parameters = 0,
        .constructor_records = image.constructor_count,
        .activation_fields = 0,
        .environment_fields = 0,
        .invariant_terms = 0,
        .entry_transition_records = readInt(
            u32,
            envelope.section(.entry_transitions),
            0,
        ),
        .framing_bytes = image_v1.header_length + 9 * @sizeOf(u32) + 6,
    };

    inspectSchemas(envelope.section(.schemas), &counts);
    inspectFailures(envelope.section(.failures), &counts);
    inspectEffects(envelope.section(.effects), &counts);
    try inspectConstants(
        envelope.section(.constants),
        allocator,
        constants,
        &counts,
    );
    try inspectSegments(image, allocator, segments, &counts);
    try inspectConstructors(image, allocator, constructors, &counts);
    counts.framing_bytes += @as(u64, counts.entry_transition_records) * 3;
    if (counts.framing_bytes > envelope.header.total_length) {
        return error.InvalidFramingEstimate;
    }
    return counts;
}

fn inspectSchemas(bytes: []const u8, counts: *Counts) void {
    var cursor: usize = 4;
    for (0..counts.schema_records) |_| {
        const length = readInt(u32, bytes, cursor);
        counts.framing_bytes += 7;
        cursor += length;
    }
}

fn inspectFailures(bytes: []const u8, counts: *Counts) void {
    var cursor: usize = 4;
    for (0..counts.failure_records) |_| {
        const name_length = readInt(u32, bytes, cursor + 4);
        counts.framing_bytes += 4;
        cursor += 8 + name_length;
    }
}

fn inspectEffects(bytes: []const u8, counts: *Counts) void {
    var cursor: usize = 4;
    for (0..counts.effect_records) |_| {
        const identity_length = readInt(u32, bytes, cursor + 4);
        counts.framing_bytes += 8;
        cursor += 84 + identity_length;
    }
}

fn inspectConstants(
    bytes: []const u8,
    allocator: std.mem.Allocator,
    entries: *std.ArrayList(ConstantEntry),
    counts: *Counts,
) !void {
    var cursor: usize = 4;
    for (0..counts.constant_records) |id| {
        const schema_id = readInt(u32, bytes, cursor);
        const payload_length = readInt(u32, bytes, cursor + 4);
        const start = cursor + 8;
        const end = start + payload_length;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes[start..end], &digest, .{});
        try entries.append(allocator, .{
            .id = @intCast(id),
            .schema_id = schema_id,
            .record_bytes = 8 + payload_length,
            .payload_bytes = payload_length,
            .payload_sha256 = digest,
        });
        counts.constant_payload_bytes += payload_length;
        counts.framing_bytes += 4;
        cursor = end;
    }
}

fn inspectSegments(
    image: image_v1.ValidatedImage,
    allocator: std.mem.Allocator,
    entries: *std.ArrayList(SegmentEntry),
    counts: *Counts,
) !void {
    for (0..image.segment_count) |id| {
        const record = try image_v1.evaluatorSegmentRecord(image, @intCast(id));
        const parameter_count = readInt(u16, record, 10);
        const instruction_count = readInt(u32, record, 12);
        var cursor: usize = image_v1.segment_prefix_length +
            @as(usize, parameter_count) * @sizeOf(u16);
        var operand_count: u32 = 0;
        for (0..instruction_count) |_| {
            const length = readInt(u32, record, cursor);
            operand_count += readInt(u16, record, cursor + 10);
            counts.framing_bytes += 5;
            cursor += length;
        }
        counts.framing_bytes += try inspectTerminatorFraming(record, cursor);
        counts.framing_bytes += 12;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(record, &digest, .{});
        try entries.append(allocator, .{
            .id = @intCast(id),
            .function_id = readInt(u16, record, 6),
            .bytes = @intCast(record.len),
            .instructions = instruction_count,
            .operands = operand_count,
            .parameters = parameter_count,
            .sha256 = digest,
        });
        counts.instructions += instruction_count;
        counts.operands += operand_count;
        counts.parameters += parameter_count;
    }
}

fn inspectTerminatorFraming(record: []const u8, start: usize) !u64 {
    const end = start + readInt(u32, record, start);
    var cursor = start + 8;
    var framing: u64 = 7;
    const kind = std.enums.fromInt(
        program_semantics_v1.WireTerminator,
        record[start + 4],
    ) orelse return error.InvalidTerminator;
    switch (kind) {
        .jump => framing += inspectEdgeFraming(record, &cursor),
        .branch => {
            framing += 2;
            cursor += 4;
            framing += inspectEdgeFraming(record, &cursor);
            framing += inspectEdgeFraming(record, &cursor);
        },
        .@"suspend" => {
            const request_count = readInt(u16, record, cursor + 10);
            framing += 8;
            cursor += 12 + @as(usize, request_count) * @sizeOf(u16);
            const callee_present = record[cursor];
            cursor += 4;
            if (callee_present == 1) {
                framing += inspectEdgeFraming(record, &cursor);
            }
            framing += inspectEdgeFraming(record, &cursor);
            cursor += @sizeOf(u32);
        },
        .return_value => {
            framing += 1;
            cursor += 4;
        },
        .return_to_caller, .fail_value => {
            framing += 2;
            cursor += 4;
        },
        .fail => cursor += 4,
    }
    if (cursor != end) return error.InvalidTerminator;
    return framing;
}

fn inspectEdgeFraming(record: []const u8, cursor: *usize) u64 {
    const argument_count = readInt(u16, record, cursor.* + 2);
    cursor.* += 4 + @as(usize, argument_count) * 4;
    return 2 + argument_count;
}

test "terminator framing covers every wire variant" {
    var record = [_]u8{0} ** 32;

    setTerminatorHeader(&record, 16, .jump);
    std.mem.writeInt(u16, record[10..12], 1, .little);
    try std.testing.expectEqual(
        @as(u64, 10),
        try inspectTerminatorFraming(record[0..16], 0),
    );

    record = [_]u8{0} ** 32;
    setTerminatorHeader(&record, 20, .branch);
    try std.testing.expectEqual(
        @as(u64, 13),
        try inspectTerminatorFraming(record[0..20], 0),
    );

    record = [_]u8{0} ** 32;
    setTerminatorHeader(&record, 32, .@"suspend");
    record[8] = @intFromEnum(
        program_semantics_v1.WireSuspension.explicit_yield,
    );
    try std.testing.expectEqual(
        @as(u64, 17),
        try inspectTerminatorFraming(&record, 0),
    );

    inline for (.{
        .{ program_semantics_v1.WireTerminator.return_value, 8 },
        .{ program_semantics_v1.WireTerminator.return_to_caller, 9 },
        .{ program_semantics_v1.WireTerminator.fail, 7 },
        .{ program_semantics_v1.WireTerminator.fail_value, 9 },
    }) |case| {
        record = [_]u8{0} ** 32;
        setTerminatorHeader(&record, 12, case[0]);
        try std.testing.expectEqual(
            @as(u64, case[1]),
            try inspectTerminatorFraming(record[0..12], 0),
        );
    }
}

fn setTerminatorHeader(
    record: []u8,
    length: u32,
    kind: program_semantics_v1.WireTerminator,
) void {
    std.mem.writeInt(u32, record[0..4], length, .little);
    record[4] = @intFromEnum(kind);
}

fn inspectConstructors(
    image: image_v1.ValidatedImage,
    allocator: std.mem.Allocator,
    entries: *std.ArrayList(ConstructorEntry),
    counts: *Counts,
) !void {
    for (0..image.constructor_count) |id| {
        const record = try image_v1.evaluatorConstructorRecord(
            image,
            @intCast(id),
        );
        const activation_fields = readInt(u16, record, 16);
        const environment_fields = readInt(u16, record, 18);
        const invariant_terms = readInt(u16, record, 20);
        var cursor: usize = 24 +
            @as(usize, activation_fields + environment_fields) * 8;
        counts.framing_bytes += 6 +
            @as(u64, activation_fields + environment_fields) * 2;
        for (0..invariant_terms) |_| {
            const length = readInt(u32, record, cursor);
            counts.framing_bytes += 7;
            cursor += length;
        }
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(record, &digest, .{});
        try entries.append(allocator, .{
            .id = @intCast(id),
            .source_segment_id = readInt(u16, record, 12),
            .bytes = @intCast(record.len),
            .activation_fields = activation_fields,
            .environment_fields = environment_fields,
            .invariant_terms = invariant_terms,
            .sha256 = digest,
        });
        counts.activation_fields += activation_fields;
        counts.environment_fields += environment_fields;
        counts.invariant_terms += invariant_terms;
    }
}

fn writeReport(
    writer: *std.Io.Writer,
    image: image_v1.ValidatedImage,
    counts: Counts,
    constants: []const ConstantEntry,
    segments: []const SegmentEntry,
    constructors: []const ConstructorEntry,
) !void {
    const envelope = &image.catalogs.envelope;
    const image_digest = std.fmt.bytesToHex(image.artifact_sha256, .lower);
    const transition_digest = std.fmt.bytesToHex(
        envelope.header.program_transition_digest,
        .lower,
    );
    try writer.print(
        "{{\"format\":\"boundary-image-economy/v1\"," ++
            "\"imageSha256\":\"{s}\",\"imageByteLength\":{d}," ++
            "\"evaluatorSemanticsVersion\":{d}," ++
            "\"programTransitionDigest\":\"{s}\",\"sections\":{{",
        .{
            &image_digest,
            envelope.header.total_length,
            envelope.header.evaluator_semantics_version,
            &transition_digest,
        },
    );
    try writeSections(writer, envelope, counts);
    try writer.writeAll("},\"largestConstants\":[");
    try writeConstants(writer, constants[0..@min(top_entry_count, constants.len)]);
    try writer.writeAll("],\"largestSegments\":[");
    try writeSegments(writer, segments[0..@min(top_entry_count, segments.len)]);
    try writer.writeAll("],\"largestConstructors\":[");
    try writeConstructors(
        writer,
        constructors[0..@min(top_entry_count, constructors.len)],
    );
    try writer.print(
        "],\"framingByteEstimate\":{d}," ++
            "\"semanticPayloadByteEstimate\":{d}}}\n",
        .{
            counts.framing_bytes,
            envelope.header.total_length - counts.framing_bytes,
        },
    );
}

fn writeSections(
    writer: *std.Io.Writer,
    envelope: *const image_v1.ValidatedEnvelope,
    counts: Counts,
) !void {
    try writer.print(
        "\"roots\":{{\"bytes\":{d}}}," ++
            "\"schemas\":{{\"bytes\":{d},\"records\":{d}}}," ++
            "\"failures\":{{\"bytes\":{d},\"records\":{d}}}," ++
            "\"constants\":{{\"bytes\":{d},\"records\":{d}," ++
            "\"payloadBytes\":{d}}}," ++
            "\"effects\":{{\"bytes\":{d},\"records\":{d}}}," ++
            "\"values\":{{\"bytes\":{d},\"records\":{d}}}," ++
            "\"functions\":{{\"bytes\":{d},\"records\":{d}}},",
        .{
            envelope.section(.roots).len,
            envelope.section(.schemas).len,
            counts.schema_records,
            envelope.section(.failures).len,
            counts.failure_records,
            envelope.section(.constants).len,
            counts.constant_records,
            counts.constant_payload_bytes,
            envelope.section(.effects).len,
            counts.effect_records,
            envelope.section(.values).len,
            counts.value_records,
            envelope.section(.functions).len,
            counts.function_records,
        },
    );
    try writer.print(
        "\"segments\":{{\"bytes\":{d},\"records\":{d}," ++
            "\"instructions\":{d},\"operands\":{d}," ++
            "\"parameters\":{d}}}," ++
            "\"constructors\":{{\"bytes\":{d},\"records\":{d}," ++
            "\"activationFields\":{d},\"environmentFields\":{d}," ++
            "\"invariantTerms\":{d}}}," ++
            "\"entryTransitions\":{{\"bytes\":{d},\"records\":{d}}}",
        .{
            envelope.section(.segments).len,
            counts.segment_records,
            counts.instructions,
            counts.operands,
            counts.parameters,
            envelope.section(.constructors).len,
            counts.constructor_records,
            counts.activation_fields,
            counts.environment_fields,
            counts.invariant_terms,
            envelope.section(.entry_transitions).len,
            counts.entry_transition_records,
        },
    );
}

fn writeConstants(writer: *std.Io.Writer, entries: []const ConstantEntry) !void {
    for (entries, 0..) |entry, index| {
        if (index != 0) try writer.writeByte(',');
        const digest = std.fmt.bytesToHex(entry.payload_sha256, .lower);
        try writer.print(
            "{{\"constantId\":{d},\"schemaId\":{d}," ++
                "\"byteLength\":{d},\"payloadBytes\":{d}," ++
                "\"payloadSha256\":\"{s}\"}}",
            .{
                entry.id,
                entry.schema_id,
                entry.record_bytes,
                entry.payload_bytes,
                &digest,
            },
        );
    }
}

fn writeSegments(writer: *std.Io.Writer, entries: []const SegmentEntry) !void {
    for (entries, 0..) |entry, index| {
        if (index != 0) try writer.writeByte(',');
        const digest = std.fmt.bytesToHex(entry.sha256, .lower);
        try writer.print(
            "{{\"segmentId\":{d},\"functionId\":{d}," ++
                "\"byteLength\":{d},\"instructions\":{d}," ++
                "\"operands\":{d},\"parameters\":{d}," ++
                "\"sha256\":\"{s}\"}}",
            .{
                entry.id,
                entry.function_id,
                entry.bytes,
                entry.instructions,
                entry.operands,
                entry.parameters,
                &digest,
            },
        );
    }
}

fn writeConstructors(
    writer: *std.Io.Writer,
    entries: []const ConstructorEntry,
) !void {
    for (entries, 0..) |entry, index| {
        if (index != 0) try writer.writeByte(',');
        const digest = std.fmt.bytesToHex(entry.sha256, .lower);
        try writer.print(
            "{{\"constructorId\":{d},\"sourceSegmentId\":{d}," ++
                "\"byteLength\":{d},\"activationFields\":{d}," ++
                "\"environmentFields\":{d},\"invariantTerms\":{d}," ++
                "\"sha256\":\"{s}\"}}",
            .{
                entry.id,
                entry.source_segment_id,
                entry.bytes,
                entry.activation_fields,
                entry.environment_fields,
                entry.invariant_terms,
                &digest,
            },
        );
    }
}

fn constantLessThan(_: void, left: ConstantEntry, right: ConstantEntry) bool {
    if (left.record_bytes != right.record_bytes) {
        return left.record_bytes > right.record_bytes;
    }
    return left.id < right.id;
}

fn segmentLessThan(_: void, left: SegmentEntry, right: SegmentEntry) bool {
    if (left.bytes != right.bytes) return left.bytes > right.bytes;
    return left.id < right.id;
}

fn constructorLessThan(
    _: void,
    left: ConstructorEntry,
    right: ConstructorEntry,
) bool {
    if (left.bytes != right.bytes) return left.bytes > right.bytes;
    return left.id < right.id;
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
