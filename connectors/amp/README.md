# Jido Integration V2 Amp Connector

Phase 9 introduces the Amp CLI connector lane. The connector records Amp native
CLI auth, permissions, MCP configuration, MCP OAuth state, target posture, and
operation policy as refs. Standalone Amp SDK and CLI behavior remains owned by
`amp_sdk`; governed connector execution requires materialized authority.

The connector does not read ambient Amp env, config files, permissions files,
MCP OAuth stores, or normal home directories as authority.

## QC

```bash
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix test
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix format --check-formatted
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix compile --warnings-as-errors
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix credo --strict
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix dialyzer --format short
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix docs
```
