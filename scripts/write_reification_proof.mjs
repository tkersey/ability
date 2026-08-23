import fs from "node:fs";

const [
  wasmExecutionPath,
  baselinePath,
  semanticPath,
  generatedPath,
  rootPath,
  buildPath,
  ...purePaths
] = process.argv.slice(2);

const readJson = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const baseline = readJson(baselinePath);
const semantic = readJson(semanticPath);
const generated = readJson(generatedPath);
const wasmExecution = readJson(wasmExecutionPath);

if (
  baseline.format !== "boundary-reification-baseline-proof/v1" ||
  semantic.format !== "boundary-reification-semantic-proof/v1" ||
  generated.format !== "boundary-reification-generated-proof/v1" ||
  wasmExecution.format !== "boundary-machine-v2-kernel-wasm-proof/v1"
) {
  throw new Error("invalid reification proof input format");
}
if (
  baseline.mismatch_count !== 0 ||
  semantic.image_profile_invariance_passed !== true ||
  semantic.metering_annotation_invariance_passed !== true ||
  wasmExecution.import_count !== 0 ||
  wasmExecution.abi !== 1 ||
  wasmExecution.transition_comparison_count <= 0 ||
  generated.generated_trace_count <= 0 ||
  generated.native_transition_comparison_count <= 0
) {
  throw new Error("reification proof observation failed");
}
const root = fs.readFileSync(rootPath, "utf8");
const build = fs.readFileSync(buildPath, "utf8");
const pureSources = purePaths.map((path) => fs.readFileSync(path, "utf8")).join("\n");
const publicClauseEvaluatorPresent = /pub const (evaluator|reducer|clause|program_evaluator|internal_evaluator)\b/.test(root);
const pureClauseMachineV2DependencyPresent = /@import\("(?:machine|machine_v2|kernel)/.test(pureSources) ||
  /\b(?:MachineOptions|caller_fuel|cumulative_fuel|maximum_machine_fuel|maximum_frames|maximum_state_bytes|ABL_RNF2)\b/.test(pureSources);
const proofGateRequiredBeforeEmission = /emit_reification_assets_step\.dependOn\(reification_receipt_step\)/.test(build);

const proof = {
  format: "boundary-reification-proof/v1",
  gate: "check-boundary-reification-receipt",
  status: "passed",
  machine_v2_kernel_wasm_import_count: wasmExecution.import_count,
  image_profile_invariance_passed: semantic.image_profile_invariance_passed,
  metering_annotation_invariance_passed: semantic.metering_annotation_invariance_passed,
  baseline_digest_count: baseline.fixture_count,
  baseline_digest_mismatch_count: baseline.mismatch_count,
  canonical_image_fixture_count: baseline.fixture_count,
  wasm_transition_comparison_count: wasmExecution.transition_comparison_count,
  malformed_image_case_count: semantic.malformed_image_case_count,
  malformed_state_case_count: semantic.malformed_state_case_count,
  world_application_identity_match: false,
  world_frame_byte_match: false,
  agent_witness_passed: false,
  machine_abi_changed: baseline.machine_abi !== semantic.machine_abi,
  state_format_changed: baseline.state_format_version !== semantic.state_format_version,
  application_abi_changed: false,
  frame_format_changed: false,
  effect_protocol_changed: false,
  source_interpreter_present: /(?:src\/interpreter\.zig|pub const Runtime\b)/.test(root),
  runtime_definition_loader_present: /(?:DefinitionLoader|LoadedDefinition|RuntimeDefinition)/.test(root),
  callback_registry_present: /(?:CallbackRegistry|callback_registry)/.test(root),
  public_clause_evaluator_present: publicClauseEvaluatorPresent,
  pure_clause_machine_v2_dependency_present: pureClauseMachineV2DependencyPresent,
  proof_gate_required_before_emission: proofGateRequiredBeforeEmission,
  observations: {
    baseline,
    semantic,
    generated,
    wasm_execution: wasmExecution,
  },
};

if (
  proof.machine_abi_changed ||
  proof.state_format_changed ||
  proof.public_clause_evaluator_present ||
  proof.pure_clause_machine_v2_dependency_present ||
  !proof.proof_gate_required_before_emission
) {
  throw new Error("reification architecture proof failed");
}

process.stdout.write(`${JSON.stringify(proof)}\n`);
