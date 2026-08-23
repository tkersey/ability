import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [
  wasmExecutionPath,
  baselinePath,
  semanticPath,
  generatedPath,
  rootPath,
  buildPath,
  ...sourcePaths
] = process.argv.slice(2);
const sourceDelimiter = sourcePaths.indexOf("--all-sources");
if (sourceDelimiter < 0) {
  throw new Error("missing complete source inventory delimiter");
}
const purePaths = sourcePaths.slice(0, sourceDelimiter);
const receiptSourceDelimiter = sourcePaths.indexOf("--receipt-sources");
if (receiptSourceDelimiter < sourceDelimiter) {
  throw new Error("missing receipt source inventory delimiter");
}
const allSourcePaths = sourcePaths.slice(sourceDelimiter + 1, receiptSourceDelimiter);
const receiptSourcePaths = sourcePaths.slice(receiptSourceDelimiter + 1);
if (allSourcePaths.length === 0) {
  throw new Error("empty complete source inventory");
}
if (receiptSourcePaths.length === 0) throw new Error("empty receipt source inventory");

const readJson = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const digest = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const sourceKey = (file) => path.relative(process.cwd(), file).split(path.sep).join("/");
const baseline = readJson(baselinePath);
const semantic = readJson(semanticPath);
const generated = readJson(generatedPath);
const wasmExecution = readJson(wasmExecutionPath);
const positiveCount = (owner, name) => {
  const value = owner[name];
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`invalid positive proof count: ${name}`);
  }
  return value;
};

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
  baseline.current_mismatch_count !== 0 ||
  baseline.oracle_mismatch_count !== 0 ||
  baseline.oracle_boundary_commit !== "ed4956b6229e039c72f3080dd60ddb94f58a56fc" ||
  !/^[0-9a-f]{64}$/.test(baseline.oracle_fixture_patch_sha256) ||
  semantic.image_profile_invariance_passed !== true ||
  semantic.metering_annotation_invariance_passed !== true ||
  positiveCount(semantic, "malformed_image_case_count") <= 0 ||
  positiveCount(semantic, "malformed_state_case_count") <= 0 ||
  wasmExecution.import_count !== 0 ||
  wasmExecution.abi !== 1 ||
  positiveCount(wasmExecution, "kernel_wasm_bytes") <= 0 ||
  !/^[0-9a-f]{64}$/.test(wasmExecution.kernel_wasm_sha256) ||
  Object.keys(wasmExecution.release_asset_sha256 ?? {}).length !== 4 ||
  !Object.values(wasmExecution.release_asset_sha256 ?? {}).every(
    (value) => /^[0-9a-f]{64}$/.test(value),
  ) ||
  positiveCount(wasmExecution, "transition_comparison_count") <= 0 ||
  positiveCount(generated, "generated_trace_count") <= 0 ||
  positiveCount(generated, "native_transition_comparison_count") <= 0 ||
  positiveCount(generated, "engine_switch_count") <= 0 ||
  positiveCount(generated, "finite_state_count") <= 0 ||
  !/^0x[0-9a-f]{16}$/.test(generated.generated_trace_seed) ||
  !/^[0-9a-f]{64}$/.test(generated.generated_trace_sha256)
) {
  throw new Error("reification proof observation failed");
}
const root = fs.readFileSync(rootPath, "utf8");
const build = fs.readFileSync(buildPath, "utf8");
const pureSources = purePaths.map((path) => fs.readFileSync(path, "utf8")).join("\n");
const allSources = allSourcePaths.map((path) => fs.readFileSync(path, "utf8")).join("\n");
const publicClauseEvaluatorPresent = /pub const (evaluator|reducer|clause|program_evaluator|internal_evaluator)\b/.test(root);
const pureClauseMachineV2DependencyPresent = /@import\("(?:machine|machine_v2|kernel)/.test(pureSources) ||
  /\b(?:MachineOptions|caller_fuel|cumulative_fuel|maximum_machine_fuel|maximum_frames|maximum_state_bytes|ABL_RNF2)\b/.test(pureSources);
const proofGateRequiredBeforeEmission =
  /installation\.step\.dependOn\(reification_receipt_step\)/.test(build) &&
  /emit_reification_assets_step\.dependOn\(reification_receipt_step\)/.test(build);
const sourceInventoryGuardRequired =
  /reification_proof_stamp_command\.step\.dependOn\(zig_path_coverage_guard\)/.test(build);

const proof = {
  format: "boundary-reification-proof/v1",
  gate: "check-boundary-reification-receipt",
  status: "passed",
  machine_v2_kernel_wasm_import_count: wasmExecution.import_count,
  machine_v2_kernel_wasm_bytes: wasmExecution.kernel_wasm_bytes,
  machine_v2_kernel_wasm_sha256: wasmExecution.kernel_wasm_sha256,
  release_asset_sha256: wasmExecution.release_asset_sha256,
  image_profile_invariance_passed: semantic.image_profile_invariance_passed,
  metering_annotation_invariance_passed: semantic.metering_annotation_invariance_passed,
  baseline_digest_count: baseline.fixture_count,
  baseline_digest_mismatch_count: baseline.mismatch_count,
  canonical_image_fixture_count: baseline.fixture_count,
  wasm_transition_comparison_count: wasmExecution.transition_comparison_count,
  malformed_image_case_count: semantic.malformed_image_case_count,
  malformed_state_case_count: semantic.malformed_state_case_count,
  machine_abi_changed: baseline.machine_abi !== semantic.machine_abi,
  state_format_changed: baseline.state_format_version !== semantic.state_format_version,
  source_interpreter_present: /(?:@import\("interpreter"\)|pub const Runtime\b)/.test(allSources),
  runtime_definition_loader_present: /(?:DefinitionLoader|LoadedDefinition|RuntimeDefinition)/.test(allSources),
  callback_registry_present: /(?:CallbackRegistry|callback_registry)/.test(allSources),
  public_clause_evaluator_present: publicClauseEvaluatorPresent,
  pure_clause_machine_v2_dependency_present: pureClauseMachineV2DependencyPresent,
  proof_gate_required_before_emission: proofGateRequiredBeforeEmission,
  receipt_source_sha256: Object.fromEntries(
    receiptSourcePaths.map((source) => [sourceKey(source), digest(source)]),
  ),
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
  proof.source_interpreter_present ||
  proof.runtime_definition_loader_present ||
  proof.callback_registry_present ||
  proof.public_clause_evaluator_present ||
  proof.pure_clause_machine_v2_dependency_present ||
  !sourceInventoryGuardRequired ||
  !proof.proof_gate_required_before_emission
) {
  throw new Error("reification architecture proof failed");
}

process.stdout.write(`${JSON.stringify(proof)}\n`);
