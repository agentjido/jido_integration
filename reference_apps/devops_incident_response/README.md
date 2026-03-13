# DevOps Incident Response

This is the active reference-app proving slice in the repo.

It is deterministic by default and exists to prove the substrate above the
connector layer.

## Run

From the repo root:

```bash
mix test test/reference_apps/devops_incident_response_test.exs
```

## What It Proves

- webhook auth secret resolution
- route registration
- signature verification
- durable enqueue
- callback execution
- dead-lettering
- replay
- consumer restart recovery before success and before replay

## Main Files

- runtime:
  `reference_apps/devops_incident_response/lib/devops_incident_response/runtime.ex`
- handler:
  `reference_apps/devops_incident_response/lib/devops_incident_response/github_issue_handler.ex`
- deterministic proof:
  `test/reference_apps/devops_incident_response_test.exs`

## Audience

Use this app when you want the clearest end-to-end example of how a host app
should sit above the substrate.
