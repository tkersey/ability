# StaticMachine state

StaticMachine state has two representations with different ownership:

1. `Machine.State` is a machine-branded owner handle over opaque transient
   working storage.
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

The machine contract fingerprint binds the authored program label, a
target-neutral canonical ProgramPlan identity, the recursive concrete carrier
semantics of every product and sum schema, every nested-provider target mapping,
and handler-derived after-continuation input and output refs. The legacy
`ProgramPlan.hash` and legacy session-site fingerprints remain diagnostic v0
provenance; neither is a portable StaticMachine state identity. A plan-local
`ValueRef` becomes portable only when paired with this complete machine
contract.

StaticMachine request and after-site identities use a target-neutral canonical
domain. Provenance-only changes such as `ir_hash` do not change canonical
requests or state bytes. The authored program label is not provenance-only:
changing it changes machine identity and prevents cross-decoding.
Machines with identical complete contract identities may decode each other's
state even though their live Zig `State` handle types remain distinct.

Integers use fixed little-endian encodings. Value encoding is independent of
transient pointer aliasing for the admitted v1 value surface: semantically equal
live states produce identical bytes whether equal immutable strings or
structured values share backing storage. Product and sum schemas containing a
mutable outer string-list carrier (`[][]const u8`) are rejected at comptime,
because mutation would make that discarded alias topology observable. Lengths
and the configured maximum image size are checked during writer growth, before
additional capacity is allocated.

Canonical `usize` values have a target-neutral 32-bit semantic domain, even
though the wire slot remains eight bytes. This rule covers bare values,
structural counts, and `usize` fields nested in product or sum schemas. Concrete
`u64` schema fields remain full-width. Oversized authored values, reachable
`const_usize` instructions, responses, reducer-produced values, and decoded
state all fail closed.

Readers reject a mismatched machine identity, invalid enum or boolean, malformed
frame topology, an after stack that is not reachable along the decoded control
path, an unowned root after-stack prefix, a pending operation whose after entry
is already recorded, an unwitnessed cursor after a non-completing call, any
after unwind before the function's return boundary, reducer caches that disagree
with their source locals, a first after-unwind value that differs from the
completed function value, an after-unwind current value ref that is not derived
by folding the consumed suffix of the validated after stack, a full after stack
behind a pending after-producing operation, inconsistent pending state,
checksum mismatch, and trailing bytes. Every duplicated canonical value is
compared exactly by its typed semantic structure; 64-bit trace fingerprints are
never accepted as equality witnesses. A live child frame is the explicit
witness that permits its parent cursor to remain after a non-completing helper
or provider call. The checksum detects corruption and accidental mismatches. It
is not a signature and grants no trust.

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

Every successful constructor or public mutation that leaves a runnable or
parked state proves this law before commit. `initialState`, `reduce`, `resume`,
and `resumeAfter` therefore cannot return an opaque live state that later fails
`validateState` or `encodeState` solely because it exceeds
`maximum_state_bytes`. A rejected response or parked transition leaves the
prior canonical bytes and pending request unchanged. Terminal completion and
terminal failure remain outside this resumable-state law.

Completed and terminally failed states are not encoded as runnable continuation
state. Terminal failures include program-authored failures, cumulative machine
budget exhaustion, and deterministic reduction failures after dispatch begins.

## Limits

`maximum_frames` must cover the finite statically reachable helper/provider
depth. Recursive frame graphs are rejected in v1. `maximum_state_bytes` is a
structural writer and admission bound, not merely a post-encoding check and not
a heap budget. Bounded validation reuses the canonical encoder traversal in a
count-only mode: it performs checked length arithmetic without allocating or
copying a second image. Nonterminal mutation may temporarily clone one live
state so rejection remains atomic. Core interpreter fuel and the derived
maximum turn count remain independently bounded and are exposed through
`Machine.Manifest`. After-continuation entries share the same logical
fuel-derived bound but allocate only as they are recorded; unused capacity is
neither serialized nor semantic.
