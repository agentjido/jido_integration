# Async Dispatch And Replay Guide

`core/dispatch_runtime` is the reusable async trigger runtime above
`core/control_plane`.

## Responsibilities

It owns:

- durable dispatch acceptance
- handler registration by trigger id
- worker scheduling and execution
- retry timing and exponential backoff
- dead-letter transitions and replay
- transport-state recovery after runtime restart
- package-owned `:telemetry` for live async observation

It does not replace the control plane. Runs, attempts, and events remain
canonical control-plane truth.

## Minimal Host Workflow

1. start the runtime with a storage directory
2. register a host-controlled handler for a trigger id
3. admit a trigger through `core/ingress` or accept one from a higher-level
   package
4. enqueue the admitted `TriggerRecord`
5. observe or query transport state with `fetch_dispatch/2` and
   `list_dispatches/2`
6. replay dead-lettered work with `replay/2`

## API Surface

The stable API is:

- `start_link/1`
- `register_handler/3`
- `enqueue/3`
- `enqueue/4`
- `fetch_dispatch/2`
- `list_dispatches/2`
- `replay/2`

Handlers implement `Jido.Integration.V2.DispatchRuntime.Handler` and return
execution opts for the admitted trigger.

## Lifecycle

1. `enqueue/3` or `enqueue/4` persists a durable dispatch record.
2. The runtime binds the dispatch to canonical control-plane truth unless the
   trigger already carries a `run_id`.
3. Once a handler is registered, a worker executes the run through
   `ControlPlane.execute_run/3`.
4. Success marks the dispatch completed.
5. Failure schedules retry with backoff until `max_attempts` is exhausted.
6. Exhausted work moves to `:dead_lettered`.
7. `replay/2` re-queues dead-lettered work so execution continues with the next
   attempt number.

## Recovery Boundary

Transport recovery is file-backed inside `core/dispatch_runtime`.

That means:

- queued, retry-scheduled, running, and dead-letter state can survive runtime
  restart
- in-flight work can be recovered on a new attempt after restart
- full BEAM restart recovery of both transport and run truth requires durable
  control-plane stores such as `core/store_local` or `core/store_postgres`

## Relationship To Policy

`core/policy` owns admission verdicts before attempts exist.

`core/dispatch_runtime` owns scheduling after work has already been admitted:

- retry
- backoff
- dead-letter
- replay

Backoff metadata is scheduler state, not a policy verdict.

## Proof Surface

Current proofs:

- `core/dispatch_runtime/test/jido/integration/v2/dispatch_runtime_test.exs`
- `apps/devops_incident_response`

The app proof is the end-to-end hosted example for dead-letter, replay, and
restart recovery.
