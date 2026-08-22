# Specialization equivalence

For Program `P`, canonical State `S`, command input `I`, and caller fuel `F`:

```text
Kernel(Image(P), S, I, F) == Direct(P, S, I, F)
```

Equality covers the complete observable transition: outcome, remaining fuel,
canonical State bytes, request site and payload, every RequestIdentity field,
terminal result/failure bytes, and accepted-versus-rejected operational input.

The two implementations share the Reified Program, stable wire/current tag
mapping, authored failure roles, and fuel/resource-shape law. The kernel keeps
actual canonical values separate from conservative preflight sizes because the
direct specializer propagates those bounds independently.

Canonical State is the engine-switch boundary. No translation is permitted.
`check-boundary-specialization-equivalence` and
`check-boundary-engine-switch` own this claim; final-outcome-only comparison is
insufficient.
