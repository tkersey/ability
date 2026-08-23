# Boundary Program Image v1

BPI1 is the canonical, target-neutral serialization of one Reified Program.
Executable truth is owned by
`src/image_v1.zig`, `src/image_emit_v1.zig`, and the conformance vectors.

The fixed header is 144 bytes. It contains `ABL_BPI1`, image version 1,
program-evaluator semantics version 1, exact total length,
`program_transition_digest`, and derived schema/evaluator scratch maxima. Bytes
reserved from the unreleased predecessor are canonical zero. A 240-byte
directory follows.

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

Segment records reserve their former cost word as zero. Synthetic caller-fuel
suspensions are normalized to semantic edges; explicit authored yields remain.

Validation checks the complete structure, dynamic values, graph references,
constructor laws, effect/schema/program-transition digests, scratch requirements,
and exact canonical re-encoding before execution. Image validity never grants
effect authority.

BPI1 contains no Machine ABI, State-format binding, Machine contract digest,
fuel law, segment cost, frame limit, State-byte limit, or lifetime budget.
