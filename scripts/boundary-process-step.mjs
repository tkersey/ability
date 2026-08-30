#!/usr/bin/env node
import fs from "node:fs";

const maximumKernelBytes = 64n * 1024n * 1024n;

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
  const kernelFile = openPayload(kernelPath, "kernel", maximumKernelBytes);
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
  const inputLength = exports.boundary_process_kernel_prepare_input(
    statePath === undefined ? 0 : 1,
    imageFile.generation.size,
    instanceFile.generation.size,
    resultFile === null ? 0 : 1,
    resultFile?.generation.size ?? 0n,
  );
  if (inputLength === 0) {
    verifyGenerations([imageFile, instanceFile, resultFile]);
    const capacity = kernelOutput(exports);
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
    const memory = new Uint8Array(exports.memory.buffer);
    memory.set(image, payload);
    payload += image.length;
    memory.set(instance, payload);
    payload += instance.length;
    memory.set(result, payload);
    const status = exports.boundary_process_kernel_execute(inputLength);
    if (status !== 0) {
      throw new Error(kernelError(exports).toString("utf8"));
    }
    process.stdout.write(kernelOutput(exports));
  }
} finally {
  for (const file of opened) fs.closeSync(file.fd);
}

function kernelOutput(exports) {
  return kernelBytes(
    exports,
    exports.boundary_process_kernel_output_ptr(),
    exports.boundary_process_kernel_output_len(),
    "kernel output",
  );
}

function kernelError(exports) {
  return kernelBytes(
    exports,
    exports.boundary_process_kernel_error_ptr(),
    exports.boundary_process_kernel_error_len(),
    "kernel error",
  );
}

function kernelBytes(exports, pointerValue, lengthValue, label) {
  const start = wasmOffset(pointerValue);
  const length = wasmLength(lengthValue, label);
  const memory = new Uint8Array(exports.memory.buffer);
  if (start > memory.length) {
    throw new Error(label + " pointer is outside exported memory");
  }
  if (length > memory.length - start) {
    throw new Error(label + " range is outside exported memory");
  }
  return Buffer.from(memory.subarray(start, start + length));
}

function wasmLength(value, label) {
  if (typeof value === "bigint") {
    if (value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error(label + " length is not an exact safe integer");
    }
    return Number(value);
  }
  if (!Number.isInteger(value)) {
    throw new Error(label + " length is not an exact safe integer");
  }
  const unsigned = value >>> 0;
  if (value !== unsigned && value !== (unsigned | 0)) {
    throw new Error(label + " length is not an exact safe integer");
  }
  return unsigned;
}

function wasmOffset(value) {
  return value >>> 0;
}

function openPayload(path, label, maximumBytes = null) {
  const fd = fs.openSync(
    path,
    fs.constants.O_RDONLY | fs.constants.O_NONBLOCK,
  );
  const file = { fd, generation: null, label };
  opened.push(file);
  const stat = fs.fstatSync(fd, { bigint: true });
  if (!stat.isFile()) throw new Error(label + " must be a regular file");
  file.generation = generation(stat);
  if (maximumBytes !== null && file.generation.size > maximumBytes) {
    throw new Error(label + " exceeds this relay's operational byte limit");
  }
  return file;
}

function verifyGenerations(files) {
  for (const file of files) {
    if (file !== null) verifyGeneration(file);
  }
}

function readExact(file, label) {
  verifyGeneration(file);
  const length = Number(file.generation.size);
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
  if (fs.readSync(file.fd, probe, 0, 1, length) !== 0) {
    throw new Error(label + " changed after preflight");
  }
  verifyGeneration(file);
  return bytes;
}

function verifyGeneration(file) {
  const current = generation(fs.fstatSync(file.fd, { bigint: true }));
  if (Object.keys(current).some(
    (key) => current[key] !== file.generation[key],
  )) {
    throw new Error(file.label + " changed after preflight");
  }
}

function generation(stat) {
  return {
    dev: stat.dev,
    ino: stat.ino,
    size: stat.size,
    mtimeNs: stat.mtimeNs,
    ctimeNs: stat.ctimeNs,
  };
}

function required(name) {
  const value = options.get(name);
  if (value === undefined) throw new Error("missing " + name);
  return value;
}
