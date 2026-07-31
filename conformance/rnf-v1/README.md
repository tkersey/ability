# RNF v1 release conformance

The performance gate compares the production RNF Machine against the immutable
Boundary v0.7.0 release at commit
`7f2472100454aa2cd5c62e07db0c1e23eaf46a77`.

`check_performance.sh` exports that tag into an isolated temporary directory,
applies only the focused measurement patch in this directory, and builds both
implementations with the invoking Zig toolchain. No Boundary v0 runtime source
or executable path is retained in the Boundary 1.0 package.

The paired one-effect witness measures:

- median native initial-state-to-request lifecycle time over five samples;
- median native canonical-state decode/current time over five samples;
- median import-free WASM lifecycle time over five samples;
- canonical parked-state bytes;
- the ReleaseSmall one-effect WASM artifact size; and
- production runtime semantic modules.

The baseline compile observation and the outer Zig build summary report compile
time and peak compiler RSS for the paired witness builds. Release proof runs
from an empty package/cache so those observations are not cache-hit timings.

The gate rejects native or WASM runtime above 1.25 times the v0.7.0 median, a
WASM artifact above 1.5 times the v0.7.0 artifact, any parked-state growth, or
failure to reduce the four predecessor runtime-semantic modules to the one
generated Machine owner. State and WASM sizes are deterministic. Runtime is a
same-host paired measurement rather than a portable absolute threshold.

Run:

```text
zig build check-boundary-machine-performance
zig build check-boundary-machine-performance-falsifiers
```

The falsifier step proves that exact limits pass and one-unit regressions fail.
The comparison is a release proof, not a second reducer or compatibility
runtime.
