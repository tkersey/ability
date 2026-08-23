import fs from "node:fs";

const bytes = fs.readFileSync(process.argv[2]);
const vectors = process.argv.slice(3).map((path) => fs.readFileSync(path));
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
const memory = new Uint8Array(instance.exports.memory.buffer);
const inputPtr = instance.exports.boundary_kernel_input_ptr();
for (const [name, imageSize, stateSize, auxiliarySize] of [
  ["image", 16 * 1024 * 1024 + 1, 0, 0],
  ["state", 0, 4 * 1024 * 1024 + 1, 0],
  ["auxiliary", 0, 0, 2 * 1024 * 1024 + 1],
]) {
  const oversized = Buffer.alloc(40 + imageSize + stateSize + auxiliarySize);
  oversized.write("ABL_KIN1", 0, "ascii");
  oversized.writeUInt16LE(1, 8);
  oversized.writeUInt16LE(0, 10);
  oversized.writeUInt32LE(imageSize, 24);
  oversized.writeUInt32LE(stateSize, 28);
  oversized.writeUInt32LE(auxiliarySize, 32);
  memory.set(oversized, inputPtr);
  if (instance.exports.boundary_kernel_execute(oversized.length) !== 6) {
    throw new Error(`oversized ${name} component was accepted`);
  }
  if (instance.exports.boundary_kernel_reset() !== 0) throw new Error("reset failed");
}
const vector = vectors[0];
const inputLength = vector.readUInt32LE(0);
const expectedLength = vector.readUInt32LE(4);
const input = vector.subarray(8, 8 + inputLength);
const expectedOutput = vector.subarray(8 + inputLength, 8 + inputLength + expectedLength);
const imageLength = input.readUInt32LE(24);
const wrapped = Buffer.from(input.subarray(0, 40 + imageLength));
wrapped.writeUInt16LE(0, 10);
wrapped.writeUInt32LE(0xffffffff, 28);
wrapped.writeUInt32LE(1, 32);
memory.set(wrapped, inputPtr);
if (instance.exports.boundary_kernel_execute(wrapped.length) !== 6) {
  throw new Error("wrapped aggregate input lengths were accepted");
}
if (instance.exports.boundary_kernel_reset() !== 0) throw new Error("reset failed");
const sectionOffset = (image, kind) => Number(image.readBigUInt64LE(144 + (kind - 1) * 24 + 8));
for (const [name, mutate] of [
  ["functions", (image) => image.writeUInt32LE(0x20000000, sectionOffset(image, 7))],
  ["transitions", (image) => image.writeUInt32LE(0x20000000, sectionOffset(image, 10))],
  ["effect identity tail", (image) => {
    const offset = sectionOffset(image, 5);
    image.writeUInt32LE(image.length - offset, offset + 8);
  }],
]) {
  const malformed = Buffer.from(input.subarray(0, 40 + imageLength));
  malformed.writeUInt16LE(0, 10);
  malformed.writeUInt32LE(0, 28);
  malformed.writeUInt32LE(0, 32);
  mutate(malformed.subarray(40));
  memory.set(malformed, inputPtr);
  if (instance.exports.boundary_kernel_execute(malformed.length) !== 2) {
    throw new Error(`malformed ${name} catalog was accepted`);
  }
  if (instance.exports.boundary_kernel_reset() !== 0) throw new Error("reset failed");
}
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
for (const semanticVector of vectors.slice(1)) {
  if (instance.exports.boundary_kernel_reset() !== 0) throw new Error("reset failed");
  const semanticInputLength = semanticVector.readUInt32LE(0);
  const semanticExpectedLength = semanticVector.readUInt32LE(4);
  const semanticInput = semanticVector.subarray(8, 8 + semanticInputLength);
  const semanticExpected = semanticVector.subarray(
    8 + semanticInputLength,
    8 + semanticInputLength + semanticExpectedLength,
  );
  memory.set(semanticInput, inputPtr);
  if (instance.exports.boundary_kernel_execute(semanticInput.length) !== 0) {
    throw new Error("kernel semantic failure vector failed");
  }
  const semanticOutput = memory.slice(
    outputPtr,
    outputPtr + instance.exports.boundary_kernel_output_len(),
  );
  if (!Buffer.from(semanticOutput).equals(semanticExpected)) {
    throw new Error("native/WASM Machine failure mismatch");
  }
}
process.stdout.write(`kernel_wasm_bytes=${bytes.length} imports=0 abi=1\n`);
