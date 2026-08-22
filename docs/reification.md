# Boundary Reification v1

Boundary 1.6 has one post-normalization `Reified Program`. The existing direct
reducer specializes it; the BEI1 emitter serializes it. Neither engine rebuilds
meaning from the other.

```text
source -> normalized Control IR -> RNF -> Reified Program
                                      |-> direct Machine
                                      `-> BEI1 -> fixed kernel
```

Both engines use Machine ABI v2 and byte-identical `ABL_RNF2` State. Images
carry static reducer clauses and schemas, never a persisted instruction cursor.
Valid images describe effects but grant no authority; the kernel returns a
typed request and stops.

The release claim is transition equivalence: outcome tag, caller fuel, State,
request identity and payload, result, failure, and operational rejection must
agree at every boundary. Run `zig build check-boundary-reification-receipt` for
the aggregate executable proof.

Debug names and source locations are not semantic image data. Boundary 1.6
adds no runtime definition loader, callback registry, source interpreter, or
State migration mechanism.
