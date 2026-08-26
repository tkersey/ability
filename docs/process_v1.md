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
aliases reject before writing.

`ABL_PST1` stores the program transition digest and a minimally encoded frame
sequence. Each frame contains its continuation-constructor identity and exact
future-live environment bytes. It stores no fuel, host sequence, Machine
profile, scheduler state, pointer, or instance identity.

`boundary.process_v1.state.validateEncoding` checks canonical framing;
`boundary.process_v1.validateState` additionally admits every constructor
environment and path invariant against the supplied BPI1 before execution.

The fixed `boundary-process-kernel-v1.wasm` module imports nothing and retains
no authoritative Process State between calls. The generic
`scripts/boundary-process-step.mjs` adapter builds one byte input, invokes one
kernel operation, writes the canonical outcome bytes, and exits.

Run:

```text
zig build check-boundary-process-v1 --summary all
zig build emit-boundary-process-kernel-v1
```
