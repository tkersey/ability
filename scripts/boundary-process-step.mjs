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
const imagePath = required("--image");
const statePath = options.get("--state");
const initialPath = options.get("--initial-args");
if ((statePath === undefined) === (initialPath === undefined)) {
  throw new Error("provide exactly one of --state or --initial-args");
}
const instancePath = statePath ?? initialPath;
const resultPath = options.get("--result");
const opened = [];
try {
  const kernelFile = openPayload(kernelPath, "kernel");
  const imageFile = openPayload(imagePath, "image");
  const instanceFile = openPayload(instancePath, "instance");
  const resultFile = resultPath === undefined
    ? null
    : openPayload(resultPath, "result");
  const module = await WebAssembly.compile(readExact(kernelFile, "kernel"));
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
    imageFile.size,
    instanceFile.size,
    resultFile === null ? 0 : 1,
    resultFile?.size ?? 0n,
  );
  if (inputLength === 0) {
    const capacity = kernelOutput(exports, memory);
    if (capacity.length === 0) {
      throw new Error("kernel cannot prepare the Process input");
    }
    process.stdout.write(capacity);
  } else {
    const image = readExact(imageFile, "image");
    const instance = readExact(instanceFile, "instance");
    const result = resultFile === null
      ? Buffer.alloc(0)
      : readExact(resultFile, "result");
    let payload = wasmOffset(
      exports.boundary_process_kernel_input_payload_ptr(),
    );
    memory.set(image, payload);
    payload += image.length;
    memory.set(instance, payload);
    payload += instance.length;
    memory.set(result, payload);
    const status = exports.boundary_process_kernel_execute(inputLength);
    if (status !== 0) {
      const start = wasmOffset(exports.boundary_process_kernel_error_ptr());
      const length = exports.boundary_process_kernel_error_len();
      throw new Error(
        Buffer.from(memory.subarray(start, start + length)).toString("utf8"),
      );
    }
    process.stdout.write(kernelOutput(exports, memory));
  }
} finally {
  for (const file of opened) fs.closeSync(file.fd);
}

function kernelOutput(exports, memory) {
  const start = wasmOffset(exports.boundary_process_kernel_output_ptr());
  const length = Number(exports.boundary_process_kernel_output_len());
  return Buffer.from(memory.subarray(start, start + length));
}

function wasmOffset(value) {
  return value >>> 0;
}

function openPayload(path, label) {
  const fd = fs.openSync(path, "r");
  const file = { fd, size: 0n, label };
  opened.push(file);
  const stat = fs.fstatSync(fd, { bigint: true });
  if (!stat.isFile()) throw new Error(label + " must be a regular file");
  file.size = stat.size;
  return file;
}

function readExact(file, label) {
  const length = Number(file.size);
  if (!Number.isSafeInteger(length)) {
    throw new Error(label + " is too large to materialize after preflight");
  }
  const bytes = Buffer.alloc(length);
  let offset = 0;
  while (offset < length) {
    const consumed = fs.readSync(
      file.fd,
      bytes,
      offset,
      length - offset,
      offset,
    );
    if (consumed === 0) throw new Error(label + " changed after preflight");
    offset += consumed;
  }
  const probe = Buffer.alloc(1);
  if (fs.readSync(file.fd, probe, 0, 1, length) !== 0 ||
      fs.fstatSync(file.fd, { bigint: true }).size !== file.size) {
    throw new Error(label + " changed after preflight");
  }
  return bytes;
}

function required(name) {
  const value = options.get(name);
  if (value === undefined) throw new Error("missing " + name);
  return value;
}
