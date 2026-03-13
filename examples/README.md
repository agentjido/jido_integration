# Core Examples

These examples are local to the root package because they prove substrate and
control-plane behavior, not a specific provider integration.

## Quick Run

Run every deterministic core example:

```bash
mix test test/examples/
```

Run an individual example:

```bash
mix test test/examples/hello_world_test.exs
mix test test/examples/webhook_ingress_demo_test.exs
mix test test/examples/harness_core_loop_test.exs
```

## What Each Example Proves

### Hello World

- source: `examples/hello_world.ex`
- test: `test/examples/hello_world_test.exs`
- proves:
  - minimal adapter shape
  - manifest loading
  - conformance wiring

### Webhook Ingress Demo

- source: `examples/webhook_ingress_demo.ex`
- test: `test/examples/webhook_ingress_demo_test.exs`
- proves:
  - route registration
  - HMAC verification
  - dedupe
  - normalized trigger event creation
  - enqueue through the durable dispatch consumer
  - canonical `dispatch.*` transport telemetry plus separate `run.*`
    execution telemetry

### Harness Core Loop

- source: `examples/harness_core_loop/`
- test: `test/examples/harness_core_loop_test.exs`
- proves:
  - dispatcher flow
  - result aggregation
  - policy checks
  - target compatibility checks

## GitHub Examples

GitHub examples do not run from the root package. They live in the connector
package and are env-gated on purpose.

Read-only live acceptance:

```bash
cd packages/connectors/github
JIDO_INTEGRATION_GITHUB_LIVE=1 ./scripts/live_acceptance.sh read
```

Write-path live acceptance:

```bash
cd packages/connectors/github
export GITHUB_TEST_OWNER=you
export GITHUB_TEST_REPO=your-sandbox-repo
JIDO_INTEGRATION_GITHUB_LIVE=1 \
JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1 \
./scripts/live_acceptance.sh write
```

Important:

- `mix test test/examples/` inside the GitHub package is not enough by itself
  because live tests are excluded by default
- use the env-gated commands above or the package README
- those examples call `Auth.Server` directly to prove the canonical lifecycle
  engine; a production host app would place `Auth.Bridge` around the same calls

See `packages/connectors/github/README.md` for the full runbook.
