import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const repository = process.cwd();
const script = path.join(repository, "scripts", "write_reification_receipt.mjs");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-reification-receipt-"));

try {
  const artifact = path.join(temporary, "artifact.bin");
  fs.writeFileSync(artifact, "artifact");
  const generated = path.join(temporary, "boundary-reification-generated-proof.json");
  fs.writeFileSync(generated, JSON.stringify({
    native_transition_comparison_count: 1,
    engine_switch_count: 1,
    finite_state_count: 1,
    generated_trace_count: 1,
    generated_trace_seed: "seed",
    generated_trace_sha256: "digest",
  }));
  const proof = {
    format: "boundary-reification-proof/v1",
    gate: "check-boundary-reification-receipt",
    status: "passed",
    machine_v2_kernel_wasm_import_count: 0,
    image_profile_invariance_passed: true,
    metering_annotation_invariance_passed: true,
    baseline_digest_count: 10,
    baseline_digest_mismatch_count: 0,
    canonical_image_fixture_count: 10,
    wasm_transition_comparison_count: 1,
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
    public_clause_evaluator_present: false,
    pure_clause_machine_v2_dependency_present: false,
    proof_gate_required_before_emission: true,
  };
  const proofPath = path.join(temporary, "boundary-reification-v1-proof.json");
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const args = [script, artifact, artifact, artifact, artifact, artifact, generated, proofPath];
  const receipt = JSON.parse(childProcess.execFileSync(process.execPath, args, { encoding: "utf8" }));
  if (receipt.image_profile_invariance_passed !== true || receipt.baseline_digest_count !== 10) {
    throw new Error("receipt did not derive claims from the executed proof stamp");
  }

  proof.status = "failed";
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const rejected = childProcess.spawnSync(process.execPath, args, { encoding: "utf8" });
  if (rejected.status === 0) throw new Error("failed proof stamp was accepted");

  proof.status = "passed";
  proof.image_profile_invariance_passed = "true";
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const mistyped = childProcess.spawnSync(process.execPath, args, { encoding: "utf8" });
  if (mistyped.status === 0) throw new Error("mistyped proof claim was accepted");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
