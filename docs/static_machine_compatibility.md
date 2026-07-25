# Boundary StaticMachine ABI v1 compatibility matrix

This document is the release matrix for the supported
`boundary.staticMachine` surface in Boundary v0.7.0. It describes the current
admitted domain; it does not add execution semantics.

## Release identity

The reviewed Boundary code package is the immutable `v0.7.0` archive. Its tag
target, archive URL, archive SHA-256, and Zig package hash are recorded in
`conformance/static-machine-v1/release-metadata.json`.

This matrix, the primary README changes, and later release-hardening
documentation form a separate documentation supplement. The supplement is not
part of the fixed `v0.7.0` code archive. Its ordered file digests are recorded
in the same metadata, while the publication receipt binds the reviewed
release-closure commit.

## Public ABI

| Surface | ABI v1 contract |
| --- | --- |
| Constructor | `boundary.staticMachine(Program, options)` |
| Options | `boundary.StaticMachineOptions` |
| Program authority | an authentic type returned by `boundary.program` |
| ABI identity | `Machine.abi_version == 1` |
| Portable state | `initialState`, `cloneState`, `encodeState`, `decodeState`, `validateState`, `deinitState` |
| Reduction | `reduce`, `current`, `resume`, `resumeAfter`, `returnNow` |
| Static declarations | `InitialArgs`, `State`, `Result`, `EffectRow`, `Manifest`, authored `Failure`, closed `Error` |
| State encoding | `.canonical_v1` |
| Residual ports | `.explicit` |
| Semantic parity authority | `Program.Session` on the admitted StaticMachine domain |

World v1 closes `Machine.EffectRow`. It must not infer the residual static row
from `Program.protocol`.

## Supported domain

| Area | StaticMachine ABI v1 |
| --- | --- |
| Program source | validated comptime `ProgramPlan` owned by `boundary.program` |
| Scalar values | admitted ProgramPlan scalar carriers |
| Structured values | admitted product and sum schemas with exact `Body.value_schema_types` |
| String lists | immutable `[]const []const u8` |
| Enums | exhaustive enums, bound by ordered names and explicit discriminants |
| `usize` | canonical unsigned 32-bit semantic domain |
| Helpers/providers | statically known, acyclic helper and nested-provider frame graphs |
| Effects | statically known operation and after sites; residual ports remain explicit |
| Control | control paths exactly representable by the compact condition authority |
| Failure | closed `Body.Error`, excluding reserved operational error names |
| Limits | positive `maximum_frames`; positive `maximum_state_bytes` within `u32`; generated validation ceilings |
| Target | native Zig and `wasm32-freestanding` compile gates |

## Fail-closed restrictions

Construction rejects these shapes at comptime:

- a type not returned by `boundary.program`;
- recursive helper or nested-provider frame graphs;
- output collection, result cleanup, or output cleanup hooks;
- mutable `[][]const u8`, comptime struct fields, non-exhaustive enums, or
  `noreturn` schema carriers;
- a non-closed `Body.Error` or authored use of reserved operational errors;
- zero or insufficient `maximum_frames`;
- zero or greater-than-`u32` `maximum_state_bytes`;
- control and predicate histories the compact v1 state carrier cannot validate
  exactly;
- after-continuation chains that do not close over their static input, output,
  and function-result types;
- programs exceeding the fixed control-path, scratch-memory, or validation-work
  ceilings.

There is no fallback to a loaded module, dynamic provider discovery, or runtime
module loading. Broader programs remain usable through `Program.Session`; they
are outside StaticMachine ABI v1 until a later reviewed ABI expands the portable
representation.

## Compatibility rules

- Contract-compatible machines exchange canonical state bytes, not live `State`
  pointers.
- Live `State` handles remain machine-branded and single-owner.
- Machine identity binds the admitted ProgramPlan, structured carriers, effect
  row, options, limits, and corrected StaticMachine reachability.
- Nominal type renames preserve compatibility only when admitted carrier
  semantics are unchanged.
- Logical field, enum discriminant, effect-site, option, or resource-limit
  changes alter the machine contract.
- `Program.Session` retains native-width `usize`, dynamic completion behavior,
  and its legacy reachability interpretation. StaticMachine v1 does not silently
  inherit those behaviors.
- No transparent migration from a v0 continuation or loaded module into a
  StaticMachine v1 state is supported.

## Proof gates

```sh
zig build check-boundary-static-machine
zig build check-boundary-static-machine-parity
zig build check-boundary-static-machine-wasm32
zig build check-boundary-static-machine-release
zig build check-boundary-static-machine-release-falsifiers
zig build check --summary all
```

The release verifier checks the public declarations, exact code identity,
documentation-supplement digests, required matrix claims, and negative
falsifiers. The existing StaticMachine, parity, wasm32, and aggregate gates
remain the semantic proof.
