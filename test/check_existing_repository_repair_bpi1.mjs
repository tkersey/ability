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
  const instance = await WebAssembly.instantiate(module, {});
  const exports = instance.exports;
  const inputLength = exports.boundary_process_kernel_prepare_input(
    currentIsState ? 1 : 0,
    BigInt(image.length),
    BigInt(current.length),
    0,
    0n,
  );
  if (exports.boundary_process_kernel_abi_version() !== 1 ||
      inputLength === 0) {
    throw new Error("fixed Process kernel rejected landed BPI1 input");
  }
  const memory = new Uint8Array(exports.memory.buffer);
  let payload = exports.boundary_process_kernel_input_payload_ptr();
  memory.set(image, payload);
  payload += image.length;
  memory.set(current, payload);
  if (exports.boundary_process_kernel_execute(inputLength) !== 0) {
    const start = exports.boundary_process_kernel_error_ptr();
    const length = exports.boundary_process_kernel_error_len();
    throw new Error(Buffer.from(memory.subarray(start, start + length)).toString("utf8"));
  }
  const outputStart = exports.boundary_process_kernel_output_ptr();
  const outputLength = Number(exports.boundary_process_kernel_output_len());
  const output = Buffer.from(
    memory.subarray(outputStart, outputStart + outputLength),
  );
  if (output.subarray(0, 8).toString("ascii") !== "ABL_PKO1" ||
      output.readUInt16LE(8) !== 1) {
    throw new Error("malformed Process outcome");
  }
  const kind = output[10];
  const primaryLength = Number(output.readBigUInt64LE(12));
  const secondaryLength = Number(output.readBigUInt64LE(20));
  const primary = output.subarray(32, 32 + primaryLength);
  const secondary = output.subarray(
    32 + primaryLength,
    32 + primaryLength + secondaryLength,
  );
  if (32 + primaryLength + secondaryLength !== output.length) {
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
