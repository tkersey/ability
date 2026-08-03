const std = @import("std");

/// Construct a semantics-free local owner and typed effect driver.
pub fn Driver(comptime Machine: type) type {
    return struct {
        const Self = @This();

        fn requireSemanticSite(
            comptime Handler: type,
            comptime Site: type,
        ) void {
            if (!@hasDecl(Handler, "semantic_site_contract_digests")) {
                @compileError(
                    "Boundary Driver handlers must declare semantic_site_contract_digests",
                );
            }
            inline for (
                Handler.semantic_site_contract_digests,
            ) |contract_digest| {
                if (std.mem.eql(
                    u8,
                    &contract_digest,
                    &Site.semantic_contract_digest,
                )) return;
            }
            @compileError(
                "Boundary Driver handler does not admit effect site semantic contract",
            );
        }

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
            var pending_request = try Machine.current(self.state);
            while (true) {
                if (pending_request) |request| {
                    if (comptime Machine.RequestValue == void) {
                        return error.ProgramContractViolation;
                    }
                    switch (request.value) {
                        inline else => |payload, tag| {
                            const Site = Machine.EffectRow.site(
                                comptime @intFromEnum(tag),
                            );
                            comptime requireSemanticSite(
                                @TypeOf(handlers.*),
                                Site,
                            );
                            const prepared_resume =
                                try Machine.prepareResume(
                                    self.state,
                                    request,
                                );
                            defer Machine.deinitPreparedResume(
                                prepared_resume,
                            );
                            const response = handlers.handle(
                                Site,
                                payload,
                                request.identity,
                            ) catch |err| return .{ .handler_error = .{
                                .request = request,
                                .err = err,
                            } };
                            if (comptime @TypeOf(response) != Site.Resume) {
                                @compileError(
                                    "Boundary Machine response type must match the selected effect site Resume type",
                                );
                            }
                            try Machine.@"resume"(
                                prepared_resume,
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
