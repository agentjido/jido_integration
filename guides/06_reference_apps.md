# Reference Apps

Reference apps live above the substrate. They are where control-plane behavior
is proved honestly instead of hidden inside connector packages.

## Current Reference Apps

- `reference_apps/devops_incident_response`
- `reference_apps/sales_pipeline`

## Recommended First Run

The active proving slice is the incident-response app.

```bash
mix test test/reference_apps/devops_incident_response_test.exs
```

That single deterministic test proves:

- webhook auth secret resolution
- route registration and ingress
- durable dispatch acceptance
- callback execution
- dead-lettering
- replay
- consumer restart recovery before success and before replay

## Incident Response App

Files:

- runtime:
  `reference_apps/devops_incident_response/lib/devops_incident_response/runtime.ex`
- handler:
  `reference_apps/devops_incident_response/lib/devops_incident_response/github_issue_handler.ex`
- proof:
  `test/reference_apps/devops_incident_response_test.exs`

Use this app when you want to understand the intended host/runtime boundary.

In particular, `runtime.ex` shows the current dispatch contract clearly: the
host starts `Dispatch.Consumer`, registers the trigger callback, and passes the
consumer into `Webhook.Ingress.process/2`.

## Sales Pipeline App

`reference_apps/sales_pipeline` is a scaffold only.

That is intentional. The directory exists so the same substrate can host the
office-workflow tranche later, but the repo does not yet ship a full proving
slice there.

## Operator Guidance

If you are onboarding to the repo:

1. run the root deterministic tests
2. run the core examples
3. run the incident-response reference-app proof
4. only then move to env-gated GitHub live acceptance

That order gives you the shortest path from zero context to a full substrate
proof without requiring external accounts or network state.
