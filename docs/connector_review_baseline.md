# Connector Review Baseline

Date: 2026-03-13
Status: final V2 proof surface

## Baseline Packages

Connector runtime-family baseline:

- direct: `connectors/github`
- direct: `connectors/notion`
- session: `connectors/codex_cli`
- stream: `connectors/market_data`

Supporting proof surfaces:

- repo-root conformance via `core/conformance`
- package-local GitHub live acceptance in `connectors/github`
- package-local Notion live acceptance in `connectors/notion`
- cross-runtime operator proof in `apps/trading_ops`
- hosted webhook and async recovery proof in `apps/devops_incident_response`

## What The Final Baseline Proves

- connector discovery is public and deterministic through
  `Jido.Integration.V2.connectors/0`, `fetch_connector/1`, and
  `fetch_capability/1`
- connector manifests are authored through explicit auth, catalog, operation,
  and trigger contracts, with executable capabilities derived from that source
- authored auth remains internally consistent with the published slice:
  `requested_scopes` cover all operation and trigger scope requirements, and
  `secret_names` cover every trigger verification or webhook secret reference
- public invocation can be expressed either as `invoke/3` or through the typed
  `InvocationRequest` helper, with `connection_id` as the public auth binding
  when auth is required
- direct, session, and stream connectors all emit runtime-specific
  `RuntimeResult` evidence while keeping durable review truth in the control
  plane
- the session example connector publishes the shared `codex.exec.session`
  common surface on the accepted ASM-backed Harness seam instead of staying
  connector-local
- runtime execution uses short-lived credential leases, not durable credential
  secrets
- policy posture remains explicit at the capability boundary through declared
  scopes, environment, runtime-class, and sandbox metadata
- Notion OAuth control endpoints stay in install/auth flow rather than widening
  the published invoke surface
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
- `notion.users.get_self`
- `notion.search.search`
- `notion.pages.create`
- `notion.pages.retrieve`
- `notion.pages.update`
- `notion.blocks.list_children`
- `notion.blocks.append_children`
- `notion.data_sources.query`
- `notion.comments.create`
- `codex.exec.session`
- `market.alert.detected`
- `market.ticks.pull`

Reference-app proofs:

- `apps/trading_ops`
  - market-alert trigger admission through `core/ingress`
  - authored trigger capability identity stays `market.alert.detected`
  - downstream stream work stays the explicit `market.ticks.pull` invocation
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
mix jido.conformance Jido.Integration.V2.Connectors.Notion
mix jido.conformance Jido.Integration.V2.Connectors.CodexCli
mix jido.conformance Jido.Integration.V2.Connectors.MarketData
mix monorepo.test
mix ci
```

Package and app proof commands:

```bash
cd connectors/github && mix test
cd connectors/notion && mix test
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

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN="..." \
JIDO_INTEGRATION_V2_NOTION_READ_PAGE_ID="..." \
scripts/live_acceptance.sh read
```

## Design Boundary Preserved

This baseline intentionally does not restore V1 layout or semantics:

- no root OTP runtime is reintroduced
- no root `examples/` or `reference_apps/` directories return
- no generic adapter contract replaces the V2 manifest and capability model
- async and webhook proofs stay in child packages and top-level apps
