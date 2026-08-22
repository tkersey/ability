# Boundary Executable Image v1

BEI1 is the canonical, target-neutral serialization of one Reified Program and
one Machine execution envelope. Executable truth is owned by
`src/image_v1.zig`, `src/image_emit_v1.zig`, and the conformance vectors.

The fixed header is 144 bytes. It contains `ABL_BEI1`, image version 1, Machine
ABI 2, State format 1, kernel semantics 1, exact total length, existing Program
and Machine digests, Machine limits, and derived scratch/value maxima. A
240-byte directory follows.

Exactly ten contiguous sections occur in this order:

1. roots
2. schemas
3. failures
4. constants
5. effects
6. values
7. functions
8. segments
9. constructors
10. entry transitions

Integers are little-endian; lengths are logical and exact; reserved bytes are
zero; there is no padding or trailing data. Schemas are structurally interned
in depth-first postorder. Constants are interned by schema and canonical bytes.
All program identities are dense semantic identities, not source ordinals.

Validation checks the complete structure, dynamic values, graph references,
constructor laws, effect/schema/Program/Machine digests, scratch requirements,
and exact canonical re-encoding before execution. Image validity never grants
effect authority.
