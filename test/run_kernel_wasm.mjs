import fs from "node:fs";

const bytes = fs.readFileSync(process.argv[2]);
const vector = fs.readFileSync(process.argv[3]);
if (bytes.length > 2 * 1024 * 1024) throw new Error("kernel WASM exceeds 2 MiB");
const module = await WebAssembly.compile(bytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("kernel WASM must have zero imports");
}
const instance = await WebAssembly.instantiate(module, {});
const expected = [
  "memory",
  "boundary_kernel_abi_version",
  "boundary_kernel_input_ptr",
  "boundary_kernel_input_capacity",
  "boundary_kernel_execute",
  "boundary_kernel_output_ptr",
  "boundary_kernel_output_len",
  "boundary_kernel_error_ptr",
  "boundary_kernel_error_len",
  "boundary_kernel_reset",
];
for (const name of expected) {
  if (!(name in instance.exports)) throw new Error(`missing export ${name}`);
}
if (instance.exports.boundary_kernel_abi_version() !== 1) {
  throw new Error("unexpected kernel ABI");
}
if (instance.exports.boundary_kernel_input_capacity() < 24 * 1024 * 1024) {
  throw new Error("kernel input profile is undersized");
}
if (instance.exports.boundary_kernel_reset() !== 0) throw new Error("reset failed");
if (instance.exports.boundary_kernel_execute(24 * 1024 * 1024 + 1) !== 1) {
  throw new Error("oversized kernel input was accepted");
}
const inputLength = vector.readUInt32LE(0);
const expectedLength = vector.readUInt32LE(4);
const input = vector.subarray(8, 8 + inputLength);
const expectedOutput = vector.subarray(8 + inputLength, 8 + inputLength + expectedLength);
const memory = new Uint8Array(instance.exports.memory.buffer);
const inputPtr = instance.exports.boundary_kernel_input_ptr();
memory.set(input, inputPtr);
if (instance.exports.boundary_kernel_execute(input.length) !== 0) {
  throw new Error("kernel semantic vector failed");
}
const outputPtr = instance.exports.boundary_kernel_output_ptr();
const outputLength = instance.exports.boundary_kernel_output_len();
const actualOutput = memory.slice(outputPtr, outputPtr + outputLength);
if (!Buffer.from(actualOutput).equals(expectedOutput)) {
  throw new Error("native/WASM kernel output mismatch");
}
process.stdout.write(`kernel_wasm_bytes=${bytes.length} imports=0 abi=1\n`);
