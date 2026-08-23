# Machine ABI v2 Kernel v1

`boundary.machine_v2.kernel` is the fixed compatibility evaluator of validated
BPI1, `ABL_MV2P1` MachineV2Profile, and canonical `ABL_RNF2` bytes. It retains
no authoritative State and invokes no callback. It is not the future generic
Boundary Process kernel.

Native operations are `initial`, `validateState`, `current`, `step`, and
`resume`. A funded segment executes atomically. Insufficient caller fuel yields
before the segment, preserving State and fuel. Ordinary transitions remain
internal to one call; external effect requests park a canonical await
constructor and include RequestIdentity v2.

`boundary-machine-v2-kernel-v1.wasm` targets `wasm32-freestanding`, imports nothing,
exports memory, and exposes Kernel ABI v1:

```text
boundary_machine_v2_kernel_abi_version
boundary_machine_v2_kernel_input_ptr / boundary_machine_v2_kernel_input_capacity
boundary_machine_v2_kernel_execute
boundary_machine_v2_kernel_output_ptr / boundary_machine_v2_kernel_output_len
boundary_machine_v2_kernel_error_ptr / boundary_machine_v2_kernel_error_len
boundary_machine_v2_kernel_reset
```

The input carries BPI1 bytes and separate MachineV2Profile bytes before State
and auxiliary data. The public artifact admits 16 MiB images, 1 MiB profiles,
4 MiB States, 2 MiB auxiliary values,
64 MiB kernel scratch, 24 MiB input, 8 MiB output, and at most 128 MiB linear
memory. Commands validate image, initialize, validate State, inspect current
request, step, and resume. Semantic outcomes are successful ABI outputs;
malformed/resource failures are result codes.

Kernel output outcomes `7` and `8` carry Machine-owned
`execution_budget_exceeded` and `frame_depth_exceeded` results respectively.
They preserve remaining caller fuel and the canonical State selected by the
Machine law; they are semantic outcomes, not kernel result-code failures.
