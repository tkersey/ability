const fixture = @import("reified_program_fixture");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const witness = try fixture.reificationReceiptWitness(
        std.heap.page_allocator,
    );
    var output_buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &output_buffer);
    try writer.interface.print(
        "{{\"format\":\"boundary-reification-semantic-proof/v1\"," ++
            "\"image_profile_invariance_passed\":{}," ++
            "\"metering_annotation_invariance_passed\":{}," ++
            "\"malformed_image_case_count\":{d}," ++
            "\"malformed_state_case_count\":{d}," ++
            "\"machine_abi\":{d},\"state_format_version\":{d}}}\n",
        .{
            witness.image_profile_invariance_passed,
            witness.metering_annotation_invariance_passed,
            witness.malformed_image_case_count,
            witness.malformed_state_case_count,
            witness.machine_abi,
            witness.state_format_version,
        },
    );
    try writer.interface.flush();
}
