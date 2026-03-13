# Jido Integration V2 Control Plane

Owns:

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

The important current contract is:

- `control_plane` owns the domain-facing persistence behaviours, not the Repo
- restart-safe local control-plane truth is implemented by `core/store_local`
- Postgres-backed control-plane truth is implemented by `core/store_postgres`
- artifact truth is exposed through `record_artifact/1`, `fetch_artifact/1`, and `run_artifacts/1`
- ingress truth is exposed through `admit_trigger/2`, `record_rejected_trigger/2`, `fetch_trigger/4`, and `fetch_trigger_checkpoint/4`
- accepted runs can be executed or retried later through `execute_run/3`
- target truth is exposed through `announce_target/1`, `fetch_target/1`, and `compatible_targets/1`
- target compatibility is explicit and negotiates protocol versions instead of hiding version checks inside runtimes
- denied work becomes a denied run
- policy denials append a separate `audit.policy_denied` event with actor, tenant, connector, runtime, and trace context
- denied runs persist the admission snapshot inside durable run truth
- trigger admission produces durable run truth without creating an execution attempt
- async runtimes above the control plane should reuse `execute_run/3` instead of
  inventing parallel attempt or event ledgers
- no attempt is created until auth and policy admit execution
- admitted work creates deterministic attempt `1` as `#{run_id}:1`
- attempts carry explicit `aggregator_id` and `aggregator_epoch` authority
- runtimes receive `CredentialLease`, not durable credential truth
- runtimes receive execution policy inputs separately from pre-dispatch admission facts
- run, attempt, and event truth are redactable by construction even when runtime code echoes lease-shaped auth material
