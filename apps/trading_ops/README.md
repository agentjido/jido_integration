# Jido Integration V2 Trading Ops

Top-level reference app for the first operator-facing slice above the public
platform packages.

This app proves one reviewable workflow across the public facade plus the three
runtime families.

Its session proof now tracks the accepted Phase 4 session seam: the analyst
target announces the authored Runtime Control driver `asm`, the common consumer
surface stays `codex.session.turn`, and runtime session state remains below the
durable integration layer.

## Current Scope

- provisions one reference trading-ops stack through the host-facing auth API
- admits one market-alert poll trigger through the connector-authored
  `market_data` ingress definition
- invokes one review workflow across stream, session, and direct runtimes
- reshapes the shared `Jido.Integration.V2.review_packet/2` operator packet for
  one workflow-local market review

The app stays thin by design:

- connector registration still belongs to the control plane
- authored-compatible target selection and durable review assembly still belong
  to the shared platform surface
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
- target announcement and authored-compatible lookup
- workflow-local review shaping above the shared durable packet

## Proof

Primary end-to-end proof:

- `test/jido/integration/v2/apps/trading_ops_test.exs`

It covers:

- one accepted trigger admitted through `core/ingress`
- trigger admission that now uses the authored trigger capability
  `market.alert.detected` instead of overloading `market.ticks.pull`
- one stream pull, one session execution, and one direct GitHub escalation
- explicit downstream `market.ticks.pull` invocation after trigger admission
- durable target ids on runs, attempts, and events
- durable review artifacts for each runtime family
- market target descriptors that advertise the authored Runtime Control `asm` driver
  and refuse same-capability descriptors that do not publish the required
  authored `asm` feature
- analyst target descriptors that advertise the authored Runtime Control `asm` driver
  and refuse mismatched `jido_session` descriptors for the same capability
- non-direct target lookup that requires the authored `asm` feature so a
  mismatched `jido_session` or mismatched-driver descriptor is not selected by
  mistake

Package tests keep the direct GitHub step offline by forcing the connector's
client factory onto the deterministic fixture transport in
`test/test_helper.exs`. Live GitHub proof remains package-local to
`connectors/github`.

That keeps the operator app boundary honest:

- `market_data` authors the common poll trigger definition and trigger
  capability
- `core/ingress` owns admission, dedupe, and checkpoint truth
- `trading_ops` consumes the authored trigger and decides what downstream
  operations to run next

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
