import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";

const [
  kernelPath,
  oneEffectPath,
  portableValuesPath,
  oneEffectProfilePath,
  portableValuesProfilePath,
  ...proofPaths
] = process.argv.slice(2);
const digest = (path) => crypto.createHash("sha256").update(fs.readFileSync(path)).digest("hex");
const sourceKey = (file) => path.relative(process.cwd(), file).split(path.sep).join("/");
const generatedProofPath = proofPaths.find((path) => path.endsWith("boundary-reification-generated-proof.json"));
if (!generatedProofPath) throw new Error("missing executed generated proof");
const generatedProof = JSON.parse(fs.readFileSync(generatedProofPath, "utf8"));
const proofStampPath = proofPaths.find((path) => path.endsWith("boundary-reification-v1-proof.json"));
if (!proofStampPath) throw new Error("missing executed reification proof stamp");
const proofStamp = JSON.parse(fs.readFileSync(proofStampPath, "utf8"));
const receiptSourcePaths = proofPaths.filter(
  (path) => path !== generatedProofPath && path !== proofStampPath,
);
if (
  proofStamp.format !== "boundary-reification-proof/v1" ||
  proofStamp.gate !== "check-boundary-reification-receipt" ||
  proofStamp.status !== "passed"
) {
  throw new Error("invalid executed reification proof stamp");
}
if (!isDeepStrictEqual(proofStamp.observations?.generated, generatedProof)) {
  throw new Error("generated proof is not bound to the executed proof stamp");
}
const kernelDigest = digest(kernelPath);
if (
  proofStamp.machine_v2_kernel_wasm_sha256 !== kernelDigest ||
  proofStamp.machine_v2_kernel_wasm_bytes !== fs.statSync(kernelPath).size
) {
  throw new Error("kernel artifact is not bound to the executed WASM proof");
}
const receiptSourceSha256 = Object.fromEntries(
  receiptSourcePaths.map((source) => [sourceKey(source), digest(source)]),
);
if (!isDeepStrictEqual(proofStamp.receipt_source_sha256, receiptSourceSha256)) {
  throw new Error("receipt sources are not bound to the executed proof stamp");
}
const releaseAssetSha256 = {
  one_effect_image: digest(oneEffectPath),
  portable_values_image: digest(portableValuesPath),
  one_effect_profile: digest(oneEffectProfilePath),
  portable_values_profile: digest(portableValuesProfilePath),
};
if (!isDeepStrictEqual(proofStamp.release_asset_sha256, releaseAssetSha256)) {
  throw new Error("release assets are not bound to fixed-kernel validation");
}
const proofBoolean = (name) => {
  if (typeof proofStamp[name] !== "boolean") throw new Error(`invalid proof boolean: ${name}`);
  return proofStamp[name];
};
const proofCount = (name) => {
  const value = proofStamp[name];
  if (!Number.isSafeInteger(value) || value < 0) throw new Error(`invalid proof count: ${name}`);
  return value;
};
const receipt = {
  format: "boundary-reification-receipt/v1",
  boundary_version: "1.7.0",
  kernel_release_version: "1.7.0",
  zig_version: "0.16.0",
  image_format: "BPI1",
  image_magic: "ABL_BPI1",
  image_header_length: 316,
  program_transition_domain: "boundary-program-transition-v1",
  machine_v2_profile_format: "ABL_MV2P1",
  machine_v2_kernel_abi: 1,
  machine_abi: 2,
  state_format: "ABL_RNF2",
  state_format_version: 1,
  machine_v2_semantic_domain: "boundary-rnf-compiler-semantics-v4",
  fuel_semantic_domain: "segment-fuel=preflight-resource-shape-v4",
  dynamic_fuel_quantum_bytes: 16,
  machine_v2_kernel_wasm_sha256: kernelDigest,
  machine_v2_kernel_wasm_import_count: proofCount("machine_v2_kernel_wasm_import_count"),
  image_profile_invariance_passed: proofBoolean("image_profile_invariance_passed"),
  metering_annotation_invariance_passed: proofBoolean("metering_annotation_invariance_passed"),
  image_examples: {
    one_effect_sha256: releaseAssetSha256.one_effect_image,
    portable_values_sha256: releaseAssetSha256.portable_values_image,
  },
  machine_v2_profile_examples: {
    one_effect_sha256: releaseAssetSha256.one_effect_profile,
    portable_values_sha256: releaseAssetSha256.portable_values_profile,
  },
  baseline_digest_count: proofCount("baseline_digest_count"),
  baseline_digest_mismatch_count: proofCount("baseline_digest_mismatch_count"),
  canonical_image_fixture_count: proofCount("canonical_image_fixture_count"),
  native_transition_comparison_count: generatedProof.native_transition_comparison_count,
  wasm_transition_comparison_count: proofCount("wasm_transition_comparison_count"),
  engine_switch_count: generatedProof.engine_switch_count,
  finite_state_count: generatedProof.finite_state_count,
  generated_trace_count: generatedProof.generated_trace_count,
  generated_trace_seed: generatedProof.generated_trace_seed,
  generated_trace_sha256: generatedProof.generated_trace_sha256,
  malformed_image_case_count: proofCount("malformed_image_case_count"),
  malformed_state_case_count: proofCount("malformed_state_case_count"),
  machine_abi_changed: proofBoolean("machine_abi_changed"),
  state_format_changed: proofBoolean("state_format_changed"),
  source_interpreter_present: proofBoolean("source_interpreter_present"),
  runtime_definition_loader_present: proofBoolean("runtime_definition_loader_present"),
  callback_registry_present: proofBoolean("callback_registry_present"),
  public_clause_evaluator_present: proofBoolean("public_clause_evaluator_present"),
  pure_clause_machine_v2_dependency_present: proofBoolean("pure_clause_machine_v2_dependency_present"),
  proof_gate: "check-boundary-reification-receipt",
  proof_gate_required_before_emission: proofBoolean("proof_gate_required_before_emission"),
  proof_source_sha256: receiptSourceSha256,
};
process.stdout.write(`${JSON.stringify(receipt, null, 2)}\n`);
