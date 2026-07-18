# StaticMachine parity

\`Program.Session\` remains the executable semantic oracle for the
\`StaticMachine\` backend.

For the same Boundary program, entry arguments, responses, and deterministic
fuel, the two backends must agree on:

- operation and after-site identity;
- payload semantic values;
- response acceptance and rejection;
- helper suspension and resumption;
- terminal value;
- deterministic failure;
- the point at which fuel is exhausted.

Session-local request tokens and raw continuation bytes are deliberately
excluded. A decoded StaticMachine state receives fresh transient ownership, and
the v1 state image is not the legacy capsule format.

The focused parity gate is:

\`\`\`text
zig build check-boundary-static-machine-parity
\`\`\`

The broader StaticMachine gates cover canonical state round trips, nested
helper suspension, malformed images, explicit fuel yield, agent fixtures, and
provider fixtures:

\`\`\`text
zig build check-boundary-static-machine
zig build check-boundary-static-agent
zig build check-boundary-static-provider
\`\`\`

Parity fails if StaticMachine decodes a runtime module, observes a different
effect site or payload, accepts a response that \`Program.Session\` rejects,
changes continuation behavior, or produces a different terminal value.
