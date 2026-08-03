import { readFile } from "node:fs/promises";

const wasmPath = process.argv[2];
if (!wasmPath) {
  throw new Error("usage: node run_machine_wasm.mjs <machine.wasm>");
}

const bytes = await readFile(wasmPath);
const module = await WebAssembly.compile(bytes);
if (WebAssembly.Module.imports(module).length !== 0) {
  throw new Error("Boundary Machine parity witness must be import-free");
}

const instance = await WebAssembly.instantiate(module, {});

function observe(runName, pointerName) {
  const length = instance.exports[runName]();
  const pointer = instance.exports[pointerName]();
  if (
    typeof length !== "number" ||
    typeof pointer !== "number" ||
    length === 0
  ) {
    throw new Error(`Boundary Machine wasm parity witness failed: ${runName}`);
  }
  return Buffer.from(
    new Uint8Array(instance.exports.memory.buffer, pointer, length),
  );
}

const machineOutput = observe(
  "boundaryMachineParityRun",
  "boundaryMachineParityOutputPointer",
);
const portableValueOutput = observe(
  "boundaryMachineValueParityRun",
  "boundaryMachineValueParityOutputPointer",
);
process.stdout.write(Buffer.concat([machineOutput, portableValueOutput]));
