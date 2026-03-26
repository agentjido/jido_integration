# Observability

Observability is part of the contract, not an afterthought. Packages emit
telemetry where they own behavior, and the docs should make that ownership
clear to operators.

## Telemetry

Packages emit their own `:telemetry` families where they own runtime behavior.
That includes dispatch, webhook routing, and other package-local lifecycle
events.

## Redaction

Sensitive values must be redacted before they leave the owning package. The
system keeps durable truth and emitted telemetry deliberately separate.

## Pressure Semantics

Policy handles admission and shedding. Async runtimes handle retry timing.
Those concerns should stay separate in both code and docs.

## Operational Rule

If a package emits telemetry, its README should say what is emitted, what is
redacted, and which package owns the durable source of truth.
