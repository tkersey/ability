import crypto from "node:crypto";
import fs from "node:fs";
import { spawnSync } from "node:child_process";

const wasmBytes = fs.readFileSync(process.argv[2]);
const expectedKinds = new Set(
  (process.argv[4] ?? "").split(",").filter(Boolean).map(Number),
);
const module = await WebAssembly.compile(wasmBytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("Boundary Process kernel must be import-free");
}
const vectorBytes = process.argv[5] === "native"
  ? nativeVector(module, process.argv[3])
  : fs.readFileSync(process.argv[3]);

const requiredExports = [
  "memory",
  "boundary_process_kernel_abi_version",
  "boundary_process_kernel_reserve",
  "boundary_process_kernel_input_ptr",
  "boundary_process_kernel_input_capacity",
  "boundary_process_kernel_input_payload_ptr",
  "boundary_process_kernel_occupied_memory_bytes",
  "boundary_process_kernel_prepare_input",
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
const observedKinds = new Set();
let emptyResultInput = null;
for (let index = 0; index < count; index += 1) {
  const inputLength = vectorBytes.readUInt32LE(cursor);
  const expectedLength = vectorBytes.readUInt32LE(cursor + 4);
  cursor += 8;
  const input = vectorBytes.subarray(cursor, cursor + inputLength);
  cursor += inputLength;
  const expected = vectorBytes.subarray(cursor, cursor + expectedLength);
  cursor += expectedLength;
  observedKinds.add(expected[10]);
  if (input[10] === 1 && input[11] === 0 && emptyResultInput === null) {
    emptyResultInput = Buffer.from(input);
  }

  // Every finite reduction deliberately receives a fresh instance.
  const instance = await WebAssembly.instantiate(module, {});
  for (const name of requiredExports) {
    if (!(name in instance.exports)) throw new Error("missing export " + name);
  }
  if (instance.exports.boundary_process_kernel_abi_version() !== 1) {
    throw new Error("unexpected Process kernel ABI");
  }
  if (instance.exports.boundary_process_kernel_reserve(BigInt(input.length)) !== 1) {
    throw new Error("conformance input was not admitted");
  }
  const memory = new Uint8Array(instance.exports.memory.buffer);
  const inputPtr = instance.exports.boundary_process_kernel_input_ptr() >>> 0;
  memory.set(input, inputPtr);
  const status = instance.exports.boundary_process_kernel_execute(input.length);
  if (status !== 0) {
    const errorPtr = instance.exports.boundary_process_kernel_error_ptr() >>> 0;
    const errorLength = instance.exports.boundary_process_kernel_error_len();
    const message = Buffer.from(
      memory.subarray(errorPtr, errorPtr + errorLength),
    ).toString("utf8");
    throw new Error("Process kernel rejected vector " + index + ": " + message);
  }
  const outputPtr = instance.exports.boundary_process_kernel_output_ptr() >>> 0;
  const outputLength = Number(instance.exports.boundary_process_kernel_output_len());
  const actual = Buffer.from(memory.subarray(outputPtr, outputPtr + outputLength));
  if (!actual.equals(expected)) {
    throw new Error("native/WASM Process mismatch at vector " + index);
  }
  if (actual[10] === 5) {
    const actualMemoryPages = memory.buffer.byteLength / 65536;
    const reportedMinimumPages = Number(actual.readBigUInt64LE(56));
    if (reportedMinimumPages < actualMemoryPages) {
      throw new Error("NeedsCapacity under-reported live WASM pages");
    }
  }
  comparisons += 1;
}
if (cursor !== vectorBytes.length) throw new Error("trailing Process vectors");
if (observedKinds.size !== expectedKinds.size ||
    [...observedKinds].some((kind) => !expectedKinds.has(kind))) {
  throw new Error("Process outcome-kind coverage mismatch");
}
if (emptyResultInput !== null) {
  emptyResultInput[11] = 1;
  const emptyResultInstance = await WebAssembly.instantiate(module, {});
  const emptyResultMemory = new Uint8Array(
    emptyResultInstance.exports.memory.buffer,
  );
  emptyResultMemory.set(
    emptyResultInput,
    emptyResultInstance.exports.boundary_process_kernel_input_ptr() >>> 0,
  );
  if (emptyResultInstance.exports.boundary_process_kernel_execute(
    emptyResultInput.length,
  ) === 0) {
    throw new Error("present-but-empty EffectResult was accepted");
  }
}

const oversizedInstance = await WebAssembly.instantiate(module, {});
const oversizedCapacity =
  oversizedInstance.exports.boundary_process_kernel_input_capacity();
if (oversizedInstance.exports.boundary_process_kernel_prepare_input(
  0,
  BigInt(oversizedCapacity),
  1n,
  0,
  0n,
) !== 0) {
  throw new Error("oversized Process input was admitted");
}
const oversizedMemory = new Uint8Array(oversizedInstance.exports.memory.buffer);
const oversizedOutputPtr =
  oversizedInstance.exports.boundary_process_kernel_output_ptr() >>> 0;
const oversizedOutputLength = Number(
  oversizedInstance.exports.boundary_process_kernel_output_len(),
);
const oversizedOutput = Buffer.from(oversizedMemory.subarray(
  oversizedOutputPtr,
  oversizedOutputPtr + oversizedOutputLength,
));
if (oversizedOutput[10] !== 5 ||
    oversizedOutput.readBigUInt64LE(32) !== BigInt(oversizedCapacity + 41)) {
  throw new Error("oversized Process input did not return typed NeedsCapacity");
}

const wideInstance = await WebAssembly.instantiate(module, {});
const wideLength = 0x1_0000_0000n;
if (wideInstance.exports.boundary_process_kernel_prepare_input(
  0,
  0n,
  wideLength,
  0,
  0n,
) !== 0) {
  throw new Error("physically unaddressable Process input was admitted");
}
const wideMemory = new Uint8Array(wideInstance.exports.memory.buffer);
const wideOutputPtr =
  wideInstance.exports.boundary_process_kernel_output_ptr() >>> 0;
const wideOutputLength = Number(
  wideInstance.exports.boundary_process_kernel_output_len(),
);
const wideOutput = Buffer.from(wideMemory.subarray(
  wideOutputPtr,
  wideOutputPtr + wideOutputLength,
));
if (wideOutput[10] !== 5 ||
    wideOutput.readBigUInt64LE(32) !== wideLength + 40n) {
  throw new Error("wide Process length was truncated before NeedsCapacity");
}

const maximumI64 = 0x7fff_ffff_ffff_ffffn;
const maximumU64 = 0xffff_ffff_ffff_ffffn;
const maximumInstance = await WebAssembly.instantiate(module, {});
if (maximumInstance.exports.boundary_process_kernel_prepare_input(
  0,
  maximumI64,
  maximumI64 - 39n,
  0,
  0n,
) !== 0) {
  throw new Error("maximum representable Process input total was admitted");
}
const maximumMemory = new Uint8Array(maximumInstance.exports.memory.buffer);
const maximumOutputPtr =
  maximumInstance.exports.boundary_process_kernel_output_ptr() >>> 0;
const maximumOutputLength = Number(
  maximumInstance.exports.boundary_process_kernel_output_len(),
);
const maximumOutput = Buffer.from(maximumMemory.subarray(
  maximumOutputPtr,
  maximumOutputPtr + maximumOutputLength,
));
if (maximumOutput[10] !== 5 ||
    maximumOutput.readBigUInt64LE(32) !== maximumU64) {
  throw new Error("maximum Process input total lost exact capacity");
}
const maximumOccupied =
  maximumInstance.exports.boundary_process_kernel_occupied_memory_bytes();
const maximumInputCapacity = BigInt(
  maximumInstance.exports.boundary_process_kernel_input_capacity(),
);
const maximumRequiredPages = (
  maximumOccupied + (maximumU64 + 1n - maximumInputCapacity) + 65535n
) / 65536n;
if (maximumOutput.readBigUInt64LE(56) !== maximumRequiredPages) {
  throw new Error("maximum Process input total lost occupied page demand");
}

const overflowInstance = await WebAssembly.instantiate(module, {});
if (overflowInstance.exports.boundary_process_kernel_prepare_input(
  0,
  maximumI64,
  maximumI64 - 38n,
  0,
  0n,
) !== 0) {
  throw new Error("unrepresentable Process input total was admitted");
}
if (overflowInstance.exports.boundary_process_kernel_output_len() !== 0n) {
  throw new Error("unrepresentable Process input total was made retryable");
}
const overflowMemory = new Uint8Array(overflowInstance.exports.memory.buffer);
const overflowErrorPtr =
  overflowInstance.exports.boundary_process_kernel_error_ptr() >>> 0;
const overflowErrorLength =
  overflowInstance.exports.boundary_process_kernel_error_len();
const overflowError = Buffer.from(overflowMemory.subarray(
  overflowErrorPtr,
  overflowErrorPtr + overflowErrorLength,
)).toString("utf8");
if (overflowError !== "KernelInputLengthOverflow") {
  throw new Error("unrepresentable Process input total was not rejected");
}

const malformedInstance = await WebAssembly.instantiate(module, {});
const malformed = Buffer.alloc(40);
malformed.write("ABL_PKI1", 0, "ascii");
malformed.writeUInt16LE(1, 8);
malformed.writeUInt32LE(1, 36);
const malformedMemory = new Uint8Array(malformedInstance.exports.memory.buffer);
malformedMemory.set(
  malformed,
  malformedInstance.exports.boundary_process_kernel_input_ptr() >>> 0,
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
  outcome_kinds: [...observedKinds].sort(),
}) + "\n");

function nativeVector(module, executable) {
  const probe = new WebAssembly.Instance(module, {});
  const livePages = probe.exports.memory.buffer.byteLength / 65536;
  const occupiedBytes = probe.exports.boundary_process_kernel_occupied_memory_bytes();
  const result = spawnSync(executable, [
    String(livePages),
    String(occupiedBytes),
  ], { maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0) {
    throw new Error(result.stderr.toString("utf8"));
  }
  return result.stdout;
}
