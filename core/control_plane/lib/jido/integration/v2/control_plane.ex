defmodule Jido.Integration.V2.ControlPlane do
  @moduledoc """
  Public control-plane facade for registry, invocation, run ledger, ingress,
  artifact, target, simulation profile, and inference operations.
  """

  alias Jido.Integration.V2.ControlPlane.ArtifactService
  alias Jido.Integration.V2.ControlPlane.AttemptReconciler
  alias Jido.Integration.V2.ControlPlane.AttemptRecovery
  alias Jido.Integration.V2.ControlPlane.ConnectorRegistry
  alias Jido.Integration.V2.ControlPlane.InferenceService
  alias Jido.Integration.V2.ControlPlane.InvocationService
  alias Jido.Integration.V2.ControlPlane.RunLedgerService
  alias Jido.Integration.V2.ControlPlane.ServiceCore
  alias Jido.Integration.V2.ControlPlane.SimulationProfileService
  alias Jido.Integration.V2.ControlPlane.StoreConfig
  alias Jido.Integration.V2.ControlPlane.TargetService
  alias Jido.Integration.V2.ControlPlane.TriggerIngressService

  @type invoke_preflight_error :: ServiceCore.invoke_preflight_error()

  defdelegate register_connector(connector), to: ConnectorRegistry
  defdelegate connectors(), to: ConnectorRegistry
  defdelegate fetch_connector(connector_id), to: ConnectorRegistry
  defdelegate capabilities(), to: ConnectorRegistry
  defdelegate fetch_capability(capability_id), to: ConnectorRegistry

  defdelegate invoke(request), to: InvocationService
  defdelegate invoke(capability_id, input, opts \\ []), to: InvocationService
  defdelegate invoke_managed_session(capability_id, input, opts), to: InvocationService
  defdelegate execute_run(run_id, attempt_number, opts \\ []), to: InvocationService

  defdelegate fetch_run(run_id), to: RunLedgerService
  defdelegate runs(filters \\ %{}), to: RunLedgerService
  defdelegate fetch_attempt(attempt_id), to: RunLedgerService
  defdelegate attempts(run_id), to: RunLedgerService
  defdelegate events(run_id), to: RunLedgerService

  defdelegate mark_attempt_outcome_unknown(attempt_id, attrs \\ %{}),
    to: AttemptRecovery,
    as: :mark_outcome_unknown

  defdelegate recovery_task(task_id), to: AttemptRecovery, as: :task
  defdelegate recovery_tasks(filters \\ %{}), to: AttemptRecovery, as: :tasks

  defdelegate reconcile_attempt(task_id, observer, opts \\ []),
    to: AttemptRecovery,
    as: :reconcile_task

  defdelegate reconcile_attempts_on_start(observer, opts \\ []),
    to: AttemptRecovery,
    as: :reconcile_on_start

  defdelegate reconcile_due_attempts(observer, opts \\ []),
    to: AttemptRecovery,
    as: :reconcile_due

  defdelegate reconcile_attempts_now(), to: AttemptReconciler, as: :reconcile_now

  defdelegate admit_trigger(trigger, opts \\ []), to: TriggerIngressService
  defdelegate record_rejected_trigger(trigger, reason), to: TriggerIngressService

  defdelegate fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key),
    to: TriggerIngressService

  defdelegate fetch_trigger_checkpoint(tenant_id, connector_id, trigger_id, partition_key),
    to: TriggerIngressService

  defdelegate put_trigger_checkpoint(checkpoint), to: TriggerIngressService
  defdelegate run_triggers(run_id), to: TriggerIngressService

  defdelegate record_artifact(artifact_ref), to: ArtifactService
  defdelegate fetch_artifact(artifact_id), to: ArtifactService
  defdelegate run_artifacts(run_id), to: ArtifactService

  defdelegate announce_target(target_descriptor), to: TargetService
  defdelegate fetch_target(target_id), to: TargetService
  defdelegate targets(filters \\ %{}), to: TargetService
  defdelegate compatible_targets(requirements), to: TargetService

  defdelegate install_simulation_profile(profile, installed_scenarios, attrs \\ %{}),
    to: SimulationProfileService

  defdelegate update_simulation_profile(profile, installed_scenarios, attrs \\ %{}),
    to: SimulationProfileService

  defdelegate remove_simulation_profile(profile_id, attrs \\ %{}), to: SimulationProfileService
  defdelegate fetch_simulation_profile(profile_id), to: SimulationProfileService

  defdelegate select_simulation_profile(profile_id, environment_scope, owner_ref),
    to: SimulationProfileService

  defdelegate simulation_profiles(filters \\ %{}), to: SimulationProfileService

  defdelegate inference_capability_id(), to: InferenceService
  defdelegate record_inference_attempt(spec), to: InferenceService
  defdelegate invoke_inference(request, opts \\ []), to: InferenceService

  defdelegate reset!(), to: StoreConfig
end
