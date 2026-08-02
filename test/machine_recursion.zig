const cir = @import("control_ir");
const program_v2 = @import("program_v2");
const std = @import("std");

const state_header_length = 8 + 2 + 2 + 32 + 8 + 8 + 4 + 4;
const frame_header_length = 4 + 4;

const root_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 0 },
    .{ .value = 1 },
    .{ .value = 2 },
};
const root_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const recurse_body_arguments = [_]cir.EdgeArgument{
    .{ .value = 3 },
    .{ .value = 4 },
    .{ .value = 5 },
};
const recurse_done_arguments = [_]cir.EdgeArgument{
    .{ .value = 5 },
};
const recursive_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 7 },
    .{ .value = 11 },
    .{ .value = 12 },
};
const recursive_return_arguments = [_]cir.EdgeArgument{.@"resume"};

const root_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 0 },
    },
};
const recurse_header_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 6,
        .operands = &.{ 4, 3 },
        .operation = .integer_less_than,
    },
};
const recurse_body_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 10,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 11,
        .operands = &.{ 8, 10 },
        .operation = .integer_add,
    },
    .{
        .kind = .pure,
        .result = 12,
        .operands = &.{ 9, 11 },
        .operation = .integer_add,
    },
};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &root_call_arguments,
            },
            .continuation = .{
                .target = 4,
                .arguments = &root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .role = .loop_header,
        .parameters = &.{ 3, 4, 5 },
        .instructions = &recurse_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 6,
            .then_edge = .{
                .target = 2,
                .arguments = &recurse_body_arguments,
            },
            .else_edge = .{
                .target = 3,
                .arguments = &recurse_done_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{ 7, 8, 9 },
        .instructions = &recurse_body_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &recursive_call_arguments,
            },
            .continuation = .{
                .target = 5,
                .arguments = &recursive_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{14},
        .terminator = .{ .return_to_caller = 14 },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{15},
        .terminator = .{ .return_value = 15 },
    },
    .{
        .id = 5,
        .function_id = 1,
        .role = .call_return,
        .parameters = &.{13},
        .terminator = .{ .return_to_caller = 13 },
    },
};

const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{
        @as(u32, 0),
        @as(u32, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "bounded-recursive-helper",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const Program = program_v2.program("bounded-recursive-helper", Body);

const staged_second_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 16 },
    .{ .value = 17 },
    .{ .value = 18 },
};
const staged_third_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 19 },
    .{ .value = 20 },
    .{ .value = 22 },
};
const staged_first_yield_arguments = [_]cir.EdgeArgument{.{ .value = 15 }};
const staged_second_yield_arguments = [_]cir.EdgeArgument{.{ .value = 21 }};
const staged_base_yield_arguments = [_]cir.EdgeArgument{.{ .value = 14 }};
const staged_second_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 16,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .constant,
        .result = 17,
        .operation = .{ .constant = 0 },
    },
};
const staged_third_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 19,
        .operation = .{ .constant = 3 },
    },
    .{
        .kind = .constant,
        .result = 20,
        .operation = .{ .constant = 0 },
    },
};
const staged_blocks = [_]cir.Block{
    blocks[0],
    blocks[1],
    blocks[2],
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{14},
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 10,
                .arguments = &staged_base_yield_arguments,
            },
        } },
    },
    .{
        .id = 4,
        .parameters = &.{15},
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 6,
                .arguments = &staged_first_yield_arguments,
            },
        } },
    },
    blocks[5],
    .{
        .id = 6,
        .parameters = &.{18},
        .instructions = &staged_second_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &staged_second_call_arguments,
            },
            .continuation = .{
                .target = 7,
                .arguments = &root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 7,
        .parameters = &.{21},
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 8,
                .arguments = &staged_second_yield_arguments,
            },
        } },
    },
    .{
        .id = 8,
        .parameters = &.{22},
        .instructions = &staged_third_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &staged_third_call_arguments,
            },
            .continuation = .{
                .target = 9,
                .arguments = &root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 9,
        .role = .terminal_handoff,
        .parameters = &.{23},
        .terminator = .{ .return_value = 23 },
    },
    .{
        .id = 10,
        .function_id = 1,
        .role = .call_return,
        .parameters = &.{24},
        .terminator = .{ .return_to_caller = 24 },
    },
};
const StagedRegrowthBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { arithmetic_overflow };
    pub const constants = .{
        @as(u32, 0),
        @as(u32, 1),
        @as(u32, 5),
        @as(u32, 6),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "staged-recursive-regrowth",
        .value_types = &.{
            .{ .scalar = .u32 }, // 0
            .{ .scalar = .u32 }, // 1
            .{ .scalar = .u32 }, // 2
            .{ .scalar = .u32 }, // 3
            .{ .scalar = .u32 }, // 4
            .{ .scalar = .u32 }, // 5
            .{ .scalar = .boolean }, // 6
            .{ .scalar = .u32 }, // 7
            .{ .scalar = .u32 }, // 8
            .{ .scalar = .u32 }, // 9
            .{ .scalar = .u32 }, // 10
            .{ .scalar = .u32 }, // 11
            .{ .scalar = .u32 }, // 12
            .{ .scalar = .u32 }, // 13
            .{ .scalar = .u32 }, // 14
            .{ .scalar = .u32 }, // 15
            .{ .scalar = .u32 }, // 16
            .{ .scalar = .u32 }, // 17
            .{ .scalar = .u32 }, // 18
            .{ .scalar = .u32 }, // 19
            .{ .scalar = .u32 }, // 20
            .{ .scalar = .u32 }, // 21
            .{ .scalar = .u32 }, // 22
            .{ .scalar = .u32 }, // 23
            .{ .scalar = .u32 }, // 24
        },
        .blocks = &staged_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};
const StagedRegrowthProgram = program_v2.program(
    "staged-recursive-regrowth",
    StagedRegrowthBody,
);

const NonResizingAllocator = struct {
    child: std.mem.Allocator,
    allocation_count: usize = 0,
    free_count: usize = 0,

    fn allocator(self: *@This()) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn alloc(
        context: *anyopaque,
        length: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(context));
        const result = self.child.rawAlloc(
            length,
            alignment,
            return_address,
        );
        if (result != null) self.allocation_count += 1;
        return result;
    }

    fn resize(
        _: *anyopaque,
        _: []u8,
        _: std.mem.Alignment,
        _: usize,
        _: usize,
    ) bool {
        return false;
    }

    fn remap(
        _: *anyopaque,
        _: []u8,
        _: std.mem.Alignment,
        _: usize,
        _: usize,
    ) ?[*]u8 {
        return null;
    }

    fn free(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        const self: *@This() = @ptrCast(@alignCast(context));
        self.free_count += 1;
        self.child.rawFree(memory, alignment, return_address);
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };
};

const alternate_entry_then_arguments = [_]cir.EdgeArgument{
    .{ .value = 0 },
    .{ .value = 1 },
};
const alternate_entry_else_arguments = [_]cir.EdgeArgument{
    .{ .value = 0 },
    .{ .value = 1 },
};
const alternate_entry_then_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 3 },
    .{ .value = 4 },
};
const alternate_entry_else_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 5 },
    .{ .value = 6 },
};
const alternate_entry_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const alternate_entry_root_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{ 0, 1 },
        .operation = .integer_equal,
    },
};
const alternate_entry_helper_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 9,
    .operands = &.{ 7, 8 },
    .operation = .integer_add,
}};
const alternate_entry_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &alternate_entry_root_instructions,
        .terminator = .{ .branch = .{
            .condition = 2,
            .then_edge = .{
                .target = 1,
                .arguments = &alternate_entry_then_arguments,
            },
            .else_edge = .{
                .target = 2,
                .arguments = &alternate_entry_else_arguments,
            },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{ 3, 4 },
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 3,
                .arguments = &alternate_entry_then_call_arguments,
            },
            .continuation = .{
                .target = 4,
                .arguments = &alternate_entry_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 2,
        .parameters = &.{ 5, 6 },
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 3,
                .arguments = &alternate_entry_else_call_arguments,
            },
            .continuation = .{
                .target = 4,
                .arguments = &alternate_entry_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{ 7, 8 },
        .instructions = &alternate_entry_helper_instructions,
        .terminator = .{ .return_to_caller = 9 },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{10},
        .terminator = .{ .return_value = 10 },
    },
};

const AlternateEntryBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{@as(u32, 0)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "alternate-call-entry-provenance",
        .value_types = &.{
            .{ .scalar = .u32 }, // 0: input
            .{ .scalar = .u32 }, // 1: zero
            .{ .scalar = .boolean }, // 2: input equals zero
            .{ .scalar = .u32 }, // 3: then input
            .{ .scalar = .u32 }, // 4: then zero
            .{ .scalar = .u32 }, // 5: else input
            .{ .scalar = .u32 }, // 6: else zero
            .{ .scalar = .u32 }, // 7: helper input
            .{ .scalar = .u32 }, // 8: helper zero
            .{ .scalar = .u32 }, // 9: helper result
            .{ .scalar = .u32 }, // 10: root result
        },
        .blocks = &alternate_entry_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 3,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const AlternateEntryProgram = program_v2.program(
    "alternate-call-entry-provenance",
    AlternateEntryBody,
);

const self_target_call_arguments = [_]cir.EdgeArgument{.{ .value = 0 }};
const self_target_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const self_target_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &self_target_call_arguments,
            },
            .continuation = .{
                .target = 0,
                .arguments = &self_target_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_to_caller = 1 },
    },
};

const SelfTargetBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "self-target-call-continuation",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &self_target_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const SelfTargetProgram = program_v2.program(
    "self-target-call-continuation",
    SelfTargetBody,
);

const backedge_root_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 1 },
    .{ .value = 0 },
};
const backedge_root_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const backedge_body_arguments = [_]cir.EdgeArgument{
    .{ .value = 2 },
    .{ .value = 3 },
};
const backedge_done_arguments = [_]cir.EdgeArgument{.{ .value = 2 }};
const backedge_repeat_arguments = [_]cir.EdgeArgument{
    .{ .value = 8 },
    .{ .value = 6 },
};
const backedge_root_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 1,
    .operation = .{ .constant = 0 },
}};
const backedge_header_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 4,
    .operands = &.{ 2, 3 },
    .operation = .integer_less_than,
}};
const backedge_increment_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 7,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{ 5, 7 },
        .operation = .integer_add,
    },
};
const helper_backedge_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &backedge_root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &backedge_root_call_arguments,
            },
            .continuation = .{
                .target = 4,
                .arguments = &backedge_root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .role = .loop_header,
        .parameters = &.{ 2, 3 },
        .instructions = &backedge_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 4,
            .then_edge = .{
                .target = 2,
                .arguments = &backedge_body_arguments,
            },
            .else_edge = .{
                .target = 3,
                .arguments = &backedge_done_arguments,
            },
        } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{ 5, 6 },
        .instructions = &backedge_increment_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 1,
                .arguments = &backedge_repeat_arguments,
            },
        } },
    },
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{9},
        .terminator = .{ .return_to_caller = 9 },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{10},
        .terminator = .{ .return_value = 10 },
    },
};

const HelperBackedgeBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{
        @as(u32, 0),
        @as(u32, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "helper-entry-backedge",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &helper_backedge_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const HelperBackedgeProgram = program_v2.program(
    "helper-entry-backedge",
    HelperBackedgeBody,
);

const ObserveCurrent = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "observe-current.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};
const observed_root_call_arguments = [_]cir.EdgeArgument{
    .{ .value = 1 },
    .{ .value = 0 },
};
const observed_root_return_arguments = [_]cir.EdgeArgument{.@"resume"};
const observed_effect_arguments = [_]cir.EdgeArgument{
    .{ .value = 2 },
    .{ .value = 3 },
    .@"resume",
};
const observed_then_arguments = [_]cir.EdgeArgument{
    .{ .value = 4 },
    .{ .value = 5 },
};
const observed_else_arguments = [_]cir.EdgeArgument{.{ .value = 4 }};
const observed_repeat_arguments = [_]cir.EdgeArgument{
    .{ .value = 11 },
    .{ .value = 9 },
};
const observed_root_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 1,
    .operation = .{ .constant = 0 },
}};
const observed_compare_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 7,
    .operands = &.{ 4, 5 },
    .operation = .integer_less_than,
}};
const observed_increment_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 10,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 11,
        .operands = &.{ 8, 10 },
        .operation = .integer_add,
    },
};
const observed_backedge_blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &observed_root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = 1,
            .callee = .{
                .target = 1,
                .arguments = &observed_root_call_arguments,
            },
            .continuation = .{
                .target = 5,
                .arguments = &observed_root_return_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .function_id = 1,
        .role = .loop_header,
        .parameters = &.{ 2, 3 },
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{2},
            .continuation = .{
                .target = 2,
                .arguments = &observed_effect_arguments,
            },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .parameters = &.{ 4, 5, 6 },
        .instructions = &observed_compare_instructions,
        .terminator = .{ .branch = .{
            .condition = 7,
            .then_edge = .{
                .target = 3,
                .arguments = &observed_then_arguments,
            },
            .else_edge = .{
                .target = 4,
                .arguments = &observed_else_arguments,
            },
        } },
    },
    .{
        .id = 3,
        .function_id = 1,
        .parameters = &.{ 8, 9 },
        .instructions = &observed_increment_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .explicit_yield,
            .continuation = .{
                .target = 1,
                .arguments = &observed_repeat_arguments,
            },
        } },
    },
    .{
        .id = 4,
        .function_id = 1,
        .parameters = &.{12},
        .terminator = .{ .return_to_caller = 12 },
    },
    .{
        .id = 5,
        .role = .terminal_handoff,
        .parameters = &.{13},
        .terminator = .{ .return_value = 13 },
    },
};

const ObservedBackedgeBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum {
        arithmetic_overflow,
    };
    pub const constants = .{
        @as(u32, 0),
        @as(u32, 1),
    };
    pub const effect_sites = .{ObserveCurrent};
    pub const schema_types = .{};
    pub const control_ir: cir.Program = .{
        .label = "observed-helper-entry-backedge",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .boolean },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &observed_backedge_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
        .functions = &.{
            .{
                .id = 0,
                .entry = 0,
                .result_type = .{ .scalar = .u32 },
            },
            .{
                .id = 1,
                .entry = 1,
                .result_type = .{ .scalar = .u32 },
            },
        },
    };
};

const ObservedBackedgeProgram = program_v2.program(
    "observed-helper-entry-backedge",
    ObservedBackedgeBody,
);

test "compiled bounded recursive frames survive canonical round trip" {
    var call_return_count: usize = 0;
    for (Program.rnf.constructorSlice()) |constructor| {
        if (constructor.kind == .call_return and
            constructor.origin == .suspension)
        {
            call_return_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), call_return_count);

    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try RecursiveMachine.initialState(std.testing.allocator, 3);
    defer RecursiveMachine.deinitState(state);

    var split_fuel: u64 = 3;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(state, &split_fuel),
    );
    try std.testing.expectEqual(@as(u64, 0), split_fuel);

    const encoded = try RecursiveMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    const restored = try RecursiveMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer RecursiveMachine.deinitState(restored);

    var completion_fuel: u64 = 32;
    const done = switch (try RecursiveMachine.step(restored, &completion_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 6), done.value().*);
    try std.testing.expectEqual(@as(u64, 7), completion_fuel);
}

test "helper entry backedges rebind future state without overwriting activation context" {
    for (HelperBackedgeProgram.rnf.constructorSlice()) |constructor| {
        try std.testing.expect(
            constructor.source_block != 1 or
                constructor.origin != .block_entry,
        );
    }
    const call_entry_id = blk: {
        for (HelperBackedgeProgram.rnf.entryTransitionSlice()) |transition| {
            if (transition.source_block == 0 and
                transition.edge_kind == .call and
                transition.target_block == 1)
            {
                break :blk transition.constructor_id;
            }
        }
        return error.TestExpectedEqual;
    };
    const progressed_entry_id = blk: {
        for (HelperBackedgeProgram.rnf.entryTransitionSlice()) |transition| {
            if (transition.source_block == 2 and
                transition.edge_kind == .suspension_continuation and
                transition.target_block == 1)
            {
                break :blk transition.constructor_id;
            }
        }
        return error.TestExpectedEqual;
    };
    try std.testing.expect(call_entry_id != progressed_entry_id);
    try std.testing.expectEqual(
        .call_entry,
        HelperBackedgeProgram.rnf.constructors[call_entry_id].origin,
    );
    try std.testing.expectEqual(
        .suspension,
        HelperBackedgeProgram.rnf.constructors[progressed_entry_id].origin,
    );
    const call_entry = HelperBackedgeProgram.rnf.constructors[call_entry_id];
    const progressed_entry = HelperBackedgeProgram.rnf.constructors[
        progressed_entry_id
    ];
    try std.testing.expect(call_entry.activation_len > 0);
    for (call_entry.activationFields()) |activation_field| {
        for (call_entry.environmentFields()) |environment_field| {
            try std.testing.expect(
                activation_field.value != environment_field.value,
            );
        }
    }
    var progressed_overlap = false;
    for (progressed_entry.activationFields()) |activation_field| {
        for (progressed_entry.environmentFields()) |environment_field| {
            progressed_overlap = progressed_overlap or
                activation_field.value == environment_field.value;
        }
    }
    try std.testing.expect(progressed_overlap);

    const BackedgeMachine = HelperBackedgeProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try BackedgeMachine.initialState(std.testing.allocator, 2);
    defer BackedgeMachine.deinitState(state);

    var caller_fuel: u64 = 16;
    try std.testing.expectEqual(
        BackedgeMachine.Outcome.yielded,
        try BackedgeMachine.step(state, &caller_fuel),
    );
    const encoded = try BackedgeMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try BackedgeMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer BackedgeMachine.deinitState(restored);

    try std.testing.expectEqual(
        BackedgeMachine.Outcome.yielded,
        try BackedgeMachine.step(restored, &caller_fuel),
    );
    const done = switch (try BackedgeMachine.step(restored, &caller_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 2), done.value().*);
}

test "progressed helper requests observe current environment before activation" {
    const ObservedMachine = ObservedBackedgeProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try ObservedMachine.initialState(std.testing.allocator, 2);
    defer ObservedMachine.deinitState(state);
    var caller_fuel: u64 = 64;

    const first = switch (try ObservedMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    switch (first.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 0), payload),
    }
    {
        const prepared = try ObservedMachine.prepareResume(state, first);
        defer ObservedMachine.deinitPreparedResume(prepared);
        try ObservedMachine.@"resume"(prepared, @as(u32, 0));
    }
    try std.testing.expectEqual(
        ObservedMachine.Outcome.yielded,
        try ObservedMachine.step(state, &caller_fuel),
    );

    const second = switch (try ObservedMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    switch (second.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 1), payload),
    }
    {
        const prepared = try ObservedMachine.prepareResume(state, second);
        defer ObservedMachine.deinitPreparedResume(prepared);
        try ObservedMachine.@"resume"(prepared, @as(u32, 0));
    }
    try std.testing.expectEqual(
        ObservedMachine.Outcome.yielded,
        try ObservedMachine.step(state, &caller_fuel),
    );

    const third = switch (try ObservedMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    switch (third.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 2), payload),
    }
    {
        const prepared = try ObservedMachine.prepareResume(state, third);
        defer ObservedMachine.deinitPreparedResume(prepared);
        try ObservedMachine.@"resume"(prepared, @as(u32, 0));
    }
    const done = switch (try ObservedMachine.step(state, &caller_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 2), done.value().*);
}

test "linear PreparedResume reclaims fixed-buffer capacity before reduction" {
    const ObservedMachine = ObservedBackedgeProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    var backing: [64 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&backing);

    {
        const state = try ObservedMachine.initialState(fixed.allocator(), 2);
        defer ObservedMachine.deinitState(state);
        var caller_fuel: u64 = 64;
        const request = switch (try ObservedMachine.step(state, &caller_fuel)) {
            .request => |value| value,
            else => return error.TestUnexpectedResult,
        };
        const parked_high_water = fixed.end_index;

        for (0..32) |_| {
            const abandoned = try ObservedMachine.prepareResume(state, request);
            try std.testing.expectError(
                error.ProgramContractViolation,
                ObservedMachine.prepareResume(state, request),
            );
            ObservedMachine.deinitPreparedResume(abandoned);
            try std.testing.expectEqual(parked_high_water, fixed.end_index);
        }

        {
            const prepared = try ObservedMachine.prepareResume(state, request);
            defer ObservedMachine.deinitPreparedResume(prepared);
            try ObservedMachine.@"resume"(prepared, @as(u32, 0));
            const fuel_before = caller_fuel;
            try std.testing.expectError(
                error.ProgramContractViolation,
                ObservedMachine.step(state, &caller_fuel),
            );
            try std.testing.expectEqual(fuel_before, caller_fuel);
        }

        try std.testing.expectEqual(
            ObservedMachine.Outcome.yielded,
            try ObservedMachine.step(state, &caller_fuel),
        );
    }
    try std.testing.expectEqual(@as(usize, 0), fixed.end_index);
}

test "progressed helper rejects an authentic child from another invocation" {
    const BackedgeMachine = HelperBackedgeProgram.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const recipient_state = try BackedgeMachine.initialState(
        std.testing.allocator,
        2,
    );
    defer BackedgeMachine.deinitState(recipient_state);
    const donor_state = try BackedgeMachine.initialState(
        std.testing.allocator,
        3,
    );
    defer BackedgeMachine.deinitState(donor_state);

    var recipient_fuel: u64 = 16;
    try std.testing.expectEqual(
        BackedgeMachine.Outcome.yielded,
        try BackedgeMachine.step(recipient_state, &recipient_fuel),
    );
    var donor_fuel: u64 = 16;
    try std.testing.expectEqual(
        BackedgeMachine.Outcome.yielded,
        try BackedgeMachine.step(donor_state, &donor_fuel),
    );

    const recipient = try BackedgeMachine.encodeState(
        std.testing.allocator,
        recipient_state,
    );
    defer std.testing.allocator.free(recipient);
    const donor = try BackedgeMachine.encodeState(
        std.testing.allocator,
        donor_state,
    );
    defer std.testing.allocator.free(donor);
    const frame_count_offset = state_header_length - 8;
    try std.testing.expectEqual(
        @as(u32, 2),
        std.mem.readInt(u32, recipient[frame_count_offset..][0..4], .little),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        std.mem.readInt(u32, donor[frame_count_offset..][0..4], .little),
    );
    const recipient_parent_length = std.mem.readInt(
        u32,
        recipient[state_header_length + 4 ..][0..4],
        .little,
    );
    const donor_parent_length = std.mem.readInt(
        u32,
        donor[state_header_length + 4 ..][0..4],
        .little,
    );
    try std.testing.expectEqual(recipient_parent_length, donor_parent_length);
    const child_offset = state_header_length +
        frame_header_length + recipient_parent_length;
    const recipient_child_length = std.mem.readInt(
        u32,
        recipient[child_offset + 4 ..][0..4],
        .little,
    );
    const donor_child_length = std.mem.readInt(
        u32,
        donor[child_offset + 4 ..][0..4],
        .little,
    );
    try std.testing.expectEqual(recipient_child_length, donor_child_length);
    try std.testing.expectEqualSlices(
        u8,
        recipient[child_offset..][0..4],
        donor[child_offset..][0..4],
    );

    const forged = try std.testing.allocator.dupe(u8, recipient);
    defer std.testing.allocator.free(forged);
    const child_total_length = frame_header_length + recipient_child_length;
    @memcpy(
        forged[child_offset..][0..child_total_length],
        donor[child_offset..][0..child_total_length],
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        BackedgeMachine.decodeState(std.testing.allocator, forged),
    );
}

test "call-created entry binds parent and child arguments" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try RecursiveMachine.initialState(std.testing.allocator, 3);
    defer RecursiveMachine.deinitState(state);

    var enter_helper_fuel: u64 = 3;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(state, &enter_helper_fuel),
    );
    const encoded = try RecursiveMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);

    const authentic = try RecursiveMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    RecursiveMachine.deinitState(authentic);

    const frame_count_offset = state_header_length - 8;
    try std.testing.expectEqual(
        @as(u32, 2),
        std.mem.readInt(u32, encoded[frame_count_offset..][0..4], .little),
    );
    const parent_environment_length = std.mem.readInt(
        u32,
        encoded[state_header_length + 4 ..][0..4],
        .little,
    );
    const child_environment_offset = state_header_length +
        frame_header_length + parent_environment_length +
        frame_header_length;
    const forged = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(forged);
    std.mem.writeInt(
        u32,
        forged[child_environment_offset + 4 ..][0..4],
        4,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        RecursiveMachine.decodeState(std.testing.allocator, forged),
    );
}

test "machine call stack rejects an authentic alternate call entry" {
    const then_call_entry_id = blk: {
        for (AlternateEntryProgram.rnf.entryTransitionSlice()) |transition| {
            if (transition.source_block == 1 and
                transition.edge_kind == .call and
                transition.target_block == 3)
            {
                break :blk transition.constructor_id;
            }
        }
        return error.TestExpectedEqual;
    };
    const else_call_entry_id = blk: {
        for (AlternateEntryProgram.rnf.entryTransitionSlice()) |transition| {
            if (transition.source_block == 2 and
                transition.edge_kind == .call and
                transition.target_block == 3)
            {
                break :blk transition.constructor_id;
            }
        }
        return error.TestExpectedEqual;
    };
    try std.testing.expect(then_call_entry_id != else_call_entry_id);
    try std.testing.expectEqual(
        .call_entry,
        AlternateEntryProgram.rnf.constructors[then_call_entry_id].origin,
    );
    try std.testing.expectEqual(
        .call_entry,
        AlternateEntryProgram.rnf.constructors[else_call_entry_id].origin,
    );

    const AlternateEntryMachine = AlternateEntryProgram.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });

    const then_state = try AlternateEntryMachine.initialState(
        std.testing.allocator,
        0,
    );
    defer AlternateEntryMachine.deinitState(then_state);
    var then_fuel: u64 = 4;
    try std.testing.expectEqual(
        AlternateEntryMachine.Outcome.yielded,
        try AlternateEntryMachine.step(then_state, &then_fuel),
    );
    const then_encoded = try AlternateEntryMachine.encodeState(
        std.testing.allocator,
        then_state,
    );
    defer std.testing.allocator.free(then_encoded);

    const else_state = try AlternateEntryMachine.initialState(
        std.testing.allocator,
        1,
    );
    defer AlternateEntryMachine.deinitState(else_state);
    var else_fuel: u64 = 4;
    try std.testing.expectEqual(
        AlternateEntryMachine.Outcome.yielded,
        try AlternateEntryMachine.step(else_state, &else_fuel),
    );
    const else_encoded = try AlternateEntryMachine.encodeState(
        std.testing.allocator,
        else_state,
    );
    defer std.testing.allocator.free(else_encoded);

    const frame_count_offset = state_header_length - 8;
    try std.testing.expectEqual(
        @as(u32, 2),
        std.mem.readInt(u32, then_encoded[frame_count_offset..][0..4], .little),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        std.mem.readInt(u32, else_encoded[frame_count_offset..][0..4], .little),
    );
    const then_parent_environment_length = std.mem.readInt(
        u32,
        then_encoded[state_header_length + 4 ..][0..4],
        .little,
    );
    const else_parent_environment_length = std.mem.readInt(
        u32,
        else_encoded[state_header_length + 4 ..][0..4],
        .little,
    );
    const then_child_offset = state_header_length +
        frame_header_length + then_parent_environment_length;
    const else_child_offset = state_header_length +
        frame_header_length + else_parent_environment_length;
    try std.testing.expectEqual(
        @as(u32, @intCast(then_call_entry_id)),
        std.mem.readInt(u32, then_encoded[then_child_offset..][0..4], .little),
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(else_call_entry_id)),
        std.mem.readInt(u32, else_encoded[else_child_offset..][0..4], .little),
    );
    try std.testing.expectEqual(
        then_encoded.len - then_child_offset,
        else_encoded.len - else_child_offset,
    );

    const forged = try std.testing.allocator.dupe(u8, then_encoded);
    defer std.testing.allocator.free(forged);
    std.mem.copyForwards(
        u8,
        forged[then_child_offset..],
        else_encoded[else_child_offset..],
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        AlternateEntryMachine.decodeState(std.testing.allocator, forged),
    );
}

test "shallow recursive stepping allocates from logical depth" {
    const WideMachine = HelperBackedgeProgram.compile(.{
        .maximum_frames = 1 << 20,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const backing = try std.testing.allocator.alloc(u8, 64 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const state = try WideMachine.initialState(fixed.allocator(), 2);
    defer WideMachine.deinitState(state);

    var caller_fuel: u64 = 16;
    try std.testing.expectEqual(
        WideMachine.Outcome.yielded,
        try WideMachine.step(state, &caller_fuel),
    );
    const retained_high_water = fixed.end_index;
    var no_fuel: u64 = 0;
    try std.testing.expectEqual(
        WideMachine.Outcome.yielded,
        try WideMachine.step(state, &no_fuel),
    );
    try std.testing.expectEqual(retained_high_water, fixed.end_index);
}

test "multi-frame commits reuse fixed-buffer transaction storage" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const state = try RecursiveMachine.initialState(fixed.allocator(), 3);
    defer RecursiveMachine.deinitState(state);

    var enter_helper_fuel: u64 = 1;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(state, &enter_helper_fuel),
    );
    const retained_high_water = fixed.end_index;

    for (0..32) |_| {
        var no_fuel: u64 = 0;
        try std.testing.expectEqual(
            RecursiveMachine.Outcome.yielded,
            try RecursiveMachine.step(state, &no_fuel),
        );
        try std.testing.expectEqual(
            retained_high_water,
            fixed.end_index,
        );
    }
}

test "fixed-buffer state owns every recursive growth predecessor" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 16,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 128,
    });
    const backing = try std.testing.allocator.alloc(u8, 2 << 20);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const state = try RecursiveMachine.initialState(fixed.allocator(), 8);

    var done: ?*RecursiveMachine.OwnedResult = null;
    for (0..128) |_| {
        var caller_fuel: u64 = 4;
        switch (try RecursiveMachine.step(state, &caller_fuel)) {
            .yielded => try RecursiveMachine.validateState(state),
            .done => |result| {
                done = result;
                break;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    const result = done orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 36), result.value().*);
    result.deinit();
    RecursiveMachine.deinitState(state);
    try std.testing.expectEqual(@as(usize, 0), fixed.end_index);
}

test "retained capacity bounds repeated recursive unwind and regrowth" {
    const StagedMachine = StagedRegrowthProgram.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 512,
    });
    var non_resizing = NonResizingAllocator{
        .child = std.testing.allocator,
    };
    const state = try StagedMachine.initialState(
        non_resizing.allocator(),
        4,
    );

    const expected_depths = [_]u32{ 6, 1, 7, 1, 8 };
    inline for (expected_depths) |expected_depth| {
        var caller_fuel: u64 = 128;
        try std.testing.expectEqual(
            StagedMachine.Outcome.yielded,
            try StagedMachine.step(state, &caller_fuel),
        );
        try StagedMachine.validateState(state);
        const encoded = try StagedMachine.encodeState(
            std.testing.allocator,
            state,
        );
        defer std.testing.allocator.free(encoded);
        const frame_count_offset = state_header_length - 8;
        try std.testing.expectEqual(
            expected_depth,
            std.mem.readInt(
                u32,
                encoded[frame_count_offset..][0..4],
                .little,
            ),
        );
    }
    var completion_fuel: u64 = 128;
    const result = switch (try StagedMachine.step(
        state,
        &completion_fuel,
    )) {
        .done => |done| done,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u32, 46), result.value().*);
    result.deinit();
    StagedMachine.deinitState(state);
    try std.testing.expectEqual(
        non_resizing.allocation_count,
        non_resizing.free_count,
    );
}

test "fixed-buffer decoded terminal state fully releases in ownership order" {
    const RecursiveMachine = Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const source = try RecursiveMachine.initialState(std.testing.allocator, 3);
    defer RecursiveMachine.deinitState(source);

    var split_fuel: u64 = 3;
    try std.testing.expectEqual(
        RecursiveMachine.Outcome.yielded,
        try RecursiveMachine.step(source, &split_fuel),
    );
    const encoded = try RecursiveMachine.encodeState(
        std.testing.allocator,
        source,
    );
    defer std.testing.allocator.free(encoded);

    const backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const restored = try RecursiveMachine.decodeState(
        fixed.allocator(),
        encoded,
    );

    var completion_fuel: u64 = 32;
    const done = switch (try RecursiveMachine.step(
        restored,
        &completion_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u32, 6), done.value().*);
    done.deinit();
    RecursiveMachine.deinitState(restored);
    try std.testing.expectEqual(@as(usize, 0), fixed.end_index);

    const state_first_backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(state_first_backing);
    var state_first_fixed = std.heap.FixedBufferAllocator.init(
        state_first_backing,
    );
    const state_first = try RecursiveMachine.decodeState(
        state_first_fixed.allocator(),
        encoded,
    );
    var state_first_fuel: u64 = 32;
    const state_first_done = switch (try RecursiveMachine.step(
        state_first,
        &state_first_fuel,
    )) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    RecursiveMachine.deinitState(state_first);
    try std.testing.expectEqual(@as(u32, 6), state_first_done.value().*);
    state_first_done.deinit();
    try std.testing.expectEqual(
        @as(usize, 0),
        state_first_fixed.end_index,
    );
}

test "decode allocation follows logical frames instead of configured ceiling" {
    const TightMachine = Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const WideMachine = Program.compile(.{
        .maximum_frames = 16,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });

    const tight_source = try TightMachine.initialState(
        std.testing.allocator,
        3,
    );
    defer TightMachine.deinitState(tight_source);
    var tight_fuel: u64 = 3;
    try std.testing.expectEqual(
        TightMachine.Outcome.yielded,
        try TightMachine.step(tight_source, &tight_fuel),
    );
    const tight_encoded = try TightMachine.encodeState(
        std.testing.allocator,
        tight_source,
    );
    defer std.testing.allocator.free(tight_encoded);

    const wide_source = try WideMachine.initialState(
        std.testing.allocator,
        3,
    );
    defer WideMachine.deinitState(wide_source);
    var wide_fuel: u64 = 3;
    try std.testing.expectEqual(
        WideMachine.Outcome.yielded,
        try WideMachine.step(wide_source, &wide_fuel),
    );
    const wide_encoded = try WideMachine.encodeState(
        std.testing.allocator,
        wide_source,
    );
    defer std.testing.allocator.free(wide_encoded);
    try std.testing.expectEqual(tight_encoded.len, wide_encoded.len);

    const tight_backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(tight_backing);
    var tight_fixed = std.heap.FixedBufferAllocator.init(tight_backing);
    const tight_restored = try TightMachine.decodeState(
        tight_fixed.allocator(),
        tight_encoded,
    );
    const tight_peak = tight_fixed.end_index;
    TightMachine.deinitState(tight_restored);
    try std.testing.expectEqual(@as(usize, 0), tight_fixed.end_index);

    const wide_backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(wide_backing);
    var wide_fixed = std.heap.FixedBufferAllocator.init(wide_backing);
    const wide_restored = try WideMachine.decodeState(
        wide_fixed.allocator(),
        wide_encoded,
    );
    const wide_peak = wide_fixed.end_index;
    WideMachine.deinitState(wide_restored);
    try std.testing.expectEqual(@as(usize, 0), wide_fixed.end_index);

    try std.testing.expectEqual(tight_peak, wide_peak);
}

test "call continuation may return to its own source block" {
    var block_entry_count: usize = 0;
    var suspension_count: usize = 0;
    for (SelfTargetProgram.rnf.constructorSlice()) |constructor| {
        if (constructor.source_block != 0 or constructor.resume_target != 0) {
            continue;
        }
        switch (constructor.origin) {
            .block_entry => block_entry_count += 1,
            .call_entry => {},
            .suspension => suspension_count += 1,
        }
    }
    try std.testing.expectEqual(@as(usize, 2), block_entry_count);
    try std.testing.expectEqual(@as(usize, 1), suspension_count);

    const SelfTargetMachine = SelfTargetProgram.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 8,
    });
    const state = try SelfTargetMachine.initialState(std.testing.allocator, 7);
    defer SelfTargetMachine.deinitState(state);

    var caller_fuel: u64 = 1;
    try std.testing.expectEqual(
        SelfTargetMachine.Outcome.yielded,
        try SelfTargetMachine.step(state, &caller_fuel),
    );
    const encoded = try SelfTargetMachine.encodeState(
        std.testing.allocator,
        state,
    );
    defer std.testing.allocator.free(encoded);
    const restored = try SelfTargetMachine.decodeState(
        std.testing.allocator,
        encoded,
    );
    defer SelfTargetMachine.deinitState(restored);
    try SelfTargetMachine.validateState(restored);
}

test "compiled frame-depth failure preserves state and caller fuel" {
    const ShallowMachine = Program.compile(.{
        .maximum_frames = 3,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try ShallowMachine.initialState(std.testing.allocator, 3);
    defer ShallowMachine.deinitState(state);

    const before = try ShallowMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var caller_fuel: u64 = 20;
    switch (try ShallowMachine.step(state, &caller_fuel)) {
        .failed => |failure| try std.testing.expectEqual(
            ShallowMachine.Failure.frame_depth_exceeded,
            failure,
        ),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(u64, 20), caller_fuel);

    const after = try ShallowMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
