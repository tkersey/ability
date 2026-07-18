# StaticMachine state

StaticMachine state has two representations with different ownership:

1. \`Machine.State\` is a transient decoded working value.
2. \`Machine.encodeState\` returns the canonical portable continuation image.

Only the second representation crosses process, storage, repository, or WASM
boundaries.

## Canonical state image v1

The image encodes, in order:

\`\`\`text
magic = "ABL_STM1"
format version
fingerprint version
program label
plan label
plan hash
remaining deterministic instruction budget
next turn ordinal
active continuation frames
captured locals and values
pending operation or after continuation
image checksum
\`\`\`

Integers use fixed little-endian encodings. Lengths are checked before
allocation. Readers reject a wrong program or plan identity, an invalid enum or
boolean, malformed frame topology, inconsistent pending state, checksum
mismatch, and trailing bytes.

The checksum detects corruption and accidental mismatches. It is not a
signature and grants no trust.

## State law

For any valid runnable or parked state \`s\`:

\`\`\`text
decodeState(encodeState(s))
\`\`\`

must preserve:

- the next effect site and payload;
- the accepted response type;
- the continuation stack;
- remaining deterministic budget;
- terminal result or deterministic failure after continuation.

Encoding does not advance the machine. Decoding creates fresh working
ownership, so live request tokens may change; semantic site identity, payload,
and continuation behavior may not.

Completed states are consumed as terminal results and are not encoded as
runnable continuation state.

## Limits

\`maximum_frames\` must cover the statically reachable helper depth.
\`maximum_state_bytes\` bounds encoded state at the public seam. Core interpreter
fuel remains independently bounded and is exposed through
\`Machine.Manifest.maximum_interpreter_fuel\`.
