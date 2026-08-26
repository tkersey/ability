#!/usr/bin/env node
import fs from "node:fs";

const options = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  const name = process.argv[index];
  const value = process.argv[index + 1];
  if (!name?.startsWith("--") || value === undefined) {
    throw new Error("expected --name value arguments");
  }
  options.set(name, value);
}

const kernelPath = required("--kernel");
const image = fs.readFileSync(required("--image"));
const statePath = options.get("--state");
const initialPath = options.get("--initial-args");
if ((statePath === undefined) === (initialPath === undefined)) {
  throw new Error("provide exactly one of --state or --initial-args");
}
const instance = fs.readFileSync(statePath ?? initialPath);
const result = options.has("--result")
  ? fs.readFileSync(options.get("--result"))
  : Buffer.alloc(0);
const input = Buffer.alloc(28 + image.length + instance.length + result.length);
input.write("ABL_PKI1", 0, "ascii");
input.writeUInt16LE(1, 8);
input.writeUInt8(statePath === undefined ? 0 : 1, 10);
input.writeUInt8(options.has("--result") ? 1 : 0, 11);
input.writeUInt32LE(image.length, 12);
input.writeUInt32LE(instance.length, 16);
input.writeUInt32LE(result.length, 20);
image.copy(input, 28);
instance.copy(input, 28 + image.length);
result.copy(input, 28 + image.length + instance.length);

const module = await WebAssembly.compile(fs.readFileSync(kernelPath));
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("Boundary Process kernel must be import-free");
}
const instanceWasm = await WebAssembly.instantiate(module, {});
const exports = instanceWasm.exports;
if (typeof exports.boundary_process_kernel_abi_version !== "function" ||
    exports.boundary_process_kernel_abi_version() !== 1) {
  throw new Error("unsupported Boundary Process kernel ABI");
}
if (exports.boundary_process_kernel_reserve(input.length) !== 1) {
  throw new Error("kernel cannot reserve the required operational input capacity");
}
const memory = new Uint8Array(exports.memory.buffer);
memory.set(input, exports.boundary_process_kernel_input_ptr());
const status = exports.boundary_process_kernel_execute(input.length);
if (status !== 0) {
  const start = exports.boundary_process_kernel_error_ptr();
  const length = exports.boundary_process_kernel_error_len();
  throw new Error(
    Buffer.from(memory.subarray(start, start + length)).toString("utf8"),
  );
}
const outputStart = exports.boundary_process_kernel_output_ptr();
const outputLength = exports.boundary_process_kernel_output_len();
process.stdout.write(
  Buffer.from(memory.subarray(outputStart, outputStart + outputLength)),
);

function required(name) {
  const value = options.get(name);
  if (value === undefined) throw new Error("missing " + name);
  return value;
}
