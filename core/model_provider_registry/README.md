# Jido Model Provider Registry

Owner phase: Adaptive Phase 3.

This package owns governed model, provider, endpoint, capability, and provider
pool refs for adaptive GEPA and TRINITY model operations. It exposes refs,
capabilities, operation classes, cost posture, endpoint identity, and
materialization receipts only.

Phase 14 adds `Jido.ModelProviderRegistry.AdaptiveProof`, a ref-only adapter
proof surface for:

- live-provider proof gating after deterministic GEPA, TRINITY, and
  adaptive-control receipts are green
- governed Pristine OpenAPI operation refs
- governed Prismatic GraphQL operation refs with tenant, workspace, token
  family, and subject binding
- explicit durable persistence profile preflight
- redacted debug sidecar receipts

The adapter proof surface never calls provider SDKs and never accepts raw
prompts, raw provider payloads, auth headers, token files, API keys, credential
bodies, or provider defaults.

The package is regex-free and does not read ambient environment configuration.

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
