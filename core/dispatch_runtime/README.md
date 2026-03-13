# Jido Integration V2 Dispatch Runtime

Reusable async trigger runtime above `core/control_plane`.

Owns:

- durable dispatch acceptance
- explicit trigger-handler registration
- worker scheduling and execution
- retry and backoff timing
- dead-letter transitions and replay
- recovery of queued or in-flight transport work after runtime restart
- stable query APIs for current dispatch state

The package does not recreate a repo-root runtime supervisor. Hosts start and
name the runtime explicitly where they need it.

## API Surface

The runtime exposes:

- `start_link/1`
- `register_handler/3`
- `enqueue/3`
- `enqueue/4`
- `fetch_dispatch/2`
- `list_dispatches/2`
- `replay/2`

Handlers stay explicit and host-controlled through
`Jido.Integration.V2.DispatchRuntime.Handler`.

Hosted webhook routes typically arrive here from `core/webhook_router` after
`core/ingress` has admitted the trigger into canonical control-plane truth.

## Lifecycle

1. `enqueue/3` or `enqueue/4` persists a durable dispatch record keyed to the
   trigger dedupe scope.
2. The runtime binds that transport record to canonical control-plane truth by
   calling `ControlPlane.admit_trigger/2` unless the trigger is already bound
   to a `run_id`.
3. Once a handler is registered for the trigger id, a worker starts the next
   dispatch attempt and calls `ControlPlane.execute_run/3`.
4. Success marks the dispatch completed.
5. Failures move the dispatch into `:retry_scheduled` with exponential backoff
   until `max_attempts` is exhausted, then into `:dead_lettered`.
6. `replay/2` re-queues dead-lettered work so the next attempt number is used.

## Recovery Model

Dispatch transport state is file-backed by this package, so queued,
retry-scheduled, and dead-lettered dispatches survive runtime process restarts.

In-flight work that loses the runtime process is recovered on a new attempt.
The earlier control-plane attempt record remains as accepted evidence, and the
recovered execution continues on the next deterministic `attempt_id`.

For full BEAM restart recovery of both transport and control-plane truth, pair
this package with durable control-plane stores such as `core/store_local` or
`core/store_postgres`. With the default in-memory control-plane stores, only
the dispatch transport record survives a full application restart.
