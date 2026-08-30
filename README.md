# Boundary

Boundary is a Zig compiler and fixed Process interpreter for portable,
defunctionalized algebraic effects. It separates one canonical program meaning
from both open Process semantics and bounded Machine ABI v2 compatibility:

```text
typed source -> Control IR -> semantic RNF -> Reified Program -> BPI1
                                         |                     |
                         +---------------+---------------------+
                         |                                     |
                         v                                     v
                BPI1 + Process State                  BPI1 + MachineV2Profile
                         |                                     |
                         v                                     v
                fixed Process kernel              direct v2 or kernel v2
```

The direct reducer remains the default specialized engine. `Program.image()`
emits the canonical Boundary Program Image without execution options.
`Program.kernelMachineV2(options)` combines that image with the separately
identified bounded compatibility profile.
Its canonical
`ABL_RNF2` state contains a bounded stack of program-specific continuation
constructors and their exact future-live environments. It contains no generic
instruction cursor, local-slot table, condition history, runtime module, or
native callback.

## Public surface

- `boundary.effect` declares typed residual effect sites.
- `boundary.schema` exposes canonical portable-value codecs.
- `boundary.ir` exposes advanced typed source/control authoring.
- `boundary.program` declares a source program.
- `boundary.image` validates canonical BPI1 bytes.
- `boundary.process_v1` validates portable Process records and advances one
  finite BPI1 reducer segment.
- `boundary.machine_v2.kernel` executes BPI1 plus a MachineV2Profile.
- `boundary.Driver` drives the compiled Machine locally.
- `boundary.Agent` is deprecated compatibility surface; Agent-specific
  authoring belongs in the separate Agent package.
- `boundary.Bytes`, `boundary.Text`, and `boundary.Vector` are bounded portable
  values.

The primary construction is:

```zig
const Program = boundary.program("research-agent", Body);

const machine_options: boundary.MachineOptions = .{
    .state_encoding = .rnf_v1,
    .maximum_frames = 64,
    .maximum_state_bytes = 1 << 20,
    .maximum_machine_fuel = 1_000_000,
    .debug_metadata = false,
};

const Machine = Program.compile(machine_options);
const Image = Program.image();
const Profile = Program.machineV2Profile(machine_options);
const KernelMachine = Program.kernelMachineV2(machine_options);
```

Fuel, frame ceilings, State-byte ceilings, caller checkpoints, and cumulative
budgets belong to `Profile` and Machine ABI v2. They are not Program Image or
Process semantics. Process ABI v1 carries exact future-live continuations in
canonical `ABL_PST1` State and performs exactly one finite reducer segment per
invocation. No raw BPI1 clause evaluator is exported from the package root.

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
- [Boundary Reification](docs/reification.md)
- [Boundary Program Image v1](docs/boundary_executable_image_v1.md)
- [Machine v2 Kernel v1](docs/boundary_kernel_v1.md)
- [Process ABI v1](docs/process_v1.md)
- [Specialization equivalence](docs/specialization_equivalence.md)
- [Migration to Boundary 1.7](docs/migration_to_1_7.md)
- [Migration to Boundary 1.6](docs/migration_to_1_6.md)
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
`check-boundary-machine-deletion`. Process conformance is available through
`check-boundary-process-v1` and `emit-boundary-process-kernel-v1`. The aggregate also runs the real v0.7
performance comparison and emits the Boundary-owned completion fields through
`check-boundary-machine-receipt`.

The aggregate is a release-owner gate and its historical performance lane
requires a tagged Boundary checkout with local `.git` metadata and the reviewed
`v0.7.0` tag. Extracted package consumers can run the focused current-version
gates, but a package without repository history cannot authenticate or claim
the immutable v0.7 comparison.

Boundary 1.0 is source- and state-incompatible with Boundary 0.7. The immutable
0.7 release remains the compatibility implementation; Boundary 1.0 contains no
legacy runtime or automatic continuation migration.
