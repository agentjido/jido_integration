# Jido Integration V2 Devops Incident Response

Top-level async webhook proof app for the hosted incident-response slice above
the public platform packages.

Current scope:

- provisions one GitHub-shaped install through the public auth facade
- registers one hosted webhook route through `core/webhook_router`
- admits one signed webhook into durable ingress truth
- executes the admitted work through `core/dispatch_runtime`
- proves dead-letter, replay, and runtime restart recovery with
  `core/store_local`

The app stays thin by design:

- `core/platform` and `core/auth` still own install, connection, and credential
  contracts
- `core/webhook_router` still owns route registration, secret lookup, and
  ingress-definition assembly
- `core/dispatch_runtime` still owns queueing, retry, dead-letter, replay, and
  transport recovery
- the app only adds one local proof connector plus one callback handler so the
  hosted webhook path can be exercised end to end

The app-local connector is intentional. `connectors/github` remains the
deterministic direct-capability package from prompt 04. This proof app does not
silently widen that connector's contract with app-owned webhook behavior.

## Dependencies

The package declares explicit child-package deps on the modules it uses:

- `core/platform`
- `core/auth`
- `core/contracts`
- `core/store_local`
- `core/webhook_router`
- `core/dispatch_runtime`

It does not depend on the repo root.

## Proof

The end-to-end proof lives in:

- `test/jido/integration/v2/apps/devops_incident_response_test.exs`

It covers:

- install provisioning and connected state
- webhook route provisioning
- accepted webhook to async work handoff
- dead-letter on repeated failure
- replay success on a new attempt
- runtime restart recovery for in-flight async work

## Run

From the package directory:

```bash
mix test
```

From the repo root:

```bash
mix monorepo.test
mix ci
```
