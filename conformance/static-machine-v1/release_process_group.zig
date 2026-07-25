// zlinter-disable require_errdefer_dealloc
const std = @import("std");

const ProcessGroupError = error{
    InvalidArguments,
    ProcessGroupUnavailable,
};

fn establishProcessGroup() ProcessGroupError!std.posix.pid_t {
    switch (std.posix.errno(std.posix.system.setpgid(0, 0))) {
        .SUCCESS => {},
        else => return error.ProcessGroupUnavailable,
    }
    return std.posix.system.getpid();
}

fn writeReady(
    init: std.process.Init,
    ready_path: []const u8,
    process_group: std.posix.pid_t,
) !void {
    const receipt = try std.fmt.allocPrint(
        init.gpa,
        "boundary-release-process-group/v1 {d}\n",
        .{process_group},
    );
    defer init.gpa.free(receipt);
    var ready = try std.Io.Dir.createFileAbsolute(init.io, ready_path, .{
        .exclusive = true,
        .permissions = @enumFromInt(0o600),
    });
    defer ready.close(init.io);
    try ready.writeStreamingAll(init.io, receipt);
}

/// Establishes one verifier-owned process group before launching any verifier
/// process. The readiness receipt binds the helper PID to that group before the
/// shell accepts the verifier launch.
pub fn main(init: std.process.Init) anyerror!void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const ready_path = args.next() orelse return error.InvalidArguments;
    if (!std.Io.Dir.path.isAbsolute(ready_path)) return error.InvalidArguments;

    var command: std.ArrayList([]const u8) = .empty;
    defer command.deinit(init.gpa);
    while (args.next()) |arg| try command.append(init.gpa, arg);
    if (command.items.len == 0) return error.InvalidArguments;

    const process_group = try establishProcessGroup();
    try writeReady(init, ready_path, process_group);

    var child = try std.process.spawn(init.io, .{
        .argv = command.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
        .pgid = process_group,
    });
    const term = try child.wait(init.io);
    switch (term) {
        .exited => |status| std.process.exit(status),
        .signal => |signal| std.process.exit(128 + @as(u8, @intCast(@intFromEnum(signal)))),
        .stopped, .unknown => std.process.exit(1),
    }
}

test "readiness receipt names the owned process group" {
    const process_group: std.posix.pid_t = 42;
    const receipt = try std.fmt.allocPrint(
        std.testing.allocator,
        "boundary-release-process-group/v1 {d}\n",
        .{process_group},
    );
    defer std.testing.allocator.free(receipt);
    try std.testing.expectEqualStrings(
        "boundary-release-process-group/v1 42\n",
        receipt,
    );
}
