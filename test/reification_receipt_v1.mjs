import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const repository = process.cwd();
const script = path.join(repository, "scripts", "write_reification_receipt.mjs");
const proofScript = path.join(repository, "scripts", "write_reification_proof.mjs");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-reification-receipt-"));

try {
  const artifact = path.join(temporary, "artifact.bin");
  fs.writeFileSync(artifact, "artifact");
  const wasmExecution = path.join(temporary, "wasm-execution.json");
  fs.writeFileSync(wasmExecution, JSON.stringify({
    format: "boundary-machine-v2-kernel-wasm-proof/v1",
    kernel_wasm_bytes: 8,
    import_count: 0,
    abi: 1,
    transition_comparison_count: 3,
  }));
  const baseline = path.join(temporary, "baseline.json");
  fs.writeFileSync(baseline, JSON.stringify({
    format: "boundary-reification-baseline-proof/v1",
    fixture_count: 7,
    mismatch_count: 0,
    machine_abi: 2,
    state_format: "ABL_RNF2",
    state_format_version: 1,
  }));
  const semantic = path.join(temporary, "semantic.json");
  fs.writeFileSync(semantic, JSON.stringify({
    format: "boundary-reification-semantic-proof/v1",
    image_profile_invariance_passed: true,
    metering_annotation_invariance_passed: true,
    malformed_image_case_count: 123,
    malformed_state_case_count: 17,
    machine_abi: 2,
    state_format_version: 1,
  }));
  const generated = path.join(temporary, "boundary-reification-generated-proof.json");
  fs.writeFileSync(generated, JSON.stringify({
    format: "boundary-reification-generated-proof/v1",
    native_transition_comparison_count: 1,
    engine_switch_count: 1,
    finite_state_count: 1,
    generated_trace_count: 1,
    generated_trace_seed: "seed",
    generated_trace_sha256: "digest",
  }));
  const root = path.join(temporary, "root.zig");
  fs.writeFileSync(root, "pub const program = void;\n");
  const build = path.join(temporary, "build.zig");
  fs.writeFileSync(build, "emit_reification_assets_step.dependOn(reification_receipt_step);\n");
  const pure = path.join(temporary, "pure.zig");
  fs.writeFileSync(pure, "pub const Pure = void;\n");
  const proofPath = path.join(temporary, "boundary-reification-v1-proof.json");
  const proof = JSON.parse(childProcess.execFileSync(process.execPath, [
    proofScript,
    wasmExecution,
    baseline,
    semantic,
    generated,
    root,
    build,
    pure,
  ], { encoding: "utf8" }));
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const args = [script, artifact, artifact, artifact, artifact, artifact, generated, proofPath];
  const receipt = JSON.parse(childProcess.execFileSync(process.execPath, args, { encoding: "utf8" }));
  if (
    receipt.image_profile_invariance_passed !== true ||
    receipt.baseline_digest_count !== 7 ||
    receipt.malformed_image_case_count !== 123
  ) {
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
