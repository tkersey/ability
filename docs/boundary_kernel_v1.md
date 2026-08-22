# Boundary Kernel v1

`boundary.kernel` is the allocation-free evaluator of validated BEI1 and
canonical `ABL_RNF2` bytes. Callers provide State, result, and scratch buffers.
The kernel retains no authoritative State and invokes no callback.

Native operations are `initial`, `validateState`, `current`, `step`, and
`resume`. A funded segment executes atomically. Insufficient caller fuel yields
before the segment, preserving State and fuel. Ordinary transitions remain
internal to one call; external effect requests park a canonical await
constructor and include RequestIdentity v2.

`boundary-kernel-v1.wasm` targets `wasm32-freestanding`, imports nothing,
exports memory, and exposes Kernel ABI v1:

```text
boundary_kernel_abi_version
boundary_kernel_input_ptr / boundary_kernel_input_capacity
boundary_kernel_execute
boundary_kernel_output_ptr / boundary_kernel_output_len
boundary_kernel_error_ptr / boundary_kernel_error_len
boundary_kernel_reset
```

The public profile admits 16 MiB images, 4 MiB States, 2 MiB auxiliary values,
64 MiB kernel scratch, 24 MiB input, 8 MiB output, and at most 128 MiB linear
memory. Commands validate image, initialize, validate State, inspect current
request, step, and resume. Semantic outcomes are successful ABI outputs;
malformed/resource failures are result codes.
