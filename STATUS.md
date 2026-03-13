# jido_integration — Status

**Date:** 2026-03-08

## Current State

The repo now uses a root-core hybrid layout:

- `jido_integration/` remains the control-plane Mix project
- `packages/jido_integration_github/` is an independent first-party Mix project
- the core package does not depend on the GitHub package
- GitHub-specific tests, examples, docs, and manifest artifacts live with the GitHub package

## Core Scope

`jido_integration` owns:

- contracts and schema validation
- auth runtime
- webhook router, dedupe, and ingress
- gateway policies
- registry
- telemetry
- conformance
- scaffolding

`jido_integration` does not own:

- built-in connectors
- durable infra
- framework bridges
- production deployment substrate

## First-Party Package Scope

`packages/jido_integration_github` owns:

- `Jido.Integration.Connectors.GitHub`
- `Jido.Integration.Connectors.GitHub.DefaultClient`
- `priv/jido/integration/connectors/github/manifest.json`
- GitHub adapter tests
- GitHub conformance coverage
- GitHub end-to-end examples

## Verification Commands

Core:

```bash
cd /home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration
mix test
```

GitHub package:

```bash
cd /home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration/packages/jido_integration_github
mix test
mix jido.conformance Jido.Integration.Connectors.GitHub --profile bronze
```

## Next Work

- add more first-party connector packages under `packages/`
- add durable auth/webhook/dispatch substrate
- add framework bridges for host apps
- add live-service verification where appropriate
