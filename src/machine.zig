const portable_value = @import("portable_value");
const std = @import("std");

/// Canonical RNF state encoding selected for Machine ABI v2.
pub const StateEncoding = enum {
    rnf_v1,
};

/// Compile-time bounds and identity-bearing resource semantics.
pub const Options = struct {
    state_encoding: StateEncoding = .rnf_v1,
    maximum_frames: usize = 64,
    maximum_state_bytes: usize = 1 << 20,
    maximum_machine_fuel: u64 = 1_000_000,
    debug_metadata: bool = false,
};

/// One compiler-generated direct reducer action.
pub fn Reduction(
    comptime Frame: type,
    comptime Request: type,
    comptime Result: type,
    comptime AuthoredFailure: type,
) type {
    return ReductionWithReturns(
        Frame,
        Request,
        Result,
        AuthoredFailure,
        void,
    );
}

/// One compiler-generated reducer action with typed helper returns.
pub fn ReductionWithReturns(
    comptime Frame: type,
    comptime Request: type,
    comptime Result: type,
    comptime AuthoredFailure: type,
    comptime ReturnValue: type,
) type {
    return union(enum) {
        next: Frame,
        call: struct {
            return_frame: Frame,
            callee: Frame,
        },
        return_to: Frame,
        return_value: ReturnValue,
        request: struct {
            awaiting: Frame,
            request: Request,
        },
        yielded: Frame,
        done: Result,
        failed: AuthoredFailure,
    };
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn requireDefinition(comptime Definition: type) void {
    inline for (.{
        "Frame",
        "InitialArgs",
        "Result",
        "Failure",
        "Request",
        "EffectRow",
        "Transition",
        "contract_bytes",
        "initial",
        "minimumCost",
        "plan",
        "current",
        "resume",
        "requestEql",
        "requestSiteDigest",
        "validateFrame",
        "validateStack",
    }) |name| {
        if (!hasDeclSafe(Definition, name)) {
            @compileError("Boundary Machine definition is missing " ++ name);
        }
    }
}

fn assertDenseFrameTags(comptime Frame: type) void {
    const info = @typeInfo(Frame);
    if (info != .@"union" or info.@"union".tag_type == null) {
        @compileError("Boundary Machine Frame must be a tagged union");
    }
    const Tag = info.@"union".tag_type.?;
    const tag_fields = std.meta.fields(Tag);
    if (tag_fields.len != info.@"union".fields.len) {
        @compileError("Boundary Machine Frame tag and environment counts differ");
    }
    inline for (tag_fields, 0..) |field, index| {
        if (field.value != index) {
            @compileError("Boundary Machine constructor ids must be dense from zero");
        }
        if (!std.mem.eql(u8, field.name, info.@"union".fields[index].name)) {
            @compileError("Boundary Machine constructor tag and environment names differ");
        }
    }
}

fn assertDenseRequestTags(
    comptime Request: type,
    comptime site_count: usize,
) void {
    if (Request == void) {
        if (site_count != 0) {
            @compileError("Boundary Machine effect sites require a request union");
        }
        return;
    }
    const info = @typeInfo(Request);
    if (info != .@"union" or info.@"union".tag_type == null) {
        @compileError("Boundary Machine Request must be a tagged union");
    }
    const tag_fields = std.meta.fields(info.@"union".tag_type.?);
    if (tag_fields.len != info.@"union".fields.len or
        tag_fields.len != site_count)
    {
        @compileError("Boundary Machine request tags must match effect sites");
    }
    inline for (tag_fields, 0..) |field, index| {
        if (field.value != index) {
            @compileError("Boundary Machine request site ordinals must be dense from zero");
        }
    }
}

fn stateIdentityMaterial(
    comptime Definition: type,
    comptime options: Options,
) []const u8 {
    return Definition.contract_bytes ++ std.fmt.comptimePrint(
        "\x00boundary-machine-abi=2\x00state=rnf-v1\x00frames={d}\x00state-bytes={d}\x00fuel={d}",
        .{
            options.maximum_frames,
            options.maximum_state_bytes,
            options.maximum_machine_fuel,
        },
    );
}

fn contractDigest(
    comptime Definition: type,
    comptime options: Options,
) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        stateIdentityMaterial(Definition, options),
        &digest,
        .{},
    );
    return digest;
}

const state_magic = "ABL_RNF2";
const state_format_version: u16 = 1;
const machine_abi_version: u16 = 2;
const state_header_length: usize = 8 + 2 + 2 + 32 + 8 + 8 + 4 + 4;

const ByteWriter = struct {
    bytes: []u8,
    index: usize = 0,

    fn write(self: *ByteWriter, value: []const u8) void {
        @memcpy(self.bytes[self.index..][0..value.len], value);
        self.index += value.len;
    }

    fn writeInt(self: *ByteWriter, comptime T: type, value: T) void {
        var encoded: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
        std.mem.writeInt(T, &encoded, value, .little);
        self.write(&encoded);
    }
};

const ByteReader = struct {
    bytes: []const u8,
    index: usize = 0,

    fn read(self: *ByteReader, length: usize) error{ProgramContractViolation}![]const u8 {
        const end = std.math.add(usize, self.index, length) catch
            return error.ProgramContractViolation;
        if (end > self.bytes.len) return error.ProgramContractViolation;
        const result = self.bytes[self.index..end];
        self.index = end;
        return result;
    }

    fn readInt(self: *ByteReader, comptime T: type) error{ProgramContractViolation}!T {
        const length = @divExact(@typeInfo(T).int.bits, 8);
        return std.mem.readInt(T, (try self.read(length))[0..length], .little);
    }
};

/// Generate one direct, state-owning Machine ABI v2 implementation.
///
/// `Definition` is private compiler output: its `plan` function is the
/// program-specific defunctionalized apply function and transactional resource
/// preflight, not a runtime callback.
pub fn Machine(
    comptime Definition: type,
    comptime options: Options,
) type {
    comptime {
        requireDefinition(Definition);
        assertDenseFrameTags(Definition.Frame);
        assertDenseRequestTags(
            Definition.Request,
            Definition.EffectRow.operation_site_count,
        );
        portable_value.assertPortable(Definition.Frame);
        portable_value.assertPortable(Definition.Request);
        portable_value.assertPortable(Definition.Result);
        if (options.maximum_frames == 0) {
            @compileError("Boundary Machine maximum_frames must be positive");
        }
        if (options.maximum_frames > std.math.maxInt(u32)) {
            @compileError("Boundary Machine maximum_frames must fit canonical u32");
        }
        if (options.maximum_state_bytes < state_header_length or
            options.maximum_state_bytes > std.math.maxInt(u32))
        {
            @compileError("Boundary Machine maximum_state_bytes must fit canonical u32 and its header");
        }
    }

    const Frame = Definition.Frame;
    const FrameStack = portable_value.Vector(Frame, options.maximum_frames);
    const digest = contractDigest(Definition, options);

    return struct {
        const Self = @This();

        /// Boundary Machine ABI consumed structurally by World.
        pub const abi_version: u32 = machine_abi_version;
        /// Program-specific continuation-frame union.
        pub const FrameType = Frame;
        /// Typed entry arguments.
        pub const InitialArgs = Definition.InitialArgs;
        /// Typed terminal result.
        pub const Result = Definition.Result;
        /// Typed external request payload.
        pub const RequestValue = Definition.Request;
        /// Static residual effect row.
        pub const EffectRow = Definition.EffectRow;
        /// Program-authored and Machine-owned deterministic failures.
        pub const Failure = union(enum) {
            authored: Definition.Failure,
            execution_budget_exceeded,
            frame_depth_exceeded,
        };
        /// Operational failures that never become authored Machine failures.
        pub const Error = portable_value.Error || error{
            OutOfMemory,
            ProgramContractViolation,
        };

        const StoredState = struct {
            allocator: std.mem.Allocator,
            sequence: u64 = 0,
            cumulative_fuel: u64 = 0,
            frames: FrameStack,
            terminal: bool = false,
        };

        const StateStorage = opaque {};
        /// Machine-branded live state owner.
        pub const State = *StateStorage;

        /// Canonical, capability-neutral identity of one pending request.
        ///
        /// The Machine digest transitively binds the effect site schemas,
        /// response mapping, and response mode. The remaining fields bind the
        /// exact pending continuation and canonical payload.
        pub const RequestIdentity = struct {
            machine_contract_digest: [32]u8,
            sequence: u64,
            constructor_id: u32,
            site_ordinal: u32,
            effect_site_digest: [32]u8,
            payload_digest: [32]u8,
            digest: [32]u8,
        };

        /// One request bound to the current Machine, sequence, constructor,
        /// effect site, and canonical payload.
        pub const Request = struct {
            sequence: u64,
            constructor_id: u32,
            value: Definition.Request,
            identity: RequestIdentity,
        };

        /// Heap owner for one completed result.
        pub const OwnedResult = struct {
            allocator: std.mem.Allocator,
            result: Result,

            /// Borrow the result until this owner is deinitialized.
            pub fn value(self: *const OwnedResult) *const Result {
                return &self.result;
            }

            /// Release the terminal result owner.
            pub fn deinit(self: *OwnedResult) void {
                const allocator = self.allocator;
                allocator.destroy(self);
            }
        };

        /// One public reduction outcome.
        pub const Outcome = union(enum) {
            request: Request,
            yielded,
            done: *OwnedResult,
            failed: Failure,
        };

        /// Compile-time identity and resource manifest.
        pub const Manifest = struct {
            pub const abi = abi_version;
            pub const state_image_magic = state_magic.*;
            pub const state_image_format_version = state_format_version;
            pub const machine_contract_digest = digest;
            pub const maximum_frames = options.maximum_frames;
            pub const maximum_state_bytes = options.maximum_state_bytes;
            pub const maximum_machine_fuel = options.maximum_machine_fuel;
            pub const includes_debug_metadata = options.debug_metadata;
            pub const effect_site_count =
                Definition.EffectRow.operation_site_count;
            pub const after_site_count = Definition.EffectRow.after_site_count;
        };

        fn stored(state: State) *StoredState {
            return @ptrCast(@alignCast(state));
        }

        fn storedConst(state: State) *const StoredState {
            return @ptrCast(@alignCast(state));
        }

        fn own(allocator: std.mem.Allocator, value: StoredState) Error!State {
            const result = allocator.create(StoredState) catch return error.OutOfMemory;
            result.* = value;
            return @ptrCast(result);
        }

        fn topIndex(value: *const StoredState) Error!u32 {
            if (value.frames.logical_length == 0) return error.ProgramContractViolation;
            return value.frames.logical_length - 1;
        }

        fn top(value: *const StoredState) Error!Frame {
            return value.frames.get(try topIndex(value)) orelse
                error.ProgramContractViolation;
        }

        fn setTop(value: *StoredState, frame: Frame) Error!void {
            value.frames.set(try topIndex(value), frame) catch
                return error.ProgramContractViolation;
        }

        fn frameId(frame: Frame) Error!u32 {
            return portable_value.unionTag(Frame, frame) catch
                return error.ProgramContractViolation;
        }

        fn hashRequestInteger(
            hasher: *std.crypto.hash.sha2.Sha256,
            comptime T: type,
            value: T,
        ) void {
            var bytes: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
            std.mem.writeInt(T, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn canonicalPayloadDigest(
            allocator: std.mem.Allocator,
            request_value: RequestValue,
        ) Error![32]u8 {
            if (RequestValue == void) return error.ProgramContractViolation;
            const required = portable_value.unionPayloadEncodedSize(
                RequestValue,
                request_value,
            ) catch return error.ProgramContractViolation;
            const bytes = allocator.alloc(u8, required) catch
                return error.OutOfMemory;
            defer allocator.free(bytes);
            const written = portable_value.encodeUnionPayload(
                RequestValue,
                request_value,
                bytes,
            ) catch return error.ProgramContractViolation;
            if (written != required) return error.ProgramContractViolation;
            var result: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(bytes, &result, .{});
            return result;
        }

        fn requestIdentity(
            allocator: std.mem.Allocator,
            sequence: u64,
            constructor_id: u32,
            request_value: RequestValue,
        ) Error!RequestIdentity {
            if (RequestValue == void) return error.ProgramContractViolation;
            const site_ordinal = portable_value.unionTag(
                RequestValue,
                request_value,
            ) catch return error.ProgramContractViolation;
            if (site_ordinal >= Definition.EffectRow.operation_site_count) {
                return error.ProgramContractViolation;
            }
            const payload_digest = try canonicalPayloadDigest(
                allocator,
                request_value,
            );
            const effect_site_digest = Definition.requestSiteDigest(
                request_value,
            );
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update("boundary-request-identity-v1\x00");
            hasher.update(&digest);
            hashRequestInteger(&hasher, u64, sequence);
            hashRequestInteger(&hasher, u32, constructor_id);
            hashRequestInteger(&hasher, u32, site_ordinal);
            hasher.update(&effect_site_digest);
            hasher.update(&payload_digest);
            var identity_digest: [32]u8 = undefined;
            hasher.final(&identity_digest);
            return .{
                .machine_contract_digest = digest,
                .sequence = sequence,
                .constructor_id = constructor_id,
                .site_ordinal = site_ordinal,
                .effect_site_digest = effect_site_digest,
                .payload_digest = payload_digest,
                .digest = identity_digest,
            };
        }

        fn requestIdentityEql(
            left: RequestIdentity,
            right: RequestIdentity,
        ) bool {
            return std.mem.eql(
                u8,
                &left.machine_contract_digest,
                &right.machine_contract_digest,
            ) and
                left.sequence == right.sequence and
                left.constructor_id == right.constructor_id and
                left.site_ordinal == right.site_ordinal and
                std.mem.eql(
                    u8,
                    &left.effect_site_digest,
                    &right.effect_site_digest,
                ) and
                std.mem.eql(
                    u8,
                    &left.payload_digest,
                    &right.payload_digest,
                ) and
                std.mem.eql(u8, &left.digest, &right.digest);
        }

        fn makeRequest(
            allocator: std.mem.Allocator,
            sequence: u64,
            constructor_id: u32,
            request_value: RequestValue,
        ) Error!Request {
            return .{
                .sequence = sequence,
                .constructor_id = constructor_id,
                .value = request_value,
                .identity = try requestIdentity(
                    allocator,
                    sequence,
                    constructor_id,
                    request_value,
                ),
            };
        }

        fn currentFrom(value: *const StoredState) Error!?Request {
            if (value.terminal) return error.ProgramContractViolation;
            const frame = try top(value);
            const request_value = Definition.current(frame) orelse return null;
            return try makeRequest(
                value.allocator,
                value.sequence,
                try frameId(frame),
                request_value,
            );
        }

        fn stateSize(value: *const StoredState) Error!usize {
            if (value.terminal or value.frames.logical_length == 0) {
                return error.ProgramContractViolation;
            }
            var total: usize = state_header_length;
            for (value.frames.slice()) |frame| {
                total = std.math.add(
                    usize,
                    total,
                    8 + try portable_value.unionPayloadEncodedSize(Frame, frame),
                ) catch return error.ProgramContractViolation;
            }
            return total;
        }

        fn validate(value: *const StoredState) Error!void {
            if (value.terminal) return error.ProgramContractViolation;
            if (value.frames.logical_length == 0 or
                value.frames.logical_length > options.maximum_frames or
                value.cumulative_fuel > options.maximum_machine_fuel)
            {
                return error.ProgramContractViolation;
            }
            for (value.frames.slice()) |frame| {
                Definition.validateFrame(frame) catch
                    return error.ProgramContractViolation;
            }
            Definition.validateStack(value.frames.slice()) catch
                return error.ProgramContractViolation;
            if (try stateSize(value) > options.maximum_state_bytes) {
                return error.ProgramContractViolation;
            }
        }

        fn commit(state: State, candidate: *const StoredState) void {
            stored(state).* = candidate.*;
        }

        /// Construct the initial nonempty continuation stack.
        pub fn initialState(
            allocator: std.mem.Allocator,
            args: InitialArgs,
        ) Error!State {
            var frames = FrameStack.empty();
            frames.push(Definition.initial(args)) catch
                return error.ProgramContractViolation;
            const value: StoredState = .{
                .allocator = allocator,
                .frames = frames,
            };
            try validate(&value);
            return own(allocator, value);
        }

        /// Clone one live state into an independent allocator owner.
        pub fn cloneState(
            allocator: std.mem.Allocator,
            state: State,
        ) Error!State {
            try validate(storedConst(state));
            var copy = storedConst(state).*;
            copy.allocator = allocator;
            return own(allocator, copy);
        }

        /// Release one live Machine state.
        pub fn deinitState(state: State) void {
            const value = stored(state);
            const allocator = value.allocator;
            allocator.destroy(value);
        }

        /// Borrow the current parked request without advancing.
        pub fn current(state: State) Error!Request {
            try validate(storedConst(state));
            return (try currentFrom(storedConst(state))) orelse
                error.ProgramContractViolation;
        }

        fn commitYield(
            state: State,
            candidate: *const StoredState,
            caller_fuel: *u64,
            remaining_fuel: u64,
        ) Error!Outcome {
            try validate(candidate);
            commit(state, candidate);
            caller_fuel.* = remaining_fuel;
            return .yielded;
        }

        /// Run direct generated segments to one request, yield, result, or failure.
        pub fn step(state: State, caller_fuel: *u64) Error!Outcome {
            const original = storedConst(state);
            try validate(original);
            if (try currentFrom(original) != null) return error.ProgramContractViolation;

            const candidate = original.allocator.create(StoredState) catch
                return error.OutOfMemory;
            defer original.allocator.destroy(candidate);
            candidate.* = original.*;
            var remaining_fuel = caller_fuel.*;

            while (true) {
                const frame = try top(candidate);
                const minimum_cost = Definition.minimumCost(frame);
                if (minimum_cost == 0) return error.ProgramContractViolation;
                if (remaining_fuel < minimum_cost) {
                    return commitYield(state, candidate, caller_fuel, remaining_fuel);
                }
                const plan = Definition.plan(frame);
                const cost = plan.cost;
                if (cost < minimum_cost) return error.ProgramContractViolation;
                if (remaining_fuel < cost) {
                    return commitYield(state, candidate, caller_fuel, remaining_fuel);
                }
                const next_total = std.math.add(
                    u64,
                    candidate.cumulative_fuel,
                    cost,
                ) catch options.maximum_machine_fuel +| 1;
                if (next_total > options.maximum_machine_fuel) {
                    candidate.terminal = true;
                    commit(state, candidate);
                    caller_fuel.* = remaining_fuel;
                    return .{ .failed = .execution_budget_exceeded };
                }
                remaining_fuel -= cost;
                candidate.cumulative_fuel = next_total;

                const action = plan.transition;
                switch (action) {
                    .yielded => |next_frame| {
                        try setTop(candidate, next_frame);
                        return commitYield(
                            state,
                            candidate,
                            caller_fuel,
                            remaining_fuel,
                        );
                    },
                    .next => |next_frame| {
                        try setTop(candidate, next_frame);
                        try validate(candidate);
                    },
                    .call => |call| {
                        if (candidate.frames.logical_length == options.maximum_frames) {
                            return .{ .failed = .frame_depth_exceeded };
                        }
                        try setTop(candidate, call.return_frame);
                        candidate.frames.push(call.callee) catch
                            return error.ProgramContractViolation;
                        try validate(candidate);
                    },
                    .return_to => |return_frame| {
                        if (candidate.frames.logical_length < 2) {
                            return error.ProgramContractViolation;
                        }
                        _ = candidate.frames.pop();
                        try setTop(candidate, return_frame);
                        try validate(candidate);
                    },
                    .return_value => |return_value| {
                        if (candidate.frames.logical_length < 2) {
                            return error.ProgramContractViolation;
                        }
                        if (comptime hasDeclSafe(Definition, "applyReturn")) {
                            const parent_index =
                                candidate.frames.logical_length - 2;
                            const parent = candidate.frames.get(parent_index) orelse
                                return error.ProgramContractViolation;
                            const return_frame = Definition.applyReturn(
                                parent,
                                return_value,
                            ) catch return error.ProgramContractViolation;
                            _ = candidate.frames.pop();
                            try setTop(candidate, return_frame);
                            try validate(candidate);
                        } else {
                            return error.ProgramContractViolation;
                        }
                    },
                    .request => |request| {
                        try setTop(candidate, request.awaiting);
                        candidate.sequence = std.math.add(
                            u64,
                            candidate.sequence,
                            1,
                        ) catch return error.ProgramContractViolation;
                        try validate(candidate);
                        const outcome_request = try makeRequest(
                            candidate.allocator,
                            candidate.sequence,
                            try frameId(request.awaiting),
                            request.request,
                        );
                        const reconstructed = (try currentFrom(candidate)) orelse
                            return error.ProgramContractViolation;
                        if (reconstructed.sequence != outcome_request.sequence or
                            reconstructed.constructor_id != outcome_request.constructor_id or
                            !requestIdentityEql(
                                reconstructed.identity,
                                outcome_request.identity,
                            ) or
                            !Definition.requestEql(
                                reconstructed.value,
                                outcome_request.value,
                            ))
                        {
                            return error.ProgramContractViolation;
                        }
                        commit(state, candidate);
                        caller_fuel.* = remaining_fuel;
                        return .{ .request = outcome_request };
                    },
                    .done => |result| {
                        const owned = original.allocator.create(OwnedResult) catch
                            return error.OutOfMemory;
                        owned.* = .{
                            .allocator = original.allocator,
                            .result = result,
                        };
                        candidate.terminal = true;
                        commit(state, candidate);
                        caller_fuel.* = remaining_fuel;
                        return .{ .done = owned };
                    },
                    .failed => |failure| {
                        candidate.terminal = true;
                        commit(state, candidate);
                        caller_fuel.* = remaining_fuel;
                        return .{ .failed = .{ .authored = failure } };
                    },
                }
            }
        }

        /// Resume one exact pending request transactionally.
        pub fn @"resume"(
            state: State,
            request: Request,
            response: anytype,
        ) Error!void {
            const original = storedConst(state);
            try validate(original);
            const expected = (try currentFrom(original)) orelse
                return error.ProgramContractViolation;
            if (expected.sequence != request.sequence or
                expected.constructor_id != request.constructor_id or
                !requestIdentityEql(expected.identity, request.identity) or
                !Definition.requestEql(expected.value, request.value))
            {
                return error.ProgramContractViolation;
            }

            var candidate = original.*;
            const next_frame = Definition.@"resume"(
                try top(&candidate),
                request.value,
                response,
            ) catch return error.ProgramContractViolation;
            try setTop(&candidate, next_frame);
            try validate(&candidate);
            if (try currentFrom(&candidate) != null) {
                return error.ProgramContractViolation;
            }
            commit(state, &candidate);
        }

        /// Validate one live, nonterminal state without advancing.
        pub fn validateState(state: State) Error!void {
            try validate(storedConst(state));
        }

        /// Encode canonical ABL_RNF2 bytes.
        pub fn encodeState(
            allocator: std.mem.Allocator,
            state: State,
        ) Error![]u8 {
            const value = storedConst(state);
            try validate(value);
            const required = try stateSize(value);
            const bytes = allocator.alloc(u8, required) catch
                return error.OutOfMemory;
            errdefer allocator.free(bytes);
            var writer: ByteWriter = .{ .bytes = bytes };
            writer.write(state_magic);
            writer.writeInt(u16, state_format_version);
            writer.writeInt(u16, machine_abi_version);
            writer.write(&digest);
            writer.writeInt(u64, value.sequence);
            writer.writeInt(u64, value.cumulative_fuel);
            writer.writeInt(u32, value.frames.logical_length);
            writer.writeInt(u32, 0);
            for (value.frames.slice()) |frame| {
                const environment_length = try portable_value.unionPayloadEncodedSize(
                    Frame,
                    frame,
                );
                writer.writeInt(u32, try frameId(frame));
                writer.writeInt(u32, @intCast(environment_length));
                const written = try portable_value.encodeUnionPayload(
                    Frame,
                    frame,
                    bytes[writer.index..][0..environment_length],
                );
                if (written != environment_length) return error.ProgramContractViolation;
                writer.index += written;
            }
            if (writer.index != bytes.len) return error.ProgramContractViolation;
            return bytes;
        }

        /// Decode and locally validate canonical ABL_RNF2 bytes.
        pub fn decodeState(
            allocator: std.mem.Allocator,
            bytes: []const u8,
        ) Error!State {
            if (bytes.len > options.maximum_state_bytes) {
                return error.ProgramContractViolation;
            }
            var reader: ByteReader = .{ .bytes = bytes };
            if (!std.mem.eql(u8, try reader.read(state_magic.len), state_magic)) {
                return error.ProgramContractViolation;
            }
            if (try reader.readInt(u16) != state_format_version or
                try reader.readInt(u16) != machine_abi_version or
                !std.mem.eql(u8, try reader.read(digest.len), &digest))
            {
                return error.ProgramContractViolation;
            }
            const sequence = try reader.readInt(u64);
            const cumulative_fuel = try reader.readInt(u64);
            const frame_count = try reader.readInt(u32);
            if (try reader.readInt(u32) != 0 or
                frame_count == 0 or frame_count > options.maximum_frames)
            {
                return error.ProgramContractViolation;
            }

            var frames = FrameStack.empty();
            for (0..frame_count) |_| {
                const constructor_id = try reader.readInt(u32);
                const environment_length = try reader.readInt(u32);
                const environment = try reader.read(@intCast(environment_length));
                const frame = portable_value.decodeUnionPayload(
                    Frame,
                    constructor_id,
                    environment,
                ) catch return error.ProgramContractViolation;
                frames.push(frame) catch return error.ProgramContractViolation;
            }
            if (reader.index != bytes.len) return error.ProgramContractViolation;
            const value: StoredState = .{
                .allocator = allocator,
                .sequence = sequence,
                .cumulative_fuel = cumulative_fuel,
                .frames = frames,
            };
            try validate(&value);
            return own(allocator, value);
        }
    };
}

const TestDefinition = struct {
    const Frame = union(enum) {
        entry: struct {
            seed: u32,
        },
        loop_header: struct {
            current: u32,
            remaining: u32,
        },
        await_increment: struct {
            current: u32,
            remaining: u32,
        },
    };

    const InitialArgs = u32;
    const Result = u32;
    const Failure = enum {
        rejected,
    };
    const Request = union(enum) {
        increment: struct {
            payload: u32,
        },
    };
    const EffectRow = struct {
        pub const operation_site_count: usize = 1;
        pub const after_site_count: usize = 0;
    };
    const Transition = Reduction(Frame, Request, Result, Failure);
    const contract_bytes = "test-direct-rnf\x00entry\x00loop-header\x00await-increment";

    fn initial(seed: InitialArgs) Frame {
        return .{ .entry = .{ .seed = seed } };
    }

    fn minimumCost(_: Frame) u64 {
        return 1;
    }

    fn plan(frame: Frame) struct {
        cost: u64,
        transition: Transition,
    } {
        return .{ .cost = 1, .transition = switch (frame) {
            .entry => |environment| .{ .request = .{
                .awaiting = .{ .await_increment = .{
                    .current = environment.seed,
                    .remaining = 2,
                } },
                .request = .{ .increment = .{ .payload = environment.seed } },
            } },
            .loop_header => |environment| if (environment.remaining == 0)
                .{ .done = environment.current }
            else
                .{ .request = .{
                    .awaiting = .{ .await_increment = .{
                        .current = environment.current,
                        .remaining = environment.remaining,
                    } },
                    .request = .{
                        .increment = .{ .payload = environment.current },
                    },
                } },
            .await_increment => unreachable,
        } };
    }

    fn current(frame: Frame) ?Request {
        return switch (frame) {
            .await_increment => |environment| .{ .increment = .{
                .payload = environment.current,
            } },
            else => null,
        };
    }

    fn @"resume"(
        frame: Frame,
        request: Request,
        response: anytype,
    ) error{ProgramContractViolation}!Frame {
        if (@TypeOf(response) != u32) return error.ProgramContractViolation;
        return switch (frame) {
            .await_increment => |environment| blk: {
                const payload = switch (request) {
                    .increment => |value| value.payload,
                };
                if (payload != environment.current or
                    environment.remaining == 0)
                {
                    return error.ProgramContractViolation;
                }
                break :blk .{ .loop_header = .{
                    .current = response,
                    .remaining = environment.remaining - 1,
                } };
            },
            else => error.ProgramContractViolation,
        };
    }

    fn requestEql(left: Request, right: Request) bool {
        return switch (left) {
            .increment => |left_value| switch (right) {
                .increment => |right_value| left_value.payload ==
                    right_value.payload,
            },
        };
    }

    fn requestSiteDigest(_: Request) [32]u8 {
        return [_]u8{0x42} ** 32;
    }

    fn validateFrame(frame: Frame) error{ProgramContractViolation}!void {
        switch (frame) {
            .entry, .loop_header => {},
            .await_increment => |environment| {
                if (environment.remaining == 0) return error.ProgramContractViolation;
            },
        }
    }

    fn validateStack(frames: []const Frame) error{ProgramContractViolation}!void {
        if (frames.len != 1) return error.ProgramContractViolation;
    }
};

const AlternateTestDefinition = struct {
    const Frame = TestDefinition.Frame;
    const InitialArgs = TestDefinition.InitialArgs;
    const Result = TestDefinition.Result;
    const Failure = TestDefinition.Failure;
    const Request = TestDefinition.Request;
    const EffectRow = TestDefinition.EffectRow;
    const Transition = TestDefinition.Transition;
    const contract_bytes = "test-direct-rnf\x00semantic-alternative";
    const initial = TestDefinition.initial;
    const minimumCost = TestDefinition.minimumCost;
    const plan = TestDefinition.plan;
    const current = TestDefinition.current;
    const @"resume" = TestDefinition.@"resume";
    const requestEql = TestDefinition.requestEql;
    const requestSiteDigest = TestDefinition.requestSiteDigest;
    const validateFrame = TestDefinition.validateFrame;
    const validateStack = TestDefinition.validateStack;
};

const BudgetTestDefinition = struct {
    const Frame = union(enum) {
        entry: struct {},
        finish: struct {},
    };
    const InitialArgs = void;
    const Result = u32;
    const Failure = enum { rejected };
    const Request = void;
    const EffectRow = struct {
        pub const operation_site_count: usize = 0;
        pub const after_site_count: usize = 0;
    };
    const Transition = Reduction(Frame, Request, Result, Failure);
    const contract_bytes = "test-direct-rnf\x00budget-accounting";

    fn initial(_: InitialArgs) Frame {
        return .{ .entry = .{} };
    }

    fn minimumCost(_: Frame) u64 {
        return 1;
    }

    fn plan(frame: Frame) struct {
        cost: u64,
        transition: Transition,
    } {
        return .{
            .cost = 1,
            .transition = switch (frame) {
                .entry => .{ .next = .{ .finish = .{} } },
                .finish => .{ .done = 42 },
            },
        };
    }

    fn current(_: Frame) ?Request {
        return null;
    }

    fn @"resume"(
        _: Frame,
        _: Request,
        _: anytype,
    ) error{ProgramContractViolation}!Frame {
        return error.ProgramContractViolation;
    }

    fn requestEql(_: Request, _: Request) bool {
        return true;
    }

    fn requestSiteDigest(_: Request) [32]u8 {
        return [_]u8{0} ** 32;
    }

    fn validateFrame(_: Frame) error{ProgramContractViolation}!void {}

    fn validateStack(frames: []const Frame) error{ProgramContractViolation}!void {
        if (frames.len != 1) return error.ProgramContractViolation;
    }
};

fn expectRejectedOrCanonical(
    comptime SubjectMachine: type,
    bytes: []const u8,
) !void {
    const decoded = SubjectMachine.decodeState(
        std.testing.allocator,
        bytes,
    ) catch |err| {
        try std.testing.expect(err == error.ProgramContractViolation);
        return;
    };
    defer SubjectMachine.deinitState(decoded);
    try SubjectMachine.validateState(decoded);
    const canonical = try SubjectMachine.encodeState(
        std.testing.allocator,
        decoded,
    );
    defer std.testing.allocator.free(canonical);
    try std.testing.expectEqualSlices(u8, bytes, canonical);
}

fn nextFuzzWord(state: *u64) u64 {
    var value = state.*;
    value ^= value << 13;
    value ^= value >> 7;
    value ^= value << 17;
    state.* = value;
    return value;
}

test "direct Machine reducer resumes from canonical fresh-instance state" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const state = try TestMachine.initialState(std.testing.allocator, 3);
    defer TestMachine.deinitState(state);

    var no_fuel: u64 = 0;
    try std.testing.expectEqual(
        TestMachine.Outcome.yielded,
        try TestMachine.step(state, &no_fuel),
    );

    var fuel: u64 = 10;
    const first = switch (try TestMachine.step(state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u64, 1), first.sequence);
    try std.testing.expectEqual(
        @as(u32, 3),
        first.value.increment.payload,
    );

    const bytes = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(bytes);
    const resumed_state = try TestMachine.decodeState(std.testing.allocator, bytes);
    defer TestMachine.deinitState(resumed_state);
    try std.testing.expect(TestDefinition.requestEql(
        first.value,
        (try TestMachine.current(resumed_state)).value,
    ));

    var stale = first;
    stale.sequence += 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.@"resume"(resumed_state, stale, @as(u32, 4)),
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.@"resume"(resumed_state, first, @as(u16, 4)),
    );
    try std.testing.expect(TestDefinition.requestEql(
        first.value,
        (try TestMachine.current(resumed_state)).value,
    ));
    try TestMachine.@"resume"(resumed_state, first, @as(u32, 4));
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.@"resume"(resumed_state, first, @as(u32, 4)),
    );

    const second = switch (try TestMachine.step(resumed_state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u64, 2), second.sequence);
    try std.testing.expectEqual(
        @as(u32, 4),
        second.value.increment.payload,
    );
    try TestMachine.@"resume"(resumed_state, second, @as(u32, 5));

    const done = switch (try TestMachine.step(resumed_state, &fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 5), done.value().*);
}

test "Machine candidate allocation failure preserves state and caller fuel" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{},
    );
    const state = try TestMachine.initialState(failing.allocator(), 3);
    defer TestMachine.deinitState(state);
    const before = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    var caller_fuel: u64 = 8;

    failing.fail_index = failing.allocations;
    try std.testing.expectError(
        error.OutOfMemory,
        TestMachine.step(state, &caller_fuel),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 8), caller_fuel);
    const after = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);

    failing.fail_index = std.math.maxInt(usize);
    switch (try TestMachine.step(state, &caller_fuel)) {
        .request => {},
        else => return error.TestUnexpectedResult,
    }
}

test "Machine terminal result allocation failure is retryable" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{},
    );
    const state = try TestMachine.initialState(failing.allocator(), 3);
    defer TestMachine.deinitState(state);
    var caller_fuel: u64 = 20;

    const first = switch (try TestMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try TestMachine.@"resume"(state, first, @as(u32, 4));
    const second = switch (try TestMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try TestMachine.@"resume"(state, second, @as(u32, 5));

    const before = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);
    const fuel_before = caller_fuel;
    failing.fail_index = failing.allocations + 1;
    try std.testing.expectError(
        error.OutOfMemory,
        TestMachine.step(state, &caller_fuel),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(fuel_before, caller_fuel);
    const after = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);

    failing.fail_index = std.math.maxInt(usize);
    const done = switch (try TestMachine.step(state, &caller_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u32, 5), done.value().*);
}

test "terminal budget failure retains prior segment charges" {
    const BudgetMachine = Machine(BudgetTestDefinition, .{
        .maximum_frames = 1,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 1,
    });
    const state = try BudgetMachine.initialState(std.testing.allocator, {});
    defer BudgetMachine.deinitState(state);
    var caller_fuel: u64 = 5;

    try std.testing.expectEqual(
        BudgetMachine.Outcome{
            .failed = .execution_budget_exceeded,
        },
        try BudgetMachine.step(state, &caller_fuel),
    );
    try std.testing.expectEqual(@as(u64, 4), caller_fuel);
}

test "Machine identity binds semantics and excludes debug metadata" {
    const options_without_debug: Options = .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
        .debug_metadata = false,
    };
    const options_with_debug: Options = .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
        .debug_metadata = true,
    };
    const BaseMachine = Machine(TestDefinition, options_without_debug);
    const DebugMachine = Machine(TestDefinition, options_with_debug);
    const AlternateMachine = Machine(
        AlternateTestDefinition,
        options_without_debug,
    );

    try std.testing.expectEqualSlices(
        u8,
        &BaseMachine.Manifest.machine_contract_digest,
        &DebugMachine.Manifest.machine_contract_digest,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &BaseMachine.Manifest.machine_contract_digest,
        &AlternateMachine.Manifest.machine_contract_digest,
    ));

    const state = try BaseMachine.initialState(std.testing.allocator, 9);
    defer BaseMachine.deinitState(state);
    const encoded = try BaseMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectError(
        error.ProgramContractViolation,
        AlternateMachine.decodeState(std.testing.allocator, encoded),
    );
}

test "ABL_RNF2 decode rejects wrong identity constructor truncation and trailing bytes" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const state = try TestMachine.initialState(std.testing.allocator, 7);
    defer TestMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = try TestMachine.step(state, &fuel);
    const encoded = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    var forged: [4097]u8 = undefined;
    @memcpy(forged[0..encoded.len], encoded);
    forged[0] = 'X';
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u16, forged[state_magic.len..][0..2], 2, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u16, forged[state_magic.len + 2 ..][0..2], 3, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    forged[12] ^= 1;
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    const cumulative_fuel_offset = state_magic.len + 2 + 2 + 32 + 8;
    std.mem.writeInt(
        u64,
        forged[cumulative_fuel_offset..][0..8],
        TestMachine.Manifest.maximum_machine_fuel + 1,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    const frame_count_offset = cumulative_fuel_offset + 8;
    std.mem.writeInt(u32, forged[frame_count_offset..][0..4], 0, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(
        u32,
        forged[frame_count_offset..][0..4],
        TestMachine.Manifest.maximum_frames + 1,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u32, forged[frame_count_offset + 4 ..][0..4], 1, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u32, forged[state_header_length..][0..4], 99, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u32, forged[state_header_length + 4 ..][0..4], 4, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u32, forged[state_header_length + 4 ..][0..4], 9, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    std.mem.writeInt(u32, forged[state_header_length + 8 + 4 ..][0..4], 0, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..encoded.len]),
    );

    const frame_bytes = encoded[state_header_length..];
    const doubled_length = encoded.len + frame_bytes.len;
    @memcpy(forged[0..encoded.len], encoded);
    @memcpy(forged[encoded.len..doubled_length], frame_bytes);
    std.mem.writeInt(u32, forged[frame_count_offset..][0..4], 2, .little);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0..doubled_length]),
    );

    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, encoded[0 .. encoded.len - 1]),
    );

    @memcpy(forged[0..encoded.len], encoded);
    forged[encoded.len] = 0;
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, forged[0 .. encoded.len + 1]),
    );

    @memset(forged[0..], 0);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(std.testing.allocator, &forged),
    );
}

test "bounded malformed-state fuzz accepts only canonical fixed points" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const state = try TestMachine.initialState(std.testing.allocator, 7);
    defer TestMachine.deinitState(state);
    var fuel: u64 = 8;
    _ = try TestMachine.step(state, &fuel);
    const encoded = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    for (0..encoded.len) |length| {
        try std.testing.expectError(
            error.ProgramContractViolation,
            TestMachine.decodeState(
                std.testing.allocator,
                encoded[0..length],
            ),
        );
    }

    var candidate: [4097]u8 = undefined;
    for (0..encoded.len) |offset| {
        for (0..8) |bit| {
            @memcpy(candidate[0..encoded.len], encoded);
            candidate[offset] ^= @as(u8, 1) << @intCast(bit);
            try expectRejectedOrCanonical(
                TestMachine,
                candidate[0..encoded.len],
            );
        }
    }

    var fuzz_state: u64 = 0x9e37_79b9_7f4a_7c15;
    for (0..512) |_| {
        const length: usize = @intCast(
            nextFuzzWord(&fuzz_state) % @as(u64, candidate.len + 1),
        );
        for (candidate[0..length]) |*byte| {
            byte.* = @truncate(nextFuzzWord(&fuzz_state));
        }
        try expectRejectedOrCanonical(TestMachine, candidate[0..length]);
    }
}
