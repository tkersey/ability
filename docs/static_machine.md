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

- `State`, a machine-branded owner handle backed by opaque state storage;
- `InitialArgs`, derived from the entry function parameter tuple;
- `Result`, application-authored `Failure`, and the closed machine `Error` set;
- `EffectRow`, the program's static protocol and site descriptors;
- `Manifest`, compile-time identity, format, site, and limit metadata;
- `initialState`, `reduce`, `current`, `resume`, `resumeAfter`, and `returnNow`;
- `encodeState`, `decodeState`, `validateState`, and `deinitState`.

`reduce` stops at an operation request, an after-continuation request, terminal
completion, or an explicit caller-fuel yield. Caller-fuel exhaustion is
resumable. Cumulative machine-budget exhaustion, program-authored failures, and
deterministic reduction failures after dispatch begins are terminal errors.
Terminal states cannot be validated or encoded as resumable state.

`boundary.staticMachine` accepts only the authentic type returned by
`boundary.program`. Live `State` handles are branded by that Program and the
StaticMachine options, so one machine cannot consume another machine's handle.
Contract-equivalent machines may still exchange canonical state bytes through
`encodeState` and `decodeState`; that compatibility is checked from the encoded
machine contract rather than the live Zig handle type.

StaticMachine v1 rejects recursive helper/provider frame graphs and programs
with output collection or result/output cleanup hooks. Those restrictions keep
the first portable-state and completion contracts exact; a later ABI revision
may expand support.

## Authority boundary

The live `State` handle owns allocator-backed working storage because Zig
values such as strings and structured payloads require transient memory.
Accepted response values are cloned into this opaque storage before they can
affect continuation state. Failed cloning leaves the request pending and the
owned storage valid. The storage is not portable or authoritative. Only bytes
returned by `encodeState` represent continuation state across a process,
allocator, or WASM-instance boundary.

Encoded state contains no implicit allocator identity, native address, function
pointer, session token, runtime handle, or host authority. Application values
may themselves contain credentials, secrets, personal data, or other sensitive
bytes. Boundary does not classify or protect those values; callers must apply
appropriate storage and transport controls.

Decoding assigns fresh transient ownership and validates the complete state
before it can run. World may close static handlers around this machine at
comptime. Boundary does not grant receiver authority, define host policy, or
implement capabilities.

## Compatibility

`Program.run` and `Program.Session` remain available. `StaticMachine` is an
additional backend over the same semantic frontend. Unsupported plans fail at
comptime; no fallback to a runtime-loaded module occurs.
