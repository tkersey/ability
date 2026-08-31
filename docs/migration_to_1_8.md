# Migration to Boundary 1.8

Boundary 1.8 adds two generic Control IR operations:

```text
text_byte_at(Text, u32) -> u8
bytes_byte_at(Bytes, u32) -> u8
```

The index addresses the value's canonical logical payload. `text_byte_at`
observes UTF-8 code units after Text validation; `bytes_byte_at` preserves
arbitrary bytes without text decoding. Out-of-range access uses the standard
`invalid_index` failure role, including authored Failure operands. Neither
operation exposes storage slack or a borrowed view.

Programs that reach either byte-projection operation emit BPI1 evaluator
semantics version 3.
Version 3 retains version-2 authored-failure semantics and does not change the
BPI1 container, Process State, or Process ABI. Programs that do not reach the
new operation retain their prior evaluator version and byte-identical images.

Compiler-only ceilings now admit 2,048 typed values, 256 blocks, 512
constructors, 256 constructor-environment fields, and 128 invariant terms.
These bounds admit deeply staged first-order programs without changing BPI1
field widths. They are compile/validation resource limits, not runtime, State,
or process-lifetime limits. The constrained fixed-kernel proof reserves 8 MiB
of initial memory for the enlarged validation workspace.

The fixed Process kernel must explicitly admit evaluator semantics version 3.
Hosts pinning the Boundary 1.7 kernel must therefore upgrade to the Boundary
1.8 kernel before executing a version-3 image. Historical Boundary 1.7 images,
kernel assets, and the v1.7 Process conformance corpus remain unchanged.
