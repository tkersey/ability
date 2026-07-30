# Boundary Machine ABI v2

`Program.compile(options)` returns a Zig type with:

```text
abi_version == 2
State
InitialArgs
Result
OwnedResult
Failure
Error
EffectRow
Manifest
```

The operational surface is:

```text
initialState
cloneState
step
current
resume
encodeState
decodeState
validateState
deinitState
```

`step` returns a typed request, a resumable caller-fuel yield, an owned terminal
result, or a deterministic Machine failure. Allocation and malformed-contract
failures remain operational errors.

Caller fuel is a resumable scheduling quantum. Cumulative Machine fuel is a
contract-bound execution limit. A segment computes and checks its cost before
authoritative mutation. The default static cost is one unit for the terminator
plus one unit for each Control IR instruction; authored block costs may raise
but never undercut that floor. The generated direct reducer adds one
deterministic fuel unit per started 16 canonical bytes for every
variable-encoded instruction operand and successful result. It produces the
transition and exact charge together in a transactional plan; insufficient
caller fuel discards that plan and yields at the same constructor, while an
exhausted Machine budget terminates with `execution_budget_exceeded`. If
earlier segments completed in the same call, their exact charges remain
reflected in both cumulative Machine fuel and the remaining caller quantum.

An authored explicit yield commits the already-lowered continuation constructor
and returns `yielded` immediately. A compiler-inserted caller-fuel checkpoint
commits the same RNF checkpoint only when the remaining quantum cannot fund the
next segment; otherwise direct reduction continues. Neither form invents a
response value or external effect.

State mutation is transactional. Invalid responses, allocation failure, frame
overflow, and state-limit failure preserve authoritative state and caller fuel.
Pending requests expose a derived `RequestIdentity` bound to the Machine
contract, sequence, continuation constructor, residual site, and canonical
payload. The identity is recomputed from authoritative state before resume;
stale, duplicate, cross-Machine, and forged responses are rejected.

The Machine contract digest uses canonical reachable control ordinals and
structural portable schemas. Source block, function, value, schema, and
constant-table numbering cannot grant identity merely by rearranging dead
source declarations.

`boundary.Driver(Machine)` is the local convenience layer. It delegates every
transition to this ABI and owns no reducer of its own.
