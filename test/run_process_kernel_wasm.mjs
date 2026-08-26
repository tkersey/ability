import crypto from "node:crypto";
import fs from "node:fs";

const wasmBytes = fs.readFileSync(process.argv[2]);
const vectorBytes = fs.readFileSync(process.argv[3]);
const module = await WebAssembly.compile(wasmBytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("Boundary Process kernel must be import-free");
}

const requiredExports = [
  "memory",
  "boundary_process_kernel_abi_version",
  "boundary_process_kernel_reserve",
  "boundary_process_kernel_input_ptr",
  "boundary_process_kernel_input_capacity",
  "boundary_process_kernel_execute",
  "boundary_process_kernel_output_ptr",
  "boundary_process_kernel_output_len",
  "boundary_process_kernel_error_ptr",
  "boundary_process_kernel_error_len",
];

let cursor = 0;
const count = vectorBytes.readUInt32LE(cursor);
cursor += 4;
let comparisons = 0;
for (let index = 0; index < count; index += 1) {
  const inputLength = vectorBytes.readUInt32LE(cursor);
  const expectedLength = vectorBytes.readUInt32LE(cursor + 4);
  cursor += 8;
  const input = vectorBytes.subarray(cursor, cursor + inputLength);
  cursor += inputLength;
  const expected = vectorBytes.subarray(cursor, cursor + expectedLength);
  cursor += expectedLength;

  // Every finite reduction deliberately receives a fresh instance.
  const instance = await WebAssembly.instantiate(module, {});
  for (const name of requiredExports) {
    if (!(name in instance.exports)) throw new Error("missing export " + name);
  }
  if (instance.exports.boundary_process_kernel_abi_version() !== 1) {
    throw new Error("unexpected Process kernel ABI");
  }
  if (instance.exports.boundary_process_kernel_reserve(input.length) !== 1) {
    throw new Error("conformance input was not admitted");
  }
  const memory = new Uint8Array(instance.exports.memory.buffer);
  const inputPtr = instance.exports.boundary_process_kernel_input_ptr();
  memory.set(input, inputPtr);
  const status = instance.exports.boundary_process_kernel_execute(input.length);
  if (status !== 0) {
    const errorPtr = instance.exports.boundary_process_kernel_error_ptr();
    const errorLength = instance.exports.boundary_process_kernel_error_len();
    const message = Buffer.from(
      memory.subarray(errorPtr, errorPtr + errorLength),
    ).toString("utf8");
    throw new Error("Process kernel rejected vector " + index + ": " + message);
  }
  const outputPtr = instance.exports.boundary_process_kernel_output_ptr();
  const outputLength = instance.exports.boundary_process_kernel_output_len();
  const actual = Buffer.from(memory.subarray(outputPtr, outputPtr + outputLength));
  if (!actual.equals(expected)) {
    throw new Error("native/WASM Process mismatch at vector " + index);
  }
  comparisons += 1;
}
if (cursor !== vectorBytes.length) throw new Error("trailing Process vectors");

const malformedInstance = await WebAssembly.instantiate(module, {});
const malformed = Buffer.alloc(28);
malformed.write("ABL_PKI1", 0, "ascii");
malformed.writeUInt16LE(1, 8);
malformed.writeUInt32LE(1, 24);
const malformedMemory = new Uint8Array(malformedInstance.exports.memory.buffer);
malformedMemory.set(
  malformed,
  malformedInstance.exports.boundary_process_kernel_input_ptr(),
);
if (malformedInstance.exports.boundary_process_kernel_execute(malformed.length) === 0) {
  throw new Error("malformed Process input was accepted");
}

process.stdout.write(JSON.stringify({
  format: "boundary-process-kernel-wasm-proof/v1",
  kernel_sha256: crypto.createHash("sha256").update(wasmBytes).digest("hex"),
  kernel_bytes: wasmBytes.length,
  imports: 0,
  fresh_instances: comparisons,
  byte_identical_native_wasm_outcomes: comparisons,
}) + "\n");
