# Async And Webhooks

Hosted async and webhook behavior are explicit packages.

## Async Dispatch

`core/dispatch_runtime` owns durable dispatch acceptance, handler scheduling,
retry and backoff, dead-letter transitions, replay, and process restart
recovery.

## Webhook Routing

`core/webhook_router` owns hosted route registration, callback-topology
resolution, secret lookup, and bridge handoff into `core/ingress` and
`core/dispatch_runtime` when the route represents a hosted trigger.

## Boundary Rule

`core/ingress` remains the normalization and admission owner. It does not own
hosted route lifecycle, and it does not own queue execution.

## Recovery Rule

Dispatch state and route state are intentionally separate. The router keeps
hosted route records, while the async runtime keeps transport progress and
retry state.

## Consumer Surface Rule

Hosted webhook proofs do not need to move into connector packages to share the
same consumer contract posture. App-owned hosted triggers may publish the same
generated sensor and plugin shape as common poll-backed triggers while
remaining app-owned for routing, normalization, and dispatch composition.
