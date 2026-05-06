# Jido Integration Connector Admission Engine

Memory-default connector admission records for official and explicit
companion connector candidates.

The engine records manifest hashes, contract versions, bounded counts,
conformance posture, explicit app-config lineage, and tenant-scoped admission
status. Durable stores are opt-in and must be registered before selection.

## Verification

```bash
mix test
mix compile --warnings-as-errors
```
