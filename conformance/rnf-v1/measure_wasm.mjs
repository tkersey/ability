import { readFile } from "node:fs/promises";

const warmupIterations = 2_000;
const measuredIterations = 20_000;
const sampleCount = 5;

function measure(
  run,
  warmupCount = warmupIterations,
  measuredCount = measuredIterations,
  samplesCount = sampleCount,
) {
  for (let index = 0; index < warmupCount; index += 1) {
    if (run() !== 1) {
      throw new Error("WASM performance warmup invocation failed");
    }
  }

  const samples = [];
  for (let sample = 0; sample < samplesCount; sample += 1) {
    const start = process.hrtime.bigint();
    for (let index = 0; index < measuredCount; index += 1) {
      if (run() !== 1) {
        throw new Error("WASM performance measured invocation failed");
      }
    }
    samples.push(Number(process.hrtime.bigint() - start));
  }

  samples.sort((left, right) => left - right);
  return samples[Math.floor(samples.length / 2)];
}

const [wasmPath, exportName] = process.argv.slice(2);
if (wasmPath === "--self-test") {
  let calls = 0;
  try {
    measure(
      () => {
        calls += 1;
        return calls === 1 ? 1 : 0;
      },
      1,
      1,
      1,
    );
  } catch (error) {
    if (error.message === "WASM performance measured invocation failed") {
      process.stdout.write("wasm_measurement_falsifier=pass\n");
      process.exit(0);
    }
    throw error;
  }
  throw new Error("WASM performance stale-checksum falsifier was accepted");
}
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

process.stdout.write(`${measure(run)}\n`);
