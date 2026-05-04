# Jido Integration Connector Registry

Owner phase: Phase 3 prerequisite for ADDL-PHASE-09, later expanded by
ADDL-PHASE-12.

This package owns minimal registry-level identity for official connectors,
companion connectors, generated SDK clients, provider CLI adapters, and app
connectors. Phase 3 uses it to support provider feature placement and
multi-identity proof. Later phases expand it with full connector admission and
upgrade receipts.

The registry is ref-only. Provider names, connector instances, and default SDK
clients cannot select credential material without tenant, policy revision,
provider account, and credential handle refs.

## QC

```bash
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix format --check-formatted
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix compile --warnings-as-errors
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix test
```
