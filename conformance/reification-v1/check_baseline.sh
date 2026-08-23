#!/bin/sh
set -eu

generator=${1:?current baseline generator path is required}
zig=$(realpath "${2:?zig executable path is required}")
lock=conformance/reification-v1/baseline.lock.json
vectors=conformance/reification-v1/baseline/vectors.json
repo=$(pwd)

field() {
  sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$lock"
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

test "$(field boundary_commit)" = ed4956b6229e039c72f3080dd60ddb94f58a56fc
test "$(field zig_version)" = "$($zig version)"
test "$(field fixture_source_sha256)" = "$(sha256 test/reification_baseline.zig)"
fixture_patch=$(field fixture_patch)
fixture_source_sha=$(field fixture_source_sha256)
test -n "$fixture_patch"
test "$(field fixture_patch_sha256)" = "$(sha256 "$fixture_patch")"
test "$(field vectors_sha256)" = "$(sha256 "$vectors")"
test "$(field performance_gate_sha256)" = "$(sha256 conformance/rnf-v1/check_performance.sh)"
test "$(field performance_patch_sha256)" = "$(sha256 conformance/rnf-v1/v0.7.0-performance.patch)"

current_output=${TMPDIR:-/tmp}/boundary-reification-current-$$.json
oracle_output=${TMPDIR:-/tmp}/boundary-reification-oracle-$$.json
oracle_root=$(mktemp -d "${TMPDIR:-/tmp}/boundary-reification-oracle.XXXXXX")
trap 'rm -f "$current_output" "$oracle_output"; rm -rf "$oracle_root"' EXIT

"$generator" > "$current_output"
cmp "$vectors" "$current_output"

boundary_commit=$(field boundary_commit)
git archive "$boundary_commit" | tar -x -C "$oracle_root"
(
  cd "$oracle_root"
  patch -s -p1 < "$repo/$fixture_patch"
  test "$(sha256 test/reification_baseline.zig)" = "$fixture_source_sha"
  "$zig" build emit-boundary-reification-baseline --summary none
) > "$oracle_output"
cmp "$vectors" "$oracle_output"

node - "$lock" "$vectors" <<'NODE'
const fs = require('node:fs');
const [lockPath, vectorsPath] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
const vectors = JSON.parse(fs.readFileSync(vectorsPath, 'utf8'));
const expected = [
  'one-effect',
  'branch',
  'loop',
  'helper-call-return',
  'explicit-yield',
  'caller-fuel-checkpoint',
  'portable-values',
  'local-effect-handler',
  'effect-morphism',
  'recursion',
];
if (vectors.format !== 'boundary-reification-baseline-v1' ||
    vectors.boundary_commit !== lock.boundary_commit ||
    vectors.zig_version !== lock.zig_version ||
    vectors.fixtures.length !== lock.fixture_count ||
    vectors.malformed_state_cases.length !== lock.malformed_state_case_count ||
    JSON.stringify(vectors.fixtures.map((fixture) => fixture.name)) !== JSON.stringify(expected)) {
  throw new Error('Boundary reification baseline inventory mismatch');
}
for (const fixture of vectors.fixtures) {
  if (!/^[0-9a-f]{64}$/.test(fixture.program_semantic_digest) ||
      !/^[0-9a-f]{64}$/.test(fixture.machine_contract_digest) ||
      fixture.machine_abi !== 2 || fixture.state_format !== 'ABL_RNF2' ||
      fixture.state_format_version !== 1 || fixture.terminal?.kind !== 'done') {
    throw new Error(`invalid baseline fixture: ${fixture.name}`);
  }
}
if (vectors.malformed_state_cases.some((entry) => entry.rejected !== true)) {
  throw new Error('malformed State baseline contains an accepted input');
}
process.stdout.write(`${JSON.stringify({
  format: 'boundary-reification-baseline-proof/v1',
  oracle_boundary_commit: lock.boundary_commit,
  oracle_fixture_patch_sha256: lock.fixture_patch_sha256,
  fixture_count: vectors.fixtures.length,
  mismatch_count: 0,
  current_mismatch_count: 0,
  oracle_mismatch_count: 0,
  malformed_state_case_count: vectors.malformed_state_cases.length,
  machine_abi: vectors.fixtures[0].machine_abi,
  state_format: vectors.fixtures[0].state_format,
  state_format_version: vectors.fixtures[0].state_format_version,
})}\n`);
NODE
