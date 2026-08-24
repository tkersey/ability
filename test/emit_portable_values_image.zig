const boundary = @import("boundary");
const operations = @import("operations_fixture");
const std = @import("std");

const Image = operations.ReificationBaselineProgram.image();

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(&Image.bytes);
    try writer.interface.flush();
    _ = boundary.package_version;
}
