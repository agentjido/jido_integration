# Jido Integration Conformance Contracts

Lightweight external-author conformance helpers for connector companion
packages.

This package depends on `:jido_integration_contracts` and test/doc tooling
only. It does not import control-plane, runtime-router, direct-runtime, AppKit,
Mezzanine, Citadel, Execution Plane, GroundPlane, product, or provider SDK
internals.

## Verification

```bash
mix test
mix compile --warnings-as-errors
```
