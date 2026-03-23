# Reference Apps Guide

The final V2 proof surface lives in top-level apps, not root
`reference_apps/`.

## `apps/trading_ops`

Purpose:

- prove one operator-visible workflow across stream, session, and direct
  runtime families
- show how a host composes the public facade, auth lifecycle, ingress, and
  durable review surfaces

Primary public functions:

- `bootstrap_reference_stack/1`
- `run_market_review/2`
- `review_packet/1`

What it proves:

- install and connection provisioning through the public auth surface
- connector registration through the public facade
- trigger admission through `core/ingress` using the authored
  `connectors/market_data` poll trigger definition
- separation between trigger capability identity (`market.alert.detected`) and
  the downstream stream operation identity (`market.ticks.pull`)
- target announcement and authored-compatible lookup through
  `Jido.Integration.V2.compatible_targets_for/2`
- workflow-local shaping over the shared `Jido.Integration.V2.review_packet/2`
- durable review of runs, attempts, events, artifacts, triggers, targets,
  connections, installs, and catalog context without app-local restitching of
  low-level store calls

Primary proof:

- `apps/trading_ops/test/jido/integration/v2/apps/trading_ops_test.exs`

## `apps/devops_incident_response`

Purpose:

- prove the hosted webhook path above the public platform
- show how local durability, route registration, async dispatch, replay, and
  restart recovery compose without moving that behavior into the repo root or
  the GitHub connector package

Primary public functions:

- `boot/1`
- `provision_install/2`
- `ingest_issue_webhook/4`
- `fetch_route/2`
- `replay_dispatch/2`
- `restart_dispatch_runtime/1`
- `wait_for_dispatch/4`
- `wait_for_run/4`

What it proves:

- local durability with `core/store_local`
- app-local hosted trigger authorship with explicit ingress-definition
  evidence for `github.issue.ingest`
- hosted route registration with `core/webhook_router`
- alignment between the app-local trigger manifest, hosted route record, and
  normalized signal metadata
- signed webhook admission through `core/ingress`
- async execution through `core/dispatch_runtime`
- dead-letter, replay, and restart recovery

Primary proof:

- `apps/devops_incident_response/test/jido/integration/v2/apps/devops_incident_response_test.exs`

## Validation

Package-local:

```bash
cd apps/trading_ops && mix test
cd apps/devops_incident_response && mix test
```

Repo-root closeout:

```bash
mix monorepo.test
mix ci
```

These apps are the permanent proof homes for host-level flows. New reference
workflows should follow the same pattern instead of reintroducing root-level
example directories.
