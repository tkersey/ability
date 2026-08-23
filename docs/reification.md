# Boundary Reification v1

Boundary 1.6 reifies the defunctionalized computation independently of bounded
execution policy.

```text
source -> normalized Control IR -> semantic RNF -> Reified Program -> BPI1
                                              |                     |
                                              + MachineV2Profile    + MachineV2Profile
                                              v                     v
                                           direct v2             kernel v2
```

`BPI1(P)` is byte-identical under every MachineV2Profile. It contains static
reducer clauses and semantic RNF data, never fuel, Machine limits, ABI identity,
or a persisted instruction cursor. The profile owns the exact legacy metering,
checkpointing, Machine contract, and `ABL_RNF2` envelope.
The profile validator reconstructs the legacy v2 semantic digest from BPI1 and
the profile-owned deltas; profile bytes cannot alter metering while retaining
the same State or Request identity.
Valid images describe effects but grant no authority; the kernel returns a
typed request and stops.

The v2 compatibility claim is transition equivalence: outcome tag, caller fuel, State,
request identity and payload, result, failure, and operational rejection must
agree at every boundary. Run `zig build check-boundary-reification-receipt` for
the aggregate executable proof.

Debug names and source locations are not semantic image data. Boundary 1.6
adds no runtime definition loader, callback registry, source interpreter, open
Process ABI, or State migration mechanism. A later Process ABI may perform one
finite reduction without a predetermined lifetime budget; it is not delivered here.
