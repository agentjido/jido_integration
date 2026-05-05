# Jido Integration V2 Tool Contracts

Phase 9 creates this package as the bounded contract dependency required by
`connectors/amp`. Phase 13 expands the behavior surface for provider-native
tools, host tools, connector tools, product actions, operator actions,
MCP/external tools, read-only observations, and synthetic fixture events.

The package is ref-only and metadata-only. It rejects raw auth material,
provider payloads, env overrides, command secrets, cwd/config-root smuggling,
target credentials, and hidden authority fields.

## QC

```bash
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix test
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix format --check-formatted
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix compile --warnings-as-errors
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix credo --strict
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix dialyzer --format short
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix docs
```
