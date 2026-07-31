# Canonical Machine state

Machine ABI v2 uses `ABL_RNF2`, format version 1:

```text
magic                  8 bytes
format_version         u16 little-endian
machine_abi_version    u16 little-endian
machine_digest         32 bytes
sequence               u64 little-endian
cumulative_fuel        u64 little-endian
frame_count            u32 little-endian
flags                  u32 little-endian
```

Each frame contains:

```text
constructor_id         u32 little-endian
environment_length     u32 little-endian
environment_bytes      exact constructor schema
```

An await-effect constructor owns pending effect state; there is no independent
generic pending-instruction record.

Encoding stores logical lengths and live values only. It contains no pointers,
allocator capacities, padding, nominal type names, function/block/instruction
cursors, local-slot bitmaps, condition caches, or generic after stack.

The allocator-backed live state is a private ownership carrier, not a second
portable representation. It allocates exactly the logical typed frame count;
`maximum_frames` is an admission bound and never becomes spare inline storage.
Candidate transitions clone only those logical frames before commit.

Decode is fail-closed. It checks the exact Machine digest, versions, total
length, frame bounds, dense constructor schemas, portable-value bounds,
constructor-local invariants, stack compatibility, pending-request state, fuel
arithmetic, and trailing bytes. Sequence cannot exceed cumulative fuel, and a
parked request must have a nonzero sequence. Decode executes no effects or user
callbacks.

State bytes are compatible only when the Machine contract digest is identical.
There is no automatic migration from `ABL_STM1`.
