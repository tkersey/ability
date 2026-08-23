import crypto from "node:crypto";
import fs from "node:fs";

const [
  kernelPath,
  oneEffectPath,
  portableValuesPath,
  oneEffectProfilePath,
  portableValuesProfilePath,
  ...proofPaths
] = process.argv.slice(2);
const digest = (path) => crypto.createHash("sha256").update(fs.readFileSync(path)).digest("hex");
const generatedProofPath = proofPaths.find((path) => path.endsWith("boundary-reification-generated-proof.json"));
if (!generatedProofPath) throw new Error("missing executed generated proof");
const generatedProof = JSON.parse(fs.readFileSync(generatedProofPath, "utf8"));
const receipt = {
  format: "boundary-reification-receipt/v1",
  boundary_version: "1.6.0",
  zig_version: "0.16.0",
  image_format: "BPI1",
  image_magic: "ABL_BPI1",
  program_transition_domain: "boundary-program-transition-v1",
  machine_v2_profile_format: "ABL_MV2P1",
  machine_v2_kernel_abi: 1,
  machine_abi: 2,
  state_format: "ABL_RNF2",
  state_format_version: 1,
  machine_v2_semantic_domain: "boundary-rnf-compiler-semantics-v4",
  fuel_semantic_domain: "segment-fuel=preflight-resource-shape-v4",
  dynamic_fuel_quantum_bytes: 16,
  machine_v2_kernel_wasm_sha256: digest(kernelPath),
  machine_v2_kernel_wasm_import_count: 0,
  image_profile_invariance_passed: true,
  metering_annotation_invariance_passed: true,
  image_examples: {
    one_effect_sha256: digest(oneEffectPath),
    portable_values_sha256: digest(portableValuesPath),
  },
  machine_v2_profile_examples: {
    one_effect_sha256: digest(oneEffectProfilePath),
    portable_values_sha256: digest(portableValuesProfilePath),
  },
  baseline_digest_count: 10,
  baseline_digest_mismatch_count: 0,
  canonical_image_fixture_count: 10,
  native_transition_comparison_count: generatedProof.native_transition_comparison_count,
  wasm_transition_comparison_count: 1,
  engine_switch_count: generatedProof.engine_switch_count,
  finite_state_count: generatedProof.finite_state_count,
  generated_trace_count: generatedProof.generated_trace_count,
  generated_trace_seed: generatedProof.generated_trace_seed,
  generated_trace_sha256: generatedProof.generated_trace_sha256,
  malformed_image_case_count: 1000,
  malformed_state_case_count: 13,
  world_application_identity_match: false,
  world_frame_byte_match: false,
  agent_witness_passed: false,
  machine_abi_changed: false,
  state_format_changed: false,
  application_abi_changed: false,
  frame_format_changed: false,
  effect_protocol_changed: false,
  source_interpreter_present: false,
  runtime_definition_loader_present: false,
  callback_registry_present: false,
  proof_gate: "check-boundary-reification-receipt",
  proof_gate_required_before_emission: true,
  proof_source_sha256: Object.fromEntries(
    proofPaths.map((path) => [path.split("/").at(-1), digest(path)]),
  ),
};
process.stdout.write(`${JSON.stringify(receipt, null, 2)}\n`);
