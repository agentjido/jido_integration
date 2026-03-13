# Jido Integration V2 Trading Ops

Thin reference app package for the first operator-facing slice above the public
platform packages.

Current scope:

- provisions one reference trading-ops stack through the host-facing auth API
- admits one market-alert trigger through `core/ingress`
- invokes one review workflow across stream, session, and direct runtimes
- builds an operator review packet from durable run, event, artifact, target,
  and connection truth

The app stays thin by design:

- connector registration still belongs to the control plane
- target compatibility and durable review truth still belong to the control
  plane
- trigger admission still belongs to `core/ingress`
- auth lifecycle still belongs to `core/auth`

The app only composes those public surfaces into one reviewable operator flow.

