# Jido Integration Connector Admission Engine

Memory-default connector admission records for official and explicit
companion connector candidates.

The engine records manifest hashes, contract versions, bounded counts,
conformance posture, explicit app-config lineage, and tenant-scoped admission
status. Durable stores are opt-in and must be registered before selection.
The built-in `:mickey_mouse` profile is memory-only and does not require a
durable adapter. Durable GroundPlane profiles such as `:integration_postgres`
must appear in the registered durable adapter list before admission succeeds.

## Verification

```bash
mix test
mix compile --warnings-as-errors
```

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
