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
        "cost",
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
        if (options.debug_metadata and
            (!@hasDecl(Definition, "DebugMetadata") or
                !@hasDecl(Definition, "debug_metadata")))
        {
            @compileError(
                "debug_metadata requires compiler-generated diagnostic metadata",
            );
        }
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
        /// Diagnostic-only source and constructor map when requested.
        pub const DebugMetadata = if (options.debug_metadata)
            Definition.DebugMetadata
        else
            void;
        /// Diagnostic payload excluded from Machine semantic identity.
        pub const debug_metadata: DebugMetadata = if (options.debug_metadata)
            Definition.debug_metadata
        else {};
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

        /// Private live ownership carrier. Canonical ABL_RNF2 bytes remain the
        /// transferable authority; allocator-backed storage owns exactly the
        /// logical typed frames needed by the direct reducer.
        const FrameStack = union(enum) {
            const Stack = @This();

            empty,
            one: Frame,
            many: std.ArrayList(Frame),

            fn initUninitialized(
                allocator: std.mem.Allocator,
                logical_length: u32,
            ) Error!Stack {
                if (logical_length > options.maximum_frames) {
                    return error.ProgramContractViolation;
                }
                if (logical_length == 0) return .empty;
                if (logical_length == 1) return .{ .one = undefined };
                var list = std.ArrayList(Frame).initCapacity(
                    allocator,
                    @intCast(logical_length),
                ) catch return error.OutOfMemory;
                list.items.len = @intCast(logical_length);
                return .{ .many = list };
            }

            fn initOne(
                _: std.mem.Allocator,
                frame: Frame,
            ) Error!Stack {
                return .{ .one = frame };
            }

            fn clone(
                self: *const Stack,
                allocator: std.mem.Allocator,
            ) Error!Stack {
                if (!self.consistent()) return error.ProgramContractViolation;
                return switch (self.*) {
                    .empty => .empty,
                    .one => |frame| .{ .one = frame },
                    .many => |list| .{
                        .many = list.clone(allocator) catch
                            return error.OutOfMemory,
                    },
                };
            }

            fn deinit(self: *Stack, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .many => |*list| list.deinit(allocator),
                    .empty, .one => {},
                }
                self.* = .empty;
            }

            fn take(self: *Stack) Stack {
                const result = self.*;
                self.* = .empty;
                return result;
            }

            fn consistent(self: *const Stack) bool {
                return switch (self.*) {
                    .empty => true,
                    .one => options.maximum_frames >= 1,
                    .many => |list| list.items.len >= 1 and
                        list.items.len <= options.maximum_frames and
                        (@sizeOf(Frame) == 0 or
                            (list.capacity >= list.items.len and
                                list.capacity <= options.maximum_frames)),
                };
            }

            fn len(self: *const Stack) u32 {
                return switch (self.*) {
                    .empty => 0,
                    .one => 1,
                    .many => |list| @intCast(list.items.len),
                };
            }

            fn slice(self: *const Stack) []const Frame {
                return switch (self.*) {
                    .empty => &.{},
                    .one => @as(*const [1]Frame, @ptrCast(&self.one)),
                    .many => |list| list.items,
                };
            }

            fn get(self: *const Stack, index: u32) ?Frame {
                if (index >= self.len() or !self.consistent()) {
                    return null;
                }
                return switch (self.*) {
                    .one => self.one,
                    .many => |list| list.items[@intCast(index)],
                    .empty => null,
                };
            }

            fn set(self: *Stack, index: u32, frame: Frame) Error!void {
                if (index >= self.len() or !self.consistent()) {
                    return error.ProgramContractViolation;
                }
                switch (self.*) {
                    .one => self.one = frame,
                    .many => |*list| list.items[@intCast(index)] = frame,
                    .empty => unreachable,
                }
            }

            fn push(
                self: *Stack,
                allocator: std.mem.Allocator,
                frame: Frame,
            ) Error!void {
                if (!self.consistent() or self.len() == options.maximum_frames) {
                    return error.ProgramContractViolation;
                }
                switch (self.*) {
                    .empty => return error.ProgramContractViolation,
                    .one => |first| {
                        var list = std.ArrayList(Frame).initCapacity(
                            allocator,
                            2,
                        ) catch return error.OutOfMemory;
                        list.appendAssumeCapacity(first);
                        list.appendAssumeCapacity(frame);
                        self.* = .{ .many = list };
                    },
                    .many => |*list| {
                        list.ensureTotalCapacityPrecise(
                            allocator,
                            list.items.len + 1,
                        ) catch return error.OutOfMemory;
                        list.appendAssumeCapacity(frame);
                    },
                }
            }

            fn pop(
                self: *Stack,
                allocator: std.mem.Allocator,
            ) Error!Frame {
                if (!self.consistent() or self.len() == 0) {
                    return error.ProgramContractViolation;
                }
                return switch (self.*) {
                    .empty => unreachable,
                    .one => |frame| blk: {
                        self.* = .empty;
                        break :blk frame;
                    },
                    .many => |*list| blk: {
                        const next_length = list.items.len - 1;
                        const result = list.items[next_length];
                        if (next_length == 0) {
                            list.deinit(allocator);
                            self.* = .empty;
                        } else {
                            list.items.len = next_length;
                        }
                        break :blk result;
                    },
                };
            }

            fn commitFrom(
                self: *Stack,
                allocator: std.mem.Allocator,
                candidate: *Stack,
            ) void {
                switch (self.*) {
                    .many => |*destination| switch (candidate.*) {
                        .one => |frame| {
                            destination.items.len = 1;
                            destination.items[0] = frame;
                            candidate.* = .empty;
                            return;
                        },
                        .many => |*source| {
                            if (@sizeOf(Frame) == 0 or
                                source.items.len <= destination.capacity)
                            {
                                destination.items.len = source.items.len;
                                @memcpy(destination.items, source.items);
                                source.deinit(allocator);
                                candidate.* = .empty;
                                return;
                            }
                        },
                        .empty => {},
                    },
                    .empty, .one => {},
                }
                self.deinit(allocator);
                self.* = candidate.take();
            }
        };

        const StoredState = struct {
            allocator: std.mem.Allocator,
            sequence: u64 = 0,
            cumulative_fuel: u64 = 0,
            frames: FrameStack,
            // Derived from canonical state bytes when the top frame is parked.
            // This cache is private live-state acceleration, never authority
            // and never part of ABL_RNF2 encoding or Machine identity.
            request_identity: ?RequestIdentity = null,
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
            continuation_digest: [32]u8,
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

        const PreparedResumeValue = struct {
            allocator: std.mem.Allocator,
            state: State,
            request: Request,
            candidate: StoredState,
            consumed: bool = false,
        };

        const PreparedResumeStorage = opaque {};
        /// Opaque owner for a validated pending request and its preallocated
        /// candidate state. Deinitialize it on every path.
        pub const PreparedResume = *PreparedResumeStorage;

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

        fn prepared(prepared_resume: PreparedResume) *PreparedResumeValue {
            return @ptrCast(@alignCast(prepared_resume));
        }

        fn own(allocator: std.mem.Allocator, value: *StoredState) Error!State {
            const result = allocator.create(StoredState) catch return error.OutOfMemory;
            result.* = value.*;
            result.frames = value.frames.take();
            return @ptrCast(result);
        }

        fn topIndex(value: *const StoredState) Error!u32 {
            if (value.frames.len() == 0) return error.ProgramContractViolation;
            return value.frames.len() - 1;
        }

        fn top(value: *const StoredState) Error!Frame {
            return value.frames.get(try topIndex(value)) orelse
                error.ProgramContractViolation;
        }

        fn setTop(value: *StoredState, frame: Frame) Error!void {
            try value.frames.set(try topIndex(value), frame);
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
            request_value: RequestValue,
        ) Error![32]u8 {
            if (RequestValue == void) return error.ProgramContractViolation;
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            portable_value.updateUnionPayloadCanonicalHash(
                RequestValue,
                request_value,
                &hasher,
            ) catch return error.ProgramContractViolation;
            var result: [32]u8 = undefined;
            hasher.final(&result);
            return result;
        }

        fn requestIdentity(
            value: *const StoredState,
            request_value: RequestValue,
        ) Error!RequestIdentity {
            if (RequestValue == void) return error.ProgramContractViolation;
            const sequence = value.sequence;
            const constructor_id = try frameId(try top(value));
            const site_ordinal = portable_value.unionTag(
                RequestValue,
                request_value,
            ) catch return error.ProgramContractViolation;
            if (site_ordinal >= Definition.EffectRow.operation_site_count) {
                return error.ProgramContractViolation;
            }
            const payload_digest = try canonicalPayloadDigest(request_value);
            const continuation_digest = try canonicalContinuationDigest(value);
            const effect_site_digest = Definition.requestSiteDigest(
                request_value,
            );
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update("boundary-request-identity-v2\x00");
            hasher.update(&digest);
            hashRequestInteger(&hasher, u64, sequence);
            hashRequestInteger(&hasher, u32, constructor_id);
            hashRequestInteger(&hasher, u32, site_ordinal);
            hasher.update(&effect_site_digest);
            hasher.update(&payload_digest);
            hasher.update(&continuation_digest);
            var identity_digest: [32]u8 = undefined;
            hasher.final(&identity_digest);
            return .{
                .machine_contract_digest = digest,
                .sequence = sequence,
                .constructor_id = constructor_id,
                .site_ordinal = site_ordinal,
                .effect_site_digest = effect_site_digest,
                .payload_digest = payload_digest,
                .continuation_digest = continuation_digest,
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
                std.mem.eql(
                    u8,
                    &left.continuation_digest,
                    &right.continuation_digest,
                ) and
                std.mem.eql(u8, &left.digest, &right.digest);
        }

        fn validateRequestValue(request_value: RequestValue) Error!void {
            if (RequestValue == void) return error.ProgramContractViolation;
            _ = portable_value.encodedSize(
                RequestValue,
                request_value,
            ) catch return error.ProgramContractViolation;
        }

        fn refreshCurrentRequest(
            value: *StoredState,
            request_value: RequestValue,
        ) Error!Request {
            const constructor_id = try frameId(try top(value));
            const identity = try requestIdentity(value, request_value);
            value.request_identity = identity;
            return Request{
                .sequence = value.sequence,
                .constructor_id = constructor_id,
                .value = request_value,
                .identity = identity,
            };
        }

        fn currentFrom(value: *const StoredState) Error!?Request {
            if (value.terminal) return error.ProgramContractViolation;
            if (comptime RequestValue == void) return null;
            const frame = try top(value);
            const request_value = Definition.current(frame) orelse return null;
            try validateRequestValue(request_value);
            const constructor_id = try frameId(frame);
            const site_ordinal = portable_value.unionTag(
                RequestValue,
                request_value,
            ) catch return error.ProgramContractViolation;
            if (site_ordinal >= Definition.EffectRow.operation_site_count) {
                return error.ProgramContractViolation;
            }
            const identity = value.request_identity orelse
                return error.ProgramContractViolation;
            if (!std.mem.eql(
                u8,
                &identity.machine_contract_digest,
                &digest,
            ) or
                identity.sequence != value.sequence or
                identity.constructor_id != constructor_id or
                identity.site_ordinal != site_ordinal or
                !std.mem.eql(
                    u8,
                    &identity.effect_site_digest,
                    &Definition.requestSiteDigest(request_value),
                ))
            {
                return error.ProgramContractViolation;
            }
            return Request{
                .sequence = value.sequence,
                .constructor_id = constructor_id,
                .value = request_value,
                .identity = identity,
            };
        }

        fn refreshRequestCache(value: *StoredState) Error!void {
            if (value.terminal) return error.ProgramContractViolation;
            if (comptime RequestValue == void) {
                value.request_identity = null;
                return;
            }
            const frame = try top(value);
            const request_value = Definition.current(frame) orelse {
                value.request_identity = null;
                return;
            };
            _ = try refreshCurrentRequest(value, request_value);
        }

        fn stateSize(value: *const StoredState) Error!usize {
            if (value.terminal or value.frames.len() == 0) {
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

        fn maximumResumeStateSize(
            value: *const StoredState,
            request: Request,
        ) Error!usize {
            const frame = try top(value);
            const current_payload_size =
                try portable_value.unionPayloadEncodedSize(Frame, frame);
            const maximum_next_payload_size =
                if (comptime hasDeclSafe(
                    Definition,
                    "maximumResumeFramePayloadSize",
                ))
                    Definition.maximumResumeFramePayloadSize(
                        frame,
                        request.value,
                    ) catch return error.ProgramContractViolation
                else
                    comptime portable_value.maximumUnionPayloadSize(Frame);
            const without_current_payload = std.math.sub(
                usize,
                try stateSize(value),
                current_payload_size,
            ) catch return error.ProgramContractViolation;
            return std.math.add(
                usize,
                without_current_payload,
                maximum_next_payload_size,
            ) catch return error.ProgramContractViolation;
        }

        fn writeCanonicalState(
            value: *const StoredState,
            output: []u8,
        ) Error!void {
            const required = try stateSize(value);
            if (output.len != required) return error.ProgramContractViolation;
            var writer: ByteWriter = .{ .bytes = output };
            writer.write(state_magic);
            writer.writeInt(u16, state_format_version);
            writer.writeInt(u16, machine_abi_version);
            writer.write(&digest);
            writer.writeInt(u64, value.sequence);
            writer.writeInt(u64, value.cumulative_fuel);
            writer.writeInt(u32, @intCast(value.frames.len()));
            writer.writeInt(u32, 0);
            for (value.frames.slice()) |frame| {
                const environment_length =
                    try portable_value.unionPayloadEncodedSize(Frame, frame);
                writer.writeInt(u32, try frameId(frame));
                writer.writeInt(u32, @intCast(environment_length));
                const written = portable_value.encodeUnionPayload(
                    Frame,
                    frame,
                    output[writer.index..][0..environment_length],
                ) catch return error.ProgramContractViolation;
                if (written != environment_length) {
                    return error.ProgramContractViolation;
                }
                writer.index += written;
            }
            if (writer.index != output.len) {
                return error.ProgramContractViolation;
            }
        }

        fn canonicalContinuationDigest(
            value: *const StoredState,
        ) Error![32]u8 {
            _ = try stateSize(value);
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update(state_magic);
            hashRequestInteger(&hasher, u16, state_format_version);
            hashRequestInteger(&hasher, u16, machine_abi_version);
            hasher.update(&digest);
            hashRequestInteger(&hasher, u64, value.sequence);
            hashRequestInteger(&hasher, u64, value.cumulative_fuel);
            hashRequestInteger(
                &hasher,
                u32,
                @intCast(value.frames.len()),
            );
            hashRequestInteger(&hasher, u32, 0);
            for (value.frames.slice()) |frame| {
                const environment_length =
                    try portable_value.unionPayloadEncodedSize(Frame, frame);
                hashRequestInteger(&hasher, u32, try frameId(frame));
                hashRequestInteger(
                    &hasher,
                    u32,
                    @intCast(environment_length),
                );
                portable_value.updateUnionPayloadCanonicalHash(
                    Frame,
                    frame,
                    &hasher,
                ) catch return error.ProgramContractViolation;
            }
            var result: [32]u8 = undefined;
            hasher.final(&result);
            return result;
        }

        fn validate(value: *const StoredState) Error!void {
            if (value.terminal) return error.ProgramContractViolation;
            if (!value.frames.consistent() or
                value.frames.len() == 0 or
                value.frames.len() > options.maximum_frames or
                value.cumulative_fuel > options.maximum_machine_fuel or
                value.sequence > value.cumulative_fuel)
            {
                return error.ProgramContractViolation;
            }
            for (value.frames.slice()) |frame| {
                Definition.validateFrame(frame) catch
                    return error.ProgramContractViolation;
            }
            Definition.validateStack(value.frames.slice()) catch
                return error.ProgramContractViolation;
            const frame = try top(value);
            if (Definition.current(frame) != null and value.sequence == 0) {
                return error.ProgramContractViolation;
            }
            if (try stateSize(value) > options.maximum_state_bytes) {
                return error.ProgramContractViolation;
            }
        }

        fn commit(state: State, candidate: *StoredState) void {
            const destination = stored(state);
            destination.frames.commitFrom(
                destination.allocator,
                &candidate.frames,
            );
            destination.allocator = candidate.allocator;
            destination.sequence = candidate.sequence;
            destination.cumulative_fuel = candidate.cumulative_fuel;
            destination.request_identity = candidate.request_identity;
            destination.terminal = candidate.terminal;
        }

        /// Construct the initial nonempty continuation stack.
        pub fn initialState(
            allocator: std.mem.Allocator,
            args: InitialArgs,
        ) Error!State {
            var value: StoredState = .{
                .allocator = allocator,
                .frames = try FrameStack.initOne(
                    allocator,
                    Definition.initial(args),
                ),
            };
            errdefer value.frames.deinit(allocator);
            try validate(&value);
            try refreshRequestCache(&value);
            return own(allocator, &value);
        }

        /// Clone one live state into an independent allocator owner.
        pub fn cloneState(
            allocator: std.mem.Allocator,
            state: State,
        ) Error!State {
            try validate(storedConst(state));
            var copy = storedConst(state).*;
            copy.allocator = allocator;
            copy.frames = try storedConst(state).frames.clone(allocator);
            errdefer copy.frames.deinit(allocator);
            return own(allocator, &copy);
        }

        /// Release one live Machine state.
        pub fn deinitState(state: State) void {
            const value = stored(state);
            const allocator = value.allocator;
            value.frames.deinit(allocator);
            allocator.destroy(value);
        }

        /// Borrow the current parked request without advancing.
        pub fn current(state: State) Error!Request {
            try validate(storedConst(state));
            return (try currentFrom(storedConst(state))) orelse
                error.ProgramContractViolation;
        }

        fn validatePendingRequest(
            value: *const StoredState,
            request: Request,
        ) Error!void {
            try validateRequestValue(request.value);
            const expected = (try currentFrom(value)) orelse
                return error.ProgramContractViolation;
            if (expected.sequence != request.sequence or
                expected.constructor_id != request.constructor_id or
                !requestIdentityEql(expected.identity, request.identity) or
                !Definition.requestEql(expected.value, request.value))
            {
                return error.ProgramContractViolation;
            }
        }

        fn pendingRequestStillMatches(
            value: *const StoredState,
            request: Request,
        ) Error!void {
            try validate(value);
            const frame = try top(value);
            const request_value = Definition.current(frame) orelse
                return error.ProgramContractViolation;
            const current_request = (try currentFrom(value)) orelse
                return error.ProgramContractViolation;
            if (current_request.sequence != request.sequence or
                current_request.constructor_id != request.constructor_id or
                !requestIdentityEql(
                    current_request.identity,
                    request.identity,
                ) or
                !Definition.requestEql(request_value, request.value))
            {
                return error.ProgramContractViolation;
            }
        }

        /// Validate one request and allocate its complete candidate state
        /// before external handler authority is invoked.
        pub fn prepareResume(
            state: State,
            request: Request,
        ) Error!PreparedResume {
            const original = storedConst(state);
            try validate(original);
            try validatePendingRequest(original, request);
            if (try maximumResumeStateSize(original, request) >
                options.maximum_state_bytes)
            {
                return error.ProgramContractViolation;
            }

            const value = original.allocator.create(PreparedResumeValue) catch
                return error.OutOfMemory;
            errdefer original.allocator.destroy(value);
            value.* = .{
                .allocator = original.allocator,
                .state = state,
                .request = request,
                .candidate = original.*,
            };
            value.candidate.frames = .empty;
            value.candidate.frames =
                try original.frames.clone(original.allocator);
            return @ptrCast(value);
        }

        /// Release a prepared resume that was committed or abandoned.
        pub fn deinitPreparedResume(
            prepared_resume: PreparedResume,
        ) void {
            const value = prepared(prepared_resume);
            value.candidate.frames.deinit(value.allocator);
            value.allocator.destroy(value);
        }

        /// Apply one typed response to an already allocated candidate and
        /// commit it without further allocation.
        pub fn commitPreparedResume(
            prepared_resume: PreparedResume,
            response: anytype,
        ) Error!void {
            const value = prepared(prepared_resume);
            if (value.consumed) return error.ProgramContractViolation;
            const original = storedConst(value.state);
            try pendingRequestStillMatches(original, value.request);

            const next_frame = Definition.@"resume"(
                try top(&value.candidate),
                value.request.value,
                response,
            ) catch return error.ProgramContractViolation;
            value.candidate.request_identity = null;
            try setTop(&value.candidate, next_frame);
            try validate(&value.candidate);
            if (Definition.current(try top(&value.candidate)) != null) {
                return error.ProgramContractViolation;
            }
            commit(value.state, &value.candidate);
            value.consumed = true;
        }

        fn commitYield(
            state: State,
            candidate: *StoredState,
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

            var candidate = original.*;
            candidate.frames = try original.frames.clone(original.allocator);
            defer candidate.frames.deinit(candidate.allocator);
            candidate.request_identity = null;
            var remaining_fuel = caller_fuel.*;

            while (true) {
                const frame = try top(&candidate);
                const minimum_cost = Definition.minimumCost(frame);
                if (minimum_cost == 0) return error.ProgramContractViolation;
                if (remaining_fuel < minimum_cost) {
                    return commitYield(state, &candidate, caller_fuel, remaining_fuel);
                }
                const cost = Definition.cost(frame);
                if (cost < minimum_cost) return error.ProgramContractViolation;
                if (remaining_fuel < cost) {
                    return commitYield(state, &candidate, caller_fuel, remaining_fuel);
                }
                const next_total = std.math.add(
                    u64,
                    candidate.cumulative_fuel,
                    cost,
                ) catch {
                    candidate.terminal = true;
                    commit(state, &candidate);
                    caller_fuel.* = remaining_fuel;
                    return .{ .failed = .execution_budget_exceeded };
                };
                if (next_total > options.maximum_machine_fuel) {
                    candidate.terminal = true;
                    commit(state, &candidate);
                    caller_fuel.* = remaining_fuel;
                    return .{ .failed = .execution_budget_exceeded };
                }
                const plan = Definition.plan(frame);
                if (plan.cost != cost) return error.ProgramContractViolation;
                remaining_fuel -= cost;
                candidate.cumulative_fuel = next_total;

                const action = plan.transition;
                switch (action) {
                    .yielded => |next_frame| {
                        try setTop(&candidate, next_frame);
                        return commitYield(
                            state,
                            &candidate,
                            caller_fuel,
                            remaining_fuel,
                        );
                    },
                    .next => |next_frame| {
                        try setTop(&candidate, next_frame);
                        try validate(&candidate);
                    },
                    .call => |call| {
                        if (candidate.frames.len() == options.maximum_frames) {
                            return .{ .failed = .frame_depth_exceeded };
                        }
                        try setTop(&candidate, call.return_frame);
                        try candidate.frames.push(
                            candidate.allocator,
                            call.callee,
                        );
                        try validate(&candidate);
                    },
                    .return_to => |return_frame| {
                        if (candidate.frames.len() < 2) {
                            return error.ProgramContractViolation;
                        }
                        _ = try candidate.frames.pop(candidate.allocator);
                        try setTop(&candidate, return_frame);
                        try validate(&candidate);
                    },
                    .return_value => |return_value| {
                        if (candidate.frames.len() < 2) {
                            return error.ProgramContractViolation;
                        }
                        if (comptime hasDeclSafe(Definition, "applyReturn")) {
                            const parent_index =
                                candidate.frames.len() - 2;
                            const parent = candidate.frames.get(parent_index) orelse
                                return error.ProgramContractViolation;
                            const return_frame = Definition.applyReturn(
                                parent,
                                return_value,
                            ) catch return error.ProgramContractViolation;
                            _ = try candidate.frames.pop(candidate.allocator);
                            try setTop(&candidate, return_frame);
                            try validate(&candidate);
                        } else {
                            return error.ProgramContractViolation;
                        }
                    },
                    .request => |request| {
                        try setTop(&candidate, request.awaiting);
                        candidate.sequence = std.math.add(
                            u64,
                            candidate.sequence,
                            1,
                        ) catch return error.ProgramContractViolation;
                        try validate(&candidate);
                        const outcome_request = try refreshCurrentRequest(
                            &candidate,
                            request.request,
                        );
                        const reconstructed = (try currentFrom(&candidate)) orelse
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
                        commit(state, &candidate);
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
                        commit(state, &candidate);
                        caller_fuel.* = remaining_fuel;
                        return .{ .done = owned };
                    },
                    .failed => |failure| {
                        candidate.terminal = true;
                        commit(state, &candidate);
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
            const prepared_resume = try prepareResume(state, request);
            defer deinitPreparedResume(prepared_resume);
            try commitPreparedResume(prepared_resume, response);
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
            try writeCanonicalState(value, bytes);
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
            const minimum_frame_bytes = std.math.mul(
                usize,
                @intCast(frame_count),
                8,
            ) catch return error.ProgramContractViolation;
            if (minimum_frame_bytes > bytes.len - reader.index) {
                return error.ProgramContractViolation;
            }

            var frames = try FrameStack.initUninitialized(
                allocator,
                frame_count,
            );
            errdefer frames.deinit(allocator);
            for (0..frame_count) |frame_index| {
                const constructor_id = try reader.readInt(u32);
                const environment_length = try reader.readInt(u32);
                const environment = try reader.read(@intCast(environment_length));
                const frame = portable_value.decodeUnionPayload(
                    Frame,
                    constructor_id,
                    environment,
                ) catch return error.ProgramContractViolation;
                try frames.set(@intCast(frame_index), frame);
            }
            if (reader.index != bytes.len) return error.ProgramContractViolation;
            var value: StoredState = .{
                .allocator = allocator,
                .sequence = sequence,
                .cumulative_fuel = cumulative_fuel,
                .frames = frames,
            };
            frames = .empty;
            errdefer value.frames.deinit(allocator);
            try validate(&value);
            try refreshRequestCache(&value);
            return own(allocator, &value);
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
    const DebugMetadata = struct {
        program_label: []const u8,
    };
    const debug_metadata: DebugMetadata = .{
        .program_label = "test-direct-rnf",
    };

    fn initial(seed: InitialArgs) Frame {
        return .{ .entry = .{ .seed = seed } };
    }

    fn minimumCost(_: Frame) u64 {
        return 1;
    }

    fn cost(_: Frame) u64 {
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
    const cost = TestDefinition.cost;
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

    fn cost(_: Frame) u64 {
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

const LargeFrameText = portable_value.Text(128 << 10);

const LargeFrameDefinition = struct {
    const Frame = union(enum) {
        entry: struct {
            payload: LargeFrameText,
        },
    };
    const InitialArgs = void;
    const Result = void;
    const Failure = enum { rejected };
    const Request = void;
    const EffectRow = struct {
        pub const operation_site_count: usize = 0;
        pub const after_site_count: usize = 0;
    };
    const Transition = Reduction(Frame, Request, Result, Failure);
    const contract_bytes = "test-direct-rnf\x00exact-logical-frame-storage";

    fn initial(_: InitialArgs) Frame {
        return .{ .entry = .{ .payload = LargeFrameText.empty() } };
    }

    fn minimumCost(_: Frame) u64 {
        return 1;
    }

    fn cost(_: Frame) u64 {
        return 1;
    }

    fn plan(_: Frame) struct {
        cost: u64,
        transition: Transition,
    } {
        return .{ .cost = 1, .transition = .{ .done = {} } };
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

const MalformedRequestText = portable_value.Text(8);

const MalformedRequestDefinition = struct {
    const Frame = union(enum) {
        entry: struct {},
        awaiting_lookup: struct {},
    };
    const InitialArgs = void;
    const Result = void;
    const Failure = enum { rejected };
    const Request = union(enum) {
        lookup: MalformedRequestText,
    };
    const EffectRow = struct {
        pub const operation_site_count: usize = 1;
        pub const after_site_count: usize = 0;
    };
    const Transition = Reduction(Frame, Request, Result, Failure);
    const contract_bytes = "test-direct-rnf\x00malformed-request";
    const lookup = MalformedRequestText.fromSlice("lookup") catch unreachable;

    fn initial(_: InitialArgs) Frame {
        return .{ .entry = .{} };
    }

    fn minimumCost(_: Frame) u64 {
        return 1;
    }

    fn cost(_: Frame) u64 {
        return 1;
    }

    fn plan(frame: Frame) struct {
        cost: u64,
        transition: Transition,
    } {
        return .{ .cost = 1, .transition = switch (frame) {
            .entry => .{ .request = .{
                .awaiting = .{ .awaiting_lookup = .{} },
                .request = .{ .lookup = lookup },
            } },
            .awaiting_lookup => unreachable,
        } };
    }

    fn current(frame: Frame) ?Request {
        return switch (frame) {
            .entry => null,
            .awaiting_lookup => .{ .lookup = lookup },
        };
    }

    fn @"resume"(
        frame: Frame,
        _: Request,
        response: anytype,
    ) error{ProgramContractViolation}!Frame {
        if (@TypeOf(response) != void) return error.ProgramContractViolation;
        return switch (frame) {
            .awaiting_lookup => .{ .entry = .{} },
            .entry => error.ProgramContractViolation,
        };
    }

    fn requestEql(left: Request, right: Request) bool {
        return portable_value.eqlValue(Request, left, right);
    }

    fn requestSiteDigest(_: Request) [32]u8 {
        return [_]u8{0x51} ** 32;
    }

    fn validateFrame(_: Frame) error{ProgramContractViolation}!void {}

    fn validateStack(frames: []const Frame) error{ProgramContractViolation}!void {
        if (frames.len != 1) return error.ProgramContractViolation;
    }
};

const CostPreflightDefinition = struct {
    const Frame = union(enum) {
        entry: struct {},
    };
    const InitialArgs = void;
    const Result = void;
    const Failure = enum { rejected };
    const Request = void;
    const EffectRow = struct {
        pub const operation_site_count: usize = 0;
        pub const after_site_count: usize = 0;
    };
    const Transition = Reduction(Frame, Request, Result, Failure);
    const contract_bytes = "test-direct-rnf\x00cost-preflight";
    var plan_calls: usize = 0;

    fn initial(_: InitialArgs) Frame {
        return .{ .entry = .{} };
    }

    fn minimumCost(_: Frame) u64 {
        return 1;
    }

    fn cost(_: Frame) u64 {
        return 5;
    }

    fn plan(_: Frame) struct {
        cost: u64,
        transition: Transition,
    } {
        plan_calls += 1;
        return .{
            .cost = 5,
            .transition = .{ .done = {} },
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

test "request identity binds the complete canonical continuation" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const first_state = try TestMachine.initialState(std.testing.allocator, 3);
    defer TestMachine.deinitState(first_state);
    var fuel: u64 = 10;
    const first_request = switch (try TestMachine.step(first_state, &fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };

    const first_bytes = try TestMachine.encodeState(
        std.testing.allocator,
        first_state,
    );
    defer std.testing.allocator.free(first_bytes);
    var expected_continuation_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        first_bytes,
        &expected_continuation_digest,
        .{},
    );
    try std.testing.expectEqualSlices(
        u8,
        &expected_continuation_digest,
        &first_request.identity.continuation_digest,
    );
    const second_bytes = try std.testing.allocator.dupe(u8, first_bytes);
    defer std.testing.allocator.free(second_bytes);
    std.mem.writeInt(
        u32,
        second_bytes[state_header_length + 8 + 4 ..][0..4],
        1,
        .little,
    );
    const second_state = try TestMachine.decodeState(
        std.testing.allocator,
        second_bytes,
    );
    defer TestMachine.deinitState(second_state);
    const second_request = try TestMachine.current(second_state);

    try std.testing.expect(TestDefinition.requestEql(
        first_request.value,
        second_request.value,
    ));
    try std.testing.expectEqual(first_request.sequence, second_request.sequence);
    try std.testing.expectEqual(
        first_request.constructor_id,
        second_request.constructor_id,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &first_request.identity.continuation_digest,
        &second_request.identity.continuation_digest,
    ));
    try std.testing.expect(!std.mem.eql(
        u8,
        &first_request.identity.digest,
        &second_request.identity.digest,
    ));
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.@"resume"(second_state, first_request, @as(u32, 4)),
    );
    try TestMachine.@"resume"(second_state, second_request, @as(u32, 4));
}

test "live frame storage scales with logical frames, not maximum capacity" {
    const LargeFrameMachine = Machine(LargeFrameDefinition, .{
        .maximum_frames = 64,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 8,
    });
    const backing = try std.testing.allocator.alloc(u8, 512 << 10);
    defer std.testing.allocator.free(backing);
    var fixed = std.heap.FixedBufferAllocator.init(backing);

    const state = try LargeFrameMachine.initialState(fixed.allocator(), {});
    defer LargeFrameMachine.deinitState(state);
    try LargeFrameMachine.validateState(state);

    var caller_fuel: u64 = 1;
    const done = switch (try LargeFrameMachine.step(state, &caller_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(@as(u64, 0), caller_fuel);
}

test "cloned Machine state owns an independent logical frame stack" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const original = try TestMachine.initialState(std.testing.allocator, 7);
    defer TestMachine.deinitState(original);
    const clone = try TestMachine.cloneState(std.testing.allocator, original);
    defer TestMachine.deinitState(clone);

    const before = try TestMachine.encodeState(std.testing.allocator, original);
    defer std.testing.allocator.free(before);
    var caller_fuel: u64 = 1;
    _ = switch (try TestMachine.step(clone, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const after = try TestMachine.encodeState(std.testing.allocator, original);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.current(original),
    );
}

test "Machine validates untrusted request payloads before equality" {
    const RequestMachine = Machine(MalformedRequestDefinition, .{
        .maximum_frames = 1,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 8,
    });
    const state = try RequestMachine.initialState(std.testing.allocator, {});
    defer RequestMachine.deinitState(state);
    var caller_fuel: u64 = 1;
    var forged = switch (try RequestMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    switch (forged.value) {
        .lookup => |*text| text.logical_length =
            MalformedRequestText.maximum_length + 1,
    }

    try std.testing.expectError(
        error.ProgramContractViolation,
        RequestMachine.@"resume"(state, forged, {}),
    );
    const current = try RequestMachine.current(state);
    try std.testing.expect(MalformedRequestDefinition.requestEql(
        current.value,
        .{ .lookup = MalformedRequestDefinition.lookup },
    ));
}

test "Machine request identity hashing does not allocate" {
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
    const request = switch (try TestMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 7), caller_fuel);
    const after = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expect(!std.mem.eql(u8, before, after));
    const current = try TestMachine.current(state);
    try std.testing.expect(TestDefinition.requestEql(
        request.value,
        current.value,
    ));
    try std.testing.expectEqualSlices(
        u8,
        &request.identity.digest,
        &current.identity.digest,
    );
}

test "Machine prepared resume allocation failure preserves pending state" {
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
    var caller_fuel: u64 = 8;
    const request = switch (try TestMachine.step(state, &caller_fuel)) {
        .request => |request| request,
        else => return error.TestUnexpectedResult,
    };
    const before = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(before);

    failing.fail_index = failing.allocations;
    try std.testing.expectError(
        error.OutOfMemory,
        TestMachine.prepareResume(state, request),
    );
    try std.testing.expect(failing.has_induced_failure);
    const after = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    const current = try TestMachine.current(state);
    try std.testing.expectEqualSlices(
        u8,
        &request.identity.digest,
        &current.identity.digest,
    );
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
    failing.fail_index = failing.allocations;
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

test "caller fuel preflight does not execute the segment plan" {
    const PreflightMachine = Machine(CostPreflightDefinition, .{
        .maximum_frames = 1,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 8,
    });
    CostPreflightDefinition.plan_calls = 0;
    const state = try PreflightMachine.initialState(std.testing.allocator, {});
    defer PreflightMachine.deinitState(state);
    var insufficient_fuel: u64 = 4;

    try std.testing.expectEqual(
        PreflightMachine.Outcome.yielded,
        try PreflightMachine.step(state, &insufficient_fuel),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        CostPreflightDefinition.plan_calls,
    );

    var sufficient_fuel: u64 = 5;
    const done = switch (try PreflightMachine.step(state, &sufficient_fuel)) {
        .done => |result| result,
        else => return error.TestUnexpectedResult,
    };
    defer done.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        CostPreflightDefinition.plan_calls,
    );
}

test "cumulative fuel overflow fails before segment execution" {
    const OverflowMachine = Machine(BudgetTestDefinition, .{
        .maximum_frames = 1,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = std.math.maxInt(u64),
    });
    const initial = try OverflowMachine.initialState(std.testing.allocator, {});
    defer OverflowMachine.deinitState(initial);
    const encoded = try OverflowMachine.encodeState(
        std.testing.allocator,
        initial,
    );
    defer std.testing.allocator.free(encoded);
    var forged: [4096]u8 = undefined;
    @memcpy(forged[0..encoded.len], encoded);
    const cumulative_fuel_offset = state_magic.len + 2 + 2 + 32 + 8;
    std.mem.writeInt(
        u64,
        forged[cumulative_fuel_offset..][0..8],
        std.math.maxInt(u64),
        .little,
    );
    const state = try OverflowMachine.decodeState(
        std.testing.allocator,
        forged[0..encoded.len],
    );
    defer OverflowMachine.deinitState(state);
    var caller_fuel: u64 = 1;

    try std.testing.expectEqual(
        OverflowMachine.Outcome{
            .failed = .execution_budget_exceeded,
        },
        try OverflowMachine.step(state, &caller_fuel),
    );
    try std.testing.expectEqual(@as(u64, 1), caller_fuel);
}

test "decode rejects impossible request sequence and fuel histories" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const initial = try TestMachine.initialState(std.testing.allocator, 3);
    defer TestMachine.deinitState(initial);
    const initial_bytes = try TestMachine.encodeState(
        std.testing.allocator,
        initial,
    );
    defer std.testing.allocator.free(initial_bytes);
    var forged_initial: [4096]u8 = undefined;
    @memcpy(forged_initial[0..initial_bytes.len], initial_bytes);
    const sequence_offset = state_magic.len + 2 + 2 + 32;
    std.mem.writeInt(
        u64,
        forged_initial[sequence_offset..][0..8],
        1,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(
            std.testing.allocator,
            forged_initial[0..initial_bytes.len],
        ),
    );

    var caller_fuel: u64 = 2;
    _ = try TestMachine.step(initial, &caller_fuel);
    const parked_bytes = try TestMachine.encodeState(
        std.testing.allocator,
        initial,
    );
    defer std.testing.allocator.free(parked_bytes);
    var forged_parked: [4096]u8 = undefined;
    @memcpy(forged_parked[0..parked_bytes.len], parked_bytes);
    std.mem.writeInt(
        u64,
        forged_parked[sequence_offset..][0..8],
        0,
        .little,
    );
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(
            std.testing.allocator,
            forged_parked[0..parked_bytes.len],
        ),
    );
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
    try std.testing.expect(DebugMachine.Manifest.includes_debug_metadata);
    try std.testing.expectEqualStrings(
        "test-direct-rnf",
        DebugMachine.debug_metadata.program_label,
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

test "ABL_RNF2 decode rejects impossible frame count before allocation" {
    const TestMachine = Machine(TestDefinition, .{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const state = try TestMachine.initialState(std.testing.allocator, 7);
    defer TestMachine.deinitState(state);
    const encoded = try TestMachine.encodeState(std.testing.allocator, state);
    defer std.testing.allocator.free(encoded);

    var forged: [4096]u8 = undefined;
    @memcpy(forged[0..encoded.len], encoded);
    const frame_count_offset = state_magic.len + 2 + 2 + 32 + 8 + 8;
    std.mem.writeInt(
        u32,
        forged[frame_count_offset..][0..4],
        TestMachine.Manifest.maximum_frames,
        .little,
    );

    var no_storage: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_storage);
    try std.testing.expectError(
        error.ProgramContractViolation,
        TestMachine.decodeState(
            fixed.allocator(),
            forged[0..encoded.len],
        ),
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
