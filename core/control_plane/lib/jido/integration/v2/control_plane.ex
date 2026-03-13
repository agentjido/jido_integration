defmodule Jido.Integration.V2.ControlPlane do
  @moduledoc """
  Capability registry plus canonical run/attempt/event ledger.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.Registry
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Gateway
  alias Jido.Integration.V2.Policy
  alias Jido.Integration.V2.PolicyDecision
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.SessionKernel
  alias Jido.Integration.V2.StreamRuntime
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @spec register_connector(module()) :: :ok | {:error, term()}
  def register_connector(connector) do
    Registry.register_manifest(connector.manifest())
  end

  @spec capabilities() :: [Capability.t()]
  def capabilities, do: Registry.capabilities()

  @spec invoke(String.t(), map(), keyword()) ::
          {:ok, %{run: Run.t(), attempt: Attempt.t(), output: map()}}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Attempt.t() | nil,
               policy_decision: PolicyDecision.t() | nil
             }}
  def invoke(capability_id, input, opts \\ []) do
    with {:ok, capability} <- Registry.fetch_capability(capability_id) do
      credential_ref = Keyword.get(opts, :credential_ref, anonymous_credential())
      run = build_run(capability, input, credential_ref, opts)

      :ok = Stores.run_store().put_run(run)
      continue_invoke(capability, run, input, opts)
    end
  end

  @spec fetch_run(String.t()) :: {:ok, Run.t()} | :error
  def fetch_run(run_id), do: Stores.run_store().fetch_run(run_id)

  @spec fetch_attempt(String.t()) :: {:ok, Attempt.t()} | :error
  def fetch_attempt(attempt_id), do: Stores.attempt_store().fetch_attempt(attempt_id)

  @spec events(String.t()) :: [Event.t()]
  def events(run_id), do: Stores.event_store().list_events(run_id)

  @spec admit_trigger(TriggerRecord.t(), keyword()) ::
          {:ok, %{status: :accepted | :duplicate, trigger: TriggerRecord.t(), run: Run.t()}}
          | {:error, term()}
  def admit_trigger(%TriggerRecord{} = trigger, opts \\ []) do
    with {:ok, capability} <- Registry.fetch_capability(trigger.capability_id) do
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
    Registry.reset!()
    reset_store(Stores.target_store())
    reset_store(Stores.artifact_store())
    reset_store(Stores.event_store())
    reset_store(Stores.attempt_store())
    reset_store(Stores.run_store())
    reset_store(Stores.ingress_store())
    Auth.reset!()
    SessionKernel.reset!()
    StreamRuntime.reset!()
    :ok
  end

  defp continue_invoke(capability, run, input, opts) do
    credential_ref = run.credential_ref

    with :ok <- validate_target_selection(run, capability),
         {:ok, resolved_credential} <- resolve_credential(credential_ref),
         %PolicyDecision{status: :allowed} = policy_decision <-
           evaluate_policy(capability, resolved_credential, credential_ref, input, opts),
         {:ok, credential_lease} <-
           issue_credential_lease(credential_ref, capability) do
      execute_admitted_run(capability, run, input, opts, policy_decision, credential_lease)
    else
      {:error, reason} ->
        fail_before_attempt(run, reason)

      %PolicyDecision{status: :denied} = decision ->
        deny_run(run, decision)
    end
  end

  defp evaluate_policy(capability, resolved_credential, credential_ref, input, opts) do
    gateway =
      Gateway.new!(%{
        actor_id: Keyword.get(opts, :actor_id),
        tenant_id: Keyword.get(opts, :tenant_id),
        environment: Keyword.get(opts, :environment),
        trace_id: Keyword.get(opts, :trace_id),
        credential_ref: credential_ref,
        runtime_class: capability.runtime_class,
        allowed_operations: Keyword.get(opts, :allowed_operations, []),
        sandbox: Keyword.get(opts, :sandbox, %{}),
        metadata: %{opts: Enum.into(opts, %{})}
      })

    Policy.evaluate(capability, resolved_credential, input, gateway)
  end

  defp execute_admitted_run(capability, run, input, opts, policy_decision, credential_lease) do
    attempt = build_attempt(run, credential_lease, opts)
    context = build_context(run, attempt, opts, policy_decision, credential_lease)

    :ok = Stores.attempt_store().put_attempt(attempt)
    :ok = append_specs(run.run_id, attempt, [%{type: "run.started"}])

    case dispatch(capability, input, context) do
      {:ok, runtime_result} ->
        complete_attempt(run, attempt, runtime_result)

      {:error, reason, runtime_result} ->
        fail_attempt(run, attempt, reason, runtime_result, policy_decision)
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

  defp deny_run(run, decision) do
    :ok = Stores.run_store().update_run(run.run_id, :denied, denial_snapshot(decision))

    :ok =
      append_specs(run.run_id, nil, [
        %{type: "run.denied", payload: %{reasons: decision.reasons}},
        %{
          type: "audit.policy_denied",
          stream: :control,
          level: :error,
          payload: Map.put(decision.audit_context, :reasons, decision.reasons),
          trace: %{trace_id: Map.get(decision.audit_context, :trace_id)}
        }
      ])

    {:error,
     %{
       reason: :policy_denied,
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

  defp build_attempt(run, credential_lease, opts) do
    Attempt.new!(%{
      run_id: run.run_id,
      attempt: 1,
      aggregator_id: Keyword.get(opts, :aggregator_id, "control_plane"),
      aggregator_epoch: Keyword.get(opts, :aggregator_epoch, 1),
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

  defp build_context(run, attempt, opts, policy_decision, credential_lease) do
    %{
      run_id: run.run_id,
      attempt: attempt.attempt,
      attempt_id: attempt.attempt_id,
      credential_ref: run.credential_ref,
      credential_lease: credential_lease,
      policy_decision: policy_decision,
      policy_inputs: %{
        admission: policy_decision.audit_context,
        execution: policy_decision.execution_policy
      },
      opts: Enum.into(opts, %{})
    }
  end

  defp dispatch(%Capability{runtime_class: :direct} = capability, input, context) do
    DirectRuntime.execute(capability, input, context)
  end

  defp dispatch(%Capability{runtime_class: :session} = capability, input, context) do
    SessionKernel.execute(capability, input, context)
  end

  defp dispatch(%Capability{runtime_class: :stream} = capability, input, context) do
    StreamRuntime.execute(capability, input, context)
  end

  defp anonymous_credential do
    CredentialRef.new!(%{id: "cred-anon", subject: "anonymous", scopes: []})
  end

  defp issue_credential_lease(
         %CredentialRef{id: "cred-anon", subject: "anonymous"} = credential_ref,
         capability
       ) do
    issued_at = Contracts.now()

    {:ok,
     CredentialLease.new!(%{
       lease_id: Contracts.next_id("lease"),
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

  defp validate_target_selection(%Run{target_id: nil}, %Capability{}), do: :ok

  defp validate_target_selection(%Run{target_id: target_id}, %Capability{} = capability) do
    with {:ok, descriptor} <- fetch_target(target_id),
         {:ok, _negotiated_versions} <-
           TargetDescriptor.compatibility(descriptor, %{
             capability_id: capability.id,
             runtime_class: capability.runtime_class
           }) do
      :ok
    else
      :error ->
        {:error, {:unknown_target, target_id}}

      {:error, reason} ->
        {:error, {:target_incompatible, target_id, reason}}
    end
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
        payload_ref: artifact_ref.payload_ref,
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

  defp denial_snapshot(decision) do
    %{
      policy:
        decision.audit_context
        |> Map.put(:reasons, decision.reasons)
        |> Map.put(:status, decision.status)
    }
  end
end
