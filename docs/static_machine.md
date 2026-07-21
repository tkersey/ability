# Boundary StaticMachine

`boundary.staticMachine(Program, options)` generates a comptime-known,
defunctionalized reducer for a type returned by `boundary.program`. It is the
Boundary-to-World compile-time seam for World Comptime v1.

```zig
const Program = boundary.program("example", Handlers, Body);
const Machine = boundary.staticMachine(Program, .{
    .state_encoding = .canonical_v1,
    .world_ports = .explicit,
    .maximum_frames = 64,
    .maximum_state_bytes = 1 << 20,
});
```

The machine reuses the validated `ProgramPlan` and generated session reducer.
It does not decode a Certified Boundary Module, load bytecode, search a runtime
registry, or select handlers dynamically. Functions, blocks, instructions,
operation sites, schemas, and continuation shapes remain comptime-known to Zig.

The first backend generates dispatch from the comptime-known plan. It does not
interpret an arbitrary serialized module at runtime.

## Contract

The generated type exposes:

- `State`, a machine-branded opaque pointer handle backed by private state storage;
- `InitialArgs`, derived from the entry function parameter tuple;
- `Result`, a terminal value view that borrows from `OwnedResult`, its storage owner,
  application-authored `Failure`, and the closed machine `Error` set;
- `EffectRow`, the program's static protocol and site descriptors;
- `Manifest`, compile-time identity, format, site, and limit metadata;
- `initialState`, `cloneState`, `reduce`, `current`, `resume`, `resumeAfter`, and `returnNow`;
- `encodeState`, `decodeState`, `validateState`, and `deinitState`.

`reduce` stops at an operation request, an after-continuation request, terminal
completion, or an explicit caller-fuel yield. Caller-fuel exhaustion is
resumable. Cumulative machine-budget exhaustion, program-authored failures, and
deterministic reduction failures after dispatch begins are terminal errors.
Terminal states cannot be validated or encoded as resumable state.
`Body.Error` therefore may not reuse the reserved operational names
`OutOfMemory`, `ProgramContractViolation`, or `ExecutionBudgetExceeded`; World
can distinguish authored terminal failure from retryable or supervisory
failure directly from the closed error value.

Transferring a completed string or structured value into `OwnedResult` may
allocate. If that detachment reports `OutOfMemory`, the public reduction
transaction preserves its input State and caller fuel, and the caller may retry
`reduce`; completion is marked consumed only after the transfer succeeds.

`boundary.staticMachine` accepts only the authentic type returned by
`boundary.program`. Live `State` handles are branded by that Program and the
StaticMachine options, so one machine cannot consume another machine's handle.
Contract-equivalent machines may still exchange canonical state bytes through
`encodeState` and `decodeState`; that compatibility is checked from the encoded
machine contract rather than the live Zig handle type.

StaticMachine v1 rejects recursive helper/provider frame graphs and programs
with output collection or result/output cleanup hooks. Its compact condition
authority rejects a reachable path that revisits unchanged predicate A after
evaluating distinct predicate B, and reachable helpers may not write their
parameter locals. Broader programs remain available through `Program.Session`
until a future portable representation can validate those histories exactly.
Control-path validation admits at most 32,768 states: the count is the combined
instruction-and-block node count multiplied by eight and by one plus the
maximum distinct-predicate count of any declared function. That permits at
most 4,096 nodes when no predicate exists, 2,048 nodes when the maximum is one,
and fewer as the maximum grows. Generated direct
instruction metadata and one shared 1,048,576-unit work budget also bound CPU
across repeated after-continuation reachability checks. StaticMachine derives a
per-machine worst-case validation bound at comptime and rejects a machine whose
bound exceeds that budget. Product or sum
schemas containing `[][]const u8` reject as well: mutation of that outer
string-list carrier would make alias topology observable, while canonical state
deliberately does not preserve pointer identity. StaticMachine v1 also rejects
product schemas with comptime fields because its canonical decoder cannot
reconstruct compile-time-only values at runtime. Non-exhaustive enum carriers
are also rejected: the v1 ordinal codec cannot represent an unknown runtime
tag. Enum carriers with target-dependent `usize`, `isize`, or C-ABI integer tag
types are rejected as well so one source program has one target-neutral
contract identity. Immutable
`[]const []const u8` carriers remain supported. An authored `afterDispatch`
must also have the runtime shape used by the static after-site contract: a valid
receiver, one value parameter, and a return value. Every reachable authored
after chain must close: a
potentially innermost handler input matches the owning function value, each
inner handler output matches the adjacent outer handler input, and a potentially
outermost handler output matches the function result. Terminal aborts and
non-completing helper or provider calls end after-chain reachability; they do
not connect a site to a syntactic successor. Repeated comparisons of an
unchanged local preserve their branch relation, so mutually exclusive after
sites are not treated as an adjacent chain. Writing that source local discards
the relation. Legacy `Program.Session` retains
its dynamic final-output behavior; StaticMachine rejects that shape because
World requires a closed static effect contract. Those restrictions keep the
first portable-state and completion contracts exact; a later ABI revision may
expand support.

StaticMachine v1 gives every bare `usize` and every `usize` nested in a product
or sum schema a 32-bit semantic domain. The canonical image retains its fixed
eight-byte little-endian slot, but values above `maxInt(u32)` reject before
state mutation. Concrete `u64` fields inside product and sum schemas remain
full-width. `Machine.Manifest.canonical_usize_bits` publishes this contract,
and the complete machine fingerprint recursively binds each concrete schema
carrier. Consequently, replacing a full-width `u64` field with canonical
`usize` changes the machine contract even though both fields occupy the
ProgramPlan `.usize` codec. Extracting a `u64` schema field into a ProgramPlan
`.usize` local crosses that boundary: the extracted value must fit the same
32-bit canonical domain. Nominally distinct Zig types with the same admitted
carrier semantics remain contract-compatible. Legacy `Program.Session` keeps
its native-width `usize` behavior.

`maximum_state_bytes` must also fit the canonical unsigned 32-bit length
domain. This keeps application-selected state admission representable by the
same format on native and wasm32 targets.

Canonical plan and structured-value identity forget nominal Zig schema labels;
those labels remain source-admission and diagnostic metadata. Structural
carrier identity binds the fields that determine encoding and reduction,
including an enum's tag signedness and width, exhaustiveness, field names, and
explicit discriminant values. Renaming an otherwise identical carrier therefore
preserves compatibility, while changing an enum representation or discriminant
does not.

## Authority boundary

The live `State` handle owns allocator-backed working storage because Zig
values such as strings and structured payloads require transient memory.
It follows Zig's single-owner pointer convention: copying the pointer creates an
alias, not a second owner, and exactly one alias may be passed to `deinitState`.
Use `cloneState` when two independently releasable live states are required.
Each nonterminal mutation runs against a cloned candidate state. The candidate
commits only after exact validation proves that its complete canonical image
fits `maximum_state_bytes`. Failed cloning, response validation, or size
admission leaves the authoritative state, pending request, and caller fuel
unchanged. Deterministic reduction failures retain their existing terminal
semantics. A `reduce` call on an already parked State fails before cloning, so
the issued request borrow remains valid. After-continuation storage is
allocated lazily and reserved inside
the candidate before response ownership or handler dispatch can commit. The
temporary clone is an implementation resource, not portable state, and
`maximum_state_bytes` is not a heap budget. Only bytes returned by
`encodeState` represent continuation state across a process, allocator, or
WASM-instance boundary.

`Request` and `AfterRequest` are borrowed projections into their owning
`State`. Their structured payload or current-value fields remain valid only
until the next mutation or deinitialization of that State. A host must encode or
copy the request data it needs before mutating or releasing the State.
Live ownership uses a target-width session identifier and a `u64` per-session
token. Both sources fail closed before wrap; exhaustion never reuses an
identifier. Resume validates the session, token, turn, site, value fingerprint,
complete request fingerprint, plan contract, and continuation refs against the
authoritative pending state. Request metadata is a projection: reduction uses
the pending state, not caller-modified projection fields.

When `.debug_metadata = true`, `Manifest.debug_metadata` contains the generated
operation and after-site tables and `Manifest.includes_debug_metadata` is true.
When disabled, the optional metadata is null. This diagnostic projection does
not affect machine identity or canonical state bytes.

Direct `Machine.EffectRow` coverage accepts only the exact descriptor types
generated by that EffectRow. Copying public owner, index, or fingerprint fields
into another type does not create site authority, even when those fields are
byte-for-byte equal.

The `.done` transition carries `*OwnedResult`, a pointer to an opaque owner. Its
`value()` projection returns `Machine.Result` and borrows any backing storage
attached to that owner. Keep the owner alive until the value has been consumed
or copied, then call `deinit`. `deinit` is the only public operation that releases
the backing storage; StaticMachine exposes neither typed storage nor a
storage-detachment operation.

Encoded state contains no implicit allocator identity, native address, function
pointer, session token, runtime handle, or host authority. Application values
may themselves contain credentials, secrets, personal data, or other sensitive
bytes. Boundary does not classify or protect those values; callers must apply
appropriate storage and transport controls.

Decoding assigns fresh transient ownership and validates the complete state
before it can run. World may close static handlers around this machine at
comptime. Boundary does not grant receiver authority, define host policy, or
implement capabilities.

`Machine.Manifest.plan_hash` and `Machine.EffectRow.hash` are the canonical
ProgramPlan identity and preserve site coordinates across contract-compatible
carrier implementations. `legacy_plan_hash` retains the provenance-sensitive
Program.Session identity. `request_trace_plan_hash` identifies the complete
machine contract, including concrete schema-carrier semantics and the
deterministic `maximum_state_bytes` admission limit, and is the value carried by
StaticMachine request traces.

## Compatibility

`Program.run` and `Program.Session` remain available. `StaticMachine` is an
additional backend over the same semantic frontend. Unsupported plans fail at
comptime as the machine type is constructed, including when a caller inspects
only `Machine.Manifest`; support validation is never deferred until
`initialState` or `reduce`. No fallback to a runtime-loaded module occurs.

Legacy `ProgramPlan.validate`, entry analysis, `Program.protocol`, and
`Program.Session` retain their v0 completion interpretation. StaticMachine v1
uses a separately named corrected analysis in which jump targets remain block
coordinates rather than being read as function ordinals. Consequently,
`Program.protocol` and `Machine.EffectRow` can intentionally expose different
site sets for a legacy namespace-collision plan. Static sites retain the exact
matching legacy fingerprint as provenance, even when corrected reachability
changes their dense ordinal. World v1 must close `Machine.EffectRow`; it must
not infer the static residual row from `Program.protocol`.
