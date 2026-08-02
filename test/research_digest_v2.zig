const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

const Query = portable_value.Text(512);
const Title = portable_value.Text(256);
const Summary = portable_value.Text(1024);
const Separator = portable_value.Text(1);
const Digest = portable_value.Text(8192);

const ResearchRequest = struct {
    query: Query,
    maximum_items: u32,
};

const ResearchItem = struct {
    title: Title,
    summary: Summary,
};

const ResearchItems = portable_value.Vector(ResearchItem, 8);

const ResearchResponse = struct {
    items: ResearchItems,
};

const DigestResult = struct {
    digest: Digest,
    item_count: u32,
};

const ResearchLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "research.lookup.v2";
    pub const Payload = ResearchRequest;
    pub const Resume = ResearchResponse;
};

const value_types = [_]cir.ValueType{
    .{ .schema = 0 }, // v0  entry request
    .{ .schema = 6 }, // v1  lookup response
    .{ .schema = 5 }, // v2  response items
    .{ .scalar = .u32 }, // v3  item count
    .{ .scalar = .u32 }, // v4  initial index
    .{ .schema = 7 }, // v5  initial digest
    .{ .schema = 5 }, // v6  loop items
    .{ .scalar = .u32 }, // v7  loop count
    .{ .scalar = .u32 }, // v8  loop index
    .{ .schema = 7 }, // v9  loop digest
    .{ .scalar = .boolean }, // v10 loop condition
    .{ .schema = 5 }, // v11 body items
    .{ .scalar = .u32 }, // v12 body count
    .{ .scalar = .u32 }, // v13 body index
    .{ .schema = 7 }, // v14 body digest
    .{ .schema = 2 }, // v15 current item
    .{ .schema = 3 }, // v16 title
    .{ .schema = 4 }, // v17 summary
    .{ .schema = 7 }, // v18 digest after title
    .{ .schema = 8 }, // v19 separator
    .{ .schema = 7 }, // v20 digest after separator
    .{ .schema = 7 }, // v21 digest after summary
    .{ .schema = 7 }, // v22 completed item digest
    .{ .scalar = .u32 }, // v23 one
    .{ .scalar = .u32 }, // v24 next index
    .{ .schema = 7 }, // v25 result digest
    .{ .scalar = .u32 }, // v26 result count
    .{ .schema = 9 }, // v27 result
};

const lookup_continuation_arguments = [_]cir.EdgeArgument{.@"resume"};
const initial_loop_arguments = [_]cir.EdgeArgument{
    .{ .value = 2 },
    .{ .value = 3 },
    .{ .value = 4 },
    .{ .value = 5 },
};
const loop_body_arguments = [_]cir.EdgeArgument{
    .{ .value = 6 },
    .{ .value = 7 },
    .{ .value = 8 },
    .{ .value = 9 },
};
const loop_exit_arguments = [_]cir.EdgeArgument{
    .{ .value = 9 },
    .{ .value = 7 },
};
const loop_back_arguments = [_]cir.EdgeArgument{
    .{ .value = 11 },
    .{ .value = 12 },
    .{ .value = 24 },
    .{ .value = 22 },
};

const response_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{1},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{2},
        .operation = .vector_length,
    },
    .{
        .kind = .constant,
        .result = 4,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 5,
        .operation = .text_empty,
    },
};

const loop_header_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 10,
        .operands = &.{ 8, 7 },
        .operation = .integer_less_than,
    },
};

const loop_body_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 15,
        .operands = &.{ 11, 13 },
        .operation = .vector_get,
    },
    .{
        .kind = .pure,
        .result = 16,
        .operands = &.{15},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 17,
        .operands = &.{15},
        .operation = .{ .product_extract = 1 },
    },
    .{
        .kind = .pure,
        .result = 18,
        .operands = &.{ 14, 16 },
        .operation = .text_append,
    },
    .{
        .kind = .constant,
        .result = 19,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 20,
        .operands = &.{ 18, 19 },
        .operation = .text_append,
    },
    .{
        .kind = .pure,
        .result = 21,
        .operands = &.{ 20, 17 },
        .operation = .text_append,
    },
    .{
        .kind = .pure,
        .result = 22,
        .operands = &.{ 21, 19 },
        .operation = .text_append,
    },
    .{
        .kind = .constant,
        .result = 23,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 24,
        .operands = &.{ 13, 23 },
        .operation = .integer_add,
    },
};

const result_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 27,
        .operands = &.{ 25, 26 },
        .operation = .product_construct,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &lookup_continuation_arguments,
            },
            .resume_type = .{ .schema = 6 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .instructions = &response_instructions,
        .terminator = .{ .jump = .{
            .target = 2,
            .arguments = &initial_loop_arguments,
        } },
    },
    .{
        .id = 2,
        .role = .loop_header,
        .parameters = &.{ 6, 7, 8, 9 },
        .instructions = &loop_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 10,
            .then_edge = .{
                .target = 3,
                .arguments = &loop_body_arguments,
            },
            .else_edge = .{
                .target = 4,
                .arguments = &loop_exit_arguments,
            },
        } },
    },
    .{
        .id = 3,
        .parameters = &.{ 11, 12, 13, 14 },
        .instructions = &loop_body_instructions,
        .terminator = .{ .jump = .{
            .target = 2,
            .arguments = &loop_back_arguments,
        } },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{ 25, 26 },
        .instructions = &result_instructions,
        .terminator = .{ .return_value = 27 },
    },
};

const Body = struct {
    pub const InitialArgs = ResearchRequest;
    pub const Result = DigestResult;
    pub const Failure = enum {
        arithmetic_overflow,
        capacity_exceeded,
        invalid_index,
    };
    pub const contract_bytes = "research-digest-v2\x00machine-owned";
    pub const constants = .{
        @as(u32, 0),
        Separator.fromSlice("\n") catch unreachable,
        @as(u32, 1),
    };
    pub const effect_sites = .{ResearchLookup};
    pub const schema_types = .{
        ResearchRequest,
        Query,
        ResearchItem,
        Title,
        Summary,
        ResearchItems,
        ResearchResponse,
        Digest,
        Separator,
        DigestResult,
    };
    pub const control_ir: cir.Program = .{
        .label = "research-digest-v2",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 9 },
    };
};

const Program = program_v2.program("research-digest-v2", Body);
const DigestMachine = Program.compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 1 << 20,
    .maximum_machine_fuel = 1024,
});

test "Research Digest v2 formats capability data inside the Machine" {
    try std.testing.expect(Program.maximum_segment_value_bytes > 0);
    try std.testing.expect(
        Program.maximum_segment_value_bytes <
            Program.reachable_value_catalog_bytes,
    );

    var saw_loop_body = false;
    for (Program.rnf.constructorSlice()) |constructor| {
        if (constructor.source_block != 3 or
            constructor.kind != .segment_entry)
        {
            continue;
        }
        saw_loop_body = true;
        const expected_environment = [_]cir.ValueId{ 11, 12, 13, 14 };
        try std.testing.expectEqual(
            expected_environment.len,
            constructor.environment_len,
        );
        for (
            constructor.environmentFields(),
            expected_environment,
        ) |field, expected_value| {
            try std.testing.expectEqual(expected_value, field.value);
        }

        var saw_loop_predicate = false;
        var saw_historical_edge_copy = false;
        for (constructor.invariantTerms()) |term| switch (term) {
            .integer_relation => |predicate| {
                saw_loop_predicate = predicate.left == 13 and
                    predicate.right == 12 and
                    predicate.relation == .less_than and
                    predicate.expected;
            },
            .value_copy => saw_historical_edge_copy = true,
            else => {},
        };
        try std.testing.expect(saw_loop_predicate);
        try std.testing.expect(!saw_historical_edge_copy);
    }
    try std.testing.expect(saw_loop_body);

    var query = try Query.fromSlice("portable resumptions");
    query.storage[511] = 17;
    const initial_state = try DigestMachine.initialState(
        std.testing.allocator,
        .{
            .query = query,
            .maximum_items = 8,
        },
    );
    defer DigestMachine.deinitState(initial_state);

    var first_fuel: u64 = 8;
    var request = switch (try DigestMachine.step(initial_state, &first_fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const pending_bytes = try DigestMachine.encodeState(
        std.testing.allocator,
        initial_state,
    );
    defer std.testing.allocator.free(pending_bytes);
    const pending_state = try DigestMachine.decodeState(
        std.testing.allocator,
        pending_bytes,
    );
    defer DigestMachine.deinitState(pending_state);

    switch (request.value) {
        .s0 => |*payload| {
            try std.testing.expectEqualStrings(
                "portable resumptions",
                payload.query.slice(),
            );
            try std.testing.expectEqual(@as(u32, 8), payload.maximum_items);
            payload.query.storage[511] = 239;
        },
    }

    var items = ResearchItems.empty();
    try items.push(.{
        .title = try Title.fromSlice("Alpha"),
        .summary = try Summary.fromSlice("First"),
    });
    try items.push(.{
        .title = try Title.fromSlice("Beta"),
        .summary = try Summary.fromSlice("Second"),
    });
    {
        const prepared_resume = try DigestMachine.prepareResume(
            pending_state,
            request,
        );
        defer DigestMachine.deinitPreparedResume(prepared_resume);
        try DigestMachine.@"resume"(
            prepared_resume,
            ResearchResponse{ .items = items },
        );
    }

    var loop_fuel: u64 = 24;
    switch (try DigestMachine.step(pending_state, &loop_fuel)) {
        .yielded => {},
        else => return error.TestUnexpectedResult,
    }
    const loop_bytes = try DigestMachine.encodeState(
        std.testing.allocator,
        pending_state,
    );
    defer std.testing.allocator.free(loop_bytes);
    const continued_state = try DigestMachine.decodeState(
        std.testing.allocator,
        loop_bytes,
    );
    defer DigestMachine.deinitState(continued_state);

    const malformed = try std.testing.allocator.dupe(u8, loop_bytes);
    defer std.testing.allocator.free(malformed);
    const state_header_length = 8 + 2 + 2 + 32 + 8 + 8 + 4 + 4;
    const environment_offset = state_header_length + 4 + 4;
    const count_offset = environment_offset +
        try portable_value.encodedSize(ResearchItems, items);
    const index_offset = count_offset + @sizeOf(u32);
    std.mem.writeInt(u32, malformed[index_offset..][0..4], 3, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        DigestMachine.decodeState(std.testing.allocator, malformed),
    );

    var completion_fuel: u64 = 1024;
    const done = switch (try DigestMachine.step(
        continued_state,
        &completion_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 2), done.value().item_count);
    try std.testing.expectEqualStrings(
        "Alpha\nFirst\nBeta\nSecond\n",
        done.value().digest.slice(),
    );
}
