# Boundary StaticMachine

\`boundary.staticMachine(Program, options)\` generates a comptime-known,
defunctionalized reducer for a type returned by \`boundary.program\`. It is the
Boundary-to-World compile-time seam for World Comptime v1.

\`\`\`zig
const Program = boundary.program("example", Handlers, Body);
const Machine = boundary.staticMachine(Program, .{
    .state_encoding = .canonical_v1,
    .world_ports = .explicit,
    .maximum_frames = 64,
    .maximum_state_bytes = 1 << 20,
});
\`\`\`

The machine reuses the validated \`ProgramPlan\` and the generated session
reducer. It does not decode a Certified Boundary Module, load bytecode, search a
runtime registry, or select handlers dynamically. Functions, blocks,
instructions, operation sites, schemas, and continuation shapes remain
comptime-known to Zig.

## Contract

The generated type exposes:

- \`State\`, an ephemeral owner for one decoded machine state;
- \`InitialArgs\`, \`Result\`, and \`Failure\`;
- \`EffectRow\`, the program's static protocol and site descriptors;
- \`Manifest\`, compile-time identity, format, site, and limit metadata;
- \`initialState\`, \`reduce\`, \`current\`, \`resume\`, \`resumeAfter\`, and
  \`returnNow\`;
- \`encodeState\`, \`decodeState\`, \`validateState\`, and \`deinitState\`.

\`reduce\` stops at an operation request, an after-continuation request, terminal
completion, or an explicit fuel yield. The caller supplies fuel and receives
the unspent balance.

## Authority boundary

The live \`State\` owns allocator-backed working storage because Zig values such
as strings and structured payloads require transient memory. That storage is
not portable or authoritative. Only the bytes returned by \`encodeState\`
represent continuation state across a process, allocator, or WASM-instance
boundary.

Encoded state contains no allocator identity, native address, function pointer,
session token, runtime handle, credential, or host authority. Decoding assigns
fresh transient ownership and validates the complete state before it can run.

World may close static handlers around this machine at comptime. Boundary does
not grant receiver authority, define host policy, or implement capabilities.

## Compatibility

\`Program.run\` and \`Program.Session\` remain available. \`StaticMachine\` is an
additional backend over the same semantic frontend. Unsupported plans fail
during comptime validation; no fallback to a runtime-loaded module occurs.
