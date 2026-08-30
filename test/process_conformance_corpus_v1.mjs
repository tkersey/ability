#!/usr/bin/env node

import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  CORPUS_IDENTITY,
  CorpusValidationError,
  EXPECTED_ARTIFACT_IDS,
  MAX_MANIFEST_BYTES,
  MAX_PAYLOAD_BYTES,
  VECTOR_DESCRIPTORS,
  canonicalJsonBytes,
  main as validateCorpusMain,
  parseManifestBytes,
  sha256Hex,
  validateBoundaryProcessCorpusManifest,
  validateCorpusBytes,
} from "../scripts/check_process_conformance_corpus.mjs";
import {
  acquireReleasedKernel,
  assertFileBelongsToCommit,
  assertByteIdenticalLocalKernel,
  assertDeterministic,
  buildCorpusFromParityRecords,
  CorpusBuildError,
  generatorSourceIdentity,
  installDirectoryAtomic,
  parseKernelInput,
  resolveReleaseTagCommit,
  validateExactKernelBytes,
  validateInstanceIdentity,
  validateKernelModuleShape,
  validateWorldContractModule,
} from "../scripts/build_process_conformance_corpus.mjs";

const [manifestPath, payloadPath, kernelPath] = process.argv.slice(2);
if (manifestPath === undefined || payloadPath === undefined || process.argv.length > 5) {
  throw new Error(
    "usage: node test/process_conformance_corpus_v1.mjs MANIFEST PAYLOAD [EXACT_KERNEL]",
  );
}

const manifestBytes = fs.readFileSync(manifestPath);
const payloadBytes = fs.readFileSync(payloadPath);
const valid = validateCorpusBytes(manifestBytes, payloadBytes);
if (kernelPath !== undefined) validateExactKernelBytes(fs.readFileSync(kernelPath));

const baseManifest = valid.validated.manifest;
let negativeCaseCount = 0;

function cloneManifest() {
  return JSON.parse(JSON.stringify(baseManifest));
}

function expectReject(label, operation, ErrorType, expectedCodes = []) {
  let rejected = false;
  try {
    operation();
  } catch (error) {
    if (!(error instanceof ErrorType) ||
        (expectedCodes.length !== 0 && !expectedCodes.includes(error.code))) {
      throw new Error(
        `negative gate ${label} failed at the wrong boundary: ${error?.stack ?? error}`,
      );
    }
    rejected = true;
  }
  if (!rejected) throw new Error(`negative gate accepted ${label}`);
  negativeCaseCount += 1;
}

async function expectRejectAsync(label, operation, ErrorType, expectedCodes = []) {
  let rejected = false;
  try {
    await operation();
  } catch (error) {
    if (!(error instanceof ErrorType) ||
        (expectedCodes.length !== 0 && !expectedCodes.includes(error.code))) {
      throw new Error(
        `negative gate ${label} failed at the wrong boundary: ${error?.stack ?? error}`,
      );
    }
    rejected = true;
  }
  if (!rejected) throw new Error(`negative gate accepted ${label}`);
  negativeCaseCount += 1;
}

function rejectManifest(label, mutate, expectedCode = null, payload = payloadBytes) {
  expectReject(label, () => {
    const candidate = cloneManifest();
    mutate(candidate);
    validateCorpusBytes(canonicalJsonBytes(candidate), payload);
  }, CorpusValidationError, expectedCode === null ? [] : [expectedCode]);
}

function refreshDigests(manifest, payload) {
  manifest.payload.byteLength = payload.length;
  manifest.payload.sha256 = sha256Hex(payload);
  const artifacts = new Map();
  for (const artifact of manifest.artifacts) {
    artifact.sha256 = sha256Hex(payload.subarray(artifact.offset, artifact.offset + artifact.byteLength));
    artifacts.set(artifact.id, artifact);
  }
  for (const vector of manifest.vectors) {
    const expected = artifacts.get(vector.expectedOutcome);
    if (expected !== undefined) {
      vector.nativeOutcomeSha256 = expected.sha256;
      vector.kernelOutcomeSha256 = expected.sha256;
    }
  }
}

function rejectPayloadMutation(label, artifactId, mutate, expectedCode = null) {
  expectReject(label, () => {
    const candidate = cloneManifest();
    const payload = Buffer.from(payloadBytes);
    const artifact = candidate.artifacts.find((value) => value.id === artifactId);
    if (artifact === undefined) throw new Error(`missing fixture artifact ${artifactId}`);
    mutate(payload.subarray(artifact.offset, artifact.offset + artifact.byteLength));
    refreshDigests(candidate, payload);
    validateCorpusBytes(canonicalJsonBytes(candidate), payload);
  }, CorpusValidationError, expectedCode === null ? [] : [expectedCode]);
}

// Locked producer, Boundary, and kernel identity.
for (const [label, mutation] of [
  ["wrong producer repository", (manifest) => { manifest.producer.repository = "example/boundary"; }],
  ["wrong release tag", (manifest) => { manifest.producer.releaseTag = "v1.7.1"; }],
  ["wrong release URL", (manifest) => { manifest.producer.releaseUrl += "/wrong"; }],
  ["wrong producer commit", (manifest) => { manifest.producer.commit = "0".repeat(40); }],
  ["wrong Boundary version", (manifest) => { manifest.boundary.version = "1.7.1"; }],
  ["wrong Boundary commit", (manifest) => { manifest.boundary.commit = "0".repeat(40); }],
  ["wrong kernel digest", (manifest) => { manifest.boundary.kernelSha256 = "0".repeat(64); }],
  ["wrong kernel length", (manifest) => { manifest.boundary.kernelByteLength += 1; }],
  ["wrong kernel ABI", (manifest) => { manifest.boundary.processKernelAbiVersion = 2; }],
]) rejectManifest(label, mutation);

// Exact scenario and vector inventories.
rejectManifest("missing required scenario", (manifest) => { manifest.vectors[0].scenarios.pop(); });
rejectManifest("unknown scenario", (manifest) => { manifest.vectors[0].scenarios[0] = "unknown"; });
rejectManifest("empty scenario array", (manifest) => { manifest.vectors[3].scenarios = []; });
rejectManifest("duplicate scenario", (manifest) => {
  manifest.vectors[0].scenarios.push(manifest.vectors[0].scenarios[0]);
});
rejectManifest("missing vector", (manifest) => { manifest.vectors.pop(); });
rejectManifest("extra vector", (manifest) => { manifest.vectors.push(structuredClone(manifest.vectors[0])); });
rejectManifest("vector order drift", (manifest) => {
  [manifest.vectors[0], manifest.vectors[1]] = [manifest.vectors[1], manifest.vectors[0]];
});
rejectManifest("duplicate vector id", (manifest) => { manifest.vectors[1].id = manifest.vectors[0].id; });
rejectManifest("invalid vector id", (manifest) => { manifest.vectors[0].id = "Not-Canonical"; });
rejectManifest("wrong instance kind", (manifest) => { manifest.vectors[0].instance.kind = "state"; });
rejectManifest("EffectResult on another vector", (manifest) => {
  manifest.vectors[0].effectResult = manifest.vectors[0].instance.artifact;
});
rejectManifest("missing typed-resume EffectResult", (manifest) => { manifest.vectors[2].effectResult = null; });
rejectManifest("wrong expected kind", (manifest) => { manifest.vectors[0].expectedKind = "Completed"; });
rejectManifest("native digest divergence", (manifest) => {
  manifest.vectors[0].nativeOutcomeSha256 = "0".repeat(64);
});
rejectManifest("kernel digest divergence", (manifest) => {
  manifest.vectors[0].kernelOutcomeSha256 = "0".repeat(64);
});
rejectManifest("expected artifact digest divergence", (manifest) => {
  manifest.vectors[0].nativeOutcomeSha256 = "0".repeat(64);
  manifest.vectors[0].kernelOutcomeSha256 = "0".repeat(64);
});

// Canonical ABL_PKO1 syntax and kind binding, with all digests recomputed so
// rejection cannot be credited to a stale hash.
rejectPayloadMutation("malformed PKO1", "typed-effect-initial.outcome", (bytes) => { bytes[0] ^= 1; }, "CORPUS_OUTCOME_INVALID");
rejectPayloadMutation("high-bit PKO1 magic", "typed-effect-initial.outcome", (bytes) => { bytes[0] |= 0x80; }, "CORPUS_OUTCOME_INVALID");
rejectPayloadMutation("PKO1 kind mismatch", "recursion-complete.outcome", (bytes) => { bytes[10] = 0; }, "CORPUS_OUTCOME_KIND_MISMATCH");
rejectPayloadMutation("high-bit ERQ1 magic", "typed-effect-initial.outcome", (bytes) => {
  const primary = Number(bytes.readBigUInt64LE(12));
  bytes[32 + primary] |= 0x80;
});
rejectPayloadMutation("high-bit ERS1 magic", "typed-resume.effect-result", (bytes) => { bytes[0] |= 0x80; }, "CORPUS_EFFECT_INVALID");
rejectPayloadMutation("authored failure tag drift", "authored-failure-v2-bad-math.outcome", (bytes) => {
  bytes.writeUInt32LE(99, 32);
});
rejectPayloadMutation("authored success quotient drift", "authored-failure-v2-success.outcome", (bytes) => {
  bytes[32] = 5;
});
expectReject("high-bit PKI1 magic", () => {
  const bytes = encodeKernelInput(VECTOR_DESCRIPTORS[0], valid.files);
  bytes[0] |= 0x80;
  parseKernelInput(bytes);
}, CorpusBuildError, ["NATIVE_STREAM_INVALID"]);

// Exact vector-local artifact inventory and complete ordered partition.
rejectManifest("duplicate artifact id", (manifest) => { manifest.artifacts[1].id = manifest.artifacts[0].id; });
rejectManifest("invalid artifact id", (manifest) => { manifest.artifacts[0].id = "Invalid"; });
rejectManifest("artifact gap", (manifest) => { manifest.artifacts[1].offset += 1; }, "CORPUS_PARTITION_INVALID");
rejectManifest("artifact overlap", (manifest) => { manifest.artifacts[1].offset -= 1; }, "CORPUS_PARTITION_INVALID");
rejectManifest("artifact outside payload", (manifest) => {
  const artifact = manifest.artifacts.at(-1);
  artifact.byteLength = manifest.payload.byteLength;
}, "CORPUS_PARTITION_INVALID");
rejectManifest("payload not fully covered", (manifest) => {
  manifest.artifacts.at(-1).byteLength -= 1;
}, "CORPUS_PARTITION_INVALID");
rejectManifest("unreferenced artifact", (manifest) => {
  manifest.vectors[0].image = manifest.vectors[1].image;
});
rejectManifest("artifact digest mismatch", (manifest) => { manifest.artifacts[0].sha256 = "0".repeat(64); });
rejectManifest("payload digest mismatch", (manifest) => { manifest.payload.sha256 = "0".repeat(64); });

// Closed manifest schema and operational bounds.
rejectManifest("manifest unexpected field", (manifest) => { manifest.unexpected = true; });
rejectManifest("manifest missing field", (manifest) => { delete manifest.receipt; });
expectReject("manifest field order drift", () => {
  const entries = Object.entries(cloneManifest());
  [entries[0], entries[1]] = [entries[1], entries[0]];
  validateCorpusBytes(canonicalJsonBytes(Object.fromEntries(entries)), payloadBytes);
}, CorpusValidationError, ["CORPUS_SCHEMA_INVALID"]);
expectReject(
  "manifest over 4 MiB",
  () => parseManifestBytes(Buffer.from(`${JSON.stringify("x".repeat(MAX_MANIFEST_BYTES))}\n`)),
  CorpusValidationError,
  ["CORPUS_MANIFEST_INVALID"],
);
expectReject("payload over 512 MiB", () => {
  const manifest = cloneManifest();
  const increase = MAX_PAYLOAD_BYTES + 1 - manifest.payload.byteLength;
  manifest.payload.byteLength = MAX_PAYLOAD_BYTES + 1;
  manifest.artifacts.at(-1).byteLength += increase;
  validateBoundaryProcessCorpusManifest(manifest);
}, CorpusValidationError, ["CORPUS_SCHEMA_INVALID"]);
expectReject("noncanonical manifest JSON", () => {
  parseManifestBytes(Buffer.from(JSON.stringify(baseManifest), "utf8"));
}, CorpusValidationError);

// Builder-only kernel, determinism, parity, release, and World gates.
const importedMemoryModule = new WebAssembly.Module(Buffer.from(
  "0061736d01000000020801016d0178020001",
  "hex",
));
expectReject(
  "kernel imports",
  () => validateKernelModuleShape(importedMemoryModule),
  CorpusBuildError,
  ["KERNEL_IMPORTS_PRESENT"],
);
expectReject(
  "kernel runtime ABI mismatch",
  () => validateInstanceIdentity({ boundary_process_kernel_abi_version: () => 2 }, "fixture kernel"),
  CorpusBuildError,
  ["KERNEL_ABI_MISMATCH"],
);
expectReject("local kernel differing from release", () => {
  assertByteIdenticalLocalKernel(Buffer.from([0]), Buffer.from([1]));
}, CorpusBuildError, ["LOCAL_KERNEL_MISMATCH"]);
expectReject("nondeterministic rebuild", () => {
  assertDeterministic(
    { manifestBytes, payloadBytes, freshVectorInstanceCount: VECTOR_DESCRIPTORS.length },
    {
      manifestBytes: Buffer.from(manifestBytes),
      payloadBytes: Buffer.concat([payloadBytes, Buffer.from([0])]),
      freshVectorInstanceCount: VECTOR_DESCRIPTORS.length,
    },
  );
}, CorpusBuildError, ["CORPUS_NONDETERMINISTIC"]);
expectReject(
  "generator commit not equal to HEAD",
  () => generatorSourceIdentity("0".repeat(40)),
  CorpusBuildError,
  ["GENERATOR_IDENTITY_INVALID"],
);

const responseJson = (value) => ({
  ok: true,
  status: 200,
  json: async () => value,
  arrayBuffer: async () => Buffer.alloc(0),
});
await expectRejectAsync(
  "release tag target drift",
  () => resolveReleaseTagCommit(async () =>
    responseJson({ object: { type: "commit", sha: "0".repeat(40) } })),
  CorpusBuildError,
  ["RELEASE_TAG_DRIFT"],
);

function releaseFetch(asset, downloadBytes = null) {
  return async (url) => {
    if (url.includes("/git/ref/tags/")) {
      return responseJson({ object: { type: "commit", sha: CORPUS_IDENTITY.producer.commit } });
    }
    if (url.includes("/releases/tags/")) {
      return responseJson({ tag_name: CORPUS_IDENTITY.producer.releaseTag, assets: [asset] });
    }
    if (downloadBytes !== null && url === asset.browser_download_url) {
      return {
        ok: true,
        status: 200,
        arrayBuffer: async () => downloadBytes,
      };
    }
    throw new Error(`unexpected mock fetch ${url}`);
  };
}
await expectRejectAsync("release asset byte-length mismatch", () => acquireReleasedKernel(releaseFetch({
  name: "boundary-process-kernel-v1.wasm",
  size: CORPUS_IDENTITY.boundary.kernelByteLength + 1,
  digest: `sha256:${CORPUS_IDENTITY.boundary.kernelSha256}`,
  browser_download_url: "https://example.invalid/kernel.wasm",
})), CorpusBuildError, ["RELEASE_ASSET_LENGTH_MISMATCH"]);
await expectRejectAsync("release asset digest mismatch", () => acquireReleasedKernel(releaseFetch({
  name: "boundary-process-kernel-v1.wasm",
  size: CORPUS_IDENTITY.boundary.kernelByteLength,
  digest: `sha256:${"0".repeat(64)}`,
  browser_download_url: "https://example.invalid/kernel.wasm",
})), CorpusBuildError, ["RELEASE_ASSET_DIGEST_MISMATCH"]);
const exactReleaseMetadata = {
  name: "boundary-process-kernel-v1.wasm",
  size: CORPUS_IDENTITY.boundary.kernelByteLength,
  digest: `sha256:${CORPUS_IDENTITY.boundary.kernelSha256}`,
  browser_download_url: "https://example.invalid/kernel.wasm",
};
await expectRejectAsync(
  "downloaded release asset digest mismatch",
  () => acquireReleasedKernel(releaseFetch(
    exactReleaseMetadata,
    Buffer.alloc(CORPUS_IDENTITY.boundary.kernelByteLength),
  )),
  CorpusBuildError,
  ["KERNEL_IDENTITY_MISMATCH"],
);
expectReject("World contract rejection", () => validateWorldContractModule({
  parseManifestBytes: () => { throw new Error("rejected"); },
  validateBoundaryProcessCorpusManifest: () => {},
  validateBundlePayload: () => {},
}, manifestBytes, payloadBytes), CorpusBuildError, ["WORLD_CONTRACT_REJECTED"]);
expectReject("World manifest rejection", () => validateWorldContractModule({
  parseManifestBytes: () => ({}),
  validateBoundaryProcessCorpusManifest: () => { throw new Error("rejected"); },
  validateBundlePayload: () => {},
}, manifestBytes, payloadBytes), CorpusBuildError, ["WORLD_CONTRACT_REJECTED"]);
expectReject("World payload rejection", () => validateWorldContractModule({
  parseManifestBytes: () => ({}),
  validateBoundaryProcessCorpusManifest: () => ({}),
  validateBundlePayload: () => { throw new Error("rejected"); },
}, manifestBytes, payloadBytes), CorpusBuildError, ["WORLD_CONTRACT_REJECTED"]);

// Reconstruct the builder's private inputs from the public partition. This
// proves that a one-byte native mutation fails at the parity gate before any
// manifest, payload, directory, or loose artifact is constructed.
function encodeKernelInput(descriptor, files) {
  const image = files.get(`${descriptor.id}.image`);
  const instance = files.get(`${descriptor.id}.instance`);
  const effectResult = descriptor.effectResult ? files.get(`${descriptor.id}.effect-result`) : null;
  const bytes = Buffer.alloc(40 + image.length + instance.length + (effectResult?.length ?? 0));
  bytes.write("ABL_PKI1", 0, "ascii");
  bytes.writeUInt16LE(1, 8);
  bytes[10] = descriptor.instanceKind === "initialArgs" ? 0 : 1;
  bytes[11] = effectResult === null ? 0 : 1;
  bytes.writeBigUInt64LE(BigInt(image.length), 12);
  bytes.writeBigUInt64LE(BigInt(instance.length), 20);
  bytes.writeBigUInt64LE(BigInt(effectResult?.length ?? 0), 28);
  let cursor = 40;
  image.copy(bytes, cursor);
  cursor += image.length;
  instance.copy(bytes, cursor);
  cursor += instance.length;
  if (effectResult !== null) effectResult.copy(bytes, cursor);
  return bytes;
}

const parityRecords = VECTOR_DESCRIPTORS.map((descriptor) => {
  const outcome = Buffer.from(valid.files.get(`${descriptor.id}.outcome`));
  return Object.freeze({
    id: descriptor.id,
    operation: descriptor.operation,
    input: parseKernelInput(encodeKernelInput(descriptor, valid.files), `${descriptor.id} reconstructed PKI1`),
    nativeOutcome: outcome,
    kernelOutcome: Buffer.from(outcome),
  });
});
const constructedArtifactIds = [];
const reconstructed = buildCorpusFromParityRecords(parityRecords, {
  onArtifactConstruction: (id) => constructedArtifactIds.push(id),
});
if (constructedArtifactIds.length !== EXPECTED_ARTIFACT_IDS.length ||
    constructedArtifactIds.some((id, index) => id !== EXPECTED_ARTIFACT_IDS[index])) {
  throw new Error(
    `valid reconstruction observed noncanonical artifact construction: ${JSON.stringify(constructedArtifactIds)}`,
  );
}
if (!reconstructed.manifestBytes.equals(manifestBytes) || !reconstructed.payloadBytes.equals(payloadBytes)) {
  throw new Error("public corpus did not reconstruct through the canonical builder");
}

// The construction callback runs after parity verification. Mutating every
// caller-owned buffer from that callback must not alter the verified snapshot
// used to construct the corpus.
const mutableAliasRecords = parityRecords.map((record) => ({
  id: record.id,
  operation: record.operation,
  input: parseKernelInput(Buffer.from(record.input.bytes), `${record.id} mutable alias PKI1`),
  nativeOutcome: Buffer.from(record.nativeOutcome),
  kernelOutcome: Buffer.from(record.kernelOutcome),
}));
let mutableAliasesChanged = false;
const ownedSnapshotReconstruction = buildCorpusFromParityRecords(mutableAliasRecords, {
  onArtifactConstruction: () => {
    if (mutableAliasesChanged) return;
    mutableAliasesChanged = true;
    for (const record of mutableAliasRecords) {
      for (const bytes of [
        record.input.bytes,
        record.input.image,
        record.input.instance,
        record.input.effectResult,
        record.nativeOutcome,
        record.kernelOutcome,
      ]) {
        if (bytes !== null && bytes.length !== 0) bytes[0] ^= 0xff;
      }
    }
  },
});
if (!mutableAliasesChanged ||
    !ownedSnapshotReconstruction.manifestBytes.equals(reconstructed.manifestBytes) ||
    !ownedSnapshotReconstruction.payloadBytes.equals(reconstructed.payloadBytes)) {
  throw new Error("artifact construction did not use an owned verified-parity snapshot");
}

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-process-corpus-negative-"));
try {
  const generatedFiles = new Map([
    [CORPUS_IDENTITY.manifestAssetName, manifestBytes],
    [CORPUS_IDENTITY.payloadAssetName, payloadBytes],
    ["boundary-process-v1-conformance-generation-receipt.json", Buffer.from("{}\n")],
  ]);
  const broadOutput = process.cwd();
  expectReject(
    "broad output destination",
    () => installDirectoryAtomic(broadOutput, generatedFiles),
    CorpusBuildError,
    ["OUTPUT_DESTINATION_INVALID"],
  );
  const sentinelOutput = path.join(temporary, "unowned-output");
  fs.mkdirSync(sentinelOutput);
  const sentinel = path.join(sentinelOutput, "sentinel.txt");
  fs.writeFileSync(sentinel, "preserve-me");
  expectReject(
    "unowned output destination",
    () => installDirectoryAtomic(sentinelOutput, generatedFiles),
    CorpusBuildError,
    ["OUTPUT_DESTINATION_CONFLICT"],
  );
  if (fs.readFileSync(sentinel, "utf8") !== "preserve-me" ||
      fs.readdirSync(sentinelOutput).join("\n") !== "sentinel.txt") {
    throw new Error("unsafe output rejection changed the existing destination");
  }
  const oversizedPayload = path.join(temporary, "oversized-payload.bin");
  const oversizedPayloadFile = fs.openSync(oversizedPayload, "w");
  try {
    fs.ftruncateSync(oversizedPayloadFile, MAX_PAYLOAD_BYTES + 1);
  } finally {
    fs.closeSync(oversizedPayloadFile);
  }
  expectReject(
    "actual payload file over 512 MiB",
    () => validateCorpusMain([manifestPath, oversizedPayload]),
    CorpusValidationError,
    ["CORPUS_INPUT_INVALID"],
  );

  const worldRoot = path.join(temporary, "world");
  const worldScripts = path.join(worldRoot, "scripts");
  const worldValidator = path.join(worldScripts, "acquire_process_conformance_assets.mjs");
  fs.mkdirSync(worldScripts, { recursive: true });
  fs.writeFileSync(worldValidator, "export const validator = true;\n");
  const git = (argumentsList) => childProcess.execFileSync(
    "git",
    ["-C", worldRoot, ...argumentsList],
    { encoding: "utf8" },
  ).trim();
  git(["init", "--quiet"]);
  git(["config", "user.name", "Boundary Test"]);
  git(["config", "user.email", "boundary-test@example.invalid"]);
  git(["add", "scripts/acquire_process_conformance_assets.mjs"]);
  git(["commit", "--quiet", "-m", "validator fixture"]);
  const worldCommit = git(["rev-parse", "HEAD"]);
  fs.appendFileSync(worldValidator, "export const dirty = true;\n");
  expectReject(
    "dirty World validator provenance",
    () => assertFileBelongsToCommit(
      worldRoot,
      worldCommit,
      "scripts/acquire_process_conformance_assets.mjs",
      fs.readFileSync(worldValidator),
    ),
    CorpusBuildError,
    ["WORLD_VALIDATOR_IDENTITY_INVALID"],
  );

  const mutated = parityRecords.map((record) => ({ ...record }));
  const changedNative = Buffer.from(mutated[2].nativeOutcome);
  changedNative[32] ^= 1;
  mutated[2].nativeOutcome = changedNative;
  let artifactConstructionObserved = false;
  expectReject("native expected byte mutation before asset construction", () => {
    buildCorpusFromParityRecords(mutated, {
      onArtifactConstruction: () => {
        artifactConstructionObserved = true;
      },
    });
  }, CorpusBuildError, ["CORPUS_PARITY_MISMATCH"]);
  if (artifactConstructionObserved) {
    throw new Error("native parity mutation reached in-memory artifact construction");
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

process.stdout.write(`${JSON.stringify({
  format: "boundary-process-v1-conformance-negative-proof/v1",
  result: "passed",
  negativeCaseCount,
  vectorCount: VECTOR_DESCRIPTORS.length,
  artifactCount: baseManifest.artifacts.length,
  manifestSha256: sha256Hex(manifestBytes),
  payloadSha256: sha256Hex(payloadBytes),
})}\n`);
