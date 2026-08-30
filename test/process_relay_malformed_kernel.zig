const input_header_length: usize = 40;
const wasm_page_bytes: usize = 64 * 1024;

var input_storage: [128]u8 align(16) = undefined;
var mode: u32 = 0;
var grown_output_pointer: u32 = 0;

pub export fn boundary_process_kernel_abi_version() u32 {
    return 1;
}

pub export fn boundary_process_kernel_prepare_input(
    instance_kind: u32,
    image_length: u64,
    instance_length: u64,
    result_present: u32,
    result_length: u64,
) u32 {
    _ = instance_kind;
    _ = result_present;
    const required = input_header_length + image_length +
        instance_length + result_length;
    if (required > input_storage.len) return 0;
    mode = @intCast(instance_length);
    return @intCast(required);
}

pub export fn boundary_process_kernel_input_payload_ptr() u32 {
    return @intCast(@intFromPtr(&input_storage) + input_header_length);
}

pub export fn boundary_process_kernel_execute(input_length: u32) u32 {
    _ = input_length;
    if (mode == 4) {
        const prior_pages = @wasmMemoryGrow(0, 1);
        if (prior_pages < 0) return 1;
        const start = @as(usize, @intCast(prior_pages)) * wasm_page_bytes;
        grown_output_pointer = @intCast(start);
        const grown_output: [*]u8 = @ptrFromInt(start);
        @memcpy(grown_output[0..4], "GROW");
    }
    return @intFromBool(mode >= 5 and mode <= 7);
}

pub export fn boundary_process_kernel_output_ptr() u32 {
    const memory_length = currentMemoryLength();
    return switch (mode) {
        1 => memory_length + 1,
        3 => memory_length - 1,
        4 => grown_output_pointer,
        else => @intCast(@intFromPtr(&input_storage)),
    };
}

pub export fn boundary_process_kernel_output_len() u64 {
    return switch (mode) {
        2 => @as(u64, 1) << 53,
        3 => 2,
        4 => 4,
        else => 1,
    };
}

pub export fn boundary_process_kernel_error_ptr() u32 {
    const memory_length = currentMemoryLength();
    return switch (mode) {
        5 => memory_length + 1,
        7 => memory_length - 1,
        else => @intCast(@intFromPtr(&input_storage)),
    };
}

pub export fn boundary_process_kernel_error_len() u64 {
    return switch (mode) {
        6 => @as(u64, 1) << 53,
        7 => 2,
        else => 1,
    };
}

fn currentMemoryLength() u32 {
    return @intCast(@wasmMemorySize(0) * wasm_page_bytes);
}
