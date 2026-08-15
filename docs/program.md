# Programs

A Boundary program is a comptime-known typed source definition:

```zig
const Program = boundary.program("lookup", Body);
const Machine = Program.compile(.{
    .maximum_frames = 16,
    .maximum_state_bytes = 64 * 1024,
    .maximum_machine_fuel = 100_000,
});
```

`Body` declares:

- portable `InitialArgs` and `Result` types, plus an exhaustive authored
  `Failure` enum;
- a tuple of typed `effect_sites`;
- optional declarative `effect_handlers`;
- optional declarative `effect_morphisms`;
- a tuple of structured `schema_types`;
- optional canonical constants in a heterogeneous tuple or homogeneous array;
- optional bounded `compiler_limits`;
- one typed `control_ir`.

The source label is diagnostic. Executable semantics, portable schemas, RNF
constructors, effect sites, fuel rules, and identity-bearing limits determine
the Machine contract digest.

`boundary.ir` is an advanced source-authoring surface, not a deployment
bytecode. Its blocks define typed values, explicit edges, effects, helper calls,
returns, and failures. Compilation validates the definition before RNF
synthesis.

The portable instruction set includes `enum_to_u32`, which projects an
exhaustive enum value to its canonical unsigned tag without relying on the
enum's backing integer type. This is the boundary-owned lowering for persisted
or wire-visible enum discriminants; consumers do not need a parallel tag table.

Failures have two source forms. `.fail = tag` retains the compile-time failure
tag used by existing programs. `.fail_value = value_id` returns the exact
runtime value at that id and is admitted only when its type is exactly
`Body.Failure`. Both lower through the same Machine ABI v2 `Outcome.failed`
transition.

`compiler_limits` has type `boundary.ir.CompilerLimits`. It can lower the
implementation ceilings for values, blocks, constructors, constructor
environments, invariants, and generated reducer work. These admission ceilings
are excluded from semantic identity when the resulting RNF is unchanged.

`effect_morphisms` contains values returned by
`boundary.effect.morphism(source_id, TargetSite)`. Morphisms are
type-preserving compiler inputs: they rewrite the residual effect contract
before RNF and leave no runtime handler or callback.

`effect_handlers` contains values returned by
`boundary.effect.handler(source_id, helper_function_id)`. Each declaration
lowers the source effect to a statically typed helper call before RNF. The
helper receives the source payload, returns the source resume type, and leaves
no runtime dispatch surface.

Programs have one executable route: `Program.compile`. There is no
`Program.run`, `Program.Session`, runtime interpreter, loaded module, or
fallback backend.

For local use, instantiate `boundary.Driver(Machine)`. The Driver owns only
Machine state and handler-local resources; it repeatedly calls `Machine.step`
and `Machine.resume`, so it cannot diverge semantically from World execution.

`boundary.Agent.program` is an optional profile over this same compiler. Agent
loops use ordinary typed sums, products, branches, budgets, and residual effect
sites; they do not introduce an agent runtime or second reducer.
