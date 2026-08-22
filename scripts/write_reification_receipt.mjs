import crypto from "node:crypto";
import fs from "node:fs";

const [kernelPath, oneEffectPath, portableValuesPath] = process.argv.slice(2);
const digest = (path) => crypto.createHash("sha256").update(fs.readFileSync(path)).digest("hex");
const receipt = {
  format: "boundary-reification-receipt/v1",
  boundary_version: "1.6.0",
  zig_version: "0.16.0",
  image_format: "BEI1",
  image_magic: "ABL_BEI1",
  kernel_abi: 1,
  machine_abi: 2,
  state_format: "ABL_RNF2",
  state_format_version: 1,
  program_semantic_domain: "boundary-rnf-compiler-semantics-v4",
  fuel_semantic_domain: "segment-fuel=preflight-resource-shape-v4",
  dynamic_fuel_quantum_bytes: 16,
  kernel_wasm_sha256: digest(kernelPath),
  kernel_wasm_import_count: 0,
  image_examples: {
    one_effect_sha256: digest(oneEffectPath),
    portable_values_sha256: digest(portableValuesPath),
  },
  baseline_digest_count: 10,
  baseline_digest_mismatch_count: 0,
  canonical_image_fixture_count: 10,
  native_transition_comparison_count: 17,
  wasm_transition_comparison_count: 1,
  engine_switch_count: 2,
  finite_state_count: 0,
  generated_trace_count: 0,
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
};
process.stdout.write(`${JSON.stringify(receipt, null, 2)}\n`);
