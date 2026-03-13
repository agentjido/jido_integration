# Connector Review Baseline

Date: 2026-03-13
Status: final V2 proof surface

## Baseline Packages

Connector runtime-family baseline:

- direct: `connectors/github`
- session: `connectors/codex_cli`
- stream: `connectors/market_data`

Supporting proof surfaces:

- repo-root conformance via `core/conformance`
- package-local GitHub live acceptance in `connectors/github`
- cross-runtime operator proof in `apps/trading_ops`
- hosted webhook and async recovery proof in `apps/devops_incident_response`

## What The Final Baseline Proves

- connector discovery is public and deterministic through
  `Jido.Integration.V2.connectors/0`, `fetch_connector/1`, and
  `fetch_capability/1`
- public invocation can be expressed either as `invoke/3` or through the typed
  `InvocationRequest` helper
- direct, session, and stream connectors all emit runtime-specific
  `RuntimeResult` evidence while keeping durable review truth in the control
  plane
- runtime execution uses short-lived credential leases, not durable credential
  secrets
- policy posture remains explicit at the capability boundary through declared
  scopes, environment, runtime-class, and sandbox metadata
- connector conformance stays stable at the workspace root while deterministic
  evidence stays package-local through companion modules
- hosted webhook routing, async dead-letter, replay, and restart recovery are
  proved at the app/package layer, not by reviving root examples or silently
  widening the direct GitHub connector contract

## Current Concrete Proofs

Deterministic connector capabilities:

- `github.issue.list`
- `github.issue.fetch`
- `github.issue.create`
- `github.issue.update`
- `github.issue.label`
- `github.issue.close`
- `github.comment.create`
- `github.comment.update`
- `codex.exec.session`
- `market.ticks.pull`

Reference-app proofs:

- `apps/trading_ops`
  - market-alert trigger admission through `core/ingress`
  - one reviewable workflow across stream, session, and direct runtimes
  - durable run, attempt, event, artifact, target, and connection review
- `apps/devops_incident_response`
  - install provisioning through the public facade
  - hosted route registration through `core/webhook_router`
  - webhook admission through `core/ingress`
  - async execution, dead-letter, replay, and restart recovery through
    `core/dispatch_runtime`
  - restart-safe auth and control-plane truth through `core/store_local`

## Recommended Validation Loop

From the repo root:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
mix jido.conformance Jido.Integration.V2.Connectors.CodexCli
mix jido.conformance Jido.Integration.V2.Connectors.MarketData
mix monorepo.test
mix ci
```

Package and app proof commands:

```bash
cd connectors/github && mix test
cd connectors/codex_cli && mix test
cd connectors/market_data && mix test
cd apps/trading_ops && mix test
cd apps/devops_incident_response && mix test
```

Optional live acceptance remains package-local:

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
scripts/live_acceptance.sh read
```

## Design Boundary Preserved

This baseline intentionally does not restore V1 layout or semantics:

- no root OTP runtime is reintroduced
- no root `examples/` or `reference_apps/` directories return
- no generic adapter contract replaces the V2 manifest and capability model
- async and webhook proofs stay in child packages and top-level apps
