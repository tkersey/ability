import childProcess from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const repository = process.cwd();
const script = path.join(repository, "scripts", "write_reification_receipt.mjs");
const proofScript = path.join(repository, "scripts", "write_reification_proof.mjs");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-reification-receipt-"));
const unownedDownstreamClaims = [
  "world_application_identity_match",
  "world_frame_byte_match",
  "agent_witness_passed",
  "application_abi_changed",
  "frame_format_changed",
  "effect_protocol_changed",
];

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
    canonical_image_fixture_count: 2,
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
    fixture_count: 10,
    mismatch_count: 0,
    current_mismatch_count: 0,
    oracle_mismatch_count: 0,
    malformed_state_case_count: 4,
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
      "emit_reification_assets_step.dependOn(reification_receipt_step);\n" +
      "reification_proof_stamp_command.step.dependOn(zig_path_coverage_guard);\n",
  );
  const pureGraphSources = [
    "control_ir.zig",
    "dynamic_value_v1.zig",
    "image_v1.zig",
    "portable_value.zig",
    "program_semantics_v1.zig",
    "reducer_clause_v1.zig",
    "rnf.zig",
  ].map((name) => path.join(repository, "src", name));
  const pureSemanticSources = [
    "image_emit_v1.zig",
    "image_v1.zig",
    "program_semantics_v1.zig",
    "reducer_clause_v1.zig",
    "reified_program_v1.zig",
  ].map((name) => path.join(repository, "src", name));
  const pure = path.join(temporary, "receipt-source.zig");
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
    ...pureGraphSources,
    "--pure-semantics",
    ...pureSemanticSources,
    "--all-sources",
    root,
    ...pureGraphSources,
    ...pureSemanticSources,
    "--receipt-sources",
    pure,
    executor,
  ];
  const proof = JSON.parse(childProcess.execFileSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  ));
  if (unownedDownstreamClaims.some((field) => Object.hasOwn(proof, field))) {
    throw new Error("Boundary proof claimed an unobserved downstream result");
  }
  fs.writeFileSync(proofPath, JSON.stringify(proof));
  const pureSemanticDelimiter = proofArgs.indexOf("--pure-semantics");
  const sourceDelimiter = proofArgs.indexOf("--all-sources");
  const incompletePureGraphInventory = childProcess.spawnSync(
    process.execPath,
    [
      ...proofArgs.slice(0, pureSemanticDelimiter - 1),
      ...proofArgs.slice(pureSemanticDelimiter),
    ],
    { encoding: "utf8" },
  );
  if (incompletePureGraphInventory.status === 0) {
    throw new Error("incomplete pure graph inventory was accepted");
  }
  const incompletePureSemanticInventory = childProcess.spawnSync(
    process.execPath,
    [
      ...proofArgs.slice(0, sourceDelimiter - 1),
      ...proofArgs.slice(sourceDelimiter),
    ],
    { encoding: "utf8" },
  );
  if (incompletePureSemanticInventory.status === 0) {
    throw new Error("incomplete pure semantic inventory was accepted");
  }
  const substitutedPureDirectory = path.join(temporary, "substituted-pure");
  fs.mkdirSync(substitutedPureDirectory);
  const substitutedPure = path.join(
    substitutedPureDirectory,
    "dynamic_value_v1.zig",
  );
  fs.writeFileSync(substitutedPure, "pub const Benign = void;\n");
  const substitutedPureArgs = [...proofArgs];
  substitutedPureArgs[substitutedPureArgs.indexOf(pureGraphSources[1])] =
    substitutedPure;
  const substitutedPureInventory = childProcess.spawnSync(
    process.execPath,
    substitutedPureArgs,
    { encoding: "utf8" },
  );
  if (substitutedPureInventory.status === 0) {
    throw new Error("same-basename pure source substitution was accepted");
  }
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
    "emit_reification_assets_step.dependOn(reification_receipt_step);\n" +
      "reification_proof_stamp_command.step.dependOn(zig_path_coverage_guard);\n",
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
  const unguardedInventory = childProcess.spawnSync(
    process.execPath,
    proofArgs,
    { encoding: "utf8" },
  );
  if (unguardedInventory.status === 0) {
    throw new Error("proof source inventory without its coverage guard was accepted");
  }
  fs.writeFileSync(
    build,
    "installation.step.dependOn(reification_receipt_step);\n" +
      "emit_reification_assets_step.dependOn(reification_receipt_step);\n" +
      "reification_proof_stamp_command.step.dependOn(zig_path_coverage_guard);\n",
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

  const forgedWasmExecution = JSON.parse(fs.readFileSync(wasmExecution, "utf8"));
  for (const count of [0, 1, 3]) {
    forgedWasmExecution.canonical_image_fixture_count = count;
    fs.writeFileSync(wasmExecution, JSON.stringify(forgedWasmExecution));
    const invalidImageCount = childProcess.spawnSync(
      process.execPath,
      proofArgs,
      { encoding: "utf8" },
    );
    if (invalidImageCount.status === 0) {
      throw new Error("invalid canonical image fixture count was accepted");
    }
  }
  forgedWasmExecution.canonical_image_fixture_count = 2;
  fs.writeFileSync(wasmExecution, JSON.stringify(forgedWasmExecution));

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
  for (const [field, forged] of [
    ["fixture_count", 0],
    ["fixture_count", 9],
    ["malformed_state_case_count", 0],
    ["malformed_state_case_count", 3],
  ]) {
    const authentic = forgedBaseline[field];
    forgedBaseline[field] = forged;
    fs.writeFileSync(baseline, JSON.stringify(forgedBaseline));
    const invalidInventory = childProcess.spawnSync(
      process.execPath,
      proofArgs,
      { encoding: "utf8" },
    );
    if (invalidInventory.status === 0) {
      throw new Error(`invalid baseline ${field} inventory was accepted`);
    }
    forgedBaseline[field] = authentic;
  }
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
    receipt.boundary_version !== "1.8.0" ||
    receipt.kernel_release_version !== "1.8.0" ||
    receipt.image_profile_invariance_passed !== true ||
    receipt.baseline_digest_count !== 10 ||
    receipt.canonical_image_fixture_count !== 2 ||
    receipt.malformed_image_case_count !== 123 ||
    unownedDownstreamClaims.some((field) => Object.hasOwn(receipt, field))
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
