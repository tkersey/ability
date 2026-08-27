import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const kernel = process.argv[2];
const vectorSource = process.argv[3];
const adapter = process.argv[4];
const wrongKernel = process.argv[5];
const kernelInstance = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(kernel)),
  {},
);
const kernelInputCapacity =
  kernelInstance.exports.boundary_process_kernel_input_capacity();
const vector = process.argv[6] === "native"
  ? nativeVector(kernelInstance, vectorSource)
  : fs.readFileSync(vectorSource);
let cursor = 0;
const vectorCount = vector.readUInt32LE(cursor);
cursor += 4;
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-process-step-"));
try {
  for (let index = 0; index < vectorCount; index += 1) {
    const inputLength = vector.readUInt32LE(cursor);
    const outputLength = vector.readUInt32LE(cursor + 4);
    cursor += 8;
    const input = vector.subarray(cursor, cursor + inputLength);
    cursor += inputLength;
    const expected = vector.subarray(cursor, cursor + outputLength);
    cursor += outputLength;
    const imageLength = Number(input.readBigUInt64LE(12));
    const instanceLength = Number(input.readBigUInt64LE(20));
    const resultLength = Number(input.readBigUInt64LE(28));
    const imagePath = path.join(temporary, "system-" + index + ".bpi1");
    const instancePath = path.join(temporary, "instance-" + index + ".bin");
    const resultPath = path.join(temporary, "result-" + index + ".ers1");
    const imageEnd = 40 + imageLength;
    const instanceEnd = imageEnd + instanceLength;
    fs.writeFileSync(imagePath, input.subarray(40, imageEnd));
    fs.writeFileSync(instancePath, input.subarray(imageEnd, instanceEnd));
    const argumentsList = [
      adapter,
      "--kernel", kernel,
      "--image", imagePath,
      input[10] === 0 ? "--initial-args" : "--state", instancePath,
    ];
    if (resultLength !== 0) {
      fs.writeFileSync(
        resultPath,
        input.subarray(instanceEnd, instanceEnd + resultLength),
      );
      argumentsList.push("--result", resultPath);
    }
    const execution = spawnSync(process.execPath, argumentsList);
    if (execution.status !== 0) {
      throw new Error(execution.stderr.toString("utf8"));
    }
    if (!execution.stdout.equals(expected)) {
      throw new Error(
        "boundary-process-step changed canonical kernel output at vector " +
          index,
      );
    }
    if (input[10] === 1 && resultLength === 0) {
      fs.writeFileSync(resultPath, Buffer.alloc(0));
      const emptyResult = spawnSync(
        process.execPath,
        [...argumentsList, "--result", resultPath],
      );
      if (emptyResult.status === 0) {
        throw new Error("relay accepted a present-but-empty EffectResult");
      }
    }
  }
  const emptyImage = path.join(temporary, "empty.bpi1");
  const emptyInitial = path.join(temporary, "empty.initial");
  fs.writeFileSync(emptyImage, Buffer.alloc(0));
  fs.writeFileSync(emptyInitial, Buffer.alloc(0));
  const oversizedInitial = path.join(temporary, "oversized.initial");
  fs.writeFileSync(oversizedInitial, Buffer.alloc(kernelInputCapacity));
  const oversized = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", emptyImage,
    "--initial-args", oversizedInitial,
  ]);
  if (oversized.status !== 0 ||
      oversized.stdout.subarray(0, 8).toString("ascii") !== "ABL_PKO1" ||
      oversized.stdout[10] !== 5 ||
      oversized.stdout.readBigUInt64LE(32) !==
        BigInt(kernelInputCapacity + 40)) {
    throw new Error("relay did not return NeedsCapacity for oversized input");
  }
  const wideInitial = path.join(temporary, "wide.initial");
  const wideLength = 0x1_0000_0000;
  const wideFile = fs.openSync(wideInitial, "w");
  try {
    fs.ftruncateSync(wideFile, wideLength);
  } finally {
    fs.closeSync(wideFile);
  }
  const wide = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", emptyImage,
    "--initial-args", wideInitial,
  ]);
  if (wide.status !== 0 ||
      wide.stdout.subarray(0, 8).toString("ascii") !== "ABL_PKO1" ||
      wide.stdout[10] !== 5 ||
      wide.stdout.readBigUInt64LE(32) !== BigInt(wideLength + 40)) {
    throw new Error("relay materialized wide input before NeedsCapacity");
  }
  const oversizedKernel = path.join(temporary, "oversized-kernel.wasm");
  const oversizedKernelFile = fs.openSync(oversizedKernel, "w");
  try {
    fs.ftruncateSync(oversizedKernelFile, 64 * 1024 * 1024 + 1);
  } finally {
    fs.closeSync(oversizedKernelFile);
  }
  const boundedKernel = spawnSync(process.execPath, [
    adapter,
    "--kernel", oversizedKernel,
    "--image", emptyImage,
    "--initial-args", emptyInitial,
  ]);
  if (boundedKernel.status === 0 ||
      !boundedKernel.stderr.toString("utf8").includes(
        "kernel exceeds this relay's operational byte limit",
      )) {
    throw new Error("relay materialized an oversized kernel descriptor");
  }
  const fifo = path.join(temporary, "input.fifo");
  const madeFifo = spawnSync("mkfifo", [fifo]);
  if (madeFifo.status !== 0) throw new Error("could not create FIFO fixture");
  const fifoInput = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", emptyImage,
    "--initial-args", fifo,
  ], { timeout: 2000 });
  if (fifoInput.status === 0 || fifoInput.error?.code === "ETIMEDOUT" ||
      !fifoInput.stderr.toString("utf8").includes(
        "instance must be a regular file",
      )) {
    throw new Error("relay blocked on a FIFO before regular-file admission");
  }
  const nonRegular = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", emptyImage,
    "--initial-args", temporary,
  ]);
  if (nonRegular.status === 0 ||
      !nonRegular.stderr.toString("utf8").includes(
        "instance must be a regular file",
      )) {
    throw new Error("relay accepted a non-regular payload source");
  }
  const nonRegularKernel = spawnSync(process.execPath, [
    adapter,
    "--kernel", temporary,
    "--image", emptyImage,
    "--initial-args", emptyInitial,
  ]);
  if (nonRegularKernel.status === 0 ||
      !nonRegularKernel.stderr.toString("utf8").includes(
        "kernel must be a regular file",
      )) {
    throw new Error("relay accepted a non-regular kernel source");
  }
  const wrongAbi = spawnSync(process.execPath, [
    adapter,
    "--kernel", wrongKernel,
    "--image", emptyImage,
    "--initial-args", emptyInitial,
  ]);
  if (wrongAbi.status === 0 ||
      !wrongAbi.stderr.toString("utf8").includes(
        "unsupported Boundary Process kernel ABI",
      )) {
    throw new Error("boundary-process-step accepted a different kernel ABI");
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

function nativeVector(instance, executable) {
  const livePages = instance.exports.memory.buffer.byteLength / 65536;
  const occupiedBytes = instance.exports.boundary_process_kernel_occupied_memory_bytes();
  const result = spawnSync(executable, [
    String(livePages),
    String(occupiedBytes),
  ], { maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0) {
    throw new Error(result.stderr.toString("utf8"));
  }
  return result.stdout;
}
