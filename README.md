# Boundary

Boundary is a Zig compiler for portable, defunctionalized algebraic effects.
It compiles a typed source program into one program-specific Boundary Machine:

```text
typed source -> Control IR -> RNF -> direct reducer -> Machine ABI v2
```

The Machine is the sole executable meaning of a Boundary program. Its canonical
`ABL_RNF2` state contains a bounded stack of program-specific continuation
constructors and their exact future-live environments. It contains no generic
instruction cursor, local-slot table, condition history, runtime module, or
native callback.

## Public surface

- `boundary.effect` declares typed residual effect sites.
- `boundary.schema` exposes canonical portable-value codecs.
- `boundary.ir` exposes advanced typed source/control authoring.
- `boundary.program` declares a source program.
- `boundary.Driver` drives the compiled Machine locally.
- `boundary.Agent` is an optional profile over the same compiler.
- `boundary.Bytes`, `boundary.Text`, and `boundary.Vector` are bounded portable
  values.

The primary construction is:

```zig
const Program = boundary.program("research-agent", Body);

const Machine = Program.compile(.{
    .state_encoding = .rnf_v1,
    .maximum_frames = 64,
    .maximum_state_bytes = 1 << 20,
    .maximum_machine_fuel = 1_000_000,
    .debug_metadata = false,
});
```

`Machine` exposes ABI version 2, typed arguments/results/effects, deterministic
fuel semantics, transactional step and resume operations, and canonical state
encoding. Local execution and World execution both drive this same Machine.

## Portable language

Boundary admits explicit fixed-width integers, booleans, products, exhaustive
enums, tagged unions, optionals, fixed arrays, and bounded
`Bytes(MaxBytes)`, `Text(MaxBytes)`, and `Vector(T, MaxItems)` values. Pointer
identity, target-width integers, floats, host handles, arbitrary callbacks, and
unbounded collections are outside the portable language.

Residual effects are statically known and typed. Boundary compiles known
control, helper, loop, and local after semantics into RNF; only genuine external
authority crosses the Machine boundary.

## Documentation

- [Program authoring](docs/program.md)
- [Compiler pipeline](docs/compiler_pipeline.md)
- [Resumption Normal Form](docs/resumption_normal_form.md)
- [Machine ABI](docs/machine.md)
- [Machine state](docs/machine_state.md)
- [Portable values](docs/portable_values.md)
- [Effects](docs/effects.md)
- [World integration](docs/world_integration.md)
- [Migration from Boundary 0.7](docs/migration_from_0_7.md)

## Proof

Run the aggregate proof:

```text
zig build check --summary all
```

Focused gates include `check-boundary-machine`, `check-boundary-rnf`,
`check-boundary-rnf-values`, `check-boundary-rnf-control`,
`check-boundary-rnf-recursion`, `check-boundary-rnf-after`,
`check-boundary-machine-state`, `check-boundary-machine-malformed`,
`check-boundary-machine-native-wasm`,
`check-boundary-machine-no-interpreter`, and
`check-boundary-machine-deletion`. The aggregate also runs the real v0.7
performance comparison and emits the Boundary-owned completion fields through
`check-boundary-machine-receipt`.

Boundary 1.0 is source- and state-incompatible with Boundary 0.7. The immutable
0.7 release remains the compatibility implementation; Boundary 1.0 contains no
legacy runtime or automatic continuation migration.
