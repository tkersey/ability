const image_v1 = @import("image_v1");
const kernel_v1 = @import("kernel_v1");
const machine = @import("machine");
const portable_value = @import("portable_value");
const std = @import("std");

pub fn Machine(
    comptime Definition: type,
    comptime Image: type,
    comptime options: machine.Options,
) type {
    const Direct = machine.Machine(Definition, options);
    return struct {
        const Self = @This();

        pub const abi_version = Direct.abi_version;
        pub const InitialArgs = Definition.InitialArgs;
        pub const Result = Definition.Result;
        pub const Failure = Direct.Failure;
        pub const EffectRow = Definition.EffectRow;
        pub const RequestValue = Definition.Request;
        pub const Manifest = Direct.Manifest;
        pub const Error = portable_value.Error || error{
            OutOfMemory,
            ProgramContractViolation,
        };

        const StoredState = struct {
            allocator: std.mem.Allocator,
            storage: []u8,
            length: usize,
            request_storage: []u8,
            prepared_active: bool = false,
            terminal: bool = false,
            terminal_result: ?*OwnedResult = null,
            release_requested: bool = false,
        };
        const StateStorage = opaque {};
        pub const State = *StateStorage;

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
        pub const Request = struct {
            sequence: u64,
            constructor_id: u32,
            value: RequestValue,
            identity: RequestIdentity,
        };

        const OwnedResultValue = struct {
            allocator: std.mem.Allocator,
            state: State,
            result: Result,
            state_released: bool = false,
        };
        pub const OwnedResult = opaque {
            pub fn value(self: *const OwnedResult) *const Result {
                return &ownedResultConst(self).result;
            }

            pub fn deinit(self: *OwnedResult) void {
                releaseOwnedResult(self);
            }
        };

        pub const Outcome = union(enum) {
            request: Request,
            yielded,
            done: *OwnedResult,
            failed: Failure,
        };

        const PreparedResumeValue = struct {
            allocator: std.mem.Allocator,
            state: State,
            request: Request,
            candidate: []u8,
            consumed: bool = false,
        };
        const PreparedResumeStorage = opaque {};
        pub const PreparedResume = *PreparedResumeStorage;

        pub fn initialState(
            allocator: std.mem.Allocator,
            args: InitialArgs,
        ) Error!State {
            var args_storage = allocator.alloc(
                u8,
                portable_value.maximumEncodedSize(InitialArgs),
            ) catch return error.OutOfMemory;
            defer allocator.free(args_storage);
            const args_length = portable_value.encode(
                InitialArgs,
                args,
                args_storage,
            ) catch return error.ProgramContractViolation;
            const state = try allocateState(allocator);
            errdefer destroyState(state);
            var workspace: image_v1.ValidationWorkspace = .{};
            workspace.invariant_result = state.request_storage;
            const image = image_v1.validateImage(&Image.bytes, &workspace) catch
                return error.ProgramContractViolation;
            state.length = kernel_v1.initial(
                image,
                args_storage[0..args_length],
                state.storage,
                &workspace,
            ) catch return error.ProgramContractViolation;
            return @ptrCast(state);
        }

        pub fn cloneState(
            allocator: std.mem.Allocator,
            state: State,
        ) Error!State {
            const source = storedConst(state);
            try validateState(state);
            const clone = try allocateState(allocator);
            @memcpy(clone.storage[0..source.length], source.storage[0..source.length]);
            clone.length = source.length;
            return @ptrCast(clone);
        }

        pub fn deinitState(state: State) void {
            const value = stored(state);
            value.release_requested = true;
            if (value.terminal_result) |result| {
                ownedResult(result).state_released = true;
                return;
            }
            if (!value.prepared_active) destroyState(value);
        }

        pub fn validateState(state: State) Error!void {
            const value = storedConst(state);
            if (value.terminal) return error.ProgramContractViolation;
            var workspace: image_v1.ValidationWorkspace = .{};
            workspace.invariant_result = value.request_storage;
            const image = image_v1.validateImage(&Image.bytes, &workspace) catch
                return error.ProgramContractViolation;
            kernel_v1.validateState(
                image,
                value.storage[0..value.length],
                &workspace,
            ) catch return error.ProgramContractViolation;
        }

        pub fn encodeState(
            allocator: std.mem.Allocator,
            state: State,
        ) Error![]u8 {
            try validateState(state);
            const value = storedConst(state);
            const result = allocator.alloc(u8, value.length) catch
                return error.OutOfMemory;
            @memcpy(result, value.storage[0..value.length]);
            return result;
        }

        pub fn decodeState(
            allocator: std.mem.Allocator,
            bytes: []const u8,
        ) Error!State {
            if (bytes.len > options.maximum_state_bytes) {
                return error.ProgramContractViolation;
            }
            const state = try allocateState(allocator);
            errdefer destroyState(state);
            @memcpy(state.storage[0..bytes.len], bytes);
            state.length = bytes.len;
            const public: State = @ptrCast(state);
            try validateState(public);
            return public;
        }

        pub fn current(state: State) Error!?Request {
            const value = stored(state);
            try validateState(state);
            var workspace: image_v1.ValidationWorkspace = .{};
            workspace.invariant_result = value.request_storage;
            const image = image_v1.validateImage(&Image.bytes, &workspace) catch
                return error.ProgramContractViolation;
            const maybe_request = kernel_v1.current(
                image,
                value.storage[0..value.length],
                value.request_storage,
                &workspace,
            ) catch return error.ProgramContractViolation;
            const request = maybe_request orelse return null;
            return typedRequest(request) catch return error.ProgramContractViolation;
        }

        pub fn step(state: State, caller_fuel: *u64) Error!Outcome {
            const value = stored(state);
            if (value.terminal or value.prepared_active) {
                return error.ProgramContractViolation;
            }
            var workspace: image_v1.ValidationWorkspace = .{};
            const image = image_v1.validateImage(&Image.bytes, &workspace) catch
                return error.ProgramContractViolation;
            const candidate = value.allocator.alloc(
                u8,
                options.maximum_state_bytes,
            ) catch return error.OutOfMemory;
            errdefer value.allocator.free(candidate);
            const scratch_length = std.math.add(
                usize,
                options.maximum_state_bytes,
                @intCast(Image.maximum_kernel_scratch_bytes),
            ) catch return error.OutOfMemory;
            const scratch = value.allocator.alloc(u8, scratch_length) catch
                return error.OutOfMemory;
            defer value.allocator.free(scratch);
            workspace.invariant_result = scratch[options.maximum_state_bytes..];
            const outcome = kernel_v1.step(
                image,
                value.storage[0..value.length],
                caller_fuel,
                candidate,
                value.request_storage,
                scratch,
                &workspace,
            ) catch return error.ProgramContractViolation;
            return switch (outcome) {
                .yielded => |bytes| blk: {
                    commitState(value, candidate, bytes.len);
                    break :blk .yielded;
                },
                .requested => |request| blk: {
                    const typed = typedRequest(request) catch
                        return error.ProgramContractViolation;
                    commitState(value, candidate, request.state.len);
                    break :blk .{ .request = typed };
                },
                .done => |bytes| blk: {
                    const result = portable_value.decodeExact(Result, bytes) catch
                        return error.ProgramContractViolation;
                    const owner = value.allocator.create(OwnedResultValue) catch
                        return error.OutOfMemory;
                    value.allocator.free(candidate);
                    owner.* = .{
                        .allocator = value.allocator,
                        .state = state,
                        .result = result,
                    };
                    const public: *OwnedResult = @ptrCast(owner);
                    value.terminal = true;
                    value.terminal_result = public;
                    break :blk .{ .done = public };
                },
                .failed => |bytes| blk: {
                    const authored = portable_value.decodeExact(
                        Definition.Failure,
                        bytes,
                    ) catch return error.ProgramContractViolation;
                    value.allocator.free(candidate);
                    value.terminal = true;
                    break :blk .{ .failed = .{ .authored = authored } };
                },
                .machine_failed => |failed| blk: {
                    switch (failed.failure) {
                        .execution_budget_exceeded => {
                            commitState(value, candidate, failed.state.len);
                            value.terminal = true;
                            break :blk .{ .failed = .execution_budget_exceeded };
                        },
                        .frame_depth_exceeded => {
                            value.allocator.free(candidate);
                            break :blk .{ .failed = .frame_depth_exceeded };
                        },
                    }
                },
            };
        }

        pub fn prepareResume(
            state: State,
            request: Request,
        ) Error!PreparedResume {
            const value = stored(state);
            if (value.prepared_active) return error.ProgramContractViolation;
            const expected = (try current(state)) orelse
                return error.ProgramContractViolation;
            if (!requestEql(expected, request)) return error.ProgramContractViolation;
            var workspace: image_v1.ValidationWorkspace = .{};
            workspace.invariant_result = value.request_storage;
            const image = image_v1.validateImage(&Image.bytes, &workspace) catch
                return error.ProgramContractViolation;
            const maximum_resume_state = kernel_v1.maximumResumeStateSize(
                image,
                value.storage[0..value.length],
            ) catch return error.ProgramContractViolation;
            if (maximum_resume_state > options.maximum_state_bytes) {
                return error.ProgramContractViolation;
            }
            const prepared = value.allocator.create(PreparedResumeValue) catch
                return error.OutOfMemory;
            errdefer value.allocator.destroy(prepared);
            const candidate = value.allocator.alloc(
                u8,
                options.maximum_state_bytes,
            ) catch return error.OutOfMemory;
            prepared.* = .{
                .allocator = value.allocator,
                .state = state,
                .request = request,
                .candidate = candidate,
            };
            value.prepared_active = true;
            return @ptrCast(prepared);
        }

        pub fn deinitPreparedResume(prepared: PreparedResume) void {
            const value = preparedValue(prepared);
            const state = stored(value.state);
            if (!value.consumed) value.allocator.free(value.candidate);
            const allocator = value.allocator;
            allocator.destroy(value);
            state.prepared_active = false;
            if (state.release_requested and state.terminal_result == null) {
                destroyState(state);
            }
        }

        pub fn @"resume"(
            prepared: PreparedResume,
            response: anytype,
        ) Error!void {
            const value = preparedValue(prepared);
            if (value.consumed) return error.ProgramContractViolation;
            const state = stored(value.state);
            const response_bytes = value.allocator.alloc(
                u8,
                portable_value.maximumEncodedSize(@TypeOf(response)),
            ) catch return error.OutOfMemory;
            defer value.allocator.free(response_bytes);
            const response_length = portable_value.encode(
                @TypeOf(response),
                response,
                response_bytes,
            ) catch return error.ProgramContractViolation;
            var workspace: image_v1.ValidationWorkspace = .{};
            workspace.invariant_result = state.request_storage;
            const image = image_v1.validateImage(&Image.bytes, &workspace) catch
                return error.ProgramContractViolation;
            const next_length = kernel_v1.@"resume"(
                image,
                state.storage[0..state.length],
                kernelIdentity(value.request.identity),
                response_bytes[0..response_length],
                value.candidate,
                &workspace,
            ) catch return error.ProgramContractViolation;
            state.allocator.free(state.storage);
            state.storage = value.candidate;
            state.length = next_length;
            value.consumed = true;
        }

        fn allocateState(allocator: std.mem.Allocator) Error!*StoredState {
            const value = allocator.create(StoredState) catch
                return error.OutOfMemory;
            errdefer allocator.destroy(value);
            const storage = allocator.alloc(u8, options.maximum_state_bytes) catch
                return error.OutOfMemory;
            errdefer allocator.free(storage);
            const request_storage = allocator.alloc(
                u8,
                @max(1, Image.maximum_single_value_bytes),
            ) catch return error.OutOfMemory;
            value.* = .{
                .allocator = allocator,
                .storage = storage,
                .length = 0,
                .request_storage = request_storage,
            };
            return value;
        }

        fn destroyState(value: *StoredState) void {
            const allocator = value.allocator;
            allocator.free(value.storage);
            allocator.free(value.request_storage);
            allocator.destroy(value);
        }

        fn commitState(value: *StoredState, candidate: []u8, length: usize) void {
            value.allocator.free(value.storage);
            value.storage = candidate;
            value.length = length;
        }

        fn stored(state: State) *StoredState {
            return @ptrCast(@alignCast(state));
        }

        fn storedConst(state: State) *const StoredState {
            return @ptrCast(@alignCast(state));
        }

        fn preparedValue(prepared: PreparedResume) *PreparedResumeValue {
            return @ptrCast(@alignCast(prepared));
        }

        fn ownedResult(value: *OwnedResult) *OwnedResultValue {
            return @ptrCast(@alignCast(value));
        }

        fn ownedResultConst(value: *const OwnedResult) *const OwnedResultValue {
            return @ptrCast(@alignCast(value));
        }

        fn releaseOwnedResult(result: *OwnedResult) void {
            const owner = ownedResult(result);
            const state = stored(owner.state);
            state.terminal_result = null;
            const allocator = owner.allocator;
            const state_released = owner.state_released;
            allocator.destroy(owner);
            if (state_released) destroyState(state);
        }

        fn typedRequest(view: kernel_v1.RequestView) Error!Request {
            return .{
                .sequence = view.identity.sequence,
                .constructor_id = view.identity.constructor_id,
                .value = try decodeRequestValue(
                    view.identity.site_ordinal,
                    view.payload,
                ),
                .identity = typedIdentity(view.identity),
            };
        }

        fn decodeRequestValue(ordinal: u32, bytes: []const u8) Error!RequestValue {
            if (RequestValue == void) return error.ProgramContractViolation;
            inline for (std.meta.fields(RequestValue), 0..) |field, index| {
                if (ordinal == index) {
                    const payload = portable_value.decodeExact(
                        field.type,
                        bytes,
                    ) catch return error.ProgramContractViolation;
                    return @unionInit(RequestValue, field.name, payload);
                }
            }
            return error.ProgramContractViolation;
        }

        fn typedIdentity(value: kernel_v1.RequestIdentity) RequestIdentity {
            return .{
                .machine_contract_digest = value.machine_contract_digest,
                .sequence = value.sequence,
                .constructor_id = value.constructor_id,
                .site_ordinal = value.site_ordinal,
                .effect_site_digest = value.effect_site_digest,
                .payload_digest = value.payload_digest,
                .continuation_digest = value.continuation_digest,
                .digest = value.digest,
            };
        }

        fn kernelIdentity(value: RequestIdentity) kernel_v1.RequestIdentity {
            return .{
                .machine_contract_digest = value.machine_contract_digest,
                .sequence = value.sequence,
                .constructor_id = value.constructor_id,
                .site_ordinal = value.site_ordinal,
                .effect_site_digest = value.effect_site_digest,
                .payload_digest = value.payload_digest,
                .continuation_digest = value.continuation_digest,
                .digest = value.digest,
            };
        }

        fn requestEql(left: Request, right: Request) bool {
            return left.sequence == right.sequence and
                left.constructor_id == right.constructor_id and
                left.identity.sequence == right.identity.sequence and
                left.identity.constructor_id == right.identity.constructor_id and
                left.identity.site_ordinal == right.identity.site_ordinal and
                std.mem.eql(
                    u8,
                    &left.identity.machine_contract_digest,
                    &right.identity.machine_contract_digest,
                ) and
                std.mem.eql(
                    u8,
                    &left.identity.effect_site_digest,
                    &right.identity.effect_site_digest,
                ) and
                std.mem.eql(
                    u8,
                    &left.identity.payload_digest,
                    &right.identity.payload_digest,
                ) and
                std.mem.eql(
                    u8,
                    &left.identity.continuation_digest,
                    &right.identity.continuation_digest,
                ) and
                std.mem.eql(
                    u8,
                    &left.identity.digest,
                    &right.identity.digest,
                ) and
                Definition.requestEql(left.value, right.value);
        }
    };
}
