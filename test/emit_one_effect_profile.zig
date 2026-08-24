const fixture = @import("image_fixture");
const std = @import("std");

const Profile = fixture.Program.machineV2Profile(.{
    .maximum_frames = 4,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 32,
});

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(&Profile.bytes);
    try writer.interface.flush();
}
