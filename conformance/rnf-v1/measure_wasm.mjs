import { readFile } from "node:fs/promises";

const [wasmPath, exportName] = process.argv.slice(2);
if (!wasmPath || !exportName) {
  throw new Error("usage: node measure_wasm.mjs <machine.wasm> <export>");
}

const bytes = await readFile(wasmPath);
const module = await WebAssembly.compile(bytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("performance witness must be import-free");
}

const instance = await WebAssembly.instantiate(module, {});
const run = instance.exports[exportName];
if (typeof run !== "function") {
  throw new Error(`missing WASM performance export: ${exportName}`);
}

const warmupIterations = 2_000;
const measuredIterations = 20_000;
const sampleCount = 5;

let checksum = 0;
for (let index = 0; index < warmupIterations; index += 1) {
  checksum += run();
}
if (checksum === 0) {
  throw new Error("WASM performance warmup failed");
}

const samples = [];
for (let sample = 0; sample < sampleCount; sample += 1) {
  const start = process.hrtime.bigint();
  for (let index = 0; index < measuredIterations; index += 1) {
    checksum += run();
  }
  samples.push(Number(process.hrtime.bigint() - start));
}
if (checksum === 0) {
  throw new Error("WASM performance measurement failed");
}

samples.sort((left, right) => left - right);
process.stdout.write(`${samples[Math.floor(samples.length / 2)]}\n`);
