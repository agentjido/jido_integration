# Jido Integration V2 Trading Ops

Top-level reference app for the first operator-facing slice above the public
platform packages.

This app proves one reviewable workflow across the public facade plus the three
runtime families.

Its session proof now tracks the accepted Phase 4 session seam: the analyst
target announces `asm`, the common consumer surface stays `codex.exec.session`,
and runtime session state remains outside `jido_integration`.

## Current Scope

- provisions one reference trading-ops stack through the host-facing auth API
- admits one market-alert trigger through `core/ingress`
- invokes one review workflow across stream, session, and direct runtimes
- builds an operator review packet from durable run, attempt, event, artifact,
  target, and connection truth

The app stays thin by design:

- connector registration still belongs to the control plane
- target compatibility and durable review truth still belong to the control
  plane
- trigger admission still belongs to `core/ingress`
- auth lifecycle still belongs to `core/auth`

The app only composes those public surfaces into one reviewable operator flow.

## Public Entry Points

The proof surface is intentionally small:

- `bootstrap_reference_stack/1`
- `run_market_review/2`
- `review_packet/1`

These functions are the host-level reference for:

- install and connection provisioning
- connector registration through the public facade
- trigger admission
- target announcement and compatibility lookup
- durable review packet assembly

## Proof

Primary end-to-end proof:

- `test/jido/integration/v2/apps/trading_ops_test.exs`

It covers:

- one accepted trigger admitted through `core/ingress`
- one stream pull, one session execution, and one direct GitHub escalation
- durable target ids on runs, attempts, and events
- durable review artifacts for each runtime family
- analyst target descriptors that advertise the ASM-backed session seam instead
  of the legacy session bridge

Package tests keep the direct GitHub step offline by forcing the connector's
client factory onto the deterministic fixture transport in
`test/test_helper.exs`. Live GitHub proof remains package-local to
`connectors/github`.

## Run

From the package directory:

```bash
mix test
mix docs
```

From the repo root:

```bash
mix monorepo.test
mix ci
```

This app is the permanent proof home for the operator-facing cross-runtime
slice. It replaces the old root-level example posture for that workflow.
