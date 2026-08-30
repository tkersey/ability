import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";

const kernel = process.argv[2];
const vectorSource = process.argv[3];
const adapter = process.argv[4];
const wrongKernel = process.argv[5];
const malformedKernel = process.argv[6];
if (malformedKernel === undefined) {
  throw new Error("missing malformed Process relay kernel fixture");
}
const kernelInstance = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(kernel)),
  {},
);
const kernelInputCapacity =
  kernelInstance.exports.boundary_process_kernel_input_capacity();
const vector = process.argv[7] === "native"
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
  const changingInitial = path.join(temporary, "changing.initial");
  fs.writeFileSync(changingInitial, Buffer.alloc(512 * 1024));
  const writer = await startSameLengthWriter(changingInitial);
  const changedGeneration = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", emptyImage,
    "--initial-args", changingInitial,
  ], { timeout: 3000 });
  await stopWriter(writer);
  if (changedGeneration.status === 0 ||
      !changedGeneration.stderr.toString("utf8").includes(
        "instance changed after preflight",
      )) {
    throw new Error("relay admitted a changing file generation");
  }
  const earlierImage = path.join(temporary, "system-0.bpi1");
  const laterInstance = path.join(temporary, "instance-0.bin");
  const mutationPreload = path.join(temporary, "mutate-earlier-input.cjs");
  fs.writeFileSync(mutationPreload, `
    const fs = require("node:fs");
    const path = require("node:path");
    const originalOpenSync = fs.openSync;
    const originalReadSync = fs.readSync;
    const originalWriteSync = fs.writeSync;
    const openedPaths = new Map();
    fs.openSync = function(file, ...args) {
      const descriptor = originalOpenSync.call(fs, file, ...args);
      if (typeof file === "string") {
        openedPaths.set(descriptor, path.resolve(file));
      }
      return descriptor;
    };
    let mutated = false;
    fs.readSync = function(descriptor, ...args) {
      if (!mutated && openedPaths.get(descriptor) ===
          path.resolve(process.env.BOUNDARY_RELAY_TRIGGER_PATH)) {
        mutated = true;
        const target = originalOpenSync.call(
          fs,
          process.env.BOUNDARY_RELAY_MUTATE_PATH,
          "a",
        );
        try {
          originalWriteSync.call(fs, target, Buffer.from([0]));
          fs.fsyncSync(target);
        } finally {
          fs.closeSync(target);
        }
      }
      return originalReadSync.call(fs, descriptor, ...args);
    };
  `);
  const crossFileGeneration = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", earlierImage,
    "--initial-args", laterInstance,
  ], {
    env: {
      ...process.env,
      NODE_OPTIONS: [
        process.env.NODE_OPTIONS,
        "--require=" + mutationPreload,
      ].filter(Boolean).join(" "),
      BOUNDARY_RELAY_MUTATE_PATH: earlierImage,
      BOUNDARY_RELAY_TRIGGER_PATH: laterInstance,
    },
  });
  if (crossFileGeneration.status === 0 ||
      !crossFileGeneration.stderr.toString("utf8").includes(
        "image changed after preflight",
      )) {
    throw new Error(
      "relay admitted a cross-file generation change: status=" +
        crossFileGeneration.status + " stderr=" +
        crossFileGeneration.stderr.toString("utf8"),
    );
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
  const invokeMalformedKernel = (instanceLength) => {
    const malformedInitial = path.join(
      temporary,
      "malformed-kernel-" + instanceLength + ".initial",
    );
    fs.writeFileSync(malformedInitial, Buffer.alloc(instanceLength));
    return spawnSync(process.execPath, [
      adapter,
      "--kernel", malformedKernel,
      "--image", emptyImage,
      "--initial-args", malformedInitial,
    ]);
  };
  const malformedCases = [
    {
      instanceLength: 1,
      expected: "kernel output pointer is outside exported memory",
    },
    {
      instanceLength: 2,
      expected: "kernel output length is not an exact safe integer",
    },
    {
      instanceLength: 3,
      expected: "kernel output range is outside exported memory",
    },
  ];
  for (const malformedCase of malformedCases) {
    const malformed = invokeMalformedKernel(malformedCase.instanceLength);
    if (malformed.status === 0 ||
        !malformed.stderr.toString("utf8").includes(
          malformedCase.expected,
        )) {
      throw new Error(
        "relay accepted malformed kernel output mode " +
          malformedCase.instanceLength,
      );
    }
  }
  const grown = invokeMalformedKernel(4);
  if (grown.status !== 0 || grown.stdout.toString("ascii") !== "GROW") {
    throw new Error("relay used a detached memory view after kernel growth");
  }
  const malformedErrorCases = [
    {
      instanceLength: 5,
      expected: "kernel error pointer is outside exported memory",
    },
    {
      instanceLength: 6,
      expected: "kernel error length is not an exact safe integer",
    },
    {
      instanceLength: 7,
      expected: "kernel error range is outside exported memory",
    },
  ];
  for (const malformedCase of malformedErrorCases) {
    const malformed = invokeMalformedKernel(malformedCase.instanceLength);
    if (malformed.status === 0 ||
        !malformed.stderr.toString("utf8").includes(
          malformedCase.expected,
        )) {
      throw new Error(
        "relay accepted malformed kernel error mode " +
          malformedCase.instanceLength,
      );
    }
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

function startSameLengthWriter(file) {
  const source = `
    const fs = require("node:fs");
    const descriptor = fs.openSync(process.argv[1], "r+");
    let byte = 0;
    fs.writeSync(1, "ready\\n");
    while (true) {
      fs.writeSync(descriptor, Buffer.from([byte++ & 1]), 0, 1, 0);
    }
  `;
  const child = spawn(process.execPath, ["-e", source, file], {
    stdio: ["ignore", "pipe", "inherit"],
  });
  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.stdout.once("data", () => resolve(child));
  });
}

function stopWriter(child) {
  return new Promise((resolve) => {
    child.once("close", resolve);
    child.kill();
  });
}
