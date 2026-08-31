# Migration to Boundary 1.8

Boundary 1.8 adds one generic Control IR operation:

```text
text_byte_at(Text, u32) -> u8
```

The index addresses Text's canonical UTF-8 payload. Out-of-range access uses
the standard `invalid_index` failure role, including authored Failure operands.
The operation exposes neither storage slack nor a borrowed view.

Programs that reach `text_byte_at` emit BPI1 evaluator semantics version 3.
Version 3 retains version-2 authored-failure semantics and does not change the
BPI1 container, Process State, or Process ABI. Programs that do not reach the
new operation retain their prior evaluator version and byte-identical images.

The fixed Process kernel must explicitly admit evaluator semantics version 3.
Hosts pinning the Boundary 1.7 kernel must therefore upgrade to the Boundary
1.8 kernel before executing a version-3 image. Historical Boundary 1.7 images,
kernel assets, and the v1.7 Process conformance corpus remain unchanged.
