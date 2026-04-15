# Reference Apps Guide

The final V2 proof surface lives in top-level apps, not root
`reference_apps/`.

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

## `apps/inference_ops`

Purpose:

- prove the first live `:inference` runtime family above the public facade
- show that cloud and self-hosted paths both execute through `req_llm` while
  durable truth stays in `core/control_plane`

Primary public functions:

- `run_cloud_proof/1`
- `run_self_hosted_proof/1`
- `register_self_hosted_backend/0`
- `review_packet/2`

What it proves:

- cloud execution through `req_llm` with `runtime_kind: :client`
- self-hosted endpoint publication through `self_hosted_inference_core` and
  `llama_cpp_sdk`
- self-hosted execution through `req_llm` with `runtime_kind: :service`
- durable inference event recording and packet review through the control plane

Primary proof:

- `apps/inference_ops/test/jido/integration/v2/apps/inference_ops_test.exs`

## Validation

Package-local:

```bash
cd apps/devops_incident_response && mix test
cd apps/inference_ops && mix test
```

Repo-root closeout:

```bash
mix monorepo.test
mix ci
```

These apps are the permanent proof homes for host-level flows. New reference
workflows should follow the same pattern instead of reintroducing root-level
example directories.

`apps/trading_ops` remains on disk as an archived proof, but it is intentionally
excluded from the default workspace and CI lane.
