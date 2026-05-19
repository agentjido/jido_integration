defmodule Jido.Integration.V2.ControlPlane.ServiceCore do
  @moduledoc """
  Connector registry plus canonical run/attempt/event ledger.

  The control plane owns deterministic connector and capability discovery as
  well as the stable invocation boundary that powers the public facade.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.GovernedLowerAdmission
  alias Jido.Integration.V2.ControlPlane.Inference
  alias Jido.Integration.V2.ControlPlane.InferenceRecorder
  alias Jido.Integration.V2.ControlPlane.PolicyService
  alias Jido.Integration.V2.ControlPlane.Registry
  alias Jido.Integration.V2.ControlPlane.ReplayService
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.ControlPlane.TreAdapter
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.ExecutionRouter
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.PolicyDecision
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.SimulationProfileRegistryEntry
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @type invoke_preflight_error ::
          :unknown_capability
          | :connection_required
          | :unknown_connection
          | :unknown_credential
          | :credential_subject_mismatch
          | :credential_expired
          | :connection_installing
          | :connection_disabled
          | :connection_revoked
          | :reauth_required

  @cost_classes [:production, :replay, :eval, :simulation, :infrastructure]

  @spec register_connector(module()) :: :ok | {:error, term()}
  def register_connector(connector) do
    manifest = connector.manifest()
    metadata = Map.put(manifest.metadata || %{}, :connector_module, connector)

    Registry.register_manifest(%{manifest | metadata: metadata})
  end

  @spec connectors() :: [Manifest.t()]
  def connectors, do: Registry.connectors()

  @spec fetch_connector(String.t()) :: {:ok, Manifest.t()} | {:error, :unknown_connector}
  def fetch_connector(connector_id), do: Registry.fetch_connector(connector_id)

  @spec capabilities() :: [Capability.t()]
  def capabilities, do: Registry.capabilities()

  @spec fetch_capability(String.t()) :: {:ok, Capability.t()} | {:error, :unknown_capability}
  def fetch_capability(capability_id), do: Registry.fetch_capability(capability_id)

  @spec invoke(InvocationRequest.t()) ::
          {:ok, %{run: Run.t(), attempt: Attempt.t(), output: map()}}
          | {:error, invoke_preflight_error()}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Attempt.t() | nil,
               policy_decision: PolicyDecision.t() | nil
             }}
  def invoke(%InvocationRequest{} = request) do
    invoke(request.capability_id, request.input, InvocationRequest.to_opts(request))
  end

  @spec invoke(String.t(), map(), keyword()) ::
          {:ok, %{run: Run.t(), attempt: Attempt.t(), output: map()}}
          | {:error, invoke_preflight_error()}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Attempt.t() | nil,
               policy_decision: PolicyDecision.t() | nil
             }}
  def invoke(capability_id, input, opts \\ []) do
    reject_public_credential_ref!(opts)

    with {:ok, capability} <- fetch_capability(capability_id),
         {:ok, governed_lower_envelope} <-
           GovernedLowerAdmission.admit(capability, capability_id, opts),
         {:ok, auth_binding} <- resolve_invoke_auth(capability, opts) do
      opts = maybe_put_governed_lower_envelope(opts, governed_lower_envelope)
      run = build_run(capability, input, auth_binding.credential_ref, opts)

      :ok = Stores.run_store().put_run(run)
      continue_invoke(capability, run, input, opts, auth_binding)
    end
  end

  @spec execute_run(String.t(), pos_integer(), keyword()) ::
          {:ok, %{run: Run.t(), attempt: Attempt.t(), output: map()}}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Attempt.t() | nil,
               policy_decision: PolicyDecision.t() | nil
             }}
          | {:error, :unknown_run | {:unknown_capability, String.t()}}
  def execute_run(run_id, attempt_number, opts \\ [])
      when is_binary(run_id) and is_integer(attempt_number) and attempt_number > 0 do
    with {:ok, run} <- fetch_run(run_id),
         {:ok, capability} <- fetch_capability(run.capability_id) do
      continue_execute_run(capability, run, attempt_number, opts)
    else
      :error ->
        {:error, :unknown_run}

      {:error, :unknown_capability} ->
        {:error, {:unknown_capability, run_id}}
    end
  end

  @spec fetch_run(String.t()) :: {:ok, Run.t()} | :error
  def fetch_run(run_id), do: Stores.run_store().fetch_run(run_id)

  @spec runs(map()) :: [Run.t()]
  def runs(filters \\ %{}) when is_map(filters) do
    Stores.run_store().list_runs()
    |> filter_records(filters)
  end

  @spec fetch_attempt(String.t()) :: {:ok, Attempt.t()} | :error
  def fetch_attempt(attempt_id), do: Stores.attempt_store().fetch_attempt(attempt_id)

  @spec attempts(String.t()) :: [Attempt.t()]
  def attempts(run_id), do: Stores.attempt_store().list_attempts(run_id)

  @spec events(String.t()) :: [Event.t()]
  def events(run_id), do: Stores.event_store().list_events(run_id)

  @spec admit_trigger(TriggerRecord.t(), keyword()) ::
          {:ok, %{status: :accepted | :duplicate, trigger: TriggerRecord.t(), run: Run.t()}}
          | {:error, term()}
  def admit_trigger(%TriggerRecord{} = trigger, opts \\ []) do
    with {:ok, capability} <- fetch_capability(trigger.capability_id) do
      ingress_store = Stores.ingress_store()
      checkpoint = Keyword.get(opts, :checkpoint)

      dedupe_expires_at =
        DateTime.add(Contracts.now(), Keyword.get(opts, :dedupe_ttl_seconds, 86_400), :second)

      ingress_store.transaction(fn ->
        admit_trigger_once(ingress_store, capability, trigger, checkpoint, dedupe_expires_at)
      end)
    end
  end

  @spec record_rejected_trigger(TriggerRecord.t(), term()) ::
          {:ok, TriggerRecord.t()} | {:error, term()}
  def record_rejected_trigger(%TriggerRecord{} = trigger, reason) do
    ingress_store = Stores.ingress_store()
    rejected_trigger = %{trigger | status: :rejected, rejection_reason: reason, run_id: nil}

    ingress_store.transaction(fn ->
      case ingress_store.put_trigger(rejected_trigger) do
        :ok -> {:ok, rejected_trigger}
        {:error, error} -> ingress_store.rollback(error)
      end
    end)
  end

  @spec fetch_trigger(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, TriggerRecord.t()} | :error
  def fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key) do
    Stores.ingress_store().fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key)
  end

  @spec fetch_trigger_checkpoint(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, TriggerCheckpoint.t()} | :error
  def fetch_trigger_checkpoint(tenant_id, connector_id, trigger_id, partition_key) do
    Stores.ingress_store().fetch_checkpoint(tenant_id, connector_id, trigger_id, partition_key)
  end

  @spec put_trigger_checkpoint(TriggerCheckpoint.t()) :: :ok | {:error, term()}
  def put_trigger_checkpoint(%TriggerCheckpoint{} = checkpoint) do
    Stores.ingress_store().put_checkpoint(checkpoint)
  end

  @spec record_artifact(ArtifactRef.t()) :: :ok | {:error, term()}
  def record_artifact(%ArtifactRef{} = artifact_ref) do
    Stores.artifact_store().put_artifact_ref(artifact_ref)
  end

  @spec fetch_artifact(String.t()) :: {:ok, ArtifactRef.t()} | :error
  def fetch_artifact(artifact_id), do: Stores.artifact_store().fetch_artifact_ref(artifact_id)

  @spec run_artifacts(String.t()) :: [ArtifactRef.t()]
  def run_artifacts(run_id), do: Stores.artifact_store().list_artifact_refs(run_id)

  @spec announce_target(TargetDescriptor.t()) :: :ok | {:error, term()}
  def announce_target(%TargetDescriptor{} = target_descriptor) do
    Stores.target_store().put_target_descriptor(target_descriptor)
  end

  @spec fetch_target(String.t()) :: {:ok, TargetDescriptor.t()} | :error
  def fetch_target(target_id), do: Stores.target_store().fetch_target_descriptor(target_id)

  @spec targets(map()) :: [TargetDescriptor.t()]
  def targets(filters \\ %{}) when is_map(filters) do
    Stores.target_store().list_target_descriptors()
    |> filter_records(filters)
  end

  @spec install_simulation_profile(
          ServiceSimulationProfile.t() | map() | keyword(),
          [map()],
          map()
        ) ::
          {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}
  def install_simulation_profile(profile, installed_scenarios, attrs \\ %{}) do
    Stores.profile_registry_store().install_profile(profile, installed_scenarios, attrs)
  end

  @spec update_simulation_profile(
          ServiceSimulationProfile.t() | map() | keyword(),
          [map()],
          map()
        ) ::
          {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}
  def update_simulation_profile(profile, installed_scenarios, attrs \\ %{}) do
    Stores.profile_registry_store().update_profile(profile, installed_scenarios, attrs)
  end

  @spec remove_simulation_profile(String.t(), map()) ::
          {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}
  def remove_simulation_profile(profile_id, attrs \\ %{}) do
    Stores.profile_registry_store().remove_profile(profile_id, attrs)
  end

  @spec fetch_simulation_profile(String.t()) :: {:ok, SimulationProfileRegistryEntry.t()} | :error
  def fetch_simulation_profile(profile_id),
    do: Stores.profile_registry_store().fetch_profile(profile_id)

  @spec select_simulation_profile(String.t(), String.t(), String.t()) ::
          {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()} | :error
  def select_simulation_profile(profile_id, environment_scope, owner_ref) do
    Stores.profile_registry_store().select_profile(profile_id, environment_scope, owner_ref)
  end

  @spec simulation_profiles(map()) :: [SimulationProfileRegistryEntry.t()]
  def simulation_profiles(filters \\ %{}) when is_map(filters) do
    Stores.profile_registry_store().list_profiles(filters)
  end

  @spec run_triggers(String.t()) :: [TriggerRecord.t()]
  def run_triggers(run_id), do: Stores.ingress_store().list_run_triggers(run_id)

  @spec compatible_targets(map()) :: [
          %{target: TargetDescriptor.t(), negotiated_versions: map()}
        ]
  def compatible_targets(requirements) do
    Stores.target_store().list_target_descriptors()
    |> Enum.reduce([], fn descriptor, acc ->
      case TargetDescriptor.compatibility(descriptor, requirements) do
        {:ok, negotiated_versions} ->
          [%{target: descriptor, negotiated_versions: negotiated_versions} | acc]

        {:error, _reason} ->
          acc
      end
    end)
    |> Enum.sort(&target_match_sorter/2)
  end

  @spec reset!() :: :ok
  def reset! do
    assert_started!()
    Registry.reset!()
    reset_store(Stores.claim_check_store())
    reset_store(Stores.target_store())
    reset_store(Stores.artifact_store())
    reset_store(Stores.event_store())
    reset_store(Stores.attempt_store())
    reset_store(Stores.run_store())
    reset_store(Stores.ingress_store())
    Auth.reset!()
    ExecutionRouter.reset!()
    :ok
  end

  @spec inference_capability_id() :: String.t()
  def inference_capability_id, do: InferenceRecorder.inference_capability_id()

  @spec record_inference_attempt(map()) ::
          {:ok, %{run: Run.t(), attempt: Attempt.t()}} | {:error, Exception.t() | term()}
  def record_inference_attempt(spec), do: InferenceRecorder.record(spec)

  @doc """
  Public inference entrypoint for the control plane.
  """
  @spec invoke_inference(Jido.Integration.V2.InferenceRequest.t() | map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def invoke_inference(request, opts \\ []) do
    Inference.invoke(request, opts)
  end

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} -> Map.get(record, key) == value end)
    end)
  end

  defp maybe_put_governed_lower_envelope(opts, nil), do: opts

  defp maybe_put_governed_lower_envelope(opts, governed_lower_envelope) do
    Keyword.put(opts, :governed_lower_envelope, governed_lower_envelope)
  end

  defp continue_invoke(capability, run, input, opts, auth_binding) do
    opts = default_cost_budget_opts(run, opts)

    with :ok <- validate_target_selection(run, capability),
         :ok <- validate_guard_bindings(capability, opts),
         :ok <- ReplayService.validate_submission(capability, opts),
         :ok <- validate_cost_budget_submission(capability, opts),
         %PolicyDecision{status: :allowed} = policy_decision <-
           PolicyService.evaluate(
             capability,
             auth_binding.credential,
             auth_binding.credential_ref,
             input,
             opts
           ),
         {:ok, credential_lease} <- issue_invoke_lease(capability, auth_binding, opts) do
      execute_admitted_run(
        capability,
        run,
        input,
        opts,
        policy_decision,
        credential_lease,
        auth_binding.credential_ref
      )
    else
      {:error, reason} ->
        fail_before_attempt(run, reason)

      %PolicyDecision{status: status} = decision when status in [:denied, :shed] ->
        reject_run(run, decision)
    end
  end

  defp continue_execute_run(capability, run, attempt_number, opts) do
    opts = default_cost_budget_opts(run, opts)

    with {:ok, input} <- ReplayService.runtime_input(run),
         :ok <- validate_execution_status(run),
         :ok <- validate_target_selection(run, capability),
         :ok <- validate_guard_bindings(capability, opts),
         :ok <- ReplayService.validate_submission(capability, opts),
         :ok <- validate_cost_budget_submission(capability, opts),
         {:ok, auth_binding} <- resolve_run_auth(run),
         %PolicyDecision{status: :allowed} = policy_decision <-
           PolicyService.evaluate(
             capability,
             auth_binding.credential,
             auth_binding.credential_ref,
             input,
             opts
           ),
         {:ok, credential_lease} <- issue_invoke_lease(capability, auth_binding, opts) do
      execute_admitted_run(
        capability,
        run,
        input,
        opts,
        policy_decision,
        credential_lease,
        auth_binding.credential_ref,
        attempt_number
      )
    else
      {:error, reason} when reason in [:run_completed, :run_denied, :run_shed] ->
        terminal_execute_run_error(run, reason)

      {:error, reason} ->
        fail_before_attempt(run, reason)

      %PolicyDecision{status: status} = decision when status in [:denied, :shed] ->
        reject_run(run, decision)
    end
  end

  defp execute_admitted_run(
         capability,
         run,
         input,
         opts,
         policy_decision,
         credential_lease,
         credential_ref,
         attempt_number \\ 1
       ) do
    attempt = build_attempt(run, credential_lease, opts, attempt_number)

    context =
      build_context(
        capability,
        run,
        attempt,
        opts,
        policy_decision,
        credential_lease,
        credential_ref
      )

    with :ok <- Stores.attempt_store().put_attempt(attempt),
         :ok <-
           append_specs(
             run.run_id,
             attempt,
             [%{type: "run.started"}] ++ guard_input_specs(context)
           ) do
      case dispatch_or_replay(capability, input, context) do
        {:ok, runtime_result} ->
          :ok =
            append_specs(run.run_id, attempt, guard_output_specs(context, runtime_result.output))

          complete_attempt(run, attempt, runtime_result)

        {:error, reason, runtime_result} ->
          fail_attempt(run, attempt, reason, runtime_result, policy_decision)
      end
    else
      {:error, reason} ->
        fail_before_attempt(run, reason)
    end
  end

  defp complete_attempt(run, attempt, runtime_result) do
    :ok = persist_artifacts(runtime_result.artifacts)

    :ok =
      append_specs(run.run_id, attempt, runtime_result.events ++ artifact_specs(runtime_result))

    :ok =
      Stores.attempt_store().update_attempt(
        attempt.attempt_id,
        :completed,
        runtime_result.output,
        runtime_result.runtime_ref_id,
        aggregator_opts(attempt)
      )

    :ok = Stores.run_store().update_run(run.run_id, :completed, runtime_result.output)
    :ok = append_specs(run.run_id, attempt, [%{type: "run.completed"}])

    {:ok,
     %{
       run: fetch_run!(run.run_id),
       attempt: fetch_attempt!(attempt.attempt_id),
       output: runtime_result.output
     }}
  end

  defp fail_attempt(run, attempt, reason, runtime_result, policy_decision) do
    :ok = persist_artifacts(runtime_result.artifacts)

    :ok =
      append_specs(run.run_id, attempt, runtime_result.events ++ artifact_specs(runtime_result))

    :ok =
      Stores.attempt_store().update_attempt(
        attempt.attempt_id,
        :failed,
        runtime_result.output,
        runtime_result.runtime_ref_id,
        aggregator_opts(attempt)
      )

    :ok = Stores.run_store().update_run(run.run_id, :failed, %{error: inspect(reason)})

    :ok =
      append_specs(run.run_id, attempt, [
        %{type: "run.failed", payload: %{reason: inspect(reason)}}
      ])

    {:error,
     %{
       reason: reason,
       run: fetch_run!(run.run_id),
       attempt: fetch_attempt!(attempt.attempt_id),
       policy_decision: policy_decision
     }}
  end

  defp fail_before_attempt(run, reason) do
    :ok = Stores.run_store().update_run(run.run_id, :failed, %{error: inspect(reason)})

    :ok =
      append_specs(run.run_id, nil, [
        %{type: "run.failed", payload: %{reason: inspect(reason)}}
      ])

    {:error,
     %{
       reason: reason,
       run: fetch_run!(run.run_id),
       attempt: nil,
       policy_decision: nil
     }}
  end

  defp terminal_execute_run_error(run, reason) do
    {:error,
     %{
       reason: reason,
       run: fetch_run!(run.run_id),
       attempt: nil,
       policy_decision: nil
     }}
  end

  defp reject_run(run, decision) do
    :ok =
      Stores.run_store().update_run(
        run.run_id,
        PolicyService.rejection_run_status(decision),
        PolicyService.rejection_snapshot(decision)
      )

    :ok =
      append_specs(run.run_id, nil, [
        %{
          type: PolicyService.rejection_event_type(decision),
          payload: %{reasons: decision.reasons}
        },
        %{
          type: PolicyService.rejection_audit_event_type(decision),
          stream: :control,
          level: PolicyService.rejection_audit_level(decision),
          payload: Map.put(decision.audit_context, :reasons, decision.reasons),
          trace: %{trace_id: Map.get(decision.audit_context, :trace_id)}
        }
      ])

    {:error,
     %{
       reason: PolicyService.rejection_error(decision),
       run: fetch_run!(run.run_id),
       attempt: nil,
       policy_decision: decision
     }}
  end

  defp build_run(capability, input, credential_ref, opts) do
    Run.new!(%{
      capability_id: capability.id,
      runtime_class: capability.runtime_class,
      status: :accepted,
      input: input,
      credential_ref: credential_ref,
      target_id: Keyword.get(opts, :target_id)
    })
  end

  defp build_attempt(run, credential_lease, opts, attempt_number) do
    Attempt.new!(%{
      run_id: run.run_id,
      attempt: attempt_number,
      aggregator_id: Keyword.get(opts, :aggregator_id, "control_plane"),
      aggregator_epoch: Keyword.get(opts, :aggregator_epoch, attempt_number),
      runtime_class: run.runtime_class,
      status: :accepted,
      credential_lease_id: credential_lease.lease_id,
      target_id: run.target_id
    })
  end

  defp build_trigger_run(capability, trigger) do
    Run.new!(%{
      capability_id: capability.id,
      runtime_class: capability.runtime_class,
      status: :accepted,
      input: %{
        trigger: %{
          admission_id: trigger.admission_id,
          source: trigger.source,
          connector_id: trigger.connector_id,
          trigger_id: trigger.trigger_id,
          tenant_id: trigger.tenant_id,
          external_id: trigger.external_id,
          dedupe_key: trigger.dedupe_key,
          partition_key: trigger.partition_key,
          payload: trigger.payload,
          signal: trigger.signal
        }
      },
      credential_ref: anonymous_credential()
    })
  end

  defp admit_trigger_once(ingress_store, capability, trigger, checkpoint, dedupe_expires_at) do
    case ingress_store.reserve_dedupe(
           trigger.tenant_id,
           trigger.connector_id,
           trigger.trigger_id,
           trigger.dedupe_key,
           dedupe_expires_at
         ) do
      :ok ->
        accept_trigger(ingress_store, capability, trigger, checkpoint)

      {:error, :duplicate} ->
        load_duplicate_trigger(ingress_store, trigger, checkpoint)

      {:error, reason} ->
        ingress_store.rollback(reason)
    end
  end

  defp accept_trigger(ingress_store, capability, trigger, checkpoint) do
    run = build_trigger_run(capability, trigger)
    accepted_trigger = %{trigger | status: :accepted, run_id: run.run_id}

    with :ok <- Stores.run_store().put_run(run),
         :ok <- ingress_store.put_trigger(accepted_trigger),
         :ok <- maybe_put_checkpoint(ingress_store, checkpoint),
         :ok <-
           append_specs(run.run_id, nil, [
             %{
               type: "run.accepted",
               payload: %{trigger_admission_id: accepted_trigger.admission_id}
             }
           ]) do
      {:ok, %{status: :accepted, trigger: accepted_trigger, run: run}}
    else
      {:error, reason} ->
        ingress_store.rollback(reason)
    end
  end

  defp load_duplicate_trigger(ingress_store, trigger, checkpoint) do
    with {:ok, existing_trigger} <-
           ingress_store.fetch_trigger(
             trigger.tenant_id,
             trigger.connector_id,
             trigger.trigger_id,
             trigger.dedupe_key
           ),
         {:ok, existing_run} <- fetch_run(existing_trigger.run_id),
         :ok <- maybe_put_checkpoint(ingress_store, checkpoint) do
      {:ok, %{status: :duplicate, trigger: existing_trigger, run: existing_run}}
    else
      :error ->
        ingress_store.rollback(:duplicate_trigger_not_found)

      {:error, reason} ->
        ingress_store.rollback(reason)
    end
  end

  defp build_context(
         capability,
         run,
         attempt,
         opts,
         policy_decision,
         credential_lease,
         credential_ref
       ) do
    %{
      run_id: run.run_id,
      attempt: attempt.attempt,
      attempt_id: attempt.attempt_id,
      credential_ref: credential_ref,
      credential_lease: credential_lease,
      policy_decision: policy_decision,
      target_descriptor: target_descriptor(run),
      policy_inputs: %{
        admission: policy_decision.audit_context,
        execution: policy_decision.execution_policy
      },
      opts: Enum.into(opts, %{}),
      prompt_ref: ref_option(opts, :prompt_ref),
      guard_chain_ref: ref_option(opts, :guard_chain_ref),
      replay_mode: Keyword.get(opts, :replay_mode),
      replay_support_class: ReplayService.support_class(capability, opts),
      cost_meter_ref: ref_option(opts, :cost_meter_ref),
      budget_refs: budget_refs(opts),
      cost_class: cost_class(opts)
    }
  end

  defp dispatch_or_replay(capability, input, context) do
    if ReplayService.replay_mode?(Map.get(context, :replay_mode)) do
      ReplayService.fixture_result(context)
    else
      case dispatch(capability, input, context) do
        {:ok, runtime_result} ->
          {:ok, attach_cost_event(runtime_result, context)}

        {:error, reason, runtime_result} ->
          {:error, reason, attach_cost_event(runtime_result, context)}
      end
    end
  end

  defp dispatch(
         %Capability{} = capability,
         input,
         %{
           opts: %{governed_lower_envelope: %GovernedLowerEnvelope{lower_runtime_kind: :tre_rhai}}
         } =
           context
       ) do
    case TreAdapter.fetch(context.opts) do
      {:ok, adapter} ->
        adapter.execute(capability, input, context)

      :error ->
        {:error, :lower_runtime_unavailable, unavailable_tre_runtime_result(capability, context)}
    end
  end

  defp dispatch(%Capability{} = capability, input, context) do
    ExecutionRouter.execute(capability, input, context)
  end

  defp unavailable_tre_runtime_result(%Capability{} = capability, context) do
    envelope = context.opts.governed_lower_envelope

    RuntimeResult.new!(%{
      output: %{
        error: "tre_adapter_unavailable",
        capability_id: capability.id,
        lower_request_ref: envelope.lower_request_ref,
        lower_runtime_kind: envelope.lower_runtime_kind
      },
      events: [
        %{
          type: "tre.adapter.unavailable",
          stream: :control,
          level: :warn,
          payload: %{
            capability_id: capability.id,
            lower_request_ref: envelope.lower_request_ref,
            lower_runtime_kind: "tre_rhai"
          }
        }
      ],
      artifacts: []
    })
  end

  defp validate_guard_bindings(capability, opts) do
    guard_policy =
      capability.metadata
      |> Contracts.get(:policy, %{})
      |> Contracts.get(:guard, %{})

    prompt_ref = ref_option(opts, :prompt_ref)
    guard_chain_ref = ref_option(opts, :guard_chain_ref)
    required? = Contracts.get(guard_policy, :required, false) == true

    validate_guard_presence(required?, prompt_ref, guard_chain_ref)
  end

  defp validate_guard_presence(true, nil, _guard_chain_ref),
    do: {:error, :guard_prompt_ref_required}

  defp validate_guard_presence(true, _prompt_ref, nil), do: {:error, :guard_chain_ref_required}

  defp validate_guard_presence(_required?, nil, guard_chain_ref) when not is_nil(guard_chain_ref),
    do: {:error, :guard_prompt_ref_required}

  defp validate_guard_presence(_required?, prompt_ref, nil) when not is_nil(prompt_ref),
    do: {:error, :guard_chain_ref_required}

  defp validate_guard_presence(_required?, _prompt_ref, _guard_chain_ref), do: :ok

  defp validate_cost_budget_submission(capability, opts) do
    with :ok <- require_cost_meter_ref(opts),
         :ok <- require_budget_refs(opts),
         {:ok, cost_class} <- validate_cost_class(opts),
         :ok <- validate_declared_cost_class(capability, cost_class) do
      validate_replay_cost_class(opts, cost_class)
    end
  end

  defp require_cost_meter_ref(opts) do
    case ref_option(opts, :cost_meter_ref) do
      nil -> {:error, :cost_meter_ref_required}
      _ref -> :ok
    end
  end

  defp require_budget_refs(opts) do
    case budget_refs(opts) do
      [] -> {:error, :budget_ref_required}
      _refs -> :ok
    end
  end

  defp default_cost_budget_opts(%Run{} = run, opts) do
    opts
    |> default_cost_meter_ref(run)
    |> default_budget_refs(run)
  end

  defp default_cost_meter_ref(opts, %Run{} = run) do
    if Keyword.has_key?(opts, :cost_meter_ref) do
      opts
    else
      Keyword.put(opts, :cost_meter_ref, "meter://jido-integration/#{run.run_id}")
    end
  end

  defp default_budget_refs(opts, %Run{} = run) do
    if Keyword.has_key?(opts, :budget_refs) or Keyword.has_key?(opts, :budget_ref) do
      opts
    else
      Keyword.put(opts, :budget_refs, ["budget://jido-integration/#{run.run_id}/per-run"])
    end
  end

  defp validate_cost_class(opts) do
    value = cost_class(opts)

    if value in @cost_classes do
      {:ok, value}
    else
      {:error, :unknown_cost_class}
    end
  end

  defp validate_declared_cost_class(capability, cost_class) do
    if cost_class in Capability.emitted_cost_classes(capability) do
      :ok
    else
      {:error, :undeclared_capability_cost_class}
    end
  end

  defp validate_replay_cost_class(opts, :production) do
    case Keyword.get(opts, :replay_mode) do
      nil -> :ok
      _replay_mode -> {:error, :replay_production_cost_forbidden}
    end
  end

  defp validate_replay_cost_class(_opts, _cost_class), do: :ok

  defp guard_input_specs(%{prompt_ref: prompt_ref, guard_chain_ref: guard_chain_ref})
       when is_binary(prompt_ref) and is_binary(guard_chain_ref) do
    [
      %{
        type: "guard.input.evaluated",
        stream: :control,
        payload: %{
          prompt_ref: prompt_ref,
          guard_chain_ref: guard_chain_ref,
          payload_kind: "tool_input",
          decision_class: "allow"
        }
      }
    ]
  end

  defp guard_input_specs(_context), do: []

  defp guard_output_specs(%{prompt_ref: prompt_ref, guard_chain_ref: guard_chain_ref}, output)
       when is_binary(prompt_ref) and is_binary(guard_chain_ref) do
    [
      %{
        type: "guard.output.evaluated",
        stream: :control,
        payload: %{
          prompt_ref: prompt_ref,
          guard_chain_ref: guard_chain_ref,
          payload_kind: "tool_output",
          decision_class: "allow",
          output_shape_ref: output_shape_ref(output)
        }
      }
    ]
  end

  defp guard_output_specs(_context, _output), do: []

  defp resolve_invoke_auth(capability, opts) do
    case Keyword.get(opts, :connection_id) do
      nil ->
        if auth_connection_required?(capability) do
          {:error, :connection_required}
        else
          {:ok, anonymous_auth_binding(capability)}
        end

      connection_id ->
        connection_id = Contracts.validate_non_empty_string!(connection_id, "connection_id")

        Auth.resolve_connection_binding(connection_id)
    end
  end

  defp anonymous_auth_binding(_capability) do
    credential_ref = anonymous_credential()
    {:ok, credential} = resolve_credential(credential_ref)

    %{
      credential_ref: credential_ref,
      credential: credential,
      connection_id: nil
    }
  end

  defp resolve_run_auth(
         %Run{credential_ref: %CredentialRef{id: "cred-anon", subject: "anonymous"}} = run
       ) do
    anonymous_auth_binding(run)
    |> then(&{:ok, &1})
  end

  defp resolve_run_auth(%Run{credential_ref: %CredentialRef{} = credential_ref}) do
    case connection_id_from_credential_ref(credential_ref) do
      nil ->
        with {:ok, credential} <- resolve_credential(credential_ref) do
          {:ok, %{credential_ref: credential_ref, credential: credential, connection_id: nil}}
        end

      connection_id ->
        Auth.resolve_connection_binding(connection_id)
    end
  end

  defp auth_connection_required?(%Capability{} = capability) do
    Capability.required_scopes(capability) != []
  end

  defp issue_invoke_lease(
         capability,
         %{connection: %{connection_id: connection_id}},
         opts
       ) do
    Auth.request_lease(connection_id, %{
      actor_id: Keyword.get(opts, :actor_id),
      required_scopes: Capability.required_scopes(capability)
    })
  end

  defp issue_invoke_lease(capability, %{credential_ref: credential_ref}, _opts) do
    issue_credential_lease(credential_ref, capability)
  end

  defp anonymous_credential do
    CredentialRef.new!(%{id: "cred-anon", subject: "anonymous", scopes: []})
  end

  defp reject_public_credential_ref!(opts) do
    if Keyword.has_key?(opts, :credential_ref) do
      raise ArgumentError, "credential_ref is not part of the public invoke contract"
    end
  end

  defp ref_option(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp budget_refs(opts) do
    values =
      case Keyword.get(opts, :budget_refs) do
        refs when is_list(refs) -> refs
        nil -> List.wrap(Keyword.get(opts, :budget_ref))
        ref -> [ref]
      end

    Enum.filter(values, &(is_binary(&1) and &1 != ""))
  end

  defp cost_class(opts) do
    case Keyword.get(opts, :cost_class) do
      value when value in @cost_classes -> value
      value when is_binary(value) -> cost_class_from_string(value)
      _value -> if Keyword.get(opts, :replay_mode), do: :replay, else: :production
    end
  end

  defp cost_class_from_string("production"), do: :production
  defp cost_class_from_string("replay"), do: :replay
  defp cost_class_from_string("eval"), do: :eval
  defp cost_class_from_string("simulation"), do: :simulation
  defp cost_class_from_string("infrastructure"), do: :infrastructure
  defp cost_class_from_string(_value), do: :unknown

  defp attach_cost_event(%RuntimeResult{} = runtime_result, context) do
    event = %{
      type: "cost.recorded",
      stream: :control,
      payload: %{
        cost_class: Atom.to_string(context.cost_class),
        cost_meter_ref: context.cost_meter_ref,
        budget_refs: context.budget_refs
      }
    }

    %{runtime_result | events: runtime_result.events ++ [event]}
  end

  defp output_shape_ref(output) when is_map(output) do
    keys =
      output
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.sort()
      |> Enum.join(":")

    "tool-output-shape://sha256/" <> sha256(keys)
  end

  defp output_shape_ref(_output), do: "tool-output-shape://sha256/" <> sha256("unsupported")

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp issue_credential_lease(
         %CredentialRef{id: "cred-anon", subject: "anonymous"} = credential_ref,
         capability
       ) do
    issued_at = Contracts.now()

    {:ok,
     CredentialLease.new!(%{
       lease_id: Contracts.next_id("lease"),
       tenant_id: "tenant-anonymous",
       credential_ref_id: credential_ref.id,
       subject: credential_ref.subject,
       scopes: Capability.required_scopes(capability),
       payload: %{},
       issued_at: issued_at,
       expires_at: DateTime.add(issued_at, 300, :second)
     })}
  end

  defp issue_credential_lease(%CredentialRef{} = credential_ref, capability) do
    Auth.issue_lease(credential_ref, %{required_scopes: Capability.required_scopes(capability)})
  end

  defp resolve_credential(%CredentialRef{id: "cred-anon", subject: "anonymous"} = credential_ref) do
    {:ok,
     Credential.new!(%{
       id: credential_ref.id,
       subject: credential_ref.subject,
       auth_type: :none,
       scopes: [],
       secret: %{}
     })}
  end

  defp resolve_credential(%CredentialRef{} = credential_ref) do
    Auth.resolve(credential_ref, %{})
  end

  defp connection_id_from_credential_ref(%CredentialRef{} = credential_ref) do
    credential_ref.connection_id ||
      Contracts.get(credential_ref.metadata, :connection_id)
  end

  defp validate_execution_status(%Run{status: status}) when status in [:accepted, :failed],
    do: :ok

  defp validate_execution_status(%Run{status: :completed}), do: {:error, :run_completed}
  defp validate_execution_status(%Run{status: :denied}), do: {:error, :run_denied}
  defp validate_execution_status(%Run{status: :shed}), do: {:error, :run_shed}

  defp validate_target_selection(%Run{target_id: nil}, %Capability{}), do: :ok

  defp validate_target_selection(%Run{target_id: target_id}, %Capability{} = capability) do
    requirements = target_selection_requirements(capability)

    with {:ok, descriptor} <- fetch_target(target_id),
         {:ok, _negotiated_versions} <- TargetDescriptor.compatibility(descriptor, requirements) do
      :ok
    else
      :error ->
        {:error, {:unknown_target, target_id}}

      {:error, reason} ->
        {:error, {:target_incompatible, target_id, reason}}
    end
  end

  defp target_selection_requirements(%Capability{} = capability) do
    TargetDescriptor.authored_requirements(capability)
  end

  defp append_specs(run_id, attempt, specs) do
    event_store = Stores.event_store()
    attempt_id = attempt && attempt.attempt_id
    start_seq = event_store.next_seq(run_id, attempt_id)

    events =
      specs
      |> Enum.with_index(start_seq)
      |> Enum.map(fn {spec, seq} ->
        Event.new!(%{
          event_id: Contracts.event_id(run_id, attempt_id, seq),
          run_id: run_id,
          attempt: attempt && attempt.attempt,
          attempt_id: attempt_id,
          seq: seq,
          type: spec.type,
          stream: Map.get(spec, :stream, :system),
          level: Map.get(spec, :level, :info),
          payload: Map.get(spec, :payload, %{}),
          payload_ref: Map.get(spec, :payload_ref),
          trace: Map.get(spec, :trace, %{}),
          target_id: Map.get(spec, :target_id, attempt && attempt.target_id),
          session_id: Map.get(spec, :session_id),
          runtime_ref_id: Map.get(spec, :runtime_ref_id)
        })
      end)

    event_store.append_events(events, aggregator_opts(attempt))
  end

  defp aggregator_opts(nil), do: []

  defp aggregator_opts(%Attempt{} = attempt) do
    [aggregator_id: attempt.aggregator_id, aggregator_epoch: attempt.aggregator_epoch]
  end

  defp fetch_run!(run_id) do
    case fetch_run(run_id) do
      {:ok, run} -> run
      :error -> raise KeyError, key: run_id, term: :run
    end
  end

  defp fetch_attempt!(attempt_id) do
    case fetch_attempt(attempt_id) do
      {:ok, attempt} -> attempt
      :error -> raise KeyError, key: attempt_id, term: :attempt
    end
  end

  defp reset_store(module) do
    if function_exported?(module, :reset!, 0) do
      module.reset!()
    end
  end

  defp assert_started! do
    if Process.whereis(Registry) do
      :ok
    else
      raise ArgumentError,
            "control plane registry is not started; start Jido.Integration.V2.ControlPlane.Application before calling Jido.Integration.V2.ControlPlane.reset!/0"
    end
  end

  defp persist_artifacts(artifacts) when is_list(artifacts) do
    Enum.each(artifacts, fn artifact_ref ->
      :ok = Stores.artifact_store().put_artifact_ref(artifact_ref)
    end)

    :ok
  end

  defp artifact_specs(%RuntimeResult{artifacts: artifacts, runtime_ref_id: runtime_ref_id}) do
    Enum.map(artifacts, fn artifact_ref ->
      %{
        type: "artifact.recorded",
        stream: :control,
        payload: %{
          artifact_id: artifact_ref.artifact_id,
          artifact_type: artifact_ref.artifact_type,
          retention_class: artifact_ref.retention_class
        },
        runtime_ref_id: runtime_ref_id
      }
    end)
  end

  defp maybe_put_checkpoint(_ingress_store, nil), do: :ok

  defp maybe_put_checkpoint(ingress_store, %TriggerCheckpoint{} = checkpoint) do
    ingress_store.put_checkpoint(checkpoint)
  end

  defp target_match_sorter(left, right) do
    case Version.compare(left.target.version, right.target.version) do
      :gt -> true
      :lt -> false
      :eq -> left.target.target_id <= right.target.target_id
    end
  end

  defp target_descriptor(%Run{target_id: nil}), do: nil

  defp target_descriptor(%Run{target_id: target_id}) do
    case fetch_target(target_id) do
      {:ok, descriptor} -> descriptor
      :error -> nil
    end
  end
end
