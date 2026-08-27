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

For the native buffer API, allocate at least `minimum_output_bytes` for each
output/candidate/environment arena and at least `minimum_scratch_bytes` for the
scratch arena before retrying the same input. Every mutable output, scratch,
and validation arena must be disjoint from all source bytes and from every
other mutable arena; readonly source slices may overlap. Invalid mutable
aliases reject before writing. Every State-bearing outcome is returned from the
supplied output-State arena, including byte-identical pending-request recovery.

`ABL_PST1` stores the program transition digest and a minimally encoded frame
sequence. Each frame contains its continuation-constructor identity and exact
future-live environment bytes. It stores no fuel, host sequence, Machine
profile, scheduler state, pointer, or instance identity.

`boundary.process_v1.state.validateEncoding` checks canonical framing;
`boundary.process_v1.validateState` additionally admits every constructor
environment and path invariant against the supplied BPI1 before execution.
One `advance` invocation performs that full admission once and carries an
internal, non-serializable admitted top-frame projection through the reduction.
Every internal State producer must return that refinement and declare the exact
changed frame suffix through the same mutation helper that serializes it; one
checked constructor admits every frame in that suffix and their internal stack
pairs, plus the pair crossing from the preserved prefix, before publishing
canonical bytes.

The fixed `boundary-process-kernel-v1.wasm` module imports nothing and retains
no authoritative Process State between calls. The generic
`scripts/boundary-process-step.mjs` adapter asks the kernel to prepare its
canonical input header from `u64` file sizes before reading payload files,
copies only admitted BPI1 and instance/result bytes, invokes one kernel
operation, writes the canonical outcome bytes, and exits.
If the fixed input arena cannot hold those payloads, preparation returns a
canonical transactional `NeedsCapacity` outcome before any payload copy.
Kernel-input and kernel-outcome framing uses `u64` component lengths. The
wasm32 kernel accepts those lengths as scalar preflight data, so a larger finite
State reports capacity without truncation even though that instance cannot
address the State itself.
The fixed-kernel page requirement starts from live WebAssembly pages and adds
the growth delta for input, serialized output, State, candidate State, value,
request, both environment arenas, and scratch.

Run:

```text
zig build check-boundary-process-v1 --summary all
zig build emit-boundary-process-kernel-v1
```
