const parity_witness = @import("parity_witness");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const length = parity_witness.boundaryMachineParityRun();
    if (length == 0) return error.ParityWitnessFailed;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(parity_witness.outputBytes(length));

    const value_length = parity_witness.boundaryMachineValueParityRun();
    if (value_length == 0) return error.PortableValueParityWitnessFailed;
    try stdout.writeAll(parity_witness.valueOutputBytes(value_length));
    try stdout.flush();
}
