import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const kernel = process.argv[2];
const vector = fs.readFileSync(process.argv[3]);
const adapter = process.argv[4];
let cursor = 4;
const inputLength = vector.readUInt32LE(cursor);
const outputLength = vector.readUInt32LE(cursor + 4);
cursor += 8;
const input = vector.subarray(cursor, cursor + inputLength);
const expected = vector.subarray(
  cursor + inputLength,
  cursor + inputLength + outputLength,
);
const imageLength = input.readUInt32LE(12);
const instanceLength = input.readUInt32LE(16);
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "boundary-process-step-"));
try {
  const imagePath = path.join(temporary, "system.bpi1");
  const initialPath = path.join(temporary, "initial.bin");
  fs.writeFileSync(imagePath, input.subarray(28, 28 + imageLength));
  fs.writeFileSync(
    initialPath,
    input.subarray(28 + imageLength, 28 + imageLength + instanceLength),
  );
  const execution = spawnSync(process.execPath, [
    adapter,
    "--kernel", kernel,
    "--image", imagePath,
    "--initial-args", initialPath,
  ]);
  if (execution.status !== 0) {
    throw new Error(execution.stderr.toString("utf8"));
  }
  if (!execution.stdout.equals(expected)) {
    throw new Error("boundary-process-step changed canonical kernel output");
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
