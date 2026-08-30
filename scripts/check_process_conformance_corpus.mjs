#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const MAX_MANIFEST_BYTES = 4 * 1024 * 1024;
export const MAX_PAYLOAD_BYTES = 512 * 1024 * 1024;

export const CORPUS_IDENTITY = Object.freeze({
  manifestFormat: "boundary-process-v1-conformance-corpus/v1",
  manifestAssetName: "boundary-process-v1-conformance-corpus.json",
  payloadAssetName: "boundary-process-v1-conformance-corpus.bin",
  producer: Object.freeze({
    repository: "tkersey/boundary",
    releaseTag: "v1.7.0",
    releaseUrl: "https://github.com/tkersey/boundary/releases/tag/v1.7.0",
    commit: "4fd4cd959ea283a6b5af12a228f0d80a102683e3",
  }),
  boundary: Object.freeze({
    version: "1.7.0",
    commit: "4fd4cd959ea283a6b5af12a228f0d80a102683e3",
    processKernelAbiVersion: 1,
    kernelSha256: "178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0",
    kernelByteLength: 647_473,
  }),
  receipt: Object.freeze({
    format: "boundary-process-v1-parity-receipt/v1",
    vectorCount: 20,
    nativeKernelParityCount: 20,
    needsCapacityVectorId: "needs-capacity",
    nonAgentVectorId: "typed-effect-initial",
  }),
});

export const REQUIRED_SCENARIOS = Object.freeze([
  "initial-progress",
  "ordinary-progress",
  "typed-residual-effect",
  "effect-morphism",
  "recursive-call-return",
  "explicit-yield",
  "completion",
  "authored-failure-v1",
  "authored-failure-v2",
  "pending-request-reconstruction",
  "typed-resume",
  "needs-capacity",
  "non-agent",
]);

const descriptor = (id, instanceKind, effectResult, expectedKind, scenarios, operation = "execute") =>
  Object.freeze({
    id,
    operation,
    instanceKind,
    effectResult,
    expectedKind,
    scenarios: Object.freeze(scenarios),
  });

export const VECTOR_DESCRIPTORS = Object.freeze([
  descriptor("typed-effect-initial", "initialArgs", false, "Requested", ["typed-residual-effect", "non-agent"]),
  descriptor("pending-request-reconstruction", "state", false, "Requested", ["pending-request-reconstruction"]),
  descriptor("typed-resume", "state", true, "Completed", ["typed-resume", "completion"]),
  descriptor("initial-progress", "initialArgs", false, "Progressed", ["initial-progress"]),
  descriptor("explicit-yield", "initialArgs", false, "ExplicitlyYielded", ["explicit-yield"]),
  descriptor("authored-failure-v1", "initialArgs", false, "AuthoredFailure", ["authored-failure-v1"]),
  descriptor("authored-failure-v2-bad-math-progress", "initialArgs", false, "Progressed", ["authored-failure-v2"]),
  descriptor("authored-failure-v2-bad-math", "state", false, "AuthoredFailure", ["authored-failure-v2"]),
  descriptor("authored-failure-v2-bad-position-progress", "initialArgs", false, "Progressed", ["authored-failure-v2"]),
  descriptor("authored-failure-v2-bad-position", "state", false, "AuthoredFailure", ["authored-failure-v2"]),
  descriptor("authored-failure-v2-success", "initialArgs", false, "Completed", ["authored-failure-v2", "completion"]),
  descriptor("effect-morphism", "initialArgs", false, "Requested", ["effect-morphism", "typed-residual-effect"]),
  descriptor("recursion-call", "initialArgs", false, "Progressed", ["recursive-call-return", "initial-progress"]),
  descriptor("recursion-branch", "state", false, "Progressed", ["recursive-call-return", "ordinary-progress"]),
  descriptor("recursion-recur", "state", false, "Progressed", ["recursive-call-return", "ordinary-progress"]),
  descriptor("recursion-base-branch", "state", false, "Progressed", ["recursive-call-return", "ordinary-progress"]),
  descriptor("recursion-return-inner", "state", false, "Progressed", ["recursive-call-return", "ordinary-progress"]),
  descriptor("recursion-return-root", "state", false, "Progressed", ["recursive-call-return", "ordinary-progress"]),
  descriptor("recursion-complete", "state", false, "Completed", ["recursive-call-return", "completion"]),
  descriptor("needs-capacity", "initialArgs", false, "NeedsCapacity", ["needs-capacity"], "prepareInput"),
]);

export const OUTCOME_KIND_BY_BYTE = Object.freeze([
  "Progressed",
  "Requested",
  "ExplicitlyYielded",
  "Completed",
  "AuthoredFailure",
  "NeedsCapacity",
]);

const TOP_LEVEL_KEYS = Object.freeze([
  "format", "producer", "boundary", "payload", "artifacts", "vectors", "receipt",
]);
const PRODUCER_KEYS = Object.freeze(["repository", "releaseTag", "releaseUrl", "commit"]);
const BOUNDARY_KEYS = Object.freeze([
  "version", "commit", "processKernelAbiVersion", "kernelSha256", "kernelByteLength",
]);
const PAYLOAD_KEYS = Object.freeze(["assetName", "sha256", "byteLength"]);
const ARTIFACT_KEYS = Object.freeze(["id", "offset", "byteLength", "sha256"]);
const VECTOR_KEYS = Object.freeze([
  "id", "scenarios", "image", "instance", "effectResult", "expectedOutcome",
  "expectedKind", "nativeOutcomeSha256", "kernelOutcomeSha256",
]);
const INSTANCE_KEYS = Object.freeze(["kind", "artifact"]);
const RECEIPT_KEYS = Object.freeze([
  "format", "vectorCount", "nativeKernelParityCount", "needsCapacityVectorId", "nonAgentVectorId",
]);
const IDENTIFIER_PATTERN = /^[a-z0-9][a-z0-9._-]{0,127}$/;
const DIGEST_PATTERN = /^[0-9a-f]{64}$/;

export class CorpusValidationError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "CorpusValidationError";
    this.code = code;
    this.details = Object.freeze({ ...details });
  }
}

function fail(code, message, details = {}) {
  throw new CorpusValidationError(code, message, details);
}

export function sha256Hex(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function exactKeys(value, expected, label) {
  if (!isPlainObject(value)) fail("CORPUS_SCHEMA_INVALID", `${label} must be an object`, { label });
  const observed = Object.keys(value);
  const expectedSet = new Set(expected);
  for (const key of expected) {
    if (!Object.hasOwn(value, key)) {
      fail("CORPUS_SCHEMA_INVALID", `${label} is missing ${key}`, { label, key });
    }
  }
  for (const key of observed) {
    if (!expectedSet.has(key)) {
      fail("CORPUS_SCHEMA_INVALID", `${label} has unexpected field ${key}`, { label, key });
    }
  }
  if (observed.length !== expected.length ||
      observed.some((key, index) => key !== expected[index])) {
    fail("CORPUS_SCHEMA_INVALID", `${label} fields are not in canonical order`, {
      label,
      expected,
      observed,
    });
  }
}

function exactObject(value, expected, keys, label) {
  exactKeys(value, keys, label);
  for (const key of keys) {
    if (value[key] !== expected[key]) {
      fail("CORPUS_IDENTITY_MISMATCH", `${label}.${key} does not match the locked value`, {
        label: `${label}.${key}`,
        expected: expected[key],
        observed: value[key],
      });
    }
  }
}

function safeInteger(value, minimum, maximum, label) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    fail("CORPUS_SCHEMA_INVALID", `${label} is outside its admitted range`, {
      label, minimum, maximum, observed: value,
    });
  }
  return value;
}

function digest(value, label) {
  if (typeof value !== "string" || !DIGEST_PATTERN.test(value)) {
    fail("CORPUS_SCHEMA_INVALID", `${label} must be a lowercase SHA-256 digest`, { label });
  }
  return value;
}

function identifier(value, label) {
  if (typeof value !== "string" || !IDENTIFIER_PATTERN.test(value)) {
    fail("CORPUS_SCHEMA_INVALID", `${label} is not a canonical identifier`, { label, observed: value });
  }
  return value;
}

function exactArray(observed, expected, label) {
  if (!Array.isArray(observed) || observed.length !== expected.length ||
      observed.some((value, index) => value !== expected[index])) {
    fail("CORPUS_INVENTORY_MISMATCH", `${label} does not match the locked ordered inventory`, {
      label, expected, observed,
    });
  }
}

function readNatural(bytes, offset, label) {
  let value = 0n;
  let shift = 0n;
  for (let index = 0; index < 10 && offset + index < bytes.length; index += 1) {
    const byte = bytes[offset + index];
    const payload = BigInt(byte & 0x7f);
    if (shift === 63n && payload > 1n) break;
    value |= payload << shift;
    if ((byte & 0x80) === 0) {
      const length = index + 1;
      let canonicalLength = 1;
      for (let remaining = value; remaining >= 0x80n; remaining >>= 7n) canonicalLength += 1;
      if (canonicalLength !== length || value > BigInt(Number.MAX_SAFE_INTEGER)) break;
      return Object.freeze({ value: Number(value), length });
    }
    shift += 7n;
  }
  fail("CORPUS_EFFECT_INVALID", `${label} has an invalid canonical natural`, { label });
}

function parseEffectRequest(bytes, label) {
  if (bytes.length < 238 || !bytes.subarray(0, 8).equals(Buffer.from("ABL_ERQ1")) ||
      bytes.readUInt16LE(8) !== 1 || bytes.readUInt16LE(10) !== 0) {
    fail("CORPUS_EFFECT_INVALID", `${label} has a malformed ABL_ERQ1 header`, { label });
  }
  let cursor = 236;
  const identityLength = readNatural(bytes, cursor, `${label} identity length`);
  cursor += identityLength.length;
  if (identityLength.value === 0 || identityLength.value > bytes.length - cursor) {
    fail("CORPUS_EFFECT_INVALID", `${label} has an invalid semantic identity length`, { label });
  }
  let semanticIdentity;
  try {
    semanticIdentity = new TextDecoder("utf-8", { fatal: true }).decode(
      bytes.subarray(cursor, cursor + identityLength.value),
    );
  } catch {
    fail("CORPUS_EFFECT_INVALID", `${label} semantic identity is not valid UTF-8`, { label });
  }
  cursor += identityLength.value;
  const payloadLength = readNatural(bytes, cursor, `${label} payload length`);
  cursor += payloadLength.length;
  if (payloadLength.value !== bytes.length - cursor) {
    fail("CORPUS_EFFECT_INVALID", `${label} payload length does not cover the request`, { label });
  }
  return Object.freeze({
    requestIdentityDigest: bytes.subarray(12, 44),
    resumeSchemaDigest: bytes.subarray(172, 204),
    semanticIdentity,
    payload: bytes.subarray(cursor),
  });
}

function parseEffectResult(bytes, label) {
  if (bytes.length < 77 || !bytes.subarray(0, 8).equals(Buffer.from("ABL_ERS1")) ||
      bytes.readUInt16LE(8) !== 1 || bytes.readUInt16LE(10) !== 0) {
    fail("CORPUS_EFFECT_INVALID", `${label} has a malformed ABL_ERS1 header`, { label });
  }
  const resumeLength = readNatural(bytes, 76, `${label} resume length`);
  const cursor = 76 + resumeLength.length;
  if (resumeLength.value !== bytes.length - cursor) {
    fail("CORPUS_EFFECT_INVALID", `${label} resume length does not cover the result`, { label });
  }
  return Object.freeze({
    requestIdentityDigest: bytes.subarray(12, 44),
    resumeSchemaDigest: bytes.subarray(44, 76),
    resume: bytes.subarray(cursor),
  });
}

function artifactIdsFor(descriptorValue) {
  const ids = [
    `${descriptorValue.id}.image`,
    `${descriptorValue.id}.instance`,
  ];
  if (descriptorValue.effectResult) ids.push(`${descriptorValue.id}.effect-result`);
  ids.push(`${descriptorValue.id}.outcome`);
  return ids;
}

export const EXPECTED_ARTIFACT_IDS = Object.freeze(
  VECTOR_DESCRIPTORS.flatMap(artifactIdsFor),
);

export function parseManifestBytes(bytes, label = "manifest") {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 ||
      bytes.byteLength > MAX_MANIFEST_BYTES) {
    fail("CORPUS_MANIFEST_INVALID", `${label} has an invalid byte length`, {
      label, byteLength: bytes?.byteLength, maximum: MAX_MANIFEST_BYTES,
    });
  }
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("CORPUS_MANIFEST_INVALID", `${label} is not valid UTF-8`, { label });
  }
  let manifest;
  try {
    manifest = JSON.parse(text);
  } catch {
    fail("CORPUS_MANIFEST_INVALID", `${label} is not valid JSON`, { label });
  }
  const canonical = `${JSON.stringify(manifest, null, 2)}\n`;
  if (!Buffer.from(canonical, "utf8").equals(Buffer.from(bytes))) {
    fail("CORPUS_MANIFEST_NONCANONICAL", `${label} is not canonical JSON`, { label });
  }
  return manifest;
}

export function validateCanonicalOutcome(bytes, expectedKind, label = "outcome") {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength < 32) {
    fail("CORPUS_OUTCOME_INVALID", `${label} is shorter than the ABL_PKO1 header`, { label });
  }
  const outcome = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (!outcome.subarray(0, 8).equals(Buffer.from("ABL_PKO1")) ||
      outcome.readUInt16LE(8) !== 1 || outcome[10] > 5 || outcome[11] !== 0 ||
      outcome.subarray(28, 32).some((byte) => byte !== 0)) {
    fail("CORPUS_OUTCOME_INVALID", `${label} has a malformed ABL_PKO1 header`, { label });
  }
  const primaryBig = outcome.readBigUInt64LE(12);
  const secondaryBig = outcome.readBigUInt64LE(20);
  if (primaryBig > BigInt(Number.MAX_SAFE_INTEGER) || secondaryBig > BigInt(Number.MAX_SAFE_INTEGER)) {
    fail("CORPUS_OUTCOME_INVALID", `${label} has unaddressable payload lengths`, { label });
  }
  const primary = Number(primaryBig);
  const secondary = Number(secondaryBig);
  if (32 + primary + secondary !== outcome.length) {
    fail("CORPUS_OUTCOME_INVALID", `${label} payload lengths do not cover the outcome`, { label });
  }
  if (outcome[10] !== 1 && secondary !== 0) {
    fail("CORPUS_OUTCOME_INVALID", `${label} has a secondary payload for a non-Requested kind`, { label });
  }
  if (outcome[10] === 5 && (primary !== 32 || secondary !== 0 || outcome.length !== 64)) {
    fail("CORPUS_OUTCOME_INVALID", `${label} has a malformed NeedsCapacity payload`, { label });
  }
  const actualKind = OUTCOME_KIND_BY_BYTE[outcome[10]];
  if (actualKind !== expectedKind) {
    fail("CORPUS_OUTCOME_KIND_MISMATCH", `${label} kind does not match the vector`, {
      label, expected: expectedKind, observed: actualKind,
    });
  }
  return Object.freeze({
    kind: actualKind,
    primaryByteLength: primary,
    secondaryByteLength: secondary,
  });
}

export function validateBoundaryProcessCorpusManifest(manifest) {
  exactKeys(manifest, TOP_LEVEL_KEYS, "manifest");
  if (manifest.format !== CORPUS_IDENTITY.manifestFormat) {
    fail("CORPUS_IDENTITY_MISMATCH", "manifest.format does not match the locked value");
  }
  exactObject(manifest.producer, CORPUS_IDENTITY.producer, PRODUCER_KEYS, "manifest.producer");
  exactObject(manifest.boundary, CORPUS_IDENTITY.boundary, BOUNDARY_KEYS, "manifest.boundary");

  exactKeys(manifest.payload, PAYLOAD_KEYS, "manifest.payload");
  if (manifest.payload.assetName !== CORPUS_IDENTITY.payloadAssetName) {
    fail("CORPUS_IDENTITY_MISMATCH", "manifest.payload.assetName does not match the locked value");
  }
  const payloadByteLength = safeInteger(
    manifest.payload.byteLength, 1, MAX_PAYLOAD_BYTES, "manifest.payload.byteLength",
  );
  const payloadSha256 = digest(manifest.payload.sha256, "manifest.payload.sha256");

  if (!Array.isArray(manifest.artifacts) || manifest.artifacts.length !== EXPECTED_ARTIFACT_IDS.length) {
    fail("CORPUS_INVENTORY_MISMATCH", "manifest.artifacts must contain exactly 61 records", {
      expected: EXPECTED_ARTIFACT_IDS.length,
      observed: manifest.artifacts?.length,
    });
  }
  const artifacts = new Map();
  let cursor = 0;
  for (let index = 0; index < manifest.artifacts.length; index += 1) {
    const artifact = manifest.artifacts[index];
    const label = `manifest.artifacts[${index}]`;
    exactKeys(artifact, ARTIFACT_KEYS, label);
    const id = identifier(artifact.id, `${label}.id`);
    if (id !== EXPECTED_ARTIFACT_IDS[index]) {
      fail("CORPUS_INVENTORY_MISMATCH", `${label}.id does not match payload order`, {
        expected: EXPECTED_ARTIFACT_IDS[index], observed: id,
      });
    }
    if (artifacts.has(id)) fail("CORPUS_INVENTORY_MISMATCH", `duplicate artifact id ${id}`, { id });
    const offset = safeInteger(artifact.offset, 0, payloadByteLength, `${label}.offset`);
    const byteLength = safeInteger(artifact.byteLength, 0, payloadByteLength, `${label}.byteLength`);
    if (offset !== cursor) {
      fail("CORPUS_PARTITION_INVALID", `${label} creates a gap, overlap, or order drift`, {
        id, expectedOffset: cursor, observedOffset: offset,
      });
    }
    if (byteLength > payloadByteLength - offset) {
      fail("CORPUS_PARTITION_INVALID", `${label} extends outside the payload`, { id, offset, byteLength });
    }
    const normalized = Object.freeze({
      id,
      offset,
      byteLength,
      sha256: digest(artifact.sha256, `${label}.sha256`),
    });
    artifacts.set(id, normalized);
    cursor += byteLength;
  }
  if (cursor !== payloadByteLength) {
    fail("CORPUS_PARTITION_INVALID", "artifact table does not cover the complete payload", {
      coveredBytes: cursor, payloadByteLength,
    });
  }

  if (!Array.isArray(manifest.vectors) || manifest.vectors.length !== VECTOR_DESCRIPTORS.length) {
    fail("CORPUS_INVENTORY_MISMATCH", "manifest.vectors must contain exactly 20 vectors", {
      expected: VECTOR_DESCRIPTORS.length, observed: manifest.vectors?.length,
    });
  }
  const referencedArtifacts = [];
  const scenarioSet = new Set();
  const vectors = [];
  for (let index = 0; index < VECTOR_DESCRIPTORS.length; index += 1) {
    const expected = VECTOR_DESCRIPTORS[index];
    const vector = manifest.vectors[index];
    const label = `manifest.vectors[${index}]`;
    exactKeys(vector, VECTOR_KEYS, label);
    identifier(vector.id, `${label}.id`);
    if (vector.id !== expected.id) {
      fail("CORPUS_INVENTORY_MISMATCH", `${label}.id does not match the locked vector order`, {
        expected: expected.id, observed: vector.id,
      });
    }
    if (vector.scenarios.length === 0 || new Set(vector.scenarios).size !== vector.scenarios.length) {
      fail("CORPUS_SCENARIO_INVALID", `${label}.scenarios must be nonempty and unique`, { id: vector.id });
    }
    for (const scenario of vector.scenarios) {
      if (!REQUIRED_SCENARIOS.includes(scenario)) {
        fail("CORPUS_SCENARIO_INVALID", `${label}.scenarios contains unknown scenario ${scenario}`, {
          id: vector.id, scenario,
        });
      }
      scenarioSet.add(scenario);
    }
    exactArray(vector.scenarios, expected.scenarios, `${label}.scenarios`);
    const image = `${expected.id}.image`;
    const instanceArtifact = `${expected.id}.instance`;
    const effectResult = expected.effectResult ? `${expected.id}.effect-result` : null;
    const expectedOutcome = `${expected.id}.outcome`;
    if (vector.image !== image || !artifacts.has(vector.image)) {
      fail("CORPUS_REFERENCE_INVALID", `${label}.image is not the vector-local image artifact`, { id: vector.id });
    }
    exactKeys(vector.instance, INSTANCE_KEYS, `${label}.instance`);
    if (vector.instance.kind !== expected.instanceKind || vector.instance.artifact !== instanceArtifact ||
        !artifacts.has(vector.instance.artifact)) {
      fail("CORPUS_REFERENCE_INVALID", `${label}.instance does not match the locked vector contract`, {
        id: vector.id,
      });
    }
    if (vector.effectResult !== effectResult || (effectResult !== null && !artifacts.has(effectResult))) {
      fail("CORPUS_REFERENCE_INVALID", `${label}.effectResult does not match the locked vector contract`, {
        id: vector.id,
      });
    }
    if (vector.expectedOutcome !== expectedOutcome || !artifacts.has(vector.expectedOutcome)) {
      fail("CORPUS_REFERENCE_INVALID", `${label}.expectedOutcome is not the vector-local outcome`, {
        id: vector.id,
      });
    }
    if (vector.expectedKind !== expected.expectedKind) {
      fail("CORPUS_OUTCOME_KIND_MISMATCH", `${label}.expectedKind does not match the locked vector contract`, {
        id: vector.id, expected: expected.expectedKind, observed: vector.expectedKind,
      });
    }
    const expectedDigest = artifacts.get(expectedOutcome).sha256;
    const nativeDigest = digest(vector.nativeOutcomeSha256, `${label}.nativeOutcomeSha256`);
    const kernelDigest = digest(vector.kernelOutcomeSha256, `${label}.kernelOutcomeSha256`);
    if (nativeDigest !== expectedDigest || kernelDigest !== expectedDigest) {
      fail("CORPUS_PARITY_INVALID", `${label} does not bind native, kernel, and expected bytes`, {
        id: vector.id, expectedDigest, nativeDigest, kernelDigest,
      });
    }
    referencedArtifacts.push(image, instanceArtifact);
    if (effectResult !== null) referencedArtifacts.push(effectResult);
    referencedArtifacts.push(expectedOutcome);
    vectors.push(Object.freeze({ descriptor: expected, vector }));
  }
  if (scenarioSet.size !== REQUIRED_SCENARIOS.length ||
      REQUIRED_SCENARIOS.some((scenario) => !scenarioSet.has(scenario))) {
    fail("CORPUS_SCENARIO_INVALID", "manifest does not cover exactly the 13 required scenarios", {
      expected: REQUIRED_SCENARIOS,
      observed: [...scenarioSet],
    });
  }
  exactArray(referencedArtifacts, EXPECTED_ARTIFACT_IDS, "manifest artifact references");

  exactObject(manifest.receipt, CORPUS_IDENTITY.receipt, RECEIPT_KEYS, "manifest.receipt");
  return Object.freeze({
    manifest,
    payload: Object.freeze({
      assetName: CORPUS_IDENTITY.payloadAssetName,
      byteLength: payloadByteLength,
      sha256: payloadSha256,
    }),
    artifacts,
    vectors: Object.freeze(vectors),
  });
}

export function validateBundlePayload(validated, payloadBytes) {
  if (!(payloadBytes instanceof Uint8Array)) {
    fail("CORPUS_PAYLOAD_INVALID", "payload must be bytes");
  }
  if (payloadBytes.byteLength > MAX_PAYLOAD_BYTES ||
      payloadBytes.byteLength !== validated.payload.byteLength) {
    fail("CORPUS_PAYLOAD_INVALID", "payload byte length does not match the manifest", {
      expected: validated.payload.byteLength, observed: payloadBytes.byteLength,
    });
  }
  const payload = Buffer.from(payloadBytes.buffer, payloadBytes.byteOffset, payloadBytes.byteLength);
  const actualPayloadDigest = sha256Hex(payload);
  if (actualPayloadDigest !== validated.payload.sha256) {
    fail("CORPUS_PAYLOAD_INVALID", "payload digest does not match the manifest", {
      expected: validated.payload.sha256, observed: actualPayloadDigest,
    });
  }
  const files = new Map();
  for (const [id, artifact] of validated.artifacts) {
    const bytes = payload.subarray(artifact.offset, artifact.offset + artifact.byteLength);
    const observed = sha256Hex(bytes);
    if (observed !== artifact.sha256) {
      fail("CORPUS_ARTIFACT_INVALID", `artifact ${id} digest mismatch`, {
        id, expected: artifact.sha256, observed,
      });
    }
    files.set(id, bytes);
  }
  for (const { descriptor: expected } of validated.vectors) {
    validateCanonicalOutcome(
      files.get(`${expected.id}.outcome`), expected.expectedKind, `${expected.id}.outcome`,
    );
  }
  const initialRequest = files.get("typed-effect-initial.outcome");
  const reconstructedRequest = files.get("pending-request-reconstruction.outcome");
  const requestPrimaryLength = Number(initialRequest.readBigUInt64LE(12));
  const requestSecondaryLength = Number(initialRequest.readBigUInt64LE(20));
  const requestState = initialRequest.subarray(32, 32 + requestPrimaryLength);
  const requestBytes = initialRequest.subarray(
    32 + requestPrimaryLength,
    32 + requestPrimaryLength + requestSecondaryLength,
  );
  if (!initialRequest.equals(reconstructedRequest) || requestSecondaryLength === 0 ||
      !files.get("pending-request-reconstruction.instance").equals(requestState) ||
      !files.get("typed-resume.instance").equals(requestState)) {
    fail(
      "CORPUS_VECTOR_RELATION_INVALID",
      "pending request reconstruction and typed resume do not preserve the exact pending state/request",
    );
  }
  const typedResume = files.get("typed-resume.outcome");
  const typedResumePrimary = Number(typedResume.readBigUInt64LE(12));
  if (typedResumePrimary !== 4 || typedResume.readUInt32LE(32) !== 29) {
    fail("CORPUS_VECTOR_RELATION_INVALID", "typed-resume does not complete with canonical u32 value 29");
  }
  const typedRequest = parseEffectRequest(requestBytes, "typed-effect-initial request");
  const typedResult = parseEffectResult(files.get("typed-resume.effect-result"), "typed-resume EffectResult");
  if (typedRequest.semanticIdentity !== "process.kernel.fixture.lookup.v1" ||
      typedRequest.payload.length !== 4 || typedRequest.payload.readUInt32LE(0) !== 17 ||
      !typedResult.requestIdentityDigest.equals(typedRequest.requestIdentityDigest) ||
      !typedResult.resumeSchemaDigest.equals(typedRequest.resumeSchemaDigest) ||
      typedResult.resume.length !== 4 || typedResult.resume.readUInt32LE(0) !== 29) {
    fail("CORPUS_VECTOR_RELATION_INVALID", "typed effect request/result does not bind u32 17 to matching u32 resume 29");
  }
  const morphismOutcome = files.get("effect-morphism.outcome");
  const morphismPrimary = Number(morphismOutcome.readBigUInt64LE(12));
  const morphismSecondary = Number(morphismOutcome.readBigUInt64LE(20));
  const morphismRequest = parseEffectRequest(
    morphismOutcome.subarray(32 + morphismPrimary, 32 + morphismPrimary + morphismSecondary),
    "effect-morphism request",
  );
  if (morphismRequest.semanticIdentity !== "residual.lookup.v2" ||
      morphismRequest.payload.length !== 4 || morphismRequest.payload.readUInt32LE(0) !== 7) {
    fail("CORPUS_VECTOR_RELATION_INVALID", "effect-morphism does not preserve residual.lookup.v2 with u32 payload 7");
  }
  const primaryBytes = (id) => {
    const outcome = files.get(`${id}.outcome`);
    const length = Number(outcome.readBigUInt64LE(12));
    return outcome.subarray(32, 32 + length);
  };
  for (const [id, expectedTag] of [
    ["authored-failure-v1", 0],
    ["authored-failure-v2-bad-math", 0],
    ["authored-failure-v2-bad-position", 1],
  ]) {
    const failure = primaryBytes(id);
    if (failure.length !== 4 || failure.readUInt32LE(0) !== expectedTag) {
      fail("CORPUS_VECTOR_RELATION_INVALID", `${id} does not contain the locked authored-failure tag`);
    }
  }
  const division = primaryBytes("authored-failure-v2-success");
  if (division.length !== 1 || division[0] !== 4) {
    fail("CORPUS_VECTOR_RELATION_INVALID", "authored-failure-v2-success does not contain quotient 4");
  }
  const recursionFrames = [2, 2, 3, 3, 2, 1];
  for (let index = 0; index < recursionFrames.length; index += 1) {
    const id = VECTOR_DESCRIPTORS[12 + index].id;
    const state = primaryBytes(id);
    if (state.length < 45 || !state.subarray(0, 8).equals(Buffer.from("ABL_PST1")) ||
        state.readUInt16LE(8) !== 1 || state.readUInt16LE(10) !== 0) {
      fail("CORPUS_VECTOR_RELATION_INVALID", `${id} does not contain canonical Process State`);
    }
    const frameCount = readNatural(state, 44, `${id} frame count`);
    if (frameCount.value !== recursionFrames[index]) {
      fail("CORPUS_VECTOR_RELATION_INVALID", `${id} has the wrong recursive frame count`, {
        expected: recursionFrames[index],
        observed: frameCount.value,
      });
    }
  }
  const recursionComplete = files.get("recursion-complete.outcome");
  const recursionPrimary = Number(recursionComplete.readBigUInt64LE(12));
  if (recursionPrimary !== 4 || recursionComplete.readUInt32LE(32) !== 1) {
    fail("CORPUS_VECTOR_RELATION_INVALID", "recursion-complete does not return canonical u32 value 1");
  }
  const needsImage = files.get("needs-capacity.image");
  const needsInstance = files.get("needs-capacity.instance");
  const needsOutcome = files.get("needs-capacity.outcome");
  if (needsImage.length !== 746 ||
      sha256Hex(needsImage) !== "b62f6ea3a307fc600be79894ebd242fa07d8972e90c34194dd4219ecfc427d00" ||
      needsInstance.length !== 33_553_647 ||
      sha256Hex(needsInstance) !== "c039e4fb3ff6b2f59a9cc823a84e56c4db7cdf21033ce6496d04d6cbd1e9da28" ||
      40 + needsImage.length + needsInstance.length !== 33_554_433 ||
      needsOutcome.readBigUInt64LE(32) !== 33_554_433n ||
      needsOutcome.readBigUInt64LE(40) !== 64n ||
      needsOutcome.readBigUInt64LE(48) !== 0n ||
      needsOutcome.readBigUInt64LE(56) !== 2_457n) {
    fail("CORPUS_VECTOR_RELATION_INVALID", "needs-capacity does not bind the exact default-kernel preflight witness");
  }
  return files;
}

export function validateCorpusBytes(manifestBytes, payloadBytes) {
  const manifest = parseManifestBytes(manifestBytes);
  const validated = validateBoundaryProcessCorpusManifest(manifest);
  const files = validateBundlePayload(validated, payloadBytes);
  return Object.freeze({ validated, files });
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export function validationErrorRecord(error) {
  if (error instanceof CorpusValidationError) {
    return { ok: false, code: error.code, message: error.message, details: error.details };
  }
  return {
    ok: false,
    code: "CORPUS_VALIDATION_FAILED",
    message: error?.message ?? String(error),
  };
}

export function main(argv = process.argv.slice(2)) {
  if (argv.length !== 2) {
    throw new CorpusValidationError(
      "CORPUS_USAGE",
      "usage: node scripts/check_process_conformance_corpus.mjs MANIFEST PAYLOAD",
    );
  }
  const readBounded = (file, maximum, label) => {
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size <= 0 || stat.size > maximum) {
      fail("CORPUS_INPUT_INVALID", `${label} must be a bounded regular file`, {
        file, byteLength: stat.size, maximum,
      });
    }
    return fs.readFileSync(file);
  };
  const manifestBytes = readBounded(argv[0], MAX_MANIFEST_BYTES, "manifest");
  const payloadBytes = readBounded(argv[1], MAX_PAYLOAD_BYTES, "payload");
  const { validated } = validateCorpusBytes(manifestBytes, payloadBytes);
  process.stdout.write(`${JSON.stringify({
    ok: true,
    format: "boundary-process-v1-conformance-validation/v1",
    manifestSha256: sha256Hex(manifestBytes),
    manifestByteLength: manifestBytes.length,
    payloadSha256: validated.payload.sha256,
    payloadByteLength: validated.payload.byteLength,
    vectorCount: VECTOR_DESCRIPTORS.length,
    artifactCount: EXPECTED_ARTIFACT_IDS.length,
    declaredParityBindingCount: VECTOR_DESCRIPTORS.length,
  })}\n`);
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (isMain) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify(validationErrorRecord(error))}\n`);
    process.exitCode = 1;
  }
}
