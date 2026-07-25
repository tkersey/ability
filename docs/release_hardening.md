# Release hardening

This repository keeps the public root small while ProgramPlan becomes the single
semantic execution kernel. Release checks should protect that boundary and make
new files visible to package and lint coverage.

## Maintained proof commands

Run these before publishing a branch:

```sh
zig version
zig fmt --check build.zig src examples test bench conformance
git diff --check
zig build check-boundary-static-machine-release
zig build check-boundary-static-machine-release-falsifiers
zig build check-boundary-static-machine-release-archive -Dboundary-release-archive=/path/to/boundary-v0.7.0.tar.gz
zig build check-boundary-static-machine-release-archive-falsifiers
zig build --summary all
zig build test --summary all
zig build lint -- --max-warnings 0
```

`zig build lint` checks `build.zig` and every Zig source under `src`,
`examples`, `test`, `bench`, and `conformance`. Its path-coverage guard also
checks that every `.zig` file under `src`, `examples`, `test`, and `bench`
appears in `repo_zig_paths.txt`. Add new maintained source files to that
manifest in the same patch that adds the file.

`build.zig.zon` packages the maintained source, docs, examples, tests,
benchmarks, and manifest. Keep package paths aligned with any new top-level
surface that users need in source distributions.

The Boundary v0.7.0 code archive is immutable. Release-closure documentation
added after that tag is a distinct supplement and must not be described as
bytes from the tagged archive. The checked receipt at
`conformance/static-machine-v1/release-metadata.json` binds the tag target,
archive URL, archive SHA-256, Zig package hash, public StaticMachine ABI, and an
ordered digest set for the supplement. A publication receipt separately binds
the reviewed release-closure commit. The focused release gate checks that
receipt and its owner-derived ABI and matrix claims. The materialized-archive
gate accepts only the typed `-Dboundary-release-archive` input, snapshots it in
the build cache, recomputes its SHA-256, checks Zig `0.16.0`, and asks that
toolchain to recompute the package hash from the same snapshot without
requiring network access.

## File classification

Public:

- `src/root.zig`
- `src/boundary_shared.zig`
- `src/effect/root.zig`
- `src/ir_api.zig`
- `src/program_api.zig` through the public `boundary.program`,
  `boundary.staticMachine`, and `boundary.StaticMachineOptions` aliases
- `src/lowered_machine.zig` through the public `boundary.Runtime` alias

Public-adjacent:

- `src/effect/*.zig`
- `src/effect_schema.zig`
- `src/internal/program_plan.zig`
- `src/internal_kernel.zig`
- `src/internal_program_plan.zig`
- `examples/*.zig`
- `docs/*.md`
- `README.md`

Internal active:

- `src/internal/*.zig`
- `src/private_modules/*.zig`
- `src/effect_ir.zig`
- `src/frontend.zig`
- `src/interpreter.zig`
- `src/lowering_api.zig`
- `src/program_frontend.zig`
- `src/portable_core.zig`
- `src/reference_eval.zig`
- `src/reference_machine.zig`
- `src/parity_*.zig`
- `src/runtime_contract_registry.zig`
- `src/witnesses.zig`

Compatibility:

- `src/effect/optional.zig`
- `src/effect/state.zig`
- `src/effect/reader.zig`
- `src/effect/writer.zig`
- `src/effect/exception.zig`
- `src/effect/resource.zig`
- `src/effect/generated_family.zig`
- `src/effect/define.zig`

Migration-only:

- `examples/plan_native_optional.zig`
- `examples/plan_native_state_reader.zig`
- `examples/plan_native_writer.zig`
- `examples/plan_native_exception.zig`
- `examples/plan_native_resource.zig`
- `bench/*.zig`

Tests:

- `test/program_api_test.zig`
- `test/public_optional_bound_program_test.zig`
- `test/compile_fail/*.zig`

## Documentation map

- ProgramPlan authoring, typed schemas, tuple args, sum matching, outputs,
  cleanup hooks, nested-with targets, and `Program.contract`:
  `docs/program_plan.md`
- Custom effect authoring direction:
  `docs/custom_effect_authoring.md`
- StaticMachine ABI v1 contract:
  `docs/static_machine.md`
- StaticMachine v1 support and compatibility matrix:
  `docs/static_machine_compatibility.md`
- Release/package/lint discipline and file classification:
  this document

## Built-in effects roadmap

Built-ins stay under `boundary.effect` until plan-native replacements have
equivalent examples and tests. Compatibility APIs should remain available while
the plan-native paths prove parity.

Migration state:

1. Optional plan helpers are established under
   `boundary.effect.optional.plan`.
2. State, reader, and writer plan helpers are established under
   `boundary.effect.state.plan`, `boundary.effect.reader.plan`, and
   `boundary.effect.writer.plan`.
3. Exception and resource are the next built-in migration targets for reusable
   plan-native helper namespaces.
4. Custom effect authoring remains later: schema-first helpers should lower to
   ProgramPlan only after the built-in helper pattern has stabilized.

Non-goals for release hardening:

- Do not widen the public root.
- Do not expose Artifact, VM, compile, parser, `effect.Define`, or `effect.ops`
  as public APIs.
- Do not widen `ProgramValue`.
- Do not widen StaticMachine v1 support as part of release hardening.
- Do not remove compatibility built-ins until plan-native examples and tests are
  sufficient replacement evidence.
