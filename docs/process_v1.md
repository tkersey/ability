# Boundary Process ABI v1

The portable running system is canonical BPI1 bytes plus either initial
arguments or canonical `ABL_PST1` Process State. `boundary.process_v1.advance`
validates those bytes and evaluates exactly one finite BPI1 reducer segment.

Outcomes are progressed State, a self-contained `ABL_ERQ1` Effect Request,
explicitly yielded State, completed Result, authored Failure, or transactional
operational `NeedsCapacity`. Matching resumes use `ABL_ERS1`; wrong-request,
wrong-schema, malformed, or results applied to a distinct successor State do
not mutate the input State. Request identity is content-addressed: a recurrence
with byte-identical State, site, continuation, and payload intentionally has the
same identity. Programs requiring occurrence distinction must author a counter
or nonce in portable State; exactly-once effects are not claimed.

For the native reference API, instantiate `boundary.process_v1.CapacityStorage`
with the physical interpreter's arena capacities and pass its current page
floor to `advance`. The storage product derives all mutable reducer buffers and
is the sole owner of `minimum_memory_pages`; semantic reduction records only
byte demand. Allocate at least `minimum_output_bytes` for each output-class
arena and at least `minimum_scratch_bytes` for the scratch arena before retrying
the same input. Every mutable output, scratch, and validation arena must be
disjoint from all source bytes and from every other mutable arena; readonly
source slices may overlap. Invalid mutable aliases reject before writing. Every
State-bearing outcome is returned from the supplied storage product, including
byte-identical pending-request recovery.
An invocation-local capacity tracker records the exact bytes required at each
output producer and reducer scratch allocation before a capacity error.
`NeedsCapacity` therefore preserves the current reduction requirement rather
than reconstructing a global maximum from BPI1 schema bounds or substituting
an unrelated arena's existing capacity.
Internally, one `ReductionAttempt` carries the outcome and that capacity
evidence together through final PKO1 serialization. The public `advance`
operation attaches page evidence from its `CapacityStorage` and projects only
the normative outcome.

`ABL_PST1` stores the program transition digest and a minimally encoded frame
sequence. Each frame contains its continuation-constructor identity and exact
future-live environment bytes. It stores no fuel, host sequence, Machine
profile, scheduler state, pointer, or instance identity.

`boundary.process_v1.state.validateEncoding` checks canonical framing;
`boundary.process_v1.validateState` additionally admits every constructor
environment and path invariant against the supplied BPI1 before execution.
One `advance` invocation performs that full admission once and carries an
internal, non-serializable admitted top-frame projection through the reduction.
State encoders return the canonical `StateView` they already validate. Every
internal State producer must return that refinement and declare the exact
changed frame suffix through the same mutation carrier that serializes it; the
codec-owned `MutationView` carries the first changed frame into one admission
constructor, which admits every frame in that suffix and their internal stack
pairs, plus the pair crossing from the preserved prefix, before publishing
canonical bytes. Initial construction returns bound `AdmittedState` directly
to the first reduction instead of decoding and admitting its environment again.

The fixed `boundary-process-kernel-v1.wasm` module imports nothing and retains
no authoritative Process State between calls. The generic
`scripts/boundary-process-step.mjs` adapter asks the kernel to prepare its
canonical input header from `u64` sizes obtained from open regular-file
descriptors before reading payload bytes. When preparation admits the input,
the adapter reads exactly those bytes through the same descriptors, rejects a
changed length, copies only BPI1 and instance/result bytes, invokes one kernel
operation, writes the canonical outcome bytes, and exits. The kernel itself is
also admitted as one nonblocking regular-file descriptor before materialization.
The reference relay's 64 MiB kernel ceiling is an operational limit of that
host implementation, not Process semantics; a larger compatible fixed kernel
can be transferred to another conforming host.
If the fixed input arena cannot hold those payloads, preparation returns a
canonical transactional `NeedsCapacity` outcome before any payload copy.
Kernel-input and kernel-outcome framing uses `u64` component lengths. The
wasm32 kernel accepts those lengths as scalar preflight data, so a larger finite
State reports capacity without truncation even though that instance cannot
address the State itself.
The relay normalizes exported wasm32 pointers to unsigned offsets before
indexing linear memory. Fixed-kernel storage declares input, serialized output,
State, candidate State, value, request, both environments, and scratch as typed
capacity arenas. Page accounting folds over that actual storage product, so a
new arena cannot be omitted from the calculation or its omission witness. Each
growth delta uses the arena's aligned physical size rather than only its logical
payload length.

Run:

```text
zig build check-boundary-process-v1 --summary all
zig build emit-boundary-process-kernel-v1
```
