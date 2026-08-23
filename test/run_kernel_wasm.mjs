import fs from "node:fs";
import crypto from "node:crypto";

const bytes = fs.readFileSync(process.argv[2]);
const vectors = process.argv.slice(3).map((path) => fs.readFileSync(path));
if (bytes.length > 2 * 1024 * 1024) throw new Error("kernel WASM exceeds 2 MiB");
const module = await WebAssembly.compile(bytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("kernel WASM must have zero imports");
}
const instance = await WebAssembly.instantiate(module, {});
let transitionComparisonCount = 0;
const expected = [
  "memory",
  "boundary_machine_v2_kernel_abi_version",
  "boundary_machine_v2_kernel_input_ptr",
  "boundary_machine_v2_kernel_input_capacity",
  "boundary_machine_v2_kernel_execute",
  "boundary_machine_v2_kernel_output_ptr",
  "boundary_machine_v2_kernel_output_len",
  "boundary_machine_v2_kernel_error_ptr",
  "boundary_machine_v2_kernel_error_len",
  "boundary_machine_v2_kernel_reset",
];
for (const name of expected) {
  if (!(name in instance.exports)) throw new Error(`missing export ${name}`);
}
if (instance.exports.boundary_machine_v2_kernel_abi_version() !== 1) {
  throw new Error("unexpected kernel ABI");
}
if (instance.exports.boundary_machine_v2_kernel_input_capacity() < 24 * 1024 * 1024) {
  throw new Error("kernel input profile is undersized");
}
if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
if (instance.exports.boundary_machine_v2_kernel_execute(24 * 1024 * 1024 + 1) !== 1) {
  throw new Error("oversized kernel input was accepted");
}
const memory = new Uint8Array(instance.exports.memory.buffer);
const inputPtr = instance.exports.boundary_machine_v2_kernel_input_ptr();
for (const [name, imageSize, profileSize, stateSize, auxiliarySize] of [
  ["image", 16 * 1024 * 1024 + 1, 0, 0, 0],
  ["profile", 0, 1 * 1024 * 1024 + 1, 0, 0],
  ["state", 0, 0, 4 * 1024 * 1024 + 1, 0],
  ["auxiliary", 0, 0, 0, 2 * 1024 * 1024 + 1],
]) {
  const oversized = Buffer.alloc(48 + imageSize + profileSize + stateSize + auxiliarySize);
  oversized.write("ABL_KIN1", 0, "ascii");
  oversized.writeUInt16LE(1, 8);
  oversized.writeUInt16LE(0, 10);
  oversized.writeUInt32LE(imageSize, 24);
  oversized.writeUInt32LE(profileSize, 28);
  oversized.writeUInt32LE(stateSize, 32);
  oversized.writeUInt32LE(auxiliarySize, 36);
  memory.set(oversized, inputPtr);
  if (instance.exports.boundary_machine_v2_kernel_execute(oversized.length) !== 6) {
    throw new Error(`oversized ${name} component was accepted`);
  }
  if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
}
const vector = vectors[0];
const inputLength = vector.readUInt32LE(0);
const expectedLength = vector.readUInt32LE(4);
const input = vector.subarray(8, 8 + inputLength);
const expectedOutput = vector.subarray(8 + inputLength, 8 + inputLength + expectedLength);
const imageLength = input.readUInt32LE(24);
const profileLength = input.readUInt32LE(28);
const profileStart = 48 + imageLength;
const wrapped = Buffer.from(input.subarray(0, 48 + imageLength + profileLength));
wrapped.writeUInt16LE(0, 10);
wrapped.writeUInt32LE(0xffffffff, 32);
wrapped.writeUInt32LE(1, 36);
memory.set(wrapped, inputPtr);
if (instance.exports.boundary_machine_v2_kernel_execute(wrapped.length) !== 6) {
  throw new Error("wrapped aggregate input lengths were accepted");
}
if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
const oversizedProfile = Buffer.from(input.subarray(0, 48 + imageLength + profileLength));
oversizedProfile.writeUInt16LE(0, 10);
oversizedProfile.writeUInt32LE(0, 32);
oversizedProfile.writeUInt32LE(0, 36);
const profile = oversizedProfile.subarray(profileStart, profileStart + profileLength);
profile.writeUInt32LE(4 * 1024 * 1024 + 1, 132);
const semanticDigest = profile.subarray(64, 96);
const contract = crypto.createHash("sha256");
contract.update(semanticDigest);
contract.update("\0boundary-machine-abi=2");
contract.update("\0state=rnf-v1");
contract.update(`\0frames=${profile.readUInt32LE(128)}`);
contract.update(`\0state-bytes=${profile.readUInt32LE(132)}`);
contract.update(`\0fuel=${profile.readBigUInt64LE(136)}`);
contract.digest().copy(profile, 96);
memory.set(oversizedProfile, inputPtr);
if (instance.exports.boundary_machine_v2_kernel_execute(oversizedProfile.length) !== 6) {
  throw new Error("unexecutable Machine v2 profile capacity was accepted");
}
if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
const maximumResume = Buffer.alloc(48 + imageLength + profileLength + 184 + 2 * 1024 * 1024);
maximumResume.write("ABL_KIN1", 0, "ascii");
maximumResume.writeUInt16LE(1, 8);
maximumResume.writeUInt16LE(5, 10);
maximumResume.writeUInt32LE(imageLength, 24);
maximumResume.writeUInt32LE(profileLength, 28);
maximumResume.writeUInt32LE(0, 32);
maximumResume.writeUInt32LE(184 + 2 * 1024 * 1024, 36);
input.copy(maximumResume, 48, 48, 48 + imageLength + profileLength);
const resumeAuxiliary = 48 + imageLength + profileLength;
maximumResume.writeUInt32LE(2 * 1024 * 1024, resumeAuxiliary + 176);
memory.set(maximumResume, inputPtr);
if (instance.exports.boundary_machine_v2_kernel_execute(maximumResume.length) !== 3) {
  throw new Error("maximum response plus resume metadata was rejected at admission");
}
if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
const sectionOffset = (image, kind) => Number(image.readBigUInt64LE(76 + (kind - 1) * 24 + 8));
for (const [name, mutate] of [
  ["total length", (image) => image.writeBigUInt64LE(image.readBigUInt64LE(24) + 1n, 24)],
  ["functions", (image) => image.writeUInt32LE(0x20000000, sectionOffset(image, 7))],
  ["transitions", (image) => image.writeUInt32LE(0x20000000, sectionOffset(image, 10))],
  ["effect identity tail", (image) => {
    const offset = sectionOffset(image, 5);
    image.writeUInt32LE(image.length - offset, offset + 8);
  }],
]) {
  const malformed = Buffer.from(input.subarray(0, 48 + imageLength + profileLength));
  malformed.writeUInt16LE(0, 10);
  malformed.writeUInt32LE(0, 32);
  malformed.writeUInt32LE(0, 36);
  mutate(malformed.subarray(48, 48 + imageLength));
  memory.set(malformed, inputPtr);
  if (instance.exports.boundary_machine_v2_kernel_execute(malformed.length) !== 2) {
    throw new Error(`malformed ${name} catalog was accepted`);
  }
  if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
}
for (const [command, stateSize, auxiliarySize] of [
  [0, 1, 0],
  [0, 0, 1],
  [1, 1, 0],
  [2, 0, 1],
  [3, 0, 1],
  [4, 0, 1],
]) {
  const ignored = Buffer.alloc(48 + imageLength + profileLength + stateSize + auxiliarySize);
  ignored.write("ABL_KIN1", 0, "ascii");
  ignored.writeUInt16LE(1, 8);
  ignored.writeUInt16LE(command, 10);
  ignored.writeUInt32LE(imageLength, 24);
  ignored.writeUInt32LE(profileLength, 28);
  ignored.writeUInt32LE(stateSize, 32);
  ignored.writeUInt32LE(auxiliarySize, 36);
  input.copy(ignored, 48, 48, 48 + imageLength + profileLength);
  memory.set(ignored, inputPtr);
  if (instance.exports.boundary_machine_v2_kernel_execute(ignored.length) !== 1) {
    throw new Error(`command ${command} accepted ignored State or auxiliary bytes`);
  }
  if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) {
    throw new Error("reset failed");
  }
}
const unboundCost = Buffer.from(input.subarray(0, 48 + imageLength + profileLength));
unboundCost.writeUInt16LE(0, 10);
unboundCost.writeUInt32LE(0, 32);
unboundCost.writeUInt32LE(0, 36);
const costOffset = profileStart + 192;
unboundCost.writeBigUInt64LE(unboundCost.readBigUInt64LE(costOffset) + 1n, costOffset);
memory.set(unboundCost, inputPtr);
const unboundCostResult = instance.exports.boundary_machine_v2_kernel_execute(unboundCost.length);
if (unboundCostResult !== 2) {
  throw new Error(`unbound Machine v2 segment cost disposition ${unboundCostResult}`);
}
if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
memory.set(input, inputPtr);
if (instance.exports.boundary_machine_v2_kernel_execute(input.length) !== 0) {
  throw new Error("kernel semantic vector failed");
}
const outputPtr = instance.exports.boundary_machine_v2_kernel_output_ptr();
const outputLength = instance.exports.boundary_machine_v2_kernel_output_len();
const actualOutput = memory.slice(outputPtr, outputPtr + outputLength);
if (!Buffer.from(actualOutput).equals(expectedOutput)) {
  throw new Error("native/WASM kernel output mismatch");
}
transitionComparisonCount += 1;
for (const semanticVector of vectors.slice(1)) {
  if (instance.exports.boundary_machine_v2_kernel_reset() !== 0) throw new Error("reset failed");
  const semanticInputLength = semanticVector.readUInt32LE(0);
  const semanticExpectedLength = semanticVector.readUInt32LE(4);
  const semanticInput = semanticVector.subarray(8, 8 + semanticInputLength);
  const semanticExpected = semanticVector.subarray(
    8 + semanticInputLength,
    8 + semanticInputLength + semanticExpectedLength,
  );
  memory.set(semanticInput, inputPtr);
  if (instance.exports.boundary_machine_v2_kernel_execute(semanticInput.length) !== 0) {
    throw new Error("kernel semantic failure vector failed");
  }
  const semanticOutput = memory.slice(
    outputPtr,
    outputPtr + instance.exports.boundary_machine_v2_kernel_output_len(),
  );
  if (!Buffer.from(semanticOutput).equals(semanticExpected)) {
    throw new Error("native/WASM Machine failure mismatch");
  }
  transitionComparisonCount += 1;
}
process.stdout.write(`${JSON.stringify({
  format: "boundary-machine-v2-kernel-wasm-proof/v1",
  kernel_wasm_bytes: bytes.length,
  import_count: WebAssembly.Module.imports(module).length,
  abi: instance.exports.boundary_machine_v2_kernel_abi_version(),
  transition_comparison_count: transitionComparisonCount,
})}\n`);
