# Jido Integration V2

Greenfield restart of the integration platform as a thin-root monorepo.

## Shape

Core packages:

- `packages/core/auth`
- `packages/core/contracts`
- `packages/core/control_plane`
- `packages/core/direct_runtime`
- `packages/core/ingress`
- `packages/core/policy`
- `packages/core/session_kernel`
- `packages/core/store_postgres`
- `packages/core/stream_runtime`

Connector packages:

- `packages/connectors/github`
- `packages/connectors/codex_cli`
- `packages/connectors/market_data`

App packages:

- `packages/apps/trading_ops`

The root app stays thin on purpose:

- public facade only
- path dependency wiring only
- monorepo verification commands only
- no core runtime logic accretes at the root

## Current slice

The repo now proves all three runtime families:

- `:direct`
  - `github.issue.create`
- `:session`
  - `codex.exec.session`
- `:stream`
  - `market.ticks.pull`

The repo now also proves the first thin app layer:

- `trading_ops`
  - provisions operator-visible connection state through the public auth API
  - admits a market-alert trigger through `core/ingress`
  - reviews one workflow across market feed pull, analyst session, and operator
    escalation
  - consumes `TargetDescriptor` compatibility and records the selected
    `target_id` in durable run, attempt, and event truth

The baseline connector contract now also proves:

- every baseline connector runs through auth leases, not durable credential truth
- every admitted run emits connector-specific review events plus canonical `artifact.recorded` events
- every baseline run persists one durable review artifact reference through the control plane
- session and stream reuse are keyed to the credential ref, not only the subject
- connector policy is explicit about runtime-class sandbox and environment posture

The control plane now persists durable truth in Postgres:

- `core/control_plane` owns run, attempt, and event behaviours
- `core/control_plane` now also owns trigger admission and checkpoint behaviours
- `core/control_plane` also owns artifact-ref and target-descriptor behaviours
- `core/auth` owns install, connection, credential-ref, refresh, rotation, revocation, and lease behaviours
- `core/store_postgres` owns the Repo, migrations, and sandbox posture
- `core/ingress` normalizes webhook and polling inputs into durable trigger truth
- duplicate webhook or polling deliveries reuse the original durable run admission
- polling checkpoints and dedupe state survive Repo restarts
- host apps drive auth through install start, install completion, connection status, and lease request boundaries
- durable credential truth stays behind `core/auth` and is bound to explicit connection/install records
- runtimes receive short-lived `CredentialLease` values instead of durable credentials
- lease payloads are minimized and raw secret material is kept out of run, attempt, and event truth
- capability admission is evaluated through `core/policy`
- denied work is recorded as a denied run without an attempt
- attempts derive deterministic ids from `run_id` and `attempt`
- run, attempt, event, and auth truth survive Repo restarts
- contracts now include first-class `ArtifactRef` and `TargetDescriptor` objects
- contracts now include a shared `RuntimeResult` emission envelope for connector outputs, events, and artifact refs
- artifact refs carry checksum, payload-reference, retention, and redaction truth
- target descriptors carry explicit compatibility and version-negotiation truth

## Connector Review

The connector review baseline notes live in
`docs/connector_review_baseline.md`.

## Dependency posture

Mandatory now:

- `jido_action`
- `jido_signal`

Deferred but expected later:

- `jido`
- `Jido.Sensor`

This keeps the first greenfield skeleton honest: couple only where the abstraction
is already clearly justified.

## Monorepo commands

Run these from the root:

```bash
mix test
mix monorepo.format
mix monorepo.compile
mix monorepo.test
mix monorepo.credo --strict
mix monorepo.dialyzer
mix monorepo.docs
mix quality
mix docs.all
mix ci
```
