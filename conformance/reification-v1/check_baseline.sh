#!/bin/sh
set -eu

generator=${1:?baseline generator path is required}
zig=${2:?zig executable path is required}
lock=conformance/reification-v1/baseline.lock.json
vectors=conformance/reification-v1/baseline/vectors.json

field() {
  sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$lock"
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

test "$(field boundary_commit)" = ed4956b6229e039c72f3080dd60ddb94f58a56fc
test "$(field zig_version)" = "$($zig version)"
test "$(field fixture_source_sha256)" = "$(sha256 test/reification_baseline.zig)"
test "$(field vectors_sha256)" = "$(sha256 "$vectors")"
test "$(field performance_gate_sha256)" = "$(sha256 conformance/rnf-v1/check_performance.sh)"
test "$(field performance_patch_sha256)" = "$(sha256 conformance/rnf-v1/v0.7.0-performance.patch)"

tmp=${TMPDIR:-/tmp}/boundary-reification-baseline-$$.json
trap 'rm -f "$tmp"' EXIT
"$generator" > "$tmp"
cmp "$vectors" "$tmp"

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
NODE
