const cir = @import("control_ir");
const portable_value = @import("portable_value");
const program_v2 = @import("program_v2");
const std = @import("std");

pub const Failure = enum {
    bad_math,
    bad_position,
};
const AuthoredFailure = Failure;

pub const Values = portable_value.Vector(u8, 1);

const value_types = [_]cir.ValueType{
    .{ .scalar = .boolean },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
    .{ .schema = 0 },
    .{ .scalar = .u8 },
    .{ .schema = 1 },
    .{ .scalar = .u32 },
    .{ .schema = 0 },
    .{ .scalar = .u8 },
};
const math_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 1, 2, 3 },
        .operation = .integer_add,
    },
};
const position_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 5,
        .operation = .vector_empty,
    },
    .{
        .kind = .constant,
        .result = 6,
        .operation = .{ .constant = 3 },
    },
    .{
        .kind = .constant,
        .result = 7,
        .operation = .{ .constant = 4 },
    },
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{ 5, 6, 7 },
        .operation = .vector_get,
    },
};
const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .branch = .{
            .condition = 0,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{
        .id = 1,
        .instructions = &math_instructions,
        .terminator = .{ .return_value = 4 },
    },
    .{
        .id = 2,
        .instructions = &position_instructions,
        .terminator = .{ .return_value = 8 },
    },
};

pub const Body = struct {
    pub const InitialArgs = bool;
    pub const Result = u8;
    pub const Failure = AuthoredFailure;
    pub const constants = .{
        @as(u8, std.math.maxInt(u8)),
        @as(u8, 1),
        AuthoredFailure.bad_math,
        @as(u32, 1),
        AuthoredFailure.bad_position,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ AuthoredFailure, Values };
    pub const control_ir: cir.Program = .{
        .label = "authored-failure-v2",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};

pub const Program = program_v2.program("authored-failure-v2", Body);
pub const Image = Program.image();
pub const Machine = Program.compile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 2048,
    .maximum_machine_fuel = 64,
});

pub const bad_math_input = true;
pub const bad_position_input = false;
pub const bad_math_initial_args = [_]u8{1};
pub const bad_position_initial_args = [_]u8{0};
pub const bad_math_failure_tag: u32 = @intFromEnum(Failure.bad_math);
pub const bad_position_failure_tag: u32 = @intFromEnum(Failure.bad_position);

pub const DivisionArgs = struct {
    numerator: i8,
    denominator: i8,
};

const division_value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .scalar = .i8 },
    .{ .scalar = .i8 },
    .{ .schema = 1 },
    .{ .schema = 1 },
    .{ .scalar = .i8 },
};
const division_instructions = [_]cir.Instruction{
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
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 4,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 5,
        .operands = &.{ 1, 2, 3, 4 },
        .operation = .integer_divide,
    },
};
const division_blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &division_instructions,
    .terminator = .{ .return_value = 5 },
}};

pub const DivisionBody = struct {
    pub const InitialArgs = DivisionArgs;
    pub const Result = i8;
    pub const Failure = AuthoredFailure;
    pub const constants = .{
        AuthoredFailure.bad_math,
        AuthoredFailure.bad_position,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ DivisionArgs, AuthoredFailure };
    pub const control_ir: cir.Program = .{
        .label = "authored-failure-v2-division",
        .value_types = &division_value_types,
        .blocks = &division_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .i8 },
    };
};

pub const DivisionProgram = program_v2.program(
    "authored-failure-v2-division",
    DivisionBody,
);
pub const DivisionImage = DivisionProgram.image();
pub const DivisionMachine = DivisionProgram.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 32,
});

pub const division_success_input: DivisionArgs = .{
    .numerator = 8,
    .denominator = 2,
};
pub const division_overflow_input: DivisionArgs = .{
    .numerator = std.math.minInt(i8),
    .denominator = -1,
};
pub const division_by_zero_input: DivisionArgs = .{
    .numerator = 8,
    .denominator = 0,
};
pub const division_success_initial_args = [_]u8{ 8, 2 };
pub const division_overflow_initial_args = [_]u8{ 0x80, 0xff };
pub const division_by_zero_initial_args = [_]u8{ 8, 0 };

const composite_initial_values = Values.fromSlice(&.{1}) catch unreachable;
const composite_value_types = [_]cir.ValueType{
    .{ .scalar = .u32 },
    .{ .schema = 0 },
    .{ .scalar = .u8 },
    .{ .schema = 1 },
    .{ .schema = 0 },
};
const composite_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 1, 0, 2, 3 },
        .operation = .vector_set,
    },
};
const composite_blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &composite_instructions,
    .terminator = .{ .return_value = 4 },
}};

pub const CompositeBody = struct {
    pub const InitialArgs = u32;
    pub const Result = Values;
    pub const Failure = AuthoredFailure;
    pub const constants = .{
        composite_initial_values,
        @as(u8, 9),
        AuthoredFailure.bad_position,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{ Values, AuthoredFailure };
    pub const control_ir: cir.Program = .{
        .label = "authored-failure-v2-composite",
        .value_types = &composite_value_types,
        .blocks = &composite_blocks,
        .entry = 0,
        .result_type = .{ .schema = 0 },
    };
};

pub const CompositeProgram = program_v2.program(
    "authored-failure-v2-composite",
    CompositeBody,
);
pub const CompositeImage = CompositeProgram.image();
pub const CompositeMachine = CompositeProgram.compile(.{
    .maximum_frames = 2,
    .maximum_state_bytes = 1024,
    .maximum_machine_fuel = 32,
});
pub const composite_success_input: u32 = 0;
pub const composite_failure_input: u32 = 1;
pub const composite_success_initial_args = [_]u8{ 0, 0, 0, 0 };
pub const composite_failure_initial_args = [_]u8{ 1, 0, 0, 0 };
pub const composite_failure_tag = bad_position_failure_tag;

const admission_value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .schema = 0 },
    .{ .scalar = .boolean },
    .{ .schema = 0 },
    .{ .schema = 0 },
    .{ .schema = 0 },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
    .{ .scalar = .u8 },
};
const admission_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .copy,
        .result = 4,
        .operands = &.{0},
        .operation = .copy,
    },
    .{
        .kind = .pure,
        .result = 5,
        .operands = &.{ 2, 1, 3 },
        .operation = .select,
    },
    .{
        .kind = .constant,
        .result = 6,
        .operation = .{ .constant = 3 },
    },
    .{
        .kind = .constant,
        .result = 7,
        .operation = .{ .constant = 4 },
    },
    .{
        .kind = .pure,
        .result = 8,
        .operands = &.{ 6, 7, 1 },
        .operation = .integer_add,
    },
};
const admission_blocks = [_]cir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &admission_instructions,
    .terminator = .{ .return_value = 8 },
}};

const AdmissionBody = struct {
    pub const InitialArgs = AuthoredFailure;
    pub const Result = u8;
    pub const Failure = AuthoredFailure;
    pub const constants = .{
        AuthoredFailure.bad_math,
        true,
        AuthoredFailure.bad_position,
        @as(u8, std.math.maxInt(u8)),
        @as(u8, 1),
    };
    pub const effect_sites = .{};
    pub const schema_types = .{AuthoredFailure};
    pub const control_ir: cir.Program = .{
        .label = "authored-failure-v2-admission",
        .value_types = &admission_value_types,
        .blocks = &admission_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};

pub const AdmissionImage = program_v2.program(
    "authored-failure-v2-admission",
    AdmissionBody,
).image();
pub const admission_parameter_value: u16 = 0;
pub const admission_constant_value: u16 = 1;
pub const admission_copy_value: u16 = 4;
pub const admission_computed_value: u16 = 5;
pub const admission_result_value: u16 = 8;

const reachable_instructions = [_]cir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const unreachable_authored_instructions = [_]cir.Instruction{
    .{
        .kind = .constant,
        .result = 1,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .constant,
        .result = 3,
        .operation = .{ .constant = 3 },
    },
    .{
        .kind = .pure,
        .result = 4,
        .operands = &.{ 1, 2, 3 },
        .operation = .integer_add,
    },
};
const reachable_block = cir.Block{
    .id = 0,
    .instructions = &reachable_instructions,
    .terminator = .{ .return_value = 0 },
};
const unreachable_authored_blocks = [_]cir.Block{
    reachable_block,
    .{
        .id = 1,
        .instructions = &unreachable_authored_instructions,
        .terminator = .{ .return_value = 4 },
    },
};

fn UnreachableBody(comptime include_authored_block: bool) type {
    return struct {
        pub const InitialArgs = void;
        pub const Result = u8;
        pub const Failure = AuthoredFailure;
        pub const constants = .{
            @as(u8, 7),
            @as(u8, std.math.maxInt(u8)),
            @as(u8, 1),
            AuthoredFailure.bad_math,
        };
        pub const effect_sites = .{};
        pub const schema_types = .{AuthoredFailure};
        pub const control_ir: cir.Program = .{
            .label = "unreachable-authored-failure",
            .value_types = if (include_authored_block)
                &.{
                    .{ .scalar = .u8 },
                    .{ .scalar = .u8 },
                    .{ .scalar = .u8 },
                    .{ .schema = 0 },
                    .{ .scalar = .u8 },
                }
            else
                &.{.{ .scalar = .u8 }},
            .blocks = if (include_authored_block)
                &unreachable_authored_blocks
            else
                &.{reachable_block},
            .entry = 0,
            .result_type = .{ .scalar = .u8 },
        };
    };
}

pub const UnreachableV1Image = program_v2.program(
    "unreachable-authored-failure",
    UnreachableBody(false),
).image();
pub const UnreachableAuthoredImage = program_v2.program(
    "unreachable-authored-failure",
    UnreachableBody(true),
).image();
