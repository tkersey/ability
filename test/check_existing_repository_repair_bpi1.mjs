import crypto from "node:crypto";
import fs from "node:fs";

const expectedImageSha256 =
  "7440076a8078220d9d4000b871423d981bbbee19aedba499afaa4a86239fe6a6";
const expectedInitialArgsSha256 =
  "0b9e37f5ae18c387a8d7b02c4571f0ee76c6c1836795b02dcd3acf67254d4dfc";
const kernelBytes = fs.readFileSync(process.argv[2]);
const image = decodeFrozen(process.argv[3]);
const initialArgs = decodeFrozen(process.argv[4]);

if (image.length !== 23431 || sha256(image) !== expectedImageSha256) {
  throw new Error("landed repository-repair BPI1 identity changed");
}
if (initialArgs.length !== 288 || sha256(initialArgs) !== expectedInitialArgsSha256) {
  throw new Error("landed repository-repair InitialArgs identity changed");
}

const module = await WebAssembly.compile(kernelBytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("Boundary Process kernel must be import-free");
}

let current = initialArgs;
let currentIsState = false;
let reductions = 0;
let request = null;
for (; reductions < 128; reductions += 1) {
  const input = kernelInput(image, current, currentIsState);
  const instance = await WebAssembly.instantiate(module, {});
  const exports = instance.exports;
  if (exports.boundary_process_kernel_abi_version() !== 1 ||
      exports.boundary_process_kernel_reserve(input.length) !== 1) {
    throw new Error("fixed Process kernel rejected landed BPI1 input");
  }
  const memory = new Uint8Array(exports.memory.buffer);
  memory.set(input, exports.boundary_process_kernel_input_ptr());
  if (exports.boundary_process_kernel_execute(input.length) !== 0) {
    const start = exports.boundary_process_kernel_error_ptr();
    const length = exports.boundary_process_kernel_error_len();
    throw new Error(Buffer.from(memory.subarray(start, start + length)).toString("utf8"));
  }
  const outputStart = exports.boundary_process_kernel_output_ptr();
  const outputLength = exports.boundary_process_kernel_output_len();
  const output = Buffer.from(
    memory.subarray(outputStart, outputStart + outputLength),
  );
  if (output.subarray(0, 8).toString("ascii") !== "ABL_PKO1" ||
      output.readUInt16LE(8) !== 1) {
    throw new Error("malformed Process outcome");
  }
  const kind = output[10];
  const primaryLength = output.readUInt32LE(12);
  const secondaryLength = output.readUInt32LE(16);
  const primary = output.subarray(24, 24 + primaryLength);
  const secondary = output.subarray(
    24 + primaryLength,
    24 + primaryLength + secondaryLength,
  );
  if (24 + primaryLength + secondaryLength !== output.length) {
    throw new Error("trailing Process outcome bytes");
  }
  if (kind === 0) {
    if (primary.subarray(0, 8).toString("ascii") !== "ABL_PST1" ||
        secondary.length !== 0) {
      throw new Error("progressed outcome did not carry canonical Process State");
    }
    current = Buffer.from(primary);
    currentIsState = true;
    continue;
  }
  if (kind === 1) {
    if (primary.subarray(0, 8).toString("ascii") !== "ABL_PST1" ||
        secondary.subarray(0, 8).toString("ascii") !== "ABL_ERQ1") {
      throw new Error("landed BPI1 did not suspend as a Process request");
    }
    request = Buffer.from(secondary);
    break;
  }
  throw new Error("landed BPI1 reached unexpected outcome kind " + kind);
}
if (request === null) throw new Error("landed BPI1 did not reach its first effect");

process.stdout.write(JSON.stringify({
  format: "boundary-existing-bpi1-process-proof/v1",
  image_sha256: expectedImageSha256,
  image_bytes: image.length,
  initial_args_sha256: expectedInitialArgsSha256,
  reductions: reductions + 1,
  fresh_instances: reductions + 1,
  request_sha256: sha256(request),
  machine_v2_profile: false,
}) + "\n");

function decodeFrozen(path) {
  return Buffer.from(fs.readFileSync(path, "utf8").replaceAll(/\s/g, ""), "base64");
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function kernelInput(program, instance, isState) {
  const input = Buffer.alloc(28 + program.length + instance.length);
  input.write("ABL_PKI1", 0, "ascii");
  input.writeUInt16LE(1, 8);
  input.writeUInt8(isState ? 1 : 0, 10);
  input.writeUInt8(0, 11);
  input.writeUInt32LE(program.length, 12);
  input.writeUInt32LE(instance.length, 16);
  input.writeUInt32LE(0, 20);
  program.copy(input, 28);
  instance.copy(input, 28 + program.length);
  return input;
}
