import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [inspector, imagePath] = process.argv.slice(2);
assert(inspector && imagePath, "expected inspector and image paths");

const first = run(imagePath);
const second = run(imagePath);
assert.equal(second, first, "inspector output must be deterministic");

const report = JSON.parse(first);
assert.equal(report.format, "boundary-image-economy/v1");
assert.equal(report.imageByteLength, readFileSync(imagePath).byteLength);
assert.match(report.imageSha256, /^[0-9a-f]{64}$/);
assert.match(report.programTransitionDigest, /^[0-9a-f]{64}$/);
assert.equal(
  report.framingByteEstimate + report.semanticPayloadByteEstimate,
  report.imageByteLength,
);
assert.equal(report.sections.segments.records, 2);
assert.equal(report.sections.constructors.records, 3);
assert.equal(report.largestSegments.length, 2);
assert.equal(report.largestConstructors.length, 3);
assert.equal(report.framingByteEstimate, 461);
assert.equal(report.semanticPayloadByteEstimate, 279);
assert(!first.includes("boundary.example.lookup.v1"));

const temporary = mkdtempSync(join(tmpdir(), "boundary-image-economy-"));
try {
  const malformedPath = join(temporary, "malformed.bpi1");
  const malformed = Buffer.from(readFileSync(imagePath));
  malformed[0] ^= 0xff;
  writeFileSync(malformedPath, malformed);
  const rejected = spawnSync(inspector, [malformedPath], { encoding: "utf8" });
  assert.notEqual(rejected.status, 0, "malformed BPI1 must be rejected");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}

function run(path) {
  const result = spawnSync(inspector, [path], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  return result.stdout;
}
