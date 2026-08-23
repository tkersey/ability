const cir = @import("control_ir");
const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Pair = struct {
    left: u32,
    right: u32,
};
const Choice = union(enum) {
    none: void,
    value: u32,
};
const OptionalU32 = ?u32;
const Values = portable_value.Vector(u32, 3);
const PopResult = struct {
    values: Values,
    value: ?u32,
};
const Text = portable_value.Text(64);
const Bytes = portable_value.Bytes(16);
const SmallText = portable_value.Text(16);
const SmallBytes = portable_value.Bytes(8);
const AlgebraicResult = struct {
    pair: Pair,
    choice: Choice,
    empty_choice: Choice,
    choice_payload: u32,
    choice_matches: bool,
    none: OptionalU32,
    some: OptionalU32,
    some_matches: bool,
    values: Values,
    value_count: u32,
    value_at_one: u32,
    popped: PopResult,
    truncated: Values,
    cleared: Values,
    formatted: Text,
    copied_text: Text,
    text_comparison: i8,
    joined: SmallText,
    text_length: u32,
    bytes: Bytes,
    copied_bytes: Bytes,
    bytes_comparison: i8,
    bytes_length: u32,
    joined_bytes: SmallBytes,
    scalar_bytes: SmallBytes,
};

const value_types = [_]cir.ValueType{
    .{ .scalar = .u32 }, // v0  seven
    .{ .scalar = .u32 }, // v1  eight
    .{ .scalar = .u32 }, // v2  zero
    .{ .scalar = .u32 }, // v3  one
    .{ .scalar = .u32 }, // v4  two
    .{ .scalar = .i32 }, // v5  negative seven
    .{ .scalar = .u32 }, // v6  scalar !
    .{ .schema = 8 }, // v7  alpha
    .{ .schema = 5 }, // v8  separator
    .{ .schema = 5 }, // v9  beta
    .{ .schema = 9 }, // v10 bytes prefix
    .{ .schema = 6 }, // v11 bytes suffix
    .{ .scalar = .u32 }, // v12 forty two
    .{ .schema = 0 }, // v13 pair
    .{ .schema = 0 }, // v14 replaced pair
    .{ .scalar = .u32 }, // v15 pair field
    .{ .schema = 1 }, // v16 choice
    .{ .scalar = .boolean }, // v17 choice tag
    .{ .scalar = .u32 }, // v18 choice payload
    .{ .schema = 1 }, // v19 empty choice
    .{ .schema = 2 }, // v20 none
    .{ .schema = 2 }, // v21 some
    .{ .scalar = .boolean }, // v22 some tag
    .{ .schema = 3 }, // v23 vector empty
    .{ .schema = 3 }, // v24 vector one
    .{ .schema = 3 }, // v25 vector two
    .{ .schema = 3 }, // v26 vector set
    .{ .scalar = .u32 }, // v27 vector length
    .{ .scalar = .u32 }, // v28 vector item
    .{ .schema = 4 }, // v29 pop result
    .{ .schema = 3 }, // v30 popped vector
    .{ .schema = 2 }, // v31 popped value
    .{ .schema = 3 }, // v32 truncated
    .{ .schema = 3 }, // v33 cleared
    .{ .schema = 5 }, // v34 text empty
    .{ .schema = 5 }, // v35 appended text
    .{ .schema = 5 }, // v36 scalar text
    .{ .schema = 5 }, // v37 unsigned text
    .{ .schema = 5 }, // v38 signed text
    .{ .schema = 5 }, // v39 copied text
    .{ .scalar = .i8 }, // v40 text comparison
    .{ .schema = 8 }, // v41 joined text
    .{ .schema = 6 }, // v42 bytes empty
    .{ .schema = 6 }, // v43 bytes prefix
    .{ .schema = 6 }, // v44 bytes joined
    .{ .schema = 6 }, // v45 copied bytes
    .{ .scalar = .i8 }, // v46 bytes comparison
    .{ .scalar = .u8 }, // v47 scalar byte
    .{ .scalar = .u32 }, // v48 text length
    .{ .scalar = .u32 }, // v49 bytes length
    .{ .schema = 9 }, // v50 joined bytes
    .{ .schema = 9 }, // v51 scalar-appended bytes
    .{ .schema = 7 }, // v52 result
};

const instructions = [_]cir.Instruction{
    .{ .kind = .constant, .result = 0, .operation = .{ .constant = 0 } },
    .{ .kind = .constant, .result = 1, .operation = .{ .constant = 1 } },
    .{ .kind = .constant, .result = 2, .operation = .{ .constant = 2 } },
    .{ .kind = .constant, .result = 3, .operation = .{ .constant = 3 } },
    .{ .kind = .constant, .result = 4, .operation = .{ .constant = 4 } },
    .{ .kind = .constant, .result = 5, .operation = .{ .constant = 5 } },
    .{ .kind = .constant, .result = 6, .operation = .{ .constant = 6 } },
    .{ .kind = .constant, .result = 7, .operation = .{ .constant = 7 } },
    .{ .kind = .constant, .result = 8, .operation = .{ .constant = 8 } },
    .{ .kind = .constant, .result = 9, .operation = .{ .constant = 9 } },
    .{ .kind = .constant, .result = 10, .operation = .{ .constant = 10 } },
    .{ .kind = .constant, .result = 11, .operation = .{ .constant = 11 } },
    .{ .kind = .constant, .result = 12, .operation = .{ .constant = 12 } },
    .{ .kind = .pure, .result = 13, .operands = &.{ 0, 1 }, .operation = .product_construct },
    .{ .kind = .pure, .result = 14, .operands = &.{ 13, 0 }, .operation = .{ .product_replace = 1 } },
    .{ .kind = .pure, .result = 15, .operands = &.{14}, .operation = .{ .product_extract = 1 } },
    .{ .kind = .pure, .result = 16, .operands = &.{15}, .operation = .{ .sum_construct = 1 } },
    .{ .kind = .pure, .result = 17, .operands = &.{16}, .operation = .{ .sum_tag_is = 1 } },
    .{ .kind = .pure, .result = 18, .operands = &.{16}, .operation = .{ .sum_extract = 1 } },
    .{ .kind = .pure, .result = 19, .operation = .{ .sum_construct = 0 } },
    .{ .kind = .pure, .result = 20, .operation = .optional_none },
    .{ .kind = .pure, .result = 21, .operands = &.{18}, .operation = .optional_some },
    .{ .kind = .pure, .result = 22, .operands = &.{21}, .operation = .optional_is_some },
    .{ .kind = .pure, .result = 23, .operation = .vector_empty },
    .{ .kind = .pure, .result = 24, .operands = &.{ 23, 0 }, .operation = .vector_push },
    .{ .kind = .pure, .result = 25, .operands = &.{ 24, 1 }, .operation = .vector_push },
    .{ .kind = .pure, .result = 26, .operands = &.{ 25, 2, 1 }, .operation = .vector_set },
    .{ .kind = .pure, .result = 27, .operands = &.{26}, .operation = .vector_length },
    .{ .kind = .pure, .result = 28, .operands = &.{ 26, 3 }, .operation = .vector_get },
    .{ .kind = .pure, .result = 29, .operands = &.{26}, .operation = .vector_pop },
    .{ .kind = .pure, .result = 30, .operands = &.{29}, .operation = .{ .product_extract = 0 } },
    .{ .kind = .pure, .result = 31, .operands = &.{29}, .operation = .{ .product_extract = 1 } },
    .{ .kind = .pure, .result = 32, .operands = &.{ 30, 2 }, .operation = .vector_truncate },
    .{ .kind = .pure, .result = 33, .operands = &.{26}, .operation = .vector_clear },
    .{ .kind = .pure, .result = 34, .operation = .text_empty },
    .{ .kind = .pure, .result = 35, .operands = &.{ 34, 7 }, .operation = .text_append },
    .{ .kind = .pure, .result = 36, .operands = &.{ 35, 6 }, .operation = .text_append_scalar },
    .{ .kind = .pure, .result = 37, .operands = &.{ 36, 12 }, .operation = .text_append_unsigned },
    .{ .kind = .pure, .result = 38, .operands = &.{ 37, 5 }, .operation = .text_append_signed },
    .{ .kind = .pure, .result = 39, .operands = &.{ 38, 2, 4 }, .operation = .text_copy },
    .{ .kind = .pure, .result = 40, .operands = &.{ 39, 7 }, .operation = .text_compare },
    .{ .kind = .pure, .result = 41, .operands = &.{ 7, 8, 9 }, .operation = .text_join },
    .{ .kind = .pure, .result = 42, .operation = .bytes_empty },
    .{ .kind = .pure, .result = 43, .operands = &.{ 42, 10 }, .operation = .bytes_append },
    .{ .kind = .pure, .result = 44, .operands = &.{ 43, 11 }, .operation = .bytes_append },
    .{ .kind = .pure, .result = 45, .operands = &.{ 44, 2, 4 }, .operation = .bytes_copy },
    .{ .kind = .pure, .result = 46, .operands = &.{ 45, 10 }, .operation = .bytes_compare },
    .{ .kind = .constant, .result = 47, .operation = .{ .constant = 13 } },
    .{ .kind = .pure, .result = 48, .operands = &.{41}, .operation = .text_length },
    .{ .kind = .pure, .result = 49, .operands = &.{44}, .operation = .bytes_length },
    .{ .kind = .pure, .result = 50, .operands = &.{ 10, 11, 10 }, .operation = .bytes_join },
    .{ .kind = .pure, .result = 51, .operands = &.{ 50, 47 }, .operation = .bytes_append_scalar },
    .{
        .kind = .pure,
        .result = 52,
        .operands = &.{
            14, 16, 19, 18, 17, 20, 21,
            22, 26, 27, 28, 29, 32, 33,
            38, 39, 40, 41, 48, 44, 45,
            46, 49, 50, 51,
        },
        .operation = .product_construct,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .instructions = &instructions,
        .terminator = .{ .return_value = 52 },
    },
};

const Body = struct {
    pub const InitialArgs = void;
    pub const Result = AlgebraicResult;
    pub const Failure = enum {
        arithmetic_overflow,
        capacity_exceeded,
        division_by_zero,
        invalid_index,
        invalid_utf8,
        invalid_variant,
    };
    pub const constants = .{
        @as(u32, 7),
        @as(u32, 8),
        @as(u32, 0),
        @as(u32, 1),
        @as(u32, 2),
        @as(i32, -7),
        @as(u32, '!'),
        SmallText.fromSlice("alpha") catch unreachable,
        Text.fromSlice("-") catch unreachable,
        Text.fromSlice("beta") catch unreachable,
        SmallBytes.fromSlice(&.{ 1, 2 }) catch unreachable,
        Bytes.fromSlice(&.{3}) catch unreachable,
        @as(u32, 42),
        @as(u8, 4),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{
        Pair,
        Choice,
        OptionalU32,
        Values,
        PopResult,
        Text,
        Bytes,
        AlgebraicResult,
        SmallText,
        SmallBytes,
    };
    pub const control_ir: cir.Program = .{
        .label = "algebraic-collection-operations",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 7 },
    };
};

const Program = program_v2.program(
    "algebraic-collection-operations",
    Body,
);
const options: machine.Options = .{
    .maximum_frames = 4,
    .maximum_state_bytes = 8192,
    .maximum_machine_fuel = 512,
};
const Machine = Program.compile(options);
const Image = Program.image();
const Profile = Program.machineV2Profile(options);

const MeterText = portable_value.Text(64);
const MeterProduct = struct { label: MeterText };
const MeterVector = portable_value.Vector(MeterProduct, 1);
const MeterInput = struct {
    values: MeterVector,
    index: u32,
};
const metering_entry_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{0},
        .operation = .{ .product_extract = 1 },
    },
};
const metering_entry_arguments = [_]cir.EdgeArgument{
    .{ .value = 1 },
    .{ .value = 2 },
};
const metering_extract_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 5,
        .operands = &.{ 3, 4 },
        .operation = .vector_get,
    },
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{5},
        .operation = .{ .product_extract = 0 },
    },
};
const metering_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &metering_entry_instructions,
        .terminator = .{ .jump = .{
            .target = 1,
            .arguments = &metering_entry_arguments,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{ 3, 4 },
        .instructions = &metering_extract_instructions,
        .terminator = .{ .return_value = 6 },
    },
};
const MeteringBody = struct {
    pub const InitialArgs = MeterInput;
    pub const Result = MeterText;
    pub const Failure = enum { invalid_index };
    pub const effect_sites = .{};
    pub const schema_types = .{ MeterInput, MeterVector, MeterProduct, MeterText };
    pub const control_ir: cir.Program = .{
        .label = "vector-product-field-metering",
        .value_types = &.{
            cir.ValueType{ .schema = 0 },
            cir.ValueType{ .schema = 1 },
            cir.ValueType{ .scalar = .u32 },
            cir.ValueType{ .schema = 1 },
            cir.ValueType{ .scalar = .u32 },
            cir.ValueType{ .schema = 2 },
            cir.ValueType{ .schema = 3 },
        },
        .blocks = &metering_blocks,
        .entry = 0,
        .result_type = .{ .schema = 3 },
    };
};
const MeteringProgram = program_v2.program(
    "vector-product-field-metering",
    MeteringBody,
);
const MeteringDirect = MeteringProgram.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 256,
});
const MeteringKernel = MeteringProgram.kernelMachineV2(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 256,
});

test "compiled products sums optionals vectors text and bytes are first order" {
    const state = try Machine.initialState(std.testing.allocator, {});
    defer Machine.deinitState(state);
    var fuel: u64 = 512;
    const done = switch (try Machine.step(state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    const result = done.value();
    try std.testing.expectEqual(Pair{ .left = 7, .right = 7 }, result.pair);
    try std.testing.expect(result.choice_matches);
    try std.testing.expectEqual(@as(u32, 7), result.choice_payload);
    try std.testing.expectEqual(@as(u32, 7), result.some.?);
    try std.testing.expect(result.some_matches);
    try std.testing.expect(result.none == null);
    try std.testing.expectEqual(@as(u32, 2), result.value_count);
    try std.testing.expectEqual(@as(u32, 8), result.value_at_one);
    try std.testing.expectEqual(@as(u32, 1), try result.popped.values.len());
    try std.testing.expectEqual(@as(u32, 8), result.popped.value.?);
    try std.testing.expectEqual(@as(u32, 0), try result.truncated.len());
    try std.testing.expectEqual(@as(u32, 0), try result.cleared.len());
    try std.testing.expectEqualStrings("alpha!42-7", try result.formatted.slice());
    try std.testing.expectEqualStrings("al", try result.copied_text.slice());
    try std.testing.expectEqual(@as(i8, -1), result.text_comparison);
    try std.testing.expectEqualStrings("alpha-beta", try result.joined.slice());
    try std.testing.expectEqual(@as(u32, 10), result.text_length);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, try result.bytes.slice());
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2 },
        try result.copied_bytes.slice(),
    );
    try std.testing.expectEqual(@as(i8, 0), result.bytes_comparison);
    try std.testing.expectEqual(@as(u32, 3), result.bytes_length);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 1, 2 },
        try result.joined_bytes.slice(),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 1, 2, 4 },
        try result.scalar_bytes.slice(),
    );
    switch (result.choice) {
        .value => |value| try std.testing.expectEqual(@as(u32, 7), value),
        .none => return error.TestUnexpectedResult,
    }
    switch (result.empty_choice) {
        .none => {},
        .value => return error.TestUnexpectedResult,
    }

    var workspace: image_v1.ValidationWorkspace = .{};
    const program_image = try image_v1.validateImage(&Image.bytes, &workspace);
    const image = try kernel_v1.bindMachineV2(program_image, &Profile.bytes, &workspace);
    var kernel_state: [8192]u8 = undefined;
    var invariant_scratch: [8192]u8 = undefined;
    const kernel_state_length = try kernel_v1.initial(
        image,
        &.{},
        &kernel_state,
        &invariant_scratch,
        &workspace,
    );
    var kernel_fuel: u64 = 512;
    var kernel_output: [8192]u8 = undefined;
    var kernel_next_state: [8192]u8 = undefined;
    var scratch: [64 * 1024]u8 = undefined;
    const kernel_done = switch (try kernel_v1.step(
        image,
        kernel_state[0..kernel_state_length],
        &kernel_fuel,
        &kernel_next_state,
        &kernel_output,
        &scratch,
        &workspace,
    )) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const maximum_result_size = comptime portable_value.maximumEncodedSize(
        AlgebraicResult,
    );
    var direct_bytes: [maximum_result_size]u8 = undefined;
    const direct_length = try portable_value.encode(
        AlgebraicResult,
        result.*,
        &direct_bytes,
    );
    try std.testing.expectEqual(fuel, kernel_fuel);
    try std.testing.expectEqualSlices(
        u8,
        direct_bytes[0..direct_length],
        kernel_done,
    );
}

test "vector-derived product fields use exact Machine-v2 fuel" {
    const label = try MeterText.fromSlice("a");
    const input: MeterInput = .{
        .values = try MeterVector.fromSlice(&.{.{ .label = label }}),
        .index = 0,
    };
    var observed_yield = false;
    var observed_done = false;
    for (0..33) |fuel_value| {
        const direct = try MeteringDirect.initialState(std.testing.allocator, input);
        defer MeteringDirect.deinitState(direct);
        const kernel = try MeteringKernel.initialState(std.testing.allocator, input);
        defer MeteringKernel.deinitState(kernel);
        var direct_fuel: u64 = fuel_value;
        var kernel_fuel: u64 = fuel_value;
        const direct_outcome = try MeteringDirect.step(direct, &direct_fuel);
        const kernel_outcome = try MeteringKernel.step(kernel, &kernel_fuel);
        try std.testing.expectEqualStrings(
            @tagName(std.meta.activeTag(direct_outcome)),
            @tagName(std.meta.activeTag(kernel_outcome)),
        );
        try std.testing.expectEqual(direct_fuel, kernel_fuel);
        switch (direct_outcome) {
            .yielded => {
                observed_yield = true;
                const direct_state = try MeteringDirect.encodeState(
                    std.testing.allocator,
                    direct,
                );
                defer std.testing.allocator.free(direct_state);
                const kernel_state = try MeteringKernel.encodeState(
                    std.testing.allocator,
                    kernel,
                );
                defer std.testing.allocator.free(kernel_state);
                try std.testing.expectEqualSlices(u8, direct_state, kernel_state);
            },
            .done => |direct_result| {
                observed_done = true;
                defer direct_result.deinit();
                const kernel_result = kernel_outcome.done;
                defer kernel_result.deinit();
                try std.testing.expectEqualStrings(
                    try direct_result.value().slice(),
                    try kernel_result.value().slice(),
                );
            },
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expect(observed_yield);
    try std.testing.expect(observed_done);
}

test "fixed-payload optionals and sums expose variable canonical size" {
    const OptionalLarge = ?[1024]u8;
    const FixedSum = union(enum) {
        empty: void,
        large: [1024]u8,
    };

    try std.testing.expectEqual(
        @as(usize, 1),
        portable_value.minimumEncodedSize(OptionalLarge),
    );
    try std.testing.expectEqual(
        @as(usize, 1025),
        portable_value.maximumEncodedSize(OptionalLarge),
    );
    try std.testing.expect(
        portable_value.hasVariableEncodedSize(OptionalLarge),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        portable_value.minimumEncodedSize(FixedSum),
    );
    try std.testing.expectEqual(
        @as(usize, 1028),
        portable_value.maximumEncodedSize(FixedSum),
    );
    try std.testing.expect(portable_value.hasVariableEncodedSize(FixedSum));
}
