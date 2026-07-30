# Portable values

Boundary Machine values have explicit first-order, target-neutral semantics.

Supported scalars:

```text
void, bool
i8, i16, i32, i64
u8, u16, u32, u64
```

Supported algebraic values are structs, exhaustive enums, tagged unions,
optionals, and fixed arrays whose members are portable.

Bounded dynamic values are:

```zig
boundary.Bytes(MaxBytes)
boundary.Text(MaxBytes)
boundary.Vector(T, MaxItems)
```

Capacity is compile-time and contract-bearing. Canonical encoding stores only
logical length and live contents; spare storage and allocator identity are not
observable. Capacity overflow and invalid UTF-8 fail before mutation.

The source algebra includes deterministic fixed-width integer computation,
branching, product construction/extraction, vector construction and access, and
bounded text construction. Operations charge deterministic fuel.

Unsupported values include `usize`, `isize`, raw pointers, arbitrary slices,
floats, function values, opaque host handles, non-exhaustive enums, comptime
fields, hash maps, unordered sets, unbounded collections, and identity-bearing
object graphs.
