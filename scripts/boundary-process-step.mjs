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
const memory = new Uint8Array(exports.memory.buffer);
const inputLength = exports.boundary_process_kernel_prepare_input(
  statePath === undefined ? 0 : 1,
  image.length,
  instance.length,
  options.has("--result") ? 1 : 0,
  result.length,
);
if (inputLength === 0) {
  const capacity = kernelOutput();
  if (capacity.length === 0) {
    throw new Error("kernel cannot prepare the Process input");
  }
  process.stdout.write(capacity);
} else {
  let payload = exports.boundary_process_kernel_input_payload_ptr();
  memory.set(image, payload);
  payload += image.length;
  memory.set(instance, payload);
  payload += instance.length;
  memory.set(result, payload);
  const status = exports.boundary_process_kernel_execute(inputLength);
  if (status !== 0) {
    const start = exports.boundary_process_kernel_error_ptr();
    const length = exports.boundary_process_kernel_error_len();
    throw new Error(
      Buffer.from(memory.subarray(start, start + length)).toString("utf8"),
    );
  }
  process.stdout.write(kernelOutput());
}

function kernelOutput() {
  const start = exports.boundary_process_kernel_output_ptr();
  const length = exports.boundary_process_kernel_output_len();
  return Buffer.from(memory.subarray(start, start + length));
}

function required(name) {
  const value = options.get(name);
  if (value === undefined) throw new Error("missing " + name);
  return value;
}
