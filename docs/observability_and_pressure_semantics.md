# Observability And Pressure Semantics

This repo uses two observation surfaces on purpose:

- durable `Jido.Integration.V2.Event` records are the canonical audit truth
- live `:telemetry` is supplemental operational visibility owned by the package
  that emits it

## Package-Owned Telemetry

Current stable package event families:

- `core/dispatch_runtime`
  - `[:jido, :integration, :dispatch_runtime, :enqueue]`
  - `[:jido, :integration, :dispatch_runtime, :deliver]`
  - `[:jido, :integration, :dispatch_runtime, :retry]`
  - `[:jido, :integration, :dispatch_runtime, :dead_letter]`
  - `[:jido, :integration, :dispatch_runtime, :replay]`
- `core/webhook_router`
  - `[:jido, :integration, :webhook_router, :route, :resolved]`
  - `[:jido, :integration, :webhook_router, :route, :failed]`

These names are documented here and in the owning package READMEs so reference
apps can attach handlers without depending on a repo-root telemetry contract.

## Redaction

Telemetry metadata is sanitized with `Jido.Integration.V2.Redaction.redact/1`
before emission.

Operational consequence:

- secret-bearing payload fields are redacted in live telemetry
- raw webhook request bodies are intentionally omitted from router telemetry
- durable control-plane run, attempt, and event truth remains the system of
  record for audits

## Pressure Split

Pressure handling is deliberately split by concern:

- `core/policy` owns admission verdicts: `:allowed`, `:denied`, or `:shed`
- `core/dispatch_runtime` owns retry timing, exponential backoff, dead-letter,
  and replay after work has been admitted

`core/policy` accepts a host-supplied pressure snapshot through gateway
metadata and can translate a shed signal into durable run truth.

It does not interpret pressure as retry timing.

`core/dispatch_runtime` may emit retry telemetry with `backoff_ms`, but that
is scheduling metadata for already-admitted work, not a policy verdict.

## Attaching Handlers

```elixir
:telemetry.attach_many(
  "ops-observer",
  [
    Jido.Integration.V2.DispatchRuntime.Telemetry.event(:retry),
    Jido.Integration.V2.WebhookRouter.Telemetry.event(:route_failed)
  ],
  &MyApp.Telemetry.handle_event/4,
  %{}
)
```
