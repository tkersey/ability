const std = @import("std");

pub const magic = "ABL_PST1".*;
pub const format_version: u16 = 1;
pub const fixed_header_length: usize = magic.len + 2 + 2 + 32;

pub const Error = error{
    InvalidEncoding,
    InvalidState,
    LengthOverflow,
    NonCanonicalNatural,
    OutputCapacity,
    UnknownFlags,
    UnsupportedVersion,
};

pub const Natural = struct {
    value: u64,
    length: usize,
};

pub const Frame = struct {
    constructor_id: u32,
    environment: []const u8,
};

pub const FrameSpan = struct {
    start: usize,
    end: usize,
    frame: Frame,
};

pub const StateView = struct {
    bytes: []const u8,
    program_transition_digest: [32]u8,
    frame_count: u64,
    frames_offset: usize,

    pub fn iterator(self: StateView) FrameIterator {
        return .{
            .bytes = self.bytes,
            .cursor = self.frames_offset,
            .remaining = self.frame_count,
        };
    }
};

pub const FrameIterator = struct {
    bytes: []const u8,
    cursor: usize,
    remaining: u64,

    pub fn next(self: *FrameIterator) Error!?Frame {
        const span = (try self.nextSpan()) orelse return null;
        return span.frame;
    }

    pub fn nextSpan(self: *FrameIterator) Error!?FrameSpan {
        if (self.remaining == 0) return null;
        const start = self.cursor;
        const constructor = try readNatural(self.bytes[self.cursor..]);
        self.cursor = try addLength(self.cursor, constructor.length);
        const constructor_id = std.math.cast(u32, constructor.value) orelse
            return error.InvalidState;
        const environment_length = try readNatural(self.bytes[self.cursor..]);
        self.cursor = try addLength(self.cursor, environment_length.length);
        const length = std.math.cast(usize, environment_length.value) orelse
            return error.InvalidState;
        const end = try addLength(self.cursor, length);
        if (end > self.bytes.len) return error.InvalidState;
        const span: FrameSpan = .{
            .start = start,
            .end = end,
            .frame = .{
                .constructor_id = constructor_id,
                .environment = self.bytes[self.cursor..end],
            },
        };
        self.cursor = end;
        self.remaining -= 1;
        return span;
    }
};

pub fn validate(
    bytes: []const u8,
    expected_program_transition_digest: ?[32]u8,
) Error!StateView {
    if (bytes.len < fixed_header_length + 1 or
        !std.mem.eql(u8, bytes[0..magic.len], &magic))
    {
        return error.InvalidState;
    }
    if (readInt(u16, bytes, magic.len) != format_version) {
        return error.UnsupportedVersion;
    }
    if (readInt(u16, bytes, magic.len + 2) != 0) {
        return error.UnknownFlags;
    }
    const digest = bytes[magic.len + 4 ..][0..32].*;
    if (expected_program_transition_digest) |expected| {
        if (!std.mem.eql(u8, &digest, &expected)) return error.InvalidState;
    }
    const frames_offset = fixed_header_length;
    const frame_count = try readNatural(bytes[frames_offset..]);
    if (frame_count.value == 0) return error.InvalidState;
    const first_frame = try addLength(frames_offset, frame_count.length);
    if (frame_count.value > bytes.len - first_frame) return error.InvalidState;
    const view: StateView = .{
        .bytes = bytes,
        .program_transition_digest = digest,
        .frame_count = frame_count.value,
        .frames_offset = first_frame,
    };
    var iterator = view.iterator();
    while (try iterator.next() != null) {}
    if (iterator.cursor != bytes.len) return error.InvalidState;
    return view;
}

pub fn encodedLength(frames: []const Frame) Error!usize {
    if (frames.len == 0) return error.InvalidState;
    var length = try addLength(
        fixed_header_length,
        naturalEncodedLength(frames.len),
    );
    for (frames) |frame| {
        length = try addLength(
            length,
            naturalEncodedLength(frame.constructor_id),
        );
        length = try addLength(
            length,
            naturalEncodedLength(frame.environment.len),
        );
        length = try addLength(length, frame.environment.len);
    }
    return length;
}

pub fn encode(
    program_transition_digest: [32]u8,
    frames: []const Frame,
    output: []u8,
) Error![]const u8 {
    return encodeTracked(
        program_transition_digest,
        frames,
        output,
        null,
    );
}

pub fn encodeTracked(
    program_transition_digest: [32]u8,
    frames: []const Frame,
    output: []u8,
    required_output: ?*u64,
) Error![]const u8 {
    if (slicesOverlap(output, std.mem.sliceAsBytes(frames))) {
        return error.InvalidEncoding;
    }
    for (frames) |frame| {
        if (slicesOverlap(output, frame.environment)) {
            return error.InvalidEncoding;
        }
    }
    const required = try encodedLength(frames);
    noteRequired(required_output, required);
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    append(output, &cursor, &magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    append(output, &cursor, &program_transition_digest);
    cursor += try writeNatural(frames.len, output[cursor..]);
    for (frames) |frame| {
        cursor += try writeNatural(frame.constructor_id, output[cursor..]);
        cursor += try writeNatural(frame.environment.len, output[cursor..]);
        append(output, &cursor, frame.environment);
    }
    if (cursor != required) return error.InvalidEncoding;
    const encoded = output[0..required];
    _ = try validate(encoded, program_transition_digest);
    return encoded;
}

pub fn topFrame(state: StateView) Error!FrameSpan {
    var iterator = state.iterator();
    var top: ?FrameSpan = null;
    while (try iterator.nextSpan()) |frame| top = frame;
    return top orelse error.InvalidState;
}

pub fn replaceTop(
    state: StateView,
    replacement: Frame,
    output: []u8,
) Error!StateView {
    return replaceTopTracked(state, replacement, output, null);
}

pub fn replaceTopTracked(
    state: StateView,
    replacement: Frame,
    output: []u8,
    required_output: ?*u64,
) Error!StateView {
    try rejectMutationAliases(output, state.bytes, &.{replacement});
    const top = try topFrame(state);
    var required = fixed_header_length;
    required = try addLength(
        required,
        naturalEncodedLength(state.frame_count),
    );
    required = try addLength(required, top.start - state.frames_offset);
    required = try addLength(
        required,
        naturalEncodedLength(replacement.constructor_id),
    );
    required = try addLength(
        required,
        naturalEncodedLength(replacement.environment.len),
    );
    required = try addLength(required, replacement.environment.len);
    noteRequired(required_output, required);
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    append(output, &cursor, &magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    append(output, &cursor, &state.program_transition_digest);
    cursor += try writeNatural(state.frame_count, output[cursor..]);
    append(
        output,
        &cursor,
        state.bytes[state.frames_offset..top.start],
    );
    cursor += try writeNatural(replacement.constructor_id, output[cursor..]);
    cursor += try writeNatural(replacement.environment.len, output[cursor..]);
    append(output, &cursor, replacement.environment);
    if (cursor != required) return error.InvalidEncoding;
    const encoded = output[0..required];
    return validate(encoded, state.program_transition_digest);
}

pub fn replaceTopAndAppend(
    state: StateView,
    replacement: Frame,
    appended: Frame,
    output: []u8,
) Error!StateView {
    return replaceTopAndAppendTracked(
        state,
        replacement,
        appended,
        output,
        null,
    );
}

pub fn replaceTopAndAppendTracked(
    state: StateView,
    replacement: Frame,
    appended: Frame,
    output: []u8,
    required_output: ?*u64,
) Error!StateView {
    try rejectMutationAliases(
        output,
        state.bytes,
        &.{ replacement, appended },
    );
    const top = try topFrame(state);
    const frame_count = std.math.add(u64, state.frame_count, 1) catch
        return error.LengthOverflow;
    var required = fixed_header_length;
    required = try addLength(required, naturalEncodedLength(frame_count));
    required = try addLength(required, top.start - state.frames_offset);
    required = try addFrameLength(required, replacement);
    required = try addFrameLength(required, appended);
    noteRequired(required_output, required);
    if (output.len < required) return error.OutputCapacity;

    var cursor: usize = 0;
    append(output, &cursor, &magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    append(output, &cursor, &state.program_transition_digest);
    cursor += try writeNatural(frame_count, output[cursor..]);
    append(output, &cursor, state.bytes[state.frames_offset..top.start]);
    try appendFrame(output, &cursor, replacement);
    try appendFrame(output, &cursor, appended);
    if (cursor != required) return error.InvalidEncoding;
    const encoded = output[0..required];
    return validate(encoded, state.program_transition_digest);
}

pub fn replaceParentAndDropTop(
    state: StateView,
    replacement: Frame,
    output: []u8,
) Error!StateView {
    return replaceParentAndDropTopTracked(state, replacement, output, null);
}

pub fn replaceParentAndDropTopTracked(
    state: StateView,
    replacement: Frame,
    output: []u8,
    required_output: ?*u64,
) Error!StateView {
    try rejectMutationAliases(output, state.bytes, &.{replacement});
    if (state.frame_count < 2) return error.InvalidState;
    var iterator = state.iterator();
    var parent: ?FrameSpan = null;
    var top: ?FrameSpan = null;
    while (try iterator.nextSpan()) |span| {
        parent = top;
        top = span;
    }
    const parent_span = parent orelse return error.InvalidState;
    const frame_count = state.frame_count - 1;
    var required = fixed_header_length;
    required = try addLength(required, naturalEncodedLength(frame_count));
    required = try addLength(
        required,
        parent_span.start - state.frames_offset,
    );
    required = try addFrameLength(required, replacement);
    noteRequired(required_output, required);
    if (output.len < required) return error.OutputCapacity;

    var cursor: usize = 0;
    append(output, &cursor, &magic);
    appendInt(u16, output, &cursor, format_version);
    appendInt(u16, output, &cursor, 0);
    append(output, &cursor, &state.program_transition_digest);
    cursor += try writeNatural(frame_count, output[cursor..]);
    append(
        output,
        &cursor,
        state.bytes[state.frames_offset..parent_span.start],
    );
    try appendFrame(output, &cursor, replacement);
    if (cursor != required) return error.InvalidEncoding;
    const encoded = output[0..required];
    return validate(encoded, state.program_transition_digest);
}

pub fn parentFrame(state: StateView) Error!FrameSpan {
    if (state.frame_count < 2) return error.InvalidState;
    var iterator = state.iterator();
    var parent: ?FrameSpan = null;
    var top: ?FrameSpan = null;
    while (try iterator.nextSpan()) |span| {
        parent = top;
        top = span;
    }
    return parent orelse error.InvalidState;
}

fn addFrameLength(length: usize, frame: Frame) Error!usize {
    var result = try addLength(length, naturalEncodedLength(frame.constructor_id));
    result = try addLength(result, naturalEncodedLength(frame.environment.len));
    return addLength(result, frame.environment.len);
}

fn rejectMutationAliases(
    output: []u8,
    state_bytes: []const u8,
    frames: []const Frame,
) Error!void {
    if (slicesOverlap(output, state_bytes)) return error.InvalidEncoding;
    for (frames) |frame| {
        if (slicesOverlap(output, frame.environment)) {
            return error.InvalidEncoding;
        }
    }
}

fn noteRequired(required_output: ?*u64, required: usize) void {
    if (required_output) |value| value.* = @max(value.*, required);
}

fn appendFrame(output: []u8, cursor: *usize, frame: Frame) Error!void {
    cursor.* += try writeNatural(frame.constructor_id, output[cursor.*..]);
    cursor.* += try writeNatural(frame.environment.len, output[cursor.*..]);
    append(output, cursor, frame.environment);
}

pub fn artifactDigest(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

pub fn slicesOverlap(left: []const u8, right: []const u8) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_end = std.math.add(usize, left_start, left.len) catch
        return true;
    const right_end = std.math.add(usize, right_start, right.len) catch
        return true;
    return left_start < right_end and right_start < left_end;
}

pub fn naturalEncodedLength(value: anytype) usize {
    var remaining: u64 = @intCast(value);
    var length: usize = 1;
    while (remaining >= 0x80) : (length += 1) remaining >>= 7;
    return length;
}

pub fn readNatural(bytes: []const u8) Error!Natural {
    var value: u64 = 0;
    var shift: u6 = 0;
    var index: usize = 0;
    while (index < bytes.len and index < 10) : (index += 1) {
        const byte = bytes[index];
        const payload = byte & 0x7f;
        if (shift == 63 and payload > 1) return error.LengthOverflow;
        value |= @as(u64, payload) << shift;
        if (byte & 0x80 == 0) {
            const length = index + 1;
            if (naturalEncodedLength(value) != length) {
                return error.NonCanonicalNatural;
            }
            return .{ .value = value, .length = length };
        }
        if (index == 9) return error.LengthOverflow;
        shift += 7;
    }
    return error.InvalidEncoding;
}

pub fn writeNatural(value: anytype, output: []u8) Error!usize {
    var remaining: u64 = @intCast(value);
    const required = naturalEncodedLength(remaining);
    if (output.len < required) return error.OutputCapacity;
    var cursor: usize = 0;
    while (true) {
        var byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining != 0) byte |= 0x80;
        output[cursor] = byte;
        cursor += 1;
        if (remaining == 0) break;
    }
    return cursor;
}

fn addLength(left: usize, right: usize) Error!usize {
    return std.math.add(usize, left, right) catch error.LengthOverflow;
}

fn append(output: []u8, cursor: *usize, bytes: []const u8) void {
    @memcpy(output[cursor.*..][0..bytes.len], bytes);
    cursor.* += bytes.len;
}

fn appendInt(
    comptime T: type,
    output: []u8,
    cursor: *usize,
    value: T,
) void {
    std.mem.writeInt(T, output[cursor.*..][0..@sizeOf(T)], value, .little);
    cursor.* += @sizeOf(T);
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
