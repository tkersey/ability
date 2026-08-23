import childProcess from "node:child_process";
import crypto from "node:crypto";
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
    kernel_wasm_sha256: crypto.createHash("sha256").update("artifact").digest("hex"),
    import_count: 0,
    abi: 1,
    transition_comparison_count: 3,
    release_asset_sha256: {
      one_effect_image: crypto.createHash("sha256").update("artifact").digest("hex"),
      portable_values_image: crypto.createHash("sha256").update("artifact").digest("hex"),
      one_effect_profile: crypto.createHash("sha256").update("artifact").digest("hex"),
      portable_values_profile: crypto.createHash("sha256").update("artifact").digest("hex"),
    },
  }));
  const baseline = path.join(temporary, "baseline.json");
  fs.writeFileSync(baseline, JSON.stringify({
    format: "boundary-reification-baseline-proof/v1",
    oracle_boundary_commit: "ed4956b6229e039c72f3080dd60ddb94f58a56fc",
    oracle_fixture_patch_sha256: "a".repeat(64),
    fixture_count: 7,
    mismatch_count: 0,
    current_mismatch_count: 0,
    oracle_mismatch_count: 0,
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
    generated_trace_seed: "0x4245493100010000",
    generated_trace_sha256: "a".repeat(64),
  }));
  const root = path.join(temporary, "root.zig");
  fs.writeFileSync(root, "pub const program = void;\n");
  const build = path.join(temporary, "build.zig");
  fs.writeFileSync(
    build,
    "installation.step.dependOn(reification_receipt_step);\n" +
      "emit_reification_assets_step.dependOn(reification_receipt_step);\n",
  );
  const pure = path.join(temporary, "pure.zig");
  fs.writeFileSync(pure, "pub const Pure = void;\n");
  const executor = path.join(temporary, "proof-executor.mjs");
  fs.writeFileSync(executor, "export const proof = true;\n");
  const proofPath = path.join(temporary, "boundary-reification-v1-proof.json");
  const proofArgs = [
    proofScript,
    wasmExecution,
    baseline,
    semantic,
    generated,
    root,
    build,
    pure,
    "--all-sources",
    root,
    pure,
    "--receipt-sources",
    pure,
    executor,
  ];
  const proof = JSON.parse(childProcess.execFileSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  ));
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const loaderSource = path.join(temporary, "loader.zig");
  fs.writeFileSync(loaderSource, "pub const DefinitionLoader = void;\n");
  const receiptSourceDelimiter = proofArgs.indexOf("--receipt-sources");
  const forgedSource = childProcess.spawnSync(
    process.execPath,
    [
      ...proofArgs.slice(0, receiptSourceDelimiter),
      loaderSource,
      ...proofArgs.slice(receiptSourceDelimiter),
    ],
    { encoding: "utf8" },
  );
  if (forgedSource.status === 0) {
    throw new Error("runtime loader outside the package root was missed");
  }
  fs.writeFileSync(
    build,
    "emit_reification_assets_step.dependOn(reification_receipt_step);\n",
  );
  const unorderedInstall = childProcess.spawnSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  );
  if (unorderedInstall.status === 0) {
    throw new Error("asset installation without proof dependency was accepted");
  }
  fs.writeFileSync(
    build,
    "installation.step.dependOn(reification_receipt_step);\n" +
      "emit_reification_assets_step.dependOn(reification_receipt_step);\n",
  );
  const malformedProvenance = JSON.parse(fs.readFileSync(generated, "utf8"));
  malformedProvenance.generated_trace_sha256 = "digest";
  fs.writeFileSync(generated, JSON.stringify(malformedProvenance));
  const forgedProvenance = childProcess.spawnSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  );
  if (forgedProvenance.status === 0) {
    throw new Error("malformed generated-trace provenance was accepted");
  }
  malformedProvenance.generated_trace_sha256 = "a".repeat(64);
  fs.writeFileSync(generated, JSON.stringify(malformedProvenance));

  const forgedBaseline = JSON.parse(fs.readFileSync(baseline, "utf8"));
  forgedBaseline.oracle_mismatch_count = 1;
  fs.writeFileSync(baseline, JSON.stringify(forgedBaseline));
  const forgedOracle = childProcess.spawnSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  );
  if (forgedOracle.status === 0) {
    throw new Error("forged locked-source oracle result was accepted");
  }
  forgedBaseline.oracle_mismatch_count = 0;
  fs.writeFileSync(baseline, JSON.stringify(forgedBaseline));

  const forgedSemantic = JSON.parse(fs.readFileSync(semantic, "utf8"));
  for (const field of ["malformed_image_case_count", "malformed_state_case_count"]) {
    const authentic = forgedSemantic[field];
    forgedSemantic[field] = 0;
    fs.writeFileSync(semantic, JSON.stringify(forgedSemantic));
    const emptyCorpus = childProcess.spawnSync(
      process.execPath,
      proofArgs,
      { encoding: "utf8" },
    );
    if (emptyCorpus.status === 0) {
      throw new Error(`empty ${field} proof was accepted`);
    }
    forgedSemantic[field] = authentic;
  }
  fs.writeFileSync(semantic, JSON.stringify(forgedSemantic));

  const args = [
    script,
    artifact,
    artifact,
    artifact,
    artifact,
    artifact,
    pure,
    executor,
    generated,
    proofPath,
  ];
  const receipt = JSON.parse(childProcess.execFileSync(process.execPath, args, { encoding: "utf8" }));
  if (
    receipt.image_profile_invariance_passed !== true ||
    receipt.baseline_digest_count !== 7 ||
    receipt.malformed_image_case_count !== 123
  ) {
    throw new Error("receipt did not derive claims from the executed proof stamp");
  }

  const replacementKernel = path.join(temporary, "replacement-kernel.bin");
  fs.writeFileSync(replacementKernel, "replacement");
  const substitutedKernel = childProcess.spawnSync(
    process.execPath,
    [script, replacementKernel, ...args.slice(2)],
    { encoding: "utf8" },
  );
  if (substitutedKernel.status === 0) {
    throw new Error("substituted kernel artifact was accepted");
  }
  const substitutedAsset = childProcess.spawnSync(
    process.execPath,
    [script, artifact, replacementKernel, ...args.slice(3)],
    { encoding: "utf8" },
  );
  if (substitutedAsset.status === 0) {
    throw new Error("substituted release asset was accepted");
  }

  fs.appendFileSync(pure, "pub const Changed = void;\n");
  const substitutedSource = childProcess.spawnSync(
    process.execPath,
    args,
    { encoding: "utf8" },
  );
  if (substitutedSource.status === 0) {
    throw new Error("post-proof source substitution was accepted");
  }
  fs.writeFileSync(pure, "pub const Pure = void;\n");

  fs.appendFileSync(executor, "export const changed = true;\n");
  const substitutedExecutor = childProcess.spawnSync(
    process.execPath,
    args,
    { encoding: "utf8" },
  );
  if (substitutedExecutor.status === 0) {
    throw new Error("post-proof executor substitution was accepted");
  }
  fs.writeFileSync(executor, "export const proof = true;\n");

  const substitutedGenerated = JSON.parse(fs.readFileSync(generated, "utf8"));
  substitutedGenerated.generated_trace_count += 1;
  fs.writeFileSync(generated, JSON.stringify(substitutedGenerated));
  const substituted = childProcess.spawnSync(process.execPath, args, { encoding: "utf8" });
  if (substituted.status === 0) throw new Error("substituted generated proof was accepted");
  substitutedGenerated.generated_trace_count -= 1;
  fs.writeFileSync(generated, JSON.stringify(substitutedGenerated));

  proof.status = "failed";
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const rejected = childProcess.spawnSync(process.execPath, args, { encoding: "utf8" });
  if (rejected.status === 0) throw new Error("failed proof stamp was accepted");

  proof.status = "passed";
  proof.image_profile_invariance_passed = "true";
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const mistyped = childProcess.spawnSync(process.execPath, args, { encoding: "utf8" });
  if (mistyped.status === 0) throw new Error("mistyped proof claim was accepted");

  const incompleteGenerated = JSON.parse(fs.readFileSync(generated, "utf8"));
  delete incompleteGenerated.engine_switch_count;
  fs.writeFileSync(generated, JSON.stringify(incompleteGenerated));
  const incomplete = childProcess.spawnSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  );
  if (incomplete.status === 0) throw new Error("incomplete generated proof was accepted");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
