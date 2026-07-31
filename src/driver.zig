const std = @import("std");

/// Construct a semantics-free local owner and typed effect driver.
pub fn Driver(comptime Machine: type) type {
    return struct {
        const Self = @This();

        /// Outcomes not consumed internally by typed effect handlers.
        pub const Outcome = union(enum) {
            yielded,
            done: *Machine.OwnedResult,
            failed: Machine.Failure,
            handler_error: struct {
                request: Machine.Request,
                err: anyerror,
            },
        };

        allocator: std.mem.Allocator,
        state: Machine.State,

        /// Initialize the same Machine state used by World execution.
        pub fn init(
            allocator: std.mem.Allocator,
            args: Machine.InitialArgs,
        ) Machine.Error!Self {
            return .{
                .allocator = allocator,
                .state = try Machine.initialState(allocator, args),
            };
        }

        /// Release the locally owned Machine state.
        pub fn deinit(self: *Self) void {
            Machine.deinitState(self.state);
            self.* = undefined;
        }

        /// Drive requests through one typed handler until yield or termination.
        pub fn run(
            self: *Self,
            handlers: anytype,
            caller_fuel: *u64,
        ) anyerror!Outcome {
            var pending_request: ?Machine.Request =
                Machine.current(self.state) catch |err| switch (err) {
                    error.ProgramContractViolation => null,
                    else => return err,
                };
            while (true) {
                if (pending_request) |request| {
                    if (comptime Machine.RequestValue == void) {
                        return error.ProgramContractViolation;
                    }
                    switch (request.value) {
                        inline else => |payload, tag| {
                            const response = handlers.handle(
                                tag,
                                payload,
                            ) catch |err| return .{ .handler_error = .{
                                .request = request,
                                .err = err,
                            } };
                            try Machine.@"resume"(
                                self.state,
                                request,
                                response,
                            );
                        },
                    }
                    pending_request = null;
                    continue;
                }
                switch (try Machine.step(self.state, caller_fuel)) {
                    .request => |request| pending_request = request,
                    .yielded => return .yielded,
                    .done => |result| return .{ .done = result },
                    .failed => |failure| return .{ .failed = failure },
                }
            }
        }
    };
}
