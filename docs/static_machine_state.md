# StaticMachine state

StaticMachine state has two representations with different ownership:

1. `Machine.State` is a machine-branded opaque pointer owner over transient
   working storage. Pointer copies are aliases; `Machine.cloneState` creates an
   independent owner.
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
handler-derived after-continuation input and output refs, and the deterministic
maximum state-image byte and control-validation work limits. The legacy
`ProgramPlan.hash` and legacy session-site fingerprints remain diagnostic v0
provenance; neither is a portable StaticMachine state identity. A plan-local
`ValueRef` becomes portable only when paired with this complete machine
contract.

Canonical schema identity is structural. Nominal Zig schema labels remain
diagnostic and source-admission metadata but do not distinguish portable state.
Enum identity includes exhaustiveness, ordered field names, and explicit
discriminant values. Physical tag signedness and width are not canonical
observations because the wire codec represents an enum by its logical tag name.
StaticMachine v1 rejects non-exhaustive enum carriers because the tag-name wire
codec cannot reconstruct unknown tags.

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
`u64` schema fields remain full-width while schema-typed; extracting one into a
ProgramPlan `.usize` local applies the canonical 32-bit domain. Oversized
authored values, reachable `const_usize` instructions, responses,
reducer-produced values, and decoded state all fail closed.

Exhaustive enums may use fixed-width, target-sized, or C-ABI integer tag types.
The carrier contract normalizes those physical representations, so equal
ordered field names and explicit discriminants retain one identity across
native and wasm32 targets.

Readers reject a mismatched machine identity, invalid enum or boolean, malformed
frame topology, an after stack that is not reachable along the decoded control
path, an unowned root after-stack prefix, a pending operation whose after entry
is already recorded, an unwitnessed cursor after a non-completing call, any
after unwind before the function's return boundary, reducer caches that disagree
with their source locals, an absent non-unit parameter, an absent non-unit local
that the exact continuation can read before defining it or reaching the next
revalidated suspension boundary, a first after-unwind value that differs from
the completed function value, an after-unwind current value ref that is not
derived by folding the consumed
suffix of the validated after stack, a full after stack behind a pending
after-producing operation, inconsistent pending state, checksum mismatch, and
trailing bytes. Every duplicated canonical value is compared exactly by its
typed semantic structure; 64-bit trace fingerprints are never accepted as
equality witnesses. A live child frame is the explicit witness that permits its
parent cursor to remain after a non-completing helper or provider call. The
checksum detects corruption and accidental mismatches. It is not a signature
and grants no trust.

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

Encoding does not advance the machine. Decoding creates a fresh live session
and issues a nonzero token for any parked request; token values may repeat only
across distinct session identities. Semantic site identity, payload, and
continuation behavior may not change.

Live session identifiers and `u64` request tokens are intentionally absent from
the image. Their allocators fail before wrap, and decoding assigns fresh live
ownership. A resume request must match the pending state's session, token, turn,
site, payload or current-value fingerprint, complete request fingerprint,
machine contract, and continuation refs. The pending state—not mutable request
projection metadata—authorizes and supplies reduction.

Every successful constructor or public mutation that leaves a runnable or
parked state proves this law before commit. `initialState`, `reduce`, `resume`,
and `resumeAfter` therefore cannot return an opaque live state that later fails
`validateState` or `encodeState` solely because it exceeds
`maximum_state_bytes`. A rejected response or parked transition leaves the
prior canonical bytes and pending request unchanged. Rejecting `reduce` on an
already parked State also preserves the State allocation and its issued request
borrow. Terminal completion and
terminal failure remain outside this resumable-state law.

Completed and terminally failed states are not encoded as runnable continuation
state. Terminal failures include program-authored failures, cumulative machine
budget exhaustion, and deterministic reduction failures after dispatch begins.

## Limits

`maximum_frames` must cover the finite statically reachable helper/provider
depth. Recursive frame graphs are rejected in v1. `maximum_state_bytes` is a
structural writer and admission bound, not merely a post-encoding check and not
a heap budget, and it must fit the canonical `u32` length domain. Bounded
validation reuses the canonical encoder traversal in a
count-only mode: it performs checked length arithmetic without allocating or
copying a second image. Nonterminal mutation may temporarily clone one live
state so rejection and allocator-dependent failure remain atomic. Core
interpreter fuel and the derived maximum turn count remain independently
bounded and are exposed through `Machine.Manifest`. After-continuation entries
share the same logical
fuel-derived bound but allocate only as they are recorded; unused capacity is
neither serialized nor semantic.

Control-path reachability validation uses a compact queue and bitset while
retaining one compact condition-authority bitset for every active frame. The
authority keeps the cached `last_condition` relation separate from the current
truth relation of its tracked predicate source. Ordinary local writes update
only the source relation; the cached relation changes only when a predicate
instruction executes.
StaticMachine v1 admits at most 32,768 `(control node, suspension traversed,
condition relation)` states. The queue and visited set reserve at most 69,632
bytes. Canonical 64-bit word rounding makes the zero-predicate, maximum-depth
case the largest simultaneous frame-authority layout at another 32,768 bytes,
for a 102,400-byte ceiling on explicit allocation-free validation
buffers. The state count is
`max(1, instructions + blocks) * 2 * (2 + 6 * maximum distinct condition predicates)`.
The predicate maximum covers every declared function because decoded function
indices remain untrusted until validation. A separate 4,096-node guard keeps
the public structural ceiling fixed; the state formula may impose a lower node
limit as the predicate count grows. A reachable control path may use one
or more predicates. Re-evaluating the same unchanged predicate preserves its
exact source relation, and the two variants of one unchanged binary sum
transfer the complementary relation exactly. Construction rejects only an
unchanged predicate revisited after an interleaved distinct predicate and
cross-local predicate aliases that require authority the compact carrier does
not encode. Final control-path authority is also checked against the decoded
source local whenever that source remains valid.
`Machine.Manifest` publishes the actual path-state count and the combined
queue, visited-set, and frame-authority scratch bytes together with both v1
ceilings. Comptime-generated `u16` metadata maps each
instruction directly to its owning block and any nested target. Every
path-state dequeue consumes one shared call-wide work unit across after entries,
frame cursors, and forward availability proof for every absent non-unit local.
Availability starts at the exact cursor, uses the stored condition only for that
cursor's terminator, and stops at a definition or the next effect or provider
suspension. Each absent local is budgeted over the complete predicate-authority
path-state domain with the fixed suspension dimension removed. Every public
resume and parked reduction revalidates the resulting state, so admission need
not reconstruct discarded execution history. One validation may consume at
most 1,048,576 units. StaticMachine derives
`Machine.Manifest.control_validation_step_bound` from the admitted control
graph, active local capacity, frame depth, and after-stack capacity. Acyclic
after graphs use their distinct reachable site count. When a function contains
both a reachable after site and a reachable control cycle, the conservative
capacity uses the cumulative fuel ceiling because the cycle may revisit an
after site. Machine construction fails at comptime when that bound exceeds the
limit. Runtime exhaustion still rejects malformed state with
`ProgramContractViolation`. The derived bound and ceiling are part of the
complete machine contract and are published through `Machine.Manifest`.
