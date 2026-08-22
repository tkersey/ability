# Migration to Boundary 1.6

Existing users may continue calling `Program.compile(options)`. Machine ABI v2,
`ABL_RNF2` version 1, effect semantics, and existing Program/Machine digests are
unchanged for unchanged source and options.

To publish a reified artifact:

```zig
const Image = Program.image(options);
const bytes = Image.bytes;
```

To use the fixed kernel through the typed Machine interface:

```zig
const Machine = Program.kernelMachine(options);
```

Direct and kernel Machines have the same Manifest identity. State bytes may be
decoded by either engine. Artifact SHA-256 identifies exact image/kernel bytes;
it does not replace semantic or Machine identity.

BEI1 is a compiler artifact and has no automatic migration promise to future
image versions. Live State migration across changed Program meaning remains an
explicit non-feature.
