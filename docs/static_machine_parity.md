# StaticMachine parity

`Program.Session` remains the executable semantic oracle for the
`StaticMachine` backend.

For the same Boundary program, entry arguments, responses, and deterministic
fuel, the two backends must agree on:

- operation and after-site semantic coordinates;
- handler-derived after input and output refs, including the final after site;
- payload semantic values;
- response acceptance and rejection;
- helper suspension and resumption;
- terminal value;
- deterministic failure;
- the point at which caller fuel yields and cumulative fuel fails.

Canonical StaticMachine additionally constrains `usize` to the explicit 32-bit
portable domain published by its manifest, including a concrete `u64` schema
field after extraction into a ProgramPlan `.usize` local. Legacy Session
remains the oracle inside that shared domain and deliberately retains
native-width behavior above it.

Session-local request tokens, legacy provenance-sensitive site fingerprints,
StaticMachine canonical site fingerprints, and raw continuation bytes are
intentionally excluded. `Program.protocol` and `Program.Session` retain the
legacy identity domain. `Machine.EffectRow` and StaticMachine requests use the
target-neutral canonical domain in their primary fingerprint fields; legacy
fingerprints remain explicit sidecars for diagnostics and adapters. Parity
compares the two backends' shared semantic coordinates and values rather than
equating their distinct identity domains. A decoded StaticMachine state receives
fresh transient ownership, and the v1 state image is not the legacy capsule
format.

The focused parity gate is:

```text
zig build check-boundary-static-machine-parity
```

The broader StaticMachine gates cover canonical state round trips,
provenance-only interoperability, nested helper suspension, malformed images,
active non-completing helper and provider children, control-path-valid after
stacks, exact typed coherence for duplicated decoded values, derived-frame cache
coherence, response and completed-result ownership under allocation failure,
atomic state-size admission, allocation-free bounded validation, compact
control-path scratch and work limits, direct instruction ownership, lazy
after-stack reservation, handler-derived
after contracts, concrete schema-carrier identity, deterministic state-limit
identity, portable numeric bounds, explicit fuel yield, terminal failure,
nominal state handles, authentic Program construction, the complete fixture
agent read/write flow, provider read/write completion, and direct compilation
of the generated reducer for `wasm32-freestanding`:

```text
zig build check-boundary-static-machine
zig build check-boundary-static-machine-wasm32
zig build check-boundary-static-agent
zig build check-boundary-static-provider
```

Parity fails if StaticMachine decodes a runtime module, observes a different
effect site or payload, accepts a response that `Program.Session` rejects,
changes continuation behavior, or produces a different terminal value.
