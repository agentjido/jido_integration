# Jido Integration Provider Feature Matrix

Owner phase: Phase 3 / ADDL-PHASE-09.

This package owns the executable feature placement matrix for all in-play
provider families. It records where auth sources, sessions, streaming, tools,
file access, shell execution, model selection, OAuth, token files, telemetry,
receipts, and sandbox attach behavior are allowed to live.

Unsupported and forbidden feature requests fail before provider effects. The
matrix is implemented with bounded maps and fixed enums, not regex or
pattern-engine parsing.

## QC

```bash
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix format --check-formatted
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix compile --warnings-as-errors
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix test
```
