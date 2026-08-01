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
observable. Machine initialization and effect resumption recursively rebuild
typed values into that same canonical representation before the values enter
authoritative RNF state. Vector pop, truncate, and clear reset every vacated element to its
canonical default before returning. Bytes truncate and clear likewise zero every
vacated byte, including malformed-length repair, so logically removed data does
not remain observable through public storage. Capacity overflow and invalid
UTF-8 fail before mutation. Zero-width Vector elements are a canonical quotient:
truncate, clear, encoding, and equality do not iterate over their logical length.

The source algebra includes deterministic fixed-width integer computation,
branching, product construction/extraction, vector construction and access, and
bounded text/byte construction. Text and Bytes expose canonical logical length,
copy, comparison, join, and append operations; Bytes also admits one-byte
scalar append, while Text admits Unicode-scalar and integer formatting.
Ordering returns an error for malformed logical lengths, and Text ordering
also rejects invalid UTF-8 before comparing bytes. Operations charge
deterministic fuel.

Unsupported values include `usize`, `isize`, raw pointers, arbitrary slices,
floats, function values, opaque host handles, non-exhaustive enums, comptime
fields, hash maps, unordered sets, unbounded collections, and identity-bearing
object graphs.
