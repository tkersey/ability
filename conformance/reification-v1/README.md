# Boundary Reification v1 baseline

`baseline.lock.json` binds the exact Boundary v1.5.0 source fixture, generated
vectors, Zig toolchain, and retained performance proof inputs before the
reification compiler refactor.

`baseline/vectors.json` records semantic and Machine contract digests, Machine
options, canonical `ABL_RNF2` States, request identities and payloads, terminal
results, and fuel transitions for the required fixture classes. The malformed
State inventory records fail-closed rejection.

Run:

```sh
zig build check-boundary-reification-baseline --summary all
```

The verifier rebuilds every vector and byte-compares it with the committed
baseline. Any intended semantic change must be specified separately; the
reification implementation must not refresh this lock to hide drift.

The release proof additionally compiles the internal BPI1 clause evaluator from
a reduced graph with no Machine-v2 modules. BPI1 is the public canonical
artifact; raw clause evaluation is not a public package API.

Asset emission consumes the executed `boundary-reification-v1-proof.json`
artifact produced only after the complete receipt gate succeeds. Its writer
derives baseline inventory, semantic invariance, malformed-corpus counts,
generated comparisons, WASM imports, and source topology from their executed
outputs. The receipt writer rejects a missing, failed, or mistyped proof and
derives its claims from that artifact rather than asserting them independently.
