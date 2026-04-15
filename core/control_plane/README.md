# Jido Integration V2 Control Plane

Capability registry, run ledger, and execution admission for the platform.

## Owns

- connector registration
- capability registry
- run / attempt / event durability behaviours
- trigger admission, dedupe, and checkpoint durability behaviours
- artifact-ref durability behaviours
- target-descriptor durability behaviours
- live inference routing and execution through `invoke_inference/2`
- durable inference attempt recording through `record_inference_attempt/1`
- credential-ref resolution through `core/auth`
- credential lease issuance through `core/auth`
- admission policy evaluation through `core/policy`
- dispatch into direct, session, or stream runtimes
- authored non-direct routing through `core/runtime_router`, which in turn
  selects `core/asm_runtime_bridge` or `core/session_runtime`

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
- `execute_run/3` re-resolves current auth truth from `connection_id` lineage
  before issuing a new execution lease, so stored run snapshots do not become
  long-lived auth authority
- runtimes receive `CredentialLease`, not durable credential truth
- runtimes receive execution policy inputs separately from pre-dispatch
  admission facts
- run, attempt, and event truth are redactable by construction even when
  runtime code echoes lease-shaped auth material
- review, planning, and sandbox execution surfaces stay secret-decoupled; the
  control plane may evaluate policy against sanitized auth handles, but it does
  not persist raw secret material in durable run truth

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
- `invoke_inference/2`
- `record_inference_attempt/1`
- `inference_capability_id/0`

## Inference Runtime

The control plane now owns the first end-to-end inference adapter.

It:

- builds `InferenceExecutionContext` and `ConsumerManifest`
- derives a local `ReqLLMCallSpec`
- executes cloud provider calls through `req_llm`
- resolves CLI-backed endpoint descriptors through `ASM.InferenceEndpoint`
- executes those CLI endpoint routes through `req_llm`
- resolves self-hosted endpoints through an optional self-hosted endpoint
  provider seam
- executes those self-hosted OpenAI-compatible endpoints through `req_llm`
- persists the resulting durable inference attempt truth

The self-hosted route now proves both runtime ownership shapes:

- spawned `llama_cpp_sdk`
- attached-local `ollama`

The concrete self-hosted runtime wiring lives outside `core/control_plane`
itself. `apps/inference_ops` supplies the current provider implementation backed
by `self_hosted_inference_core`.

The durable record includes:

- the admitted request identity
- runtime classification and route truth
- compatibility outcome
- endpoint summary
- optional stream lifecycle summaries
- terminal inference result
- usage and finish metadata when available

The minimum durable event sequence is:

- `inference.request_admitted`
- `inference.attempt_started`
- `inference.compatibility_evaluated`
- `inference.target_resolved`
- optional stream lifecycle events
- one terminal attempt event

For streaming attempts, `stream_opened.checkpoint_policy` is copied from the
admitted `InferenceExecutionContext.streaming_policy` and rejected if the
runtime summary drifts from that admitted control-plane truth.

CLI endpoint publication now stays explicit:

- `ASM.InferenceEndpoint` publishes the endpoint and returns the
  `EndpointDescriptor`
- the control plane records the route as `target_class: :cli_endpoint`
- the durable backend manifest stays `:asm_inference_endpoint`
- ordinary completion requests stay isolated from agent-loop semantics

The CLI proof path prefers Gemini as the first common-surface proof provider.

## Related Guides

- [Inference Durability](guides/inference_durability.md)
- [CLI Inference Endpoints](guides/cli_inference_endpoints.md)
- [Inference Baseline](../../guides/inference_baseline.md)
- [Architecture](../../guides/architecture.md)
- [Durability](../../guides/durability.md)
- [Async And Webhooks](../../guides/async_and_webhooks.md)
- [Observability](../../guides/observability.md)
- [Examples](examples/README.md)
