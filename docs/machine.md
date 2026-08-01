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
prepareResume
resume
deinitPreparedResume
encodeState
decodeState
validateState
deinitState
```

`step` returns a typed request, a resumable caller-fuel yield, an owned terminal
result, or a deterministic Machine failure. Allocation and malformed-contract
failures remain operational errors.

Caller fuel is a resumable scheduling quantum. Cumulative Machine fuel is a
contract-bound execution limit for one issued state lineage. A segment computes
and checks its cost before authoritative mutation. The default static cost is one unit for the terminator
plus one unit for each Control IR instruction; authored block costs may raise
but never undercut that floor. The generated direct reducer adds one
deterministic fuel unit per started 16 canonical bytes for the persisted
environment and every variable-encoded instruction operand and prospective
result. Before executing the segment, a generated resource-shape pass starts
from the exact environment and propagates canonical encoded sizes through the
closed instruction sequence. It uses exact subvalue sizes when they are
available and contract-bounded upper estimates otherwise; it does not construct
the result or invoke the segment plan. Insufficient caller fuel therefore
yields at the same constructor before reducer execution, while an exhausted
Machine budget terminates with `execution_budget_exceeded`. If earlier segments
completed in the same call, their exact scheduled charges remain reflected in
both cumulative Machine fuel and the remaining caller quantum.

An authored explicit yield commits the already-lowered continuation constructor
and returns `yielded` immediately. A compiler-inserted caller-fuel checkpoint
commits the same RNF checkpoint only when the remaining quantum cannot fund the
next segment; otherwise direct reduction continues. Neither form invents a
response value or external effect.

State mutation is transactional. Invalid responses, allocation failure, frame
overflow, and state-limit failure preserve authoritative state and caller fuel.
Direct effect handling first calls `prepareResume`, which validates the pending
request and allocates the complete candidate continuation before external
authority runs. The caller then either commits that candidate with `resume` or
releases it with `deinitPreparedResume`; every successfully prepared candidate
must follow exactly one of those ownership paths. `boundary.Driver` enforces
this ordering for typed local handlers.
Pending requests expose a derived `RequestIdentity` bound to the Machine
contract, sequence, complete canonical continuation stack, continuation
constructor, residual site, and canonical payload. The continuation digest
includes every persisted frame environment and cumulative fuel counter. The
identity is recomputed from authoritative state before resume; stale,
duplicate, cross-continuation, cross-Machine, and forged responses are rejected.

Canonical Machine bytes are bearer authority, not a signature or proof of their
own issuance history. Boundary validates current fuel bounds and transition
arithmetic, but an unsigned self-contained cumulative counter cannot prove that
it was not rolled back or replaced. World and host persistence own issued branch
heads, replay, rollback, and receiver policy; deterministic retry remains a
separate semantic operation and is not exactly-once execution.

The Machine contract digest uses canonical reachable control ordinals and
structural portable schemas. Source block, function, value, schema, and
constant-table numbering cannot grant identity merely by rearranging dead
source declarations.

`boundary.Driver(Machine)` is the local convenience layer. It delegates every
transition to this ABI and owns no reducer of its own.
