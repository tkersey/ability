# StaticMachine parity

`Program.Session` remains the executable semantic oracle for the
`StaticMachine` backend.

For the same Boundary program, entry arguments, responses, and deterministic
fuel, the two backends must agree on:

- operation and after-site semantic coordinates;
- payload semantic values;
- response acceptance and rejection;
- helper suspension and resumption;
- terminal value;
- deterministic failure;
- the point at which caller fuel yields and cumulative fuel fails.

Session-local request tokens, legacy provenance-sensitive site fingerprints,
StaticMachine canonical site fingerprints, and raw continuation bytes are
intentionally excluded. `Program.protocol` and `Program.Session` retain the
legacy identity domain. `Machine.EffectRow` and StaticMachine requests use the
target-neutral canonical domain. Parity compares their shared semantic
coordinates and values rather than equating those distinct identities. A
decoded StaticMachine state receives fresh transient ownership, and the v1
state image is not the legacy capsule format.

The focused parity gate is:

```text
zig build check-boundary-static-machine-parity
```

The broader StaticMachine gates cover canonical state round trips,
provenance-only interoperability, nested helper suspension, malformed images,
control-path-valid after stacks, response ownership under allocation failure,
handler-derived after contracts, explicit fuel yield, terminal failure, nominal
state handles, authentic Program construction, agent fixtures, and provider
fixtures:

```text
zig build check-boundary-static-machine
zig build check-boundary-static-agent
zig build check-boundary-static-provider
```

Parity fails if StaticMachine decodes a runtime module, observes a different
effect site or payload, accepts a response that `Program.Session` rejects,
changes continuation behavior, or produces a different terminal value.
