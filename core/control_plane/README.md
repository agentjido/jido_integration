# Jido Integration V2 Control Plane

Capability registry, run ledger, and execution admission for the platform.

## Owns

- connector registration
- capability registry
- run / attempt / event durability behaviours
- trigger admission, dedupe, and checkpoint durability behaviours
- artifact-ref durability behaviours
- target-descriptor durability behaviours
- credential-ref resolution through `core/auth`
- credential lease issuance through `core/auth`
- admission policy evaluation through `core/policy`
- dispatch into direct, session, or stream runtimes
- authored Harness routing through `core/runtime_asm_bridge` or
  `core/session_runtime`

## Contract

`control_plane` owns the domain-facing persistence behaviours, not the Repo.

- restart-safe local control-plane truth is implemented by `core/store_local`
- Postgres-backed control-plane truth is implemented by `core/store_postgres`
- artifact truth is exposed through `record_artifact/1`, `fetch_artifact/1`,
  and `run_artifacts/1`
- ingress truth is exposed through `admit_trigger/2`,
  `record_rejected_trigger/2`, `fetch_trigger/4`, and
  `fetch_trigger_checkpoint/4`
- accepted or failed runs can be executed or retried later through
  `execute_run/3`
- completed, denied, and shed runs stay terminal when `execute_run/3` is
  called and the control plane rejects the request without mutating durable run
  truth
- target truth is exposed through `announce_target/1`, `fetch_target/1`, and
  `compatible_targets/1`
- target compatibility is explicit and negotiates protocol versions instead of
  hiding version checks inside runtimes
- target descriptors advertise compatibility and location, but authored
  runtime routing still comes from capability metadata rather than target
  overrides
- denied or shed work becomes a denied or shed run before attempt creation
- policy denials append `audit.policy_denied` while pressure shedding appends
  `audit.policy_shed`
- denied and shed runs persist the admission snapshot inside durable run truth
- trigger admission produces durable run truth without creating an execution
  attempt
- async runtimes above the control plane should reuse `execute_run/3` instead
  of inventing parallel attempt or event ledgers
- no attempt is created until auth and policy admit execution
- admitted work creates deterministic attempt `1` as `#{run_id}:1`
- attempts carry explicit `aggregator_id` and `aggregator_epoch` authority
- runtimes receive `CredentialLease`, not durable credential truth
- runtimes receive execution policy inputs separately from pre-dispatch
  admission facts
- run, attempt, and event truth are redactable by construction even when
  runtime code echoes lease-shaped auth material

## API Surface

- `register_connector/1`
- `fetch_connector/1`
- `fetch_capability/1`
- `connectors/0`
- `capabilities/0`
- `admit_trigger/2`
- `record_rejected_trigger/2`
- `fetch_trigger/4`
- `fetch_trigger_checkpoint/4`
- `record_artifact/1`
- `fetch_artifact/1`
- `run_artifacts/1`
- `announce_target/1`
- `fetch_target/1`
- `compatible_targets/1`
- `execute_run/3`

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Durability](../../guides/durability.md)
- [Async And Webhooks](../../guides/async_and_webhooks.md)
- [Observability](../../guides/observability.md)
