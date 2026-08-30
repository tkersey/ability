#!/usr/bin/env node

import childProcess from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

import {
  CORPUS_IDENTITY,
  EXPECTED_ARTIFACT_IDS,
  OUTCOME_KIND_BY_BYTE,
  VECTOR_DESCRIPTORS,
  canonicalJsonBytes,
  sha256Hex,
  validateCanonicalOutcome,
  validateCorpusBytes,
} from "./check_process_conformance_corpus.mjs";

const STREAM_MAGIC = Buffer.from([0x42, 0x50, 0x43, 0x47, 0x45, 0x4e, 0x31, 0x00]);
const STREAM_VERSION = 1;
const MAX_NATIVE_STREAM_BYTES = 64 * 1024 * 1024;
const MAX_KERNEL_BYTES = 64 * 1024 * 1024;
const KERNEL_ASSET_NAME = "boundary-process-kernel-v1.wasm";
const PROCESS_INPUT_HEADER_BYTES = 40;
const DEFAULT_INPUT_CAPACITY = 32 * 1024 * 1024;
const EXPECTED_LIVE_PAGES = 2_457;
const EXPECTED_OCCUPIED_BYTES = 160_977_264n;
const NEEDS_CAPACITY_INPUT_BYTES = 33_554_433;
const NEEDS_CAPACITY_IMAGE_BYTES = 746;
const NEEDS_CAPACITY_IMAGE_SHA256 = "b62f6ea3a307fc600be79894ebd242fa07d8972e90c34194dd4219ecfc427d00";
const NEEDS_CAPACITY_INSTANCE_BYTES = 33_553_647;
const NEEDS_CAPACITY_INSTANCE_SHA256 = "c039e4fb3ff6b2f59a9cc823a84e56c4db7cdf21033ce6496d04d6cbd1e9da28";
const NEEDS_CAPACITY_OUTCOME_SHA256 = "d39288fd5bd8184a3edd7b69d4681d5908f05433664794090287af348a7b305a";
const WORLD_VALIDATOR_COMMIT = "87b0f24896a8c63d74de33ec84ce4b81b0682c86";
const WORLD_VALIDATOR_SHA256 = "42a11ef293a57b41bb0151c7089199756438a26a0d47744fe9cc50bc693dcf44";
const WORLD_VALIDATOR_RELATIVE = "scripts/acquire_process_conformance_assets.mjs";
const COMMIT_PATTERN = /^[0-9a-f]{40}$/;
const DIGEST_PATTERN = /^[0-9a-f]{64}$/;
const GENERATOR_SOURCE_PATHS = Object.freeze([
  "build.zig",
  "test/process_kernel_vector.zig",
  "test/process_kernel_capacity_vector.zig",
  "scripts/build_process_conformance_corpus.mjs",
  "scripts/check_process_conformance_corpus.mjs",
]);
const SUBPROCESS_TIMEOUT_MS = 120_000;

export const REQUIRED_KERNEL_EXPORTS = Object.freeze([
  Object.freeze({ name: "memory", kind: "memory" }),
  Object.freeze({ name: "boundary_process_kernel_abi_version", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_reserve", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_input_ptr", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_input_capacity", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_input_payload_ptr", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_occupied_memory_bytes", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_prepare_input", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_execute", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_output_ptr", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_output_len", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_error_ptr", kind: "function" }),
  Object.freeze({ name: "boundary_process_kernel_error_len", kind: "function" }),
]);

export class CorpusBuildError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "CorpusBuildError";
    this.code = code;
    this.details = Object.freeze({ ...details });
  }
}

function fail(code, message, details = {}) {
  throw new CorpusBuildError(code, message, details);
}

function exactSafeU64(buffer, offset, label) {
  const value = buffer.readBigUInt64LE(offset);
  if (value > BigInt(Number.MAX_SAFE_INTEGER)) {
    fail("NATIVE_STREAM_INVALID", `${label} is not an exact safe integer`, { label, value: String(value) });
  }
  return Number(value);
}

function allZero(bytes) {
  return !bytes.some((byte) => byte !== 0);
}

function canonicalIdentifier(value, label) {
  if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(value)) {
    fail("NATIVE_STREAM_INVALID", `${label} is not a canonical identifier`, { label, value });
  }
  return value;
}

export function parseKernelInput(bytes, label = "kernel input") {
  const input = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (input.length < PROCESS_INPUT_HEADER_BYTES ||
      !input.subarray(0, 8).equals(Buffer.from("ABL_PKI1")) ||
      input.readUInt16LE(8) !== 1 || input[10] > 1 || input[11] > 1 ||
      !allZero(input.subarray(36, 40))) {
    fail("NATIVE_STREAM_INVALID", `${label} has a malformed ABL_PKI1 header`, { label });
  }
  const imageLength = exactSafeU64(input, 12, `${label} image length`);
  const instanceLength = exactSafeU64(input, 20, `${label} instance length`);
  const effectResultLength = exactSafeU64(input, 28, `${label} EffectResult length`);
  const effectResultPresent = input[11] === 1;
  if (!effectResultPresent && effectResultLength !== 0) {
    fail("NATIVE_STREAM_INVALID", `${label} has absent nonempty EffectResult bytes`, { label });
  }
  const total = PROCESS_INPUT_HEADER_BYTES + imageLength + instanceLength + effectResultLength;
  if (!Number.isSafeInteger(total) || total !== input.length) {
    fail("NATIVE_STREAM_INVALID", `${label} lengths do not cover the complete input`, {
      label, expected: total, observed: input.length,
    });
  }
  const imageStart = PROCESS_INPUT_HEADER_BYTES;
  const instanceStart = imageStart + imageLength;
  const effectResultStart = instanceStart + instanceLength;
  return Object.freeze({
    bytes: input,
    instanceKind: input[10] === 0 ? "initialArgs" : "state",
    effectResultPresent,
    image: input.subarray(imageStart, instanceStart),
    instance: input.subarray(instanceStart, effectResultStart),
    effectResult: effectResultPresent ? input.subarray(effectResultStart) : null,
  });
}

export function parseNativeStream(bytes, label = "native vector stream") {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength < 16 ||
      bytes.byteLength > MAX_NATIVE_STREAM_BYTES) {
    fail("NATIVE_STREAM_INVALID", `${label} has an invalid byte length`, {
      label, byteLength: bytes?.byteLength, maximum: MAX_NATIVE_STREAM_BYTES,
    });
  }
  const stream = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (!stream.subarray(0, 8).equals(STREAM_MAGIC) || stream.readUInt32LE(8) !== STREAM_VERSION) {
    fail("NATIVE_STREAM_INVALID", `${label} has the wrong BPCGEN1 stream identity`, { label });
  }
  const count = stream.readUInt32LE(12);
  if (count === 0 || count > VECTOR_DESCRIPTORS.length) {
    fail("NATIVE_STREAM_INVALID", `${label} has an invalid record count`, { label, count });
  }
  let cursor = 16;
  const records = [];
  const decoder = new TextDecoder("utf-8", { fatal: true });
  for (let index = 0; index < count; index += 1) {
    if (stream.length - cursor < 20) {
      fail("NATIVE_STREAM_INVALID", `${label} ends inside record ${index}`, { label, index });
    }
    const idLength = stream.readUInt16LE(cursor);
    const operationByte = stream[cursor + 2];
    const reserved = stream[cursor + 3];
    const inputLength = exactSafeU64(stream, cursor + 4, `${label} record ${index} PKI1 length`);
    const outcomeLength = exactSafeU64(stream, cursor + 12, `${label} record ${index} PKO1 length`);
    cursor += 20;
    if (idLength === 0 || idLength > 128 || operationByte > 1 || reserved !== 0) {
      fail("NATIVE_STREAM_INVALID", `${label} record ${index} has an invalid header`, { label, index });
    }
    const recordLength = idLength + inputLength + outcomeLength;
    if (!Number.isSafeInteger(recordLength) || recordLength > stream.length - cursor) {
      fail("NATIVE_STREAM_INVALID", `${label} record ${index} extends outside the stream`, { label, index });
    }
    let id;
    try {
      id = decoder.decode(stream.subarray(cursor, cursor + idLength));
    } catch {
      fail("NATIVE_STREAM_INVALID", `${label} record ${index} id is not valid UTF-8`, { label, index });
    }
    canonicalIdentifier(id, `${label} record ${index} id`);
    cursor += idLength;
    const inputBytes = stream.subarray(cursor, cursor + inputLength);
    cursor += inputLength;
    const nativeOutcome = stream.subarray(cursor, cursor + outcomeLength);
    cursor += outcomeLength;
    records.push(Object.freeze({
      id,
      operation: operationByte === 0 ? "execute" : "prepareInput",
      input: parseKernelInput(inputBytes, `${id} PKI1`),
      nativeOutcome,
      kernelOutcome: null,
    }));
  }
  if (cursor !== stream.length) {
    fail("NATIVE_STREAM_INVALID", `${label} has trailing bytes`, { label, trailingBytes: stream.length - cursor });
  }
  return Object.freeze(records);
}

function validateNeedsCapacityOutcome(bytes, label) {
  validateCanonicalOutcome(bytes, "NeedsCapacity", label);
  const outcome = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const observed = Object.freeze({
    minimumInputBytes: Number(outcome.readBigUInt64LE(32)),
    minimumOutputBytes: Number(outcome.readBigUInt64LE(40)),
    minimumScratchBytes: Number(outcome.readBigUInt64LE(48)),
    minimumMemoryPages: Number(outcome.readBigUInt64LE(56)),
  });
  const expected = {
    minimumInputBytes: NEEDS_CAPACITY_INPUT_BYTES,
    minimumOutputBytes: 64,
    minimumScratchBytes: 0,
    minimumMemoryPages: EXPECTED_LIVE_PAGES,
  };
  if (Object.keys(expected).some((key) => observed[key] !== expected[key])) {
    fail("NEEDS_CAPACITY_MISMATCH", `${label} does not contain the exact default-kernel requirement`, {
      expected, observed,
    });
  }
  return observed;
}

function outcomePrimary(bytes) {
  const primaryLength = Number(bytes.readBigUInt64LE(12));
  return bytes.subarray(32, 32 + primaryLength);
}

function outcomeSecondary(bytes) {
  const primaryLength = Number(bytes.readBigUInt64LE(12));
  const secondaryLength = Number(bytes.readBigUInt64LE(20));
  return bytes.subarray(32 + primaryLength, 32 + primaryLength + secondaryLength);
}

export function validateRecordInventory(records) {
  if (!Array.isArray(records) || records.length !== VECTOR_DESCRIPTORS.length) {
    fail("VECTOR_INVENTORY_MISMATCH", "native stream inventory must contain exactly 20 vectors", {
      expected: VECTOR_DESCRIPTORS.length, observed: records?.length,
    });
  }
  for (let index = 0; index < VECTOR_DESCRIPTORS.length; index += 1) {
    const expected = VECTOR_DESCRIPTORS[index];
    const record = records[index];
    if (record.id !== expected.id || record.operation !== expected.operation) {
      fail("VECTOR_INVENTORY_MISMATCH", `native vector ${index} does not match the locked order`, {
        expected: { id: expected.id, operation: expected.operation },
        observed: { id: record.id, operation: record.operation },
      });
    }
    if (record.input.instanceKind !== expected.instanceKind ||
        record.input.effectResultPresent !== expected.effectResult) {
      fail("VECTOR_INVENTORY_MISMATCH", `${record.id} input shape does not match the locked vector`, {
        expectedInstanceKind: expected.instanceKind,
        observedInstanceKind: record.input.instanceKind,
        expectedEffectResult: expected.effectResult,
        observedEffectResult: record.input.effectResultPresent,
      });
    }
    validateCanonicalOutcome(record.nativeOutcome, expected.expectedKind, `${record.id} native outcome`);
  }

  const initialRequest = records[0].nativeOutcome;
  const reconstructedRequest = records[1].nativeOutcome;
  if (!initialRequest.equals(reconstructedRequest) ||
      !records[1].input.instance.equals(outcomePrimary(initialRequest)) ||
      !records[2].input.instance.equals(outcomePrimary(initialRequest)) ||
      outcomeSecondary(initialRequest).length === 0) {
    fail("VECTOR_RELATION_MISMATCH", "pending request reconstruction and typed resume do not share exact state/request bytes");
  }

  const capacity = records[19];
  if (capacity.input.bytes.length !== NEEDS_CAPACITY_INPUT_BYTES ||
      capacity.input.image.length !== NEEDS_CAPACITY_IMAGE_BYTES ||
      sha256Hex(capacity.input.image) !== NEEDS_CAPACITY_IMAGE_SHA256 ||
      capacity.input.instance.length !== NEEDS_CAPACITY_INSTANCE_BYTES ||
      sha256Hex(capacity.input.instance) !== NEEDS_CAPACITY_INSTANCE_SHA256 ||
      capacity.input.effectResult !== null) {
    fail("NEEDS_CAPACITY_MISMATCH", "needs-capacity does not use the exact default-kernel preflight input", {
      inputBytes: capacity.input.bytes.length,
      imageBytes: capacity.input.image.length,
      imageSha256: sha256Hex(capacity.input.image),
      instanceBytes: capacity.input.instance.length,
      instanceSha256: sha256Hex(capacity.input.instance),
    });
  }
  validateNeedsCapacityOutcome(capacity.nativeOutcome, "needs-capacity native outcome");
  if (sha256Hex(capacity.nativeOutcome) !== NEEDS_CAPACITY_OUTCOME_SHA256) {
    fail("NEEDS_CAPACITY_MISMATCH", "needs-capacity native outcome digest changed", {
      expected: NEEDS_CAPACITY_OUTCOME_SHA256,
      observed: sha256Hex(capacity.nativeOutcome),
    });
  }
  return records;
}

export function validateKernelModuleShape(module) {
  const imports = WebAssembly.Module.imports(module);
  if (imports.length !== 0) {
    fail("KERNEL_IMPORTS_PRESENT", "Boundary Process kernel must be import-free", {
      imports: imports.map(({ module: moduleName, name, kind }) => ({ module: moduleName, name, kind })),
    });
  }
  const order = (entry) => `${entry.name}\0${entry.kind}`;
  const observed = WebAssembly.Module.exports(module)
    .map(({ name, kind }) => ({ name, kind }))
    .sort((left, right) => order(left).localeCompare(order(right)));
  const expected = REQUIRED_KERNEL_EXPORTS
    .map(({ name, kind }) => ({ name, kind }))
    .sort((left, right) => order(left).localeCompare(order(right)));
  if (JSON.stringify(observed) !== JSON.stringify(expected)) {
    fail("KERNEL_EXPORT_MISMATCH", "Boundary Process kernel export inventory is not exact", {
      expected, observed,
    });
  }
  return Object.freeze({ importCount: 0, exports: Object.freeze(observed) });
}

export function validateExactKernelBytes(bytes, label = "released kernel") {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength !== CORPUS_IDENTITY.boundary.kernelByteLength) {
    fail("KERNEL_IDENTITY_MISMATCH", `${label} byte length does not match Boundary v1.7.0`, {
      expected: CORPUS_IDENTITY.boundary.kernelByteLength, observed: bytes?.byteLength,
    });
  }
  const digest = sha256Hex(bytes);
  if (digest !== CORPUS_IDENTITY.boundary.kernelSha256) {
    fail("KERNEL_IDENTITY_MISMATCH", `${label} digest does not match Boundary v1.7.0`, {
      expected: CORPUS_IDENTITY.boundary.kernelSha256, observed: digest,
    });
  }
  let module;
  try {
    module = new WebAssembly.Module(bytes);
  } catch (error) {
    fail("KERNEL_MODULE_INVALID", `${label} is not a valid WebAssembly module`, {
      cause: error?.message ?? String(error),
    });
  }
  validateKernelModuleShape(module);
  return module;
}

export function assertByteIdenticalLocalKernel(releasedBytes, localBytes) {
  if (!Buffer.from(releasedBytes).equals(Buffer.from(localBytes))) {
    fail("LOCAL_KERNEL_MISMATCH", "locally rebuilt Process kernel differs from the exact released kernel", {
      releasedSha256: sha256Hex(releasedBytes),
      localSha256: sha256Hex(localBytes),
      releasedByteLength: releasedBytes.byteLength,
      localByteLength: localBytes.byteLength,
    });
  }
}

export function validateKernelPair(releasedBytes, localBytes) {
  const releasedModule = validateExactKernelBytes(releasedBytes, "released kernel");
  validateExactKernelBytes(localBytes, "locally rebuilt kernel");
  assertByteIdenticalLocalKernel(releasedBytes, localBytes);
  return releasedModule;
}

function exactWasmU64(value, label) {
  if (typeof value === "bigint") {
    if (value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) {
      fail("KERNEL_OUTPUT_INVALID", `${label} is not an exact safe integer`, { label, value: String(value) });
    }
    return Number(value);
  }
  if (!Number.isInteger(value) || value < 0) {
    fail("KERNEL_OUTPUT_INVALID", `${label} is not a nonnegative integer`, { label, value });
  }
  return value >>> 0 === value ? value : value;
}

function memoryRange(exports, pointerValue, lengthValue, label) {
  const pointer = pointerValue >>> 0;
  const length = exactWasmU64(lengthValue, `${label} length`);
  const memory = new Uint8Array(exports.memory.buffer);
  if (pointer > memory.length || length > memory.length - pointer) {
    fail("KERNEL_OUTPUT_INVALID", `${label} lies outside exported memory`, { pointer, length, memory: memory.length });
  }
  return memory.subarray(pointer, pointer + length);
}

function kernelOutput(exports) {
  return Buffer.from(memoryRange(
    exports,
    exports.boundary_process_kernel_output_ptr(),
    exports.boundary_process_kernel_output_len(),
    "kernel output",
  ));
}

function kernelError(exports) {
  return Buffer.from(memoryRange(
    exports,
    exports.boundary_process_kernel_error_ptr(),
    exports.boundary_process_kernel_error_len(),
    "kernel error",
  )).toString("utf8");
}

export function validateInstanceIdentity(exports, label) {
  if (exports.boundary_process_kernel_abi_version() !== CORPUS_IDENTITY.boundary.processKernelAbiVersion) {
    fail("KERNEL_ABI_MISMATCH", `${label} does not expose Process kernel ABI 1`, { label });
  }
}

function instantiateFresh(module, label) {
  const instance = new WebAssembly.Instance(module, {});
  validateInstanceIdentity(instance.exports, label);
  return instance;
}

function executeEncodedRecord(module, record) {
  const instance = instantiateFresh(module, record.id);
  const exports = instance.exports;
  if (exports.boundary_process_kernel_reserve(BigInt(record.input.bytes.length)) !== 1) {
    fail("KERNEL_VECTOR_REJECTED", `${record.id} encoded input was not admitted`);
  }
  const inputPointer = exports.boundary_process_kernel_input_ptr() >>> 0;
  let memory = new Uint8Array(exports.memory.buffer);
  if (inputPointer > memory.length || record.input.bytes.length > memory.length - inputPointer) {
    fail("KERNEL_MEMORY_INVALID", `${record.id} input arena is outside exported memory`);
  }
  memory.set(record.input.bytes, inputPointer);
  const status = exports.boundary_process_kernel_execute(record.input.bytes.length);
  if (status !== 0) {
    fail("KERNEL_VECTOR_REJECTED", `${record.id} was rejected by the released kernel`, {
      status, error: kernelError(exports),
    });
  }
  if (exactWasmU64(exports.boundary_process_kernel_error_len(), `${record.id} error length`) !== 0) {
    fail("KERNEL_VECTOR_REJECTED", `${record.id} left a kernel error after success`, {
      error: kernelError(exports),
    });
  }
  return Object.freeze({ instance, outcome: kernelOutput(exports) });
}

function capacityInstanceFacts(instance) {
  const exports = instance.exports;
  const livePages = exports.memory.buffer.byteLength / 65_536;
  const occupiedBytesValue = exports.boundary_process_kernel_occupied_memory_bytes();
  const occupiedBytes = typeof occupiedBytesValue === "bigint"
    ? occupiedBytesValue
    : BigInt(occupiedBytesValue >>> 0);
  const inputCapacity = exports.boundary_process_kernel_input_capacity();
  if (livePages !== EXPECTED_LIVE_PAGES || occupiedBytes !== EXPECTED_OCCUPIED_BYTES ||
      inputCapacity !== DEFAULT_INPUT_CAPACITY) {
    fail("KERNEL_CAPACITY_PROBE_MISMATCH", "released kernel capacity projection changed", {
      expected: {
        livePages: EXPECTED_LIVE_PAGES,
        occupiedBytes: String(EXPECTED_OCCUPIED_BYTES),
        inputCapacity: DEFAULT_INPUT_CAPACITY,
      },
      observed: { livePages, occupiedBytes: String(occupiedBytes), inputCapacity },
    });
  }
  return Object.freeze({ livePages, occupiedBytes, inputCapacity });
}

function executeCapacityRecord(instance, record) {
  const exports = instance.exports;
  const inputPointer = exports.boundary_process_kernel_input_ptr() >>> 0;
  const inputCapacity = exports.boundary_process_kernel_input_capacity();
  const before = memoryRange(exports, inputPointer, inputCapacity, "kernel input arena");
  const beforeDigest = sha256Hex(before);
  const prepared = exports.boundary_process_kernel_prepare_input(
    0,
    BigInt(record.input.image.length),
    BigInt(record.input.instance.length),
    0,
    0n,
  );
  if (prepared !== 0) {
    fail("NEEDS_CAPACITY_MISMATCH", "default kernel admitted the oversized vector", { prepared });
  }
  const after = memoryRange(exports, inputPointer, inputCapacity, "kernel input arena");
  if (sha256Hex(after) !== beforeDigest) {
    fail("NEEDS_CAPACITY_MISMATCH", "prepare_input changed the guest input arena before capacity admission");
  }
  if (exactWasmU64(exports.boundary_process_kernel_error_len(), "needs-capacity error length") !== 0) {
    fail("NEEDS_CAPACITY_MISMATCH", "prepare_input returned a kernel error", { error: kernelError(exports) });
  }
  const outcome = kernelOutput(exports);
  if (outcome.length !== 64) {
    fail("NEEDS_CAPACITY_MISMATCH", "prepare_input did not return a 64-byte NeedsCapacity outcome", {
      observed: outcome.length,
    });
  }
  validateNeedsCapacityOutcome(outcome, "needs-capacity kernel outcome");
  return outcome;
}

function runEmitterToFile(executable, argumentsList, outputPath, label) {
  const output = fs.openSync(outputPath, "wx", 0o600);
  let result;
  try {
    result = childProcess.spawnSync(executable, argumentsList, {
      stdio: ["ignore", output, "pipe"],
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
      timeout: SUBPROCESS_TIMEOUT_MS,
      killSignal: "SIGKILL",
    });
  } finally {
    fs.closeSync(output);
  }
  if (result.error || result.status !== 0) {
    fail("NATIVE_EMITTER_FAILED", `${label} failed`, {
      status: result.status,
      cause: result.error?.message ?? null,
      stderr: result.stderr?.slice(0, 16_384) ?? "",
    });
  }
  const stat = fs.statSync(outputPath);
  if (!stat.isFile() || stat.size === 0 || stat.size > MAX_NATIVE_STREAM_BYTES) {
    fail("NATIVE_STREAM_INVALID", `${label} emitted an invalid stream length`, {
      byteLength: stat.size, maximum: MAX_NATIVE_STREAM_BYTES,
    });
  }
  return fs.readFileSync(outputPath);
}

function assertOutcomeParity(id, nativeOutcome, kernelOutcome) {
  if (!(kernelOutcome instanceof Uint8Array) ||
      !Buffer.from(nativeOutcome).equals(Buffer.from(kernelOutcome))) {
    fail("CORPUS_PARITY_MISMATCH", `${id} native and released-kernel outcomes differ`, {
      id,
      nativeSha256: sha256Hex(nativeOutcome),
      kernelSha256: kernelOutcome instanceof Uint8Array ? sha256Hex(kernelOutcome) : null,
    });
  }
}

const verifiedParityBrand = Symbol("verified Boundary native/kernel parity");

function verifyParityRecords(records) {
  validateRecordInventory(records);
  for (const record of records) {
    assertOutcomeParity(record.id, record.nativeOutcome, record.kernelOutcome);
  }
  const ownedRecords = records.map((record) => Object.freeze({
    id: record.id,
    operation: record.operation,
    input: Object.freeze({
      bytes: Buffer.from(record.input.bytes),
      instanceKind: record.input.instanceKind,
      effectResultPresent: record.input.effectResultPresent,
      image: Buffer.from(record.input.image),
      instance: Buffer.from(record.input.instance),
      effectResult: record.input.effectResult === null
        ? null
        : Buffer.from(record.input.effectResult),
    }),
    nativeOutcome: Buffer.from(record.nativeOutcome),
    kernelOutcome: Buffer.from(record.kernelOutcome),
  }));
  return Object.freeze({
    [verifiedParityBrand]: true,
    records: Object.freeze(ownedRecords),
  });
}

function constructCorpusFromVerifiedParity(
  verified,
  { onArtifactConstruction = () => {} } = {},
) {
  if (verified?.[verifiedParityBrand] !== true) {
    fail("CORPUS_PARITY_MISMATCH", "artifact construction requires verified native/kernel parity");
  }
  const records = verified.records;

  const artifacts = [];
  const payloadParts = [];
  const vectors = [];
  let offset = 0;
  const addArtifact = (id, bytes) => {
    onArtifactConstruction(id);
    const owned = Buffer.from(bytes);
    artifacts.push({ id, offset, byteLength: owned.length, sha256: sha256Hex(owned) });
    payloadParts.push(owned);
    offset += owned.length;
  };

  for (let index = 0; index < VECTOR_DESCRIPTORS.length; index += 1) {
    const expected = VECTOR_DESCRIPTORS[index];
    const record = records[index];
    const imageId = `${expected.id}.image`;
    const instanceId = `${expected.id}.instance`;
    const effectResultId = expected.effectResult ? `${expected.id}.effect-result` : null;
    const outcomeId = `${expected.id}.outcome`;
    addArtifact(imageId, record.input.image);
    addArtifact(instanceId, record.input.instance);
    if (effectResultId !== null) addArtifact(effectResultId, record.input.effectResult);
    addArtifact(outcomeId, record.nativeOutcome);
    const outcomeSha256 = sha256Hex(record.nativeOutcome);
    vectors.push({
      id: expected.id,
      scenarios: [...expected.scenarios],
      image: imageId,
      instance: { kind: expected.instanceKind, artifact: instanceId },
      effectResult: effectResultId,
      expectedOutcome: outcomeId,
      expectedKind: expected.expectedKind,
      nativeOutcomeSha256: outcomeSha256,
      kernelOutcomeSha256: sha256Hex(record.kernelOutcome),
    });
  }
  if (artifacts.length !== EXPECTED_ARTIFACT_IDS.length) {
    fail("CORPUS_CONSTRUCTION_INVALID", "artifact construction did not produce exactly 61 records", {
      observed: artifacts.length,
    });
  }
  const payloadBytes = Buffer.concat(payloadParts, offset);
  const manifest = {
    format: CORPUS_IDENTITY.manifestFormat,
    producer: { ...CORPUS_IDENTITY.producer },
    boundary: { ...CORPUS_IDENTITY.boundary },
    payload: {
      assetName: CORPUS_IDENTITY.payloadAssetName,
      sha256: sha256Hex(payloadBytes),
      byteLength: payloadBytes.length,
    },
    artifacts,
    vectors,
    receipt: { ...CORPUS_IDENTITY.receipt },
  };
  const manifestBytes = canonicalJsonBytes(manifest);
  validateCorpusBytes(manifestBytes, payloadBytes);
  return Object.freeze({ manifest, manifestBytes, payloadBytes });
}

export function buildCorpusFromParityRecords(records, options = {}) {
  return constructCorpusFromVerifiedParity(verifyParityRecords(records), options);
}

async function generateWorker({ kernelBytes, vectorEmitter, capacityEmitter, directory }) {
  const module = new WebAssembly.Module(kernelBytes);
  validateKernelModuleShape(module);

  const mainStreamPath = path.join(directory, "native-main.bpcgen");
  const mainRecords = parseNativeStream(
    runEmitterToFile(
      vectorEmitter,
      ["--conformance-corpus-v1"],
      mainStreamPath,
      "Boundary Process native vector emitter",
    ),
    "main native vector stream",
  );
  if (mainRecords.length !== 19 || mainRecords.some((record, index) => record.id !== VECTOR_DESCRIPTORS[index].id)) {
    fail("VECTOR_INVENTORY_MISMATCH", "main native emitter did not produce exact vectors 0 through 18");
  }

  const records = [];
  let freshVectorInstanceCount = 0;
  for (const record of mainRecords) {
    const { outcome } = executeEncodedRecord(module, record);
    freshVectorInstanceCount += 1;
    assertOutcomeParity(record.id, record.nativeOutcome, outcome);
    records.push(Object.freeze({ ...record, kernelOutcome: outcome }));
  }

  // Vector 19's own fresh instance supplies the physical probe values. It is not
  // an admission-only extra instance and it is never used for another vector.
  const capacityInstance = instantiateFresh(module, "needs-capacity");
  freshVectorInstanceCount += 1;
  const facts = capacityInstanceFacts(capacityInstance);
  const capacityStreamPath = path.join(directory, "native-capacity.bpcgen");
  const capacityRecords = parseNativeStream(
    runEmitterToFile(
      capacityEmitter,
      [
        "--conformance-corpus-v1",
        String(facts.livePages),
        String(facts.occupiedBytes),
        String(facts.inputCapacity),
      ],
      capacityStreamPath,
      "Boundary Process native capacity emitter",
    ),
    "capacity native vector stream",
  );
  if (capacityRecords.length !== 1 || capacityRecords[0].id !== "needs-capacity") {
    fail("VECTOR_INVENTORY_MISMATCH", "capacity emitter did not produce only needs-capacity");
  }
  const capacityOutcome = executeCapacityRecord(capacityInstance, capacityRecords[0]);
  assertOutcomeParity(capacityRecords[0].id, capacityRecords[0].nativeOutcome, capacityOutcome);
  records.push(Object.freeze({ ...capacityRecords[0], kernelOutcome: capacityOutcome }));
  if (freshVectorInstanceCount !== VECTOR_DESCRIPTORS.length) {
    fail("FRESH_INSTANCE_COUNT_MISMATCH", "corpus generation did not use one fresh instance per vector", {
      expected: VECTOR_DESCRIPTORS.length,
      observed: freshVectorInstanceCount,
    });
  }

  const corpus = buildCorpusFromParityRecords(records);
  fs.writeFileSync(path.join(directory, CORPUS_IDENTITY.manifestAssetName), corpus.manifestBytes, { flag: "wx" });
  fs.writeFileSync(path.join(directory, CORPUS_IDENTITY.payloadAssetName), corpus.payloadBytes, { flag: "wx" });
  return Object.freeze({ ...corpus, freshVectorInstanceCount });
}

const verifiedDeterminismBrand = Symbol("verified independent corpus rebuilds");

export function assertDeterministic(first, second) {
  if (first.freshVectorInstanceCount !== VECTOR_DESCRIPTORS.length ||
      second.freshVectorInstanceCount !== VECTOR_DESCRIPTORS.length) {
    fail("FRESH_INSTANCE_COUNT_MISMATCH", "independent rebuilds did not observe 20 fresh instances each");
  }
  if (!first.manifestBytes.equals(second.manifestBytes) ||
      !first.payloadBytes.equals(second.payloadBytes)) {
    fail("CORPUS_NONDETERMINISTIC", "independent corpus rebuilds are not byte-identical", {
      firstManifestSha256: sha256Hex(first.manifestBytes),
      secondManifestSha256: sha256Hex(second.manifestBytes),
      firstPayloadSha256: sha256Hex(first.payloadBytes),
      secondPayloadSha256: sha256Hex(second.payloadBytes),
    });
  }
  return Object.freeze({
    [verifiedDeterminismBrand]: true,
    first,
    second,
  });
}

function apiHeaders(accept = "application/vnd.github+json") {
  const headers = {
    Accept: accept,
    "User-Agent": "boundary-process-v1-conformance-builder",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function fetchChecked(fetchImpl, url, accept = "application/vnd.github+json") {
  let response;
  try {
    response = await fetchImpl(url, {
      headers: apiHeaders(accept),
      signal: AbortSignal.timeout(30_000),
    });
  } catch (error) {
    fail("RELEASE_ACQUISITION_FAILED", `failed to fetch ${url}`, {
      url, cause: error?.message ?? String(error),
    });
  }
  if (!response.ok) {
    fail("RELEASE_ACQUISITION_FAILED", `fetch returned HTTP ${response.status}`, {
      url, status: response.status,
    });
  }
  return response;
}

async function fetchJson(fetchImpl, url) {
  return (await fetchChecked(fetchImpl, url)).json();
}

export async function resolveReleaseTagCommit(fetchImpl = fetch) {
  let object = (
    await fetchJson(
      fetchImpl,
      `https://api.github.com/repos/${CORPUS_IDENTITY.producer.repository}/git/ref/tags/${CORPUS_IDENTITY.producer.releaseTag}`,
    )
  ).object;
  for (let depth = 0; depth < 8; depth += 1) {
    if (!object || typeof object.sha !== "string" || typeof object.type !== "string") {
      fail("RELEASE_TAG_INVALID", "v1.7.0 tag metadata is malformed");
    }
    if (object.type === "commit") {
      if (object.sha !== CORPUS_IDENTITY.producer.commit) {
        fail("RELEASE_TAG_DRIFT", "Boundary v1.7.0 tag target changed", {
          expected: CORPUS_IDENTITY.producer.commit, observed: object.sha,
        });
      }
      return object.sha;
    }
    if (object.type !== "tag") {
      fail("RELEASE_TAG_INVALID", "v1.7.0 tag does not resolve to a commit", { type: object.type });
    }
    object = (
      await fetchJson(
        fetchImpl,
        `https://api.github.com/repos/${CORPUS_IDENTITY.producer.repository}/git/tags/${object.sha}`,
      )
    ).object;
  }
  fail("RELEASE_TAG_INVALID", "v1.7.0 tag indirection is too deep");
}

export async function acquireReleasedKernel(fetchImpl = fetch) {
  await resolveReleaseTagCommit(fetchImpl);
  const release = await fetchJson(
    fetchImpl,
    `https://api.github.com/repos/${CORPUS_IDENTITY.producer.repository}/releases/tags/${CORPUS_IDENTITY.producer.releaseTag}`,
  );
  if (release?.tag_name !== CORPUS_IDENTITY.producer.releaseTag || !Array.isArray(release.assets)) {
    fail("RELEASE_METADATA_INVALID", "Boundary v1.7.0 release metadata is malformed");
  }
  const assets = release.assets.filter((asset) => asset?.name === KERNEL_ASSET_NAME);
  if (assets.length !== 1) {
    fail("RELEASE_METADATA_INVALID", "Boundary v1.7.0 must contain exactly one fixed Process kernel asset", {
      observed: assets.length,
    });
  }
  const asset = assets[0];
  if (asset.size !== CORPUS_IDENTITY.boundary.kernelByteLength) {
    fail("RELEASE_ASSET_LENGTH_MISMATCH", "release API kernel byte length does not match Boundary v1.7.0", {
      expected: CORPUS_IDENTITY.boundary.kernelByteLength, observed: asset.size,
    });
  }
  const expectedApiDigest = `sha256:${CORPUS_IDENTITY.boundary.kernelSha256}`;
  if (asset.digest !== expectedApiDigest) {
    fail("RELEASE_ASSET_DIGEST_MISMATCH", "release API kernel digest does not match Boundary v1.7.0", {
      expected: expectedApiDigest, observed: asset.digest ?? null,
    });
  }
  if (typeof asset.browser_download_url !== "string") {
    fail("RELEASE_METADATA_INVALID", "release API kernel download URL is missing");
  }
  const response = await fetchChecked(fetchImpl, asset.browser_download_url, "application/octet-stream");
  const bytes = Buffer.from(await response.arrayBuffer());
  validateExactKernelBytes(bytes, "downloaded released kernel");
  return bytes;
}

function readRegularBounded(file, maximum, label) {
  const stat = fs.statSync(file);
  if (!stat.isFile() || stat.size <= 0 || stat.size > maximum) {
    fail("INPUT_FILE_INVALID", `${label} must be a bounded regular file`, {
      file, byteLength: stat.size, maximum,
    });
  }
  return fs.readFileSync(file);
}

export function validateWorldContractModule(module, manifestBytes, payloadBytes) {
  for (const name of [
    "parseManifestBytes", "validateBoundaryProcessCorpusManifest", "validateBundlePayload",
  ]) {
    if (typeof module[name] !== "function") {
      fail("WORLD_CONTRACT_REJECTED", `pinned World validator does not export ${name}`);
    }
  }
  try {
    const parsed = module.parseManifestBytes(new Uint8Array(manifestBytes));
    const validated = module.validateBoundaryProcessCorpusManifest(parsed);
    module.validateBundlePayload(validated, new Uint8Array(payloadBytes));
  } catch (error) {
    fail("WORLD_CONTRACT_REJECTED", "pinned World validator rejected the Boundary corpus", {
      cause: error?.message ?? String(error),
      code: error?.code ?? null,
    });
  }
  return true;
}

export function assertFileBelongsToCommit(repository, commit, relative, source) {
  const committed = childProcess.spawnSync(
    "git",
    ["-C", repository, "show", `${commit}:${relative}`],
    { encoding: null, maxBuffer: 4 * 1024 * 1024, timeout: 10_000 },
  );
  if (committed.error || committed.status !== 0 ||
      !Buffer.from(committed.stdout).equals(source)) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "validator bytes do not belong to the claimed commit", {
      commit,
      relative,
    });
  }
}

export function validateWorldSourceIdentity(options) {
  const supplied = [options.worldValidator, options.worldCommit, options.worldValidatorSha256];
  if (supplied.some((value) => value === undefined)) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "World validator path, commit, and SHA-256 must be supplied together");
  }
  if (!COMMIT_PATTERN.test(options.worldCommit) || !DIGEST_PATTERN.test(options.worldValidatorSha256)) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "World validator commit or SHA-256 is malformed");
  }
  if (options.worldCommit !== WORLD_VALIDATOR_COMMIT ||
      options.worldValidatorSha256 !== WORLD_VALIDATOR_SHA256) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "World validator identity differs from the pinned PR 47 source", {
      expectedCommit: WORLD_VALIDATOR_COMMIT,
      observedCommit: options.worldCommit,
      expectedSha256: WORLD_VALIDATOR_SHA256,
      observedSha256: options.worldValidatorSha256,
    });
  }
  const source = readRegularBounded(options.worldValidator, 4 * 1024 * 1024, "World validator");
  const observedDigest = sha256Hex(source);
  if (observedDigest !== options.worldValidatorSha256) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "World validator digest does not match the pinned value", {
      expected: options.worldValidatorSha256, observed: observedDigest,
    });
  }
  const worldRoot = path.dirname(path.dirname(path.resolve(options.worldValidator)));
  const observedCommit = childProcess.spawnSync("git", ["-C", worldRoot, "rev-parse", "HEAD"], {
    encoding: "utf8",
    timeout: 10_000,
  });
  if (observedCommit.status !== 0 || observedCommit.stdout.trim() !== options.worldCommit) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "World validator checkout is not the pinned commit", {
      expected: options.worldCommit,
      observed: observedCommit.status === 0 ? observedCommit.stdout.trim() : null,
    });
  }
  const validatorRelative = path.relative(worldRoot, path.resolve(options.worldValidator));
  if (validatorRelative !== WORLD_VALIDATOR_RELATIVE) {
    fail("WORLD_VALIDATOR_IDENTITY_INVALID", "World validator has the wrong repository-relative path", {
      validator: options.worldValidator,
      expected: WORLD_VALIDATOR_RELATIVE,
      observed: validatorRelative,
    });
  }
  assertFileBelongsToCommit(worldRoot, options.worldCommit, validatorRelative, source);
  return Object.freeze({ source, observedDigest });
}

async function validateWithWorld(options, manifestBytes, payloadBytes) {
  const supplied = [options.worldValidator, options.worldCommit, options.worldValidatorSha256];
  if (supplied.every((value) => value === undefined)) return false;
  const { source, observedDigest } = validateWorldSourceIdentity(options);
  let module;
  try {
    module = await import(
      `data:text/javascript;base64,${source.toString("base64")}#sha256=${observedDigest}`,
    );
  } catch (error) {
    fail("WORLD_CONTRACT_REJECTED", "could not load the pinned World validator", {
      cause: error?.message ?? String(error),
    });
  }
  return validateWorldContractModule(module, manifestBytes, payloadBytes);
}

function runGit(argumentsList, label, cwd = process.cwd()) {
  const result = childProcess.spawnSync("git", argumentsList, {
    cwd,
    encoding: "utf8",
    maxBuffer: 4 * 1024 * 1024,
    timeout: 10_000,
  });
  if (result.error || result.status !== 0) {
    fail("GENERATOR_IDENTITY_INVALID", `could not ${label}`, {
      status: result.status,
      cause: result.error?.message ?? null,
      stderr: result.stderr?.slice(0, 16_384) ?? "",
    });
  }
  return result.stdout;
}

export function generatorSourceIdentity(expectedCommit = undefined) {
  const repository = runGit(["rev-parse", "--show-toplevel"], "resolve generator repository").trim();
  const head = runGit(["rev-parse", "--verify", "HEAD^{commit}"], "resolve generator HEAD", repository).trim();
  if (!COMMIT_PATTERN.test(head) ||
      (expectedCommit !== undefined && expectedCommit !== head)) {
    fail("GENERATOR_IDENTITY_INVALID", "generator commit does not equal the current repository HEAD", {
      expected: expectedCommit ?? head,
      observed: head,
    });
  }
  const status = runGit(
    ["status", "--porcelain=v1", "--untracked-files=all"],
    "inspect generator source state",
    repository,
  ).trim();
  const digestState = crypto.createHash("sha256");
  for (const sourcePath of GENERATOR_SOURCE_PATHS) {
    const absolute = path.join(repository, sourcePath);
    const bytes = readRegularBounded(absolute, 4 * 1024 * 1024, `generator source ${sourcePath}`);
    digestState.update(sourcePath);
    digestState.update("\0");
    digestState.update(String(bytes.length));
    digestState.update("\0");
    digestState.update(bytes);
    if (status.length === 0) {
      const committed = childProcess.spawnSync(
        "git",
        ["show", `${head}:${sourcePath}`],
        { cwd: repository, encoding: null, maxBuffer: 4 * 1024 * 1024, timeout: 10_000 },
      );
      if (committed.error || committed.status !== 0 || !Buffer.from(committed.stdout).equals(bytes)) {
        fail("GENERATOR_IDENTITY_INVALID", "clean generator source does not match its commit", {
          commit: head,
          sourcePath,
        });
      }
    }
  }
  return Object.freeze({
    generatorCommit: status.length === 0 ? head : null,
    generatorBaseCommit: head,
    generatorSourceSha256: digestState.digest("hex"),
    generatorWorktreeClean: status.length === 0,
  });
}

export function installDirectoryAtomic(destination, files) {
  const requested = path.resolve(destination);
  const parent = path.dirname(requested);
  const base = path.basename(requested);
  const parentStat = fs.lstatSync(parent);
  if (!parentStat.isDirectory()) {
    fail("OUTPUT_DESTINATION_INVALID", "corpus output parent must be a directory", {
      destination: requested,
    });
  }
  const absolute = path.join(fs.realpathSync(parent), base);
  const root = path.parse(absolute).root;
  const repository = path.resolve(".");
  const home = path.resolve(os.homedir());
  const contains = (ancestor, child) => {
    const relative = path.relative(ancestor, child);
    return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== "..");
  };
  if (absolute === root || contains(absolute, repository) || contains(absolute, home)) {
    fail("OUTPUT_DESTINATION_INVALID", "corpus output destination is too broad", {
      destination: absolute,
    });
  }
  const staging = fs.mkdtempSync(path.join(path.dirname(absolute), `.${base}.staging-`));
  let backup = null;
  try {
    for (const [name, bytes] of files) {
      fs.writeFileSync(path.join(staging, name), bytes, { flag: "wx", mode: 0o644 });
    }
    if (fs.existsSync(absolute)) {
      const stat = fs.lstatSync(absolute);
      if (!stat.isDirectory() || stat.isSymbolicLink()) {
        fail("OUTPUT_DESTINATION_INVALID", "corpus output destination is not a real directory", { destination: absolute });
      }
      const observed = fs.readdirSync(absolute).sort();
      const expected = [...files.keys()].sort();
      if (observed.length !== 0) {
        if (JSON.stringify(observed) !== JSON.stringify(expected)) {
          fail("OUTPUT_DESTINATION_CONFLICT", "existing corpus output inventory differs", {
            destination: absolute,
            expected,
            observed,
          });
        }
        let identical = true;
        for (const [name, bytes] of files) {
          const existing = path.join(absolute, name);
          const existingStat = fs.lstatSync(existing);
          if (!existingStat.isFile() || existingStat.isSymbolicLink()) {
            fail("OUTPUT_DESTINATION_CONFLICT", `existing corpus output ${name} is not one regular file`, {
              destination: absolute,
              name,
            });
          }
          identical &&= fs.readFileSync(existing).equals(bytes);
        }
        if (identical) {
          fs.rmSync(staging, { recursive: true, force: true });
          return;
        }
        try {
          validateCorpusBytes(
            fs.readFileSync(path.join(absolute, CORPUS_IDENTITY.manifestAssetName)),
            fs.readFileSync(path.join(absolute, CORPUS_IDENTITY.payloadAssetName)),
          );
          const priorReceipt = JSON.parse(fs.readFileSync(
            path.join(absolute, "boundary-process-v1-conformance-generation-receipt.json"),
            "utf8",
          ));
          if (priorReceipt?.format !== "boundary-process-v1-conformance-generation-receipt/v1") {
            throw new Error("wrong receipt format");
          }
        } catch (error) {
          fail("OUTPUT_DESTINATION_CONFLICT", "existing corpus output is not generator-owned", {
            destination: absolute,
            cause: error?.message ?? String(error),
          });
        }
        backup = fs.mkdtempSync(path.join(path.dirname(absolute), `.${base}.backup-`));
        fs.rmdirSync(backup);
        fs.renameSync(absolute, backup);
      }
    }
    fs.renameSync(staging, absolute);
    if (backup !== null) {
      try {
        fs.rmSync(backup, { recursive: true, force: true });
      } catch {
        // The new exact directory is already committed. A stale owned backup is
        // cleanup debt, not a failed publication of local build outputs.
      }
    }
  } catch (error) {
    if (fs.existsSync(staging)) {
      try {
        fs.rmSync(staging, { recursive: true, force: true });
      } catch {}
    }
    if (backup !== null && !fs.existsSync(absolute)) {
      try {
        fs.renameSync(backup, absolute);
      } catch {}
    }
    if (error instanceof CorpusBuildError) throw error;
    fail("OUTPUT_INSTALL_FAILED", "failed to install corpus output atomically", {
      destination: absolute, cause: error?.message ?? String(error),
    });
  }
}

function parseOptions(argv) {
  const options = {};
  const allowed = new Set([
    "--kernel", "--local-kernel", "--vector-emitter", "--capacity-emitter",
    "--output-dir", "--generator-commit", "--world-validator", "--world-commit",
    "--world-validator-sha256",
  ]);
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!allowed.has(name) || value === undefined || value.length === 0 || Object.hasOwn(options, name.slice(2))) {
      fail("CORPUS_USAGE", `invalid or duplicate argument ${name ?? "<missing>"}`);
    }
    options[name.slice(2).replaceAll(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
  }
  for (const name of ["localKernel", "vectorEmitter", "capacityEmitter", "outputDir"]) {
    if (options[name] === undefined) fail("CORPUS_USAGE", `missing --${name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`);
  }
  return options;
}

export async function buildProcessConformanceCorpus(options) {
  const releasedBytes = options.kernel === undefined
    ? await acquireReleasedKernel()
    : readRegularBounded(options.kernel, MAX_KERNEL_BYTES, "released kernel override");
  const localBytes = readRegularBounded(options.localKernel, MAX_KERNEL_BYTES, "locally rebuilt kernel");
  validateKernelPair(releasedBytes, localBytes);
  if (options.generatorCommit !== undefined && !COMMIT_PATTERN.test(options.generatorCommit)) {
    fail("GENERATOR_IDENTITY_INVALID", "generator commit must be a lowercase 40-byte Git commit");
  }
  const generatorIdentity = generatorSourceIdentity(options.generatorCommit);

  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-process-v1-corpus-"));
  try {
    const firstDirectory = path.join(temporary, "worker-1");
    const secondDirectory = path.join(temporary, "worker-2");
    fs.mkdirSync(firstDirectory);
    fs.mkdirSync(secondDirectory);
    const first = await generateWorker({
      kernelBytes: releasedBytes,
      vectorEmitter: options.vectorEmitter,
      capacityEmitter: options.capacityEmitter,
      directory: firstDirectory,
    });
    const second = await generateWorker({
      kernelBytes: releasedBytes,
      vectorEmitter: options.vectorEmitter,
      capacityEmitter: options.capacityEmitter,
      directory: secondDirectory,
    });
    const deterministic = assertDeterministic(first, second);
    if (deterministic[verifiedDeterminismBrand] !== true) {
      fail("CORPUS_NONDETERMINISTIC", "finalization requires verified independent rebuilds");
    }
    const finalBuild = deterministic.first;
    const worldContractValidated = await validateWithWorld(
      options,
      finalBuild.manifestBytes,
      finalBuild.payloadBytes,
    );
    const receipt = {
      format: "boundary-process-v1-conformance-generation-receipt/v1",
      result: generatorIdentity.generatorWorktreeClean && worldContractValidated
        ? "passed"
        : "candidate",
      semanticProducerCommit: CORPUS_IDENTITY.producer.commit,
      ...generatorIdentity,
      kernelSha256: CORPUS_IDENTITY.boundary.kernelSha256,
      kernelByteLength: CORPUS_IDENTITY.boundary.kernelByteLength,
      kernelImportCount: 0,
      kernelAbiVersion: CORPUS_IDENTITY.boundary.processKernelAbiVersion,
      vectorCount: VECTOR_DESCRIPTORS.length,
      nativeKernelParityCount: VECTOR_DESCRIPTORS.length,
      artifactCount: EXPECTED_ARTIFACT_IDS.length,
      manifestSha256: sha256Hex(finalBuild.manifestBytes),
      manifestByteLength: finalBuild.manifestBytes.length,
      payloadSha256: sha256Hex(finalBuild.payloadBytes),
      payloadByteLength: finalBuild.payloadBytes.length,
      freshVectorInstanceCount: finalBuild.freshVectorInstanceCount,
      deterministicRebuild: true,
      worldContractValidated,
      ...(worldContractValidated ? {
        worldValidatorCommit: options.worldCommit,
        worldValidatorSha256: options.worldValidatorSha256,
      } : {}),
    };
    const receiptBytes = canonicalJsonBytes(receipt);
    installDirectoryAtomic(options.outputDir, new Map([
      [CORPUS_IDENTITY.manifestAssetName, finalBuild.manifestBytes],
      [CORPUS_IDENTITY.payloadAssetName, finalBuild.payloadBytes],
      ["boundary-process-v1-conformance-generation-receipt.json", receiptBytes],
    ]));
    return Object.freeze({
      receipt,
      receiptBytes,
      manifestBytes: finalBuild.manifestBytes,
      payloadBytes: finalBuild.payloadBytes,
    });
  } finally {
    try {
      fs.rmSync(temporary, { recursive: true, force: true });
    } catch {
      // Output installation is the commit point. A temporary cleanup failure
      // must not turn a committed exact directory into an ambiguous failure.
    }
  }
}

export function buildErrorRecord(error) {
  if (error instanceof CorpusBuildError) {
    return { ok: false, code: error.code, message: error.message, details: error.details };
  }
  return {
    ok: false,
    code: "CORPUS_BUILD_FAILED",
    message: error?.message ?? String(error),
  };
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseOptions(argv);
  const result = await buildProcessConformanceCorpus(options);
  process.stdout.write(`${JSON.stringify({
    ok: true,
    format: "boundary-process-v1-conformance-build-result/v1",
    outputDirectory: path.resolve(options.outputDir),
    manifestSha256: result.receipt.manifestSha256,
    manifestByteLength: result.receipt.manifestByteLength,
    payloadSha256: result.receipt.payloadSha256,
    payloadByteLength: result.receipt.payloadByteLength,
    vectorCount: result.receipt.vectorCount,
    artifactCount: result.receipt.artifactCount,
    deterministicRebuild: result.receipt.deterministicRebuild,
    worldContractValidated: result.receipt.worldContractValidated,
  })}\n`);
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (isMain) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify(buildErrorRecord(error))}\n`);
    process.exitCode = 1;
  });
}
