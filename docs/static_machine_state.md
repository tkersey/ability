# StaticMachine state

StaticMachine state has two representations with different ownership:

1. `Machine.State` is an opaque transient working-state owner.
2. `Machine.encodeState` returns the canonical portable continuation image.

Only the second representation crosses process, storage, repository, or WASM
boundaries.

## Canonical state image v1

The image encodes, in order:

```text
magic = "ABL_STM1"
format version
fingerprint version
program label
plan label
full machine contract fingerprint
remaining deterministic instruction budget
next turn ordinal
active continuation frames
captured locals and values
pending operation, after continuation, or runnable after-unwind state
image checksum
```

The machine contract fingerprint binds a target-neutral canonical ProgramPlan
identity and every nested-provider target mapping. The legacy `ProgramPlan.hash`
remains diagnostic v0 provenance and is not the portable state identity.

Integers use fixed little-endian encodings. Value encoding is independent of
transient pointer aliasing: semantically equal live states produce identical
bytes whether equal strings or structured values share backing storage. Lengths
and the configured maximum image size are checked during writer growth, before
additional capacity is allocated.

Readers reject a mismatched machine identity, invalid enum or boolean, malformed
frame topology, inconsistent pending state, checksum mismatch, and trailing
bytes. The checksum detects corruption and accidental mismatches. It is not a
signature and grants no trust.

## State law

For any valid runnable or parked state `s`:

```text
decodeState(encodeState(s))
```

must preserve:

- the next effect site and payload;
- the accepted response type;
- the continuation stack, including a provider or after continuation parked
  across an external effect;
- remaining deterministic budget;
- terminal result or deterministic failure after continuation.

Encoding does not advance the machine. Decoding creates fresh working
ownership, so live request tokens may change; semantic site identity, payload,
and continuation behavior may not.

Completed and terminally failed states are not encoded as runnable continuation
state.

## Limits

`maximum_frames` must cover the finite statically reachable helper/provider
depth. Recursive frame graphs are rejected in v1. `maximum_state_bytes` is a
structural writer bound, not merely a post-encoding check. Core interpreter fuel
and the derived maximum turn count remain independently bounded and are exposed
through `Machine.Manifest`.
