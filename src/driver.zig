/// Construct a semantics-free local owner and typed effect driver.
pub fn Driver(comptime Machine: type) type {
    return struct {
        const Self = @This();

        /// Outcomes not consumed internally by typed effect handlers.
        pub const Outcome = union(enum) {
            yielded,
            done: *Machine.OwnedResult,
            failed: Machine.Failure,
        };

        allocator: @import("std").mem.Allocator,
        state: Machine.State,

        /// Initialize the same Machine state used by World execution.
        pub fn init(
            allocator: @import("std").mem.Allocator,
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
            while (true) {
                switch (try Machine.step(self.state, caller_fuel)) {
                    .request => |request| {
                        if (Machine.RequestValue == void) {
                            return error.ProgramContractViolation;
                        }
                        switch (request.value) {
                            inline else => |payload, tag| {
                                const response = try handlers.handle(tag, payload);
                                try Machine.@"resume"(
                                    self.state,
                                    request,
                                    response,
                                );
                            },
                        }
                    },
                    .yielded => return .yielded,
                    .done => |result| return .{ .done = result },
                    .failed => |failure| return .{ .failed = failure },
                }
            }
        }
    };
}
