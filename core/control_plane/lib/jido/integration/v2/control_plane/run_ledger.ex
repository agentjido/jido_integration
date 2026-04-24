defmodule Jido.Integration.V2.ControlPlane.RunLedger do
  @moduledoc false

  use Agent

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.ClaimCheckStore
  alias Jido.Integration.V2.ControlPlane.ClaimCheckTelemetry
  alias Jido.Integration.V2.ControlPlane.ProfileRegistryStore
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.SimulationProfileRegistryEntry
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @behaviour Jido.Integration.V2.ControlPlane.RunStore
  @behaviour Jido.Integration.V2.ControlPlane.AttemptStore
  @behaviour Jido.Integration.V2.ControlPlane.EventStore
  @behaviour Jido.Integration.V2.ControlPlane.ArtifactStore
  @behaviour ClaimCheckStore
  @behaviour Jido.Integration.V2.ControlPlane.TargetStore
  @behaviour Jido.Integration.V2.ControlPlane.IngressStore
  @behaviour ProfileRegistryStore

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          runs: %{},
          attempts: %{},
          events: %{},
          artifacts: %{},
          run_artifacts: %{},
          claim_check_blobs: %{},
          claim_check_references: %{},
          targets: %{},
          profile_registry_entries: %{},
          triggers: %{},
          run_triggers: %{},
          checkpoints: %{},
          dedupe: %{}
        }
      end,
      name: __MODULE__
    )
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def transaction(fun) when is_function(fun, 0) do
    fun.()
  catch
    {:run_ledger_rollback, reason} ->
      {:error, reason}
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def rollback(reason) do
    throw({:run_ledger_rollback, reason})
  end

  @impl Jido.Integration.V2.ControlPlane.RunStore
  def put_run(run) do
    Agent.update(__MODULE__, fn state ->
      run = sanitize_run(run)

      state
      |> put_in([:runs, run.run_id], run)
      |> maybe_put_run_claim_check_reference(run, :input, Map.get(run, :input_payload_ref))
      |> maybe_put_run_claim_check_reference(run, :result, Map.get(run, :result_payload_ref))
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.AttemptStore
  def put_attempt(attempt) do
    Agent.update(__MODULE__, fn state ->
      attempt = sanitize_attempt(attempt)

      state
      |> put_in([:attempts, attempt.attempt_id], attempt)
      |> maybe_put_attempt_claim_check_reference(
        attempt,
        :output,
        Map.get(attempt, :output_payload_ref)
      )
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.EventStore
  def next_seq(run_id, attempt_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(:events, %{})
      |> Map.get(run_id, [])
      |> Enum.count(&(&1.attempt_id == attempt_id))
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.EventStore
  def append_events(events, _opts \\ []) do
    Agent.get_and_update(__MODULE__, fn state ->
      case persist_events(state, events) do
        {:ok, next_state} -> {:ok, next_state}
        {:error, reason} -> {{:error, reason}, state}
      end
    end)
  end

  def append_specs(run_id, attempt, specs, opts \\ []) do
    start_seq = next_seq(run_id, attempt_id(attempt))

    events =
      specs
      |> Enum.with_index(start_seq)
      |> Enum.map(fn {spec, seq} ->
        Event.new!(%{
          event_id: Contracts.event_id(run_id, attempt_id(attempt), seq),
          run_id: run_id,
          attempt: attempt_number(attempt),
          attempt_id: attempt_id(attempt),
          seq: seq,
          type: spec.type,
          stream: Map.get(spec, :stream, :system),
          level: Map.get(spec, :level, :info),
          payload: Map.get(spec, :payload, %{}),
          payload_ref: Map.get(spec, :payload_ref),
          trace: Map.get(spec, :trace, %{}),
          target_id: Map.get(spec, :target_id, target_id(attempt)),
          session_id: Map.get(spec, :session_id),
          runtime_ref_id: Map.get(spec, :runtime_ref_id)
        })
      end)

    append_events(events, opts)
  end

  @impl Jido.Integration.V2.ControlPlane.RunStore
  def update_run(run_id, status, result) do
    Agent.update(__MODULE__, fn state ->
      update_in(state, [:runs, run_id], fn run ->
        %{run | status: status, result: Redaction.redact(result), updated_at: Contracts.now()}
      end)
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.AttemptStore
  def update_attempt(attempt_id, status, output, runtime_ref_id, opts \\ []) do
    Agent.update(__MODULE__, fn state ->
      update_in(state, [:attempts, attempt_id], fn attempt ->
        %{
          attempt
          | status: status,
            output: Redaction.redact(output),
            runtime_ref_id: runtime_ref_id,
            aggregator_id: Keyword.get(opts, :aggregator_id, attempt.aggregator_id),
            aggregator_epoch: Keyword.get(opts, :aggregator_epoch, attempt.aggregator_epoch),
            updated_at: Contracts.now()
        }
      end)
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.RunStore
  def fetch_run(run_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.runs, run_id) do
        {:ok, run} -> {:ok, run}
        :error -> :error
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.RunStore
  def list_runs do
    Agent.get(__MODULE__, fn state ->
      state.runs
      |> Map.values()
      |> Enum.sort_by(&{&1.inserted_at, &1.run_id})
    end)
  end

  def fetch_run!(run_id) do
    Agent.get(__MODULE__, fn state -> Map.fetch!(state.runs, run_id) end)
  end

  @impl Jido.Integration.V2.ControlPlane.AttemptStore
  def fetch_attempt(attempt_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.attempts, attempt_id) do
        {:ok, attempt} -> {:ok, attempt}
        :error -> :error
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.AttemptStore
  def list_attempts(run_id) do
    Agent.get(__MODULE__, fn state ->
      state.attempts
      |> Map.values()
      |> Enum.filter(&(&1.run_id == run_id))
      |> Enum.sort_by(&{&1.attempt, &1.attempt_id})
    end)
  end

  def fetch_attempt!(attempt_id) do
    Agent.get(__MODULE__, fn state -> Map.fetch!(state.attempts, attempt_id) end)
  end

  @impl Jido.Integration.V2.ControlPlane.EventStore
  def list_events(run_id) do
    Agent.get(__MODULE__, fn state -> Map.get(state.events, run_id, []) end)
  end

  @impl Jido.Integration.V2.ControlPlane.ArtifactStore
  def put_artifact_ref(%ArtifactRef{} = artifact_ref) do
    Agent.update(__MODULE__, fn state ->
      state
      |> put_in([:artifacts, artifact_ref.artifact_id], artifact_ref)
      |> update_in([:run_artifacts, artifact_ref.run_id], fn
        nil ->
          [artifact_ref]

        artifacts ->
          [artifact_ref | Enum.reject(artifacts, &(&1.artifact_id == artifact_ref.artifact_id))]
      end)
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.ArtifactStore
  def fetch_artifact_ref(artifact_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.artifacts, artifact_id) do
        {:ok, artifact_ref} -> {:ok, artifact_ref}
        :error -> :error
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.ArtifactStore
  def list_artifact_refs(run_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(:run_artifacts, %{})
      |> Map.get(run_id, [])
      |> Enum.reverse()
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.TargetStore
  def put_target_descriptor(%TargetDescriptor{} = descriptor) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:targets, descriptor.target_id], descriptor)
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.TargetStore
  def fetch_target_descriptor(target_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.targets, target_id) do
        {:ok, descriptor} -> {:ok, descriptor}
        :error -> :error
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.TargetStore
  def list_target_descriptors do
    Agent.get(__MODULE__, fn state ->
      state.targets
      |> Map.values()
      |> Enum.sort_by(& &1.target_id)
    end)
  end

  @impl ProfileRegistryStore
  def install_profile(profile, installed_scenarios, attrs) do
    case SimulationProfileRegistryEntry.install(profile, installed_scenarios, attrs) do
      {:ok, entry} ->
        Agent.get_and_update(__MODULE__, &install_profile_entry(&1, entry))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl ProfileRegistryStore
  def update_profile(profile, installed_scenarios, attrs) do
    case profile_id_from(profile) do
      nil ->
        {:error, :unknown_profile}

      profile_id ->
        Agent.get_and_update(__MODULE__, fn state ->
          update_profile_entry(state, profile_id, profile, installed_scenarios, attrs)
        end)
    end
  end

  @impl ProfileRegistryStore
  def remove_profile(profile_id, attrs) do
    Agent.get_and_update(__MODULE__, fn state ->
      remove_profile_entry(state, profile_id, attrs)
    end)
  end

  @impl ProfileRegistryStore
  def fetch_profile(profile_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.profile_registry_entries, profile_id) do
        {:ok, entry} -> {:ok, entry}
        :error -> :error
      end
    end)
  end

  @impl ProfileRegistryStore
  def select_profile(profile_id, environment_scope, owner_ref) do
    with {:ok, entry} <- fetch_profile(profile_id) do
      SimulationProfileRegistryEntry.select(entry, environment_scope, owner_ref)
    end
  end

  @impl ProfileRegistryStore
  def list_profiles(filters \\ %{}) do
    Agent.get(__MODULE__, fn state ->
      state.profile_registry_entries
      |> Map.values()
      |> filter_records(filters)
      |> Enum.sort_by(&{&1.audit_install_timestamp, &1.profile_id})
    end)
  end

  def events(run_id) do
    list_events(run_id)
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def reserve_dedupe(tenant_id, connector_id, trigger_id, dedupe_key, expires_at) do
    dedupe_scope = dedupe_scope(tenant_id, connector_id, trigger_id, dedupe_key)

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state.dedupe, dedupe_scope) do
        {:ok, _existing} ->
          {{:error, :duplicate}, state}

        :error ->
          {:ok, put_in(state, [:dedupe, dedupe_scope], expires_at)}
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def put_trigger(%TriggerRecord{} = trigger) do
    dedupe_scope =
      dedupe_scope(
        trigger.tenant_id,
        trigger.connector_id,
        trigger.trigger_id,
        trigger.dedupe_key
      )

    Agent.update(__MODULE__, fn state ->
      state = put_in(state, [:triggers, dedupe_scope], trigger)

      if is_nil(trigger.run_id) do
        state
      else
        update_in(state, [:run_triggers, trigger.run_id], fn
          nil ->
            [trigger]

          triggers ->
            [trigger | Enum.reject(triggers, &(&1.admission_id == trigger.admission_id))]
        end)
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key) do
    dedupe_scope = dedupe_scope(tenant_id, connector_id, trigger_id, dedupe_key)

    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.triggers, dedupe_scope) do
        {:ok, trigger} -> {:ok, trigger}
        :error -> :error
      end
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def list_run_triggers(run_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(:run_triggers, %{})
      |> Map.get(run_id, [])
      |> Enum.reverse()
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def put_checkpoint(%TriggerCheckpoint{} = checkpoint) do
    checkpoint_key =
      checkpoint_key(
        checkpoint.tenant_id,
        checkpoint.connector_id,
        checkpoint.trigger_id,
        checkpoint.partition_key
      )

    Agent.update(__MODULE__, fn state ->
      current = Map.get(state.checkpoints, checkpoint_key)

      next_checkpoint =
        case current do
          nil ->
            checkpoint

          %TriggerCheckpoint{} = current_checkpoint ->
            %{
              checkpoint
              | revision: current_checkpoint.revision + 1,
                updated_at: Contracts.now()
            }
        end

      put_in(state, [:checkpoints, checkpoint_key], next_checkpoint)
    end)
  end

  @impl Jido.Integration.V2.ControlPlane.IngressStore
  def fetch_checkpoint(tenant_id, connector_id, trigger_id, partition_key) do
    checkpoint_key = checkpoint_key(tenant_id, connector_id, trigger_id, partition_key)

    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.checkpoints, checkpoint_key) do
        {:ok, checkpoint} -> {:ok, checkpoint}
        :error -> :error
      end
    end)
  end

  def reset! do
    Agent.update(__MODULE__, fn _ ->
      %{
        runs: %{},
        attempts: %{},
        events: %{},
        artifacts: %{},
        run_artifacts: %{},
        claim_check_blobs: %{},
        claim_check_references: %{},
        targets: %{},
        profile_registry_entries: %{},
        triggers: %{},
        run_triggers: %{},
        checkpoints: %{},
        dedupe: %{}
      }
    end)
  end

  @impl ClaimCheckStore
  def stage_blob(payload_ref, encoded, metadata) when is_binary(encoded) and is_map(metadata) do
    Agent.update(__MODULE__, fn state ->
      blob_key = claim_check_blob_key(payload_ref)
      now = Contracts.now()

      blob =
        state
        |> Map.get(:claim_check_blobs, %{})
        |> Map.get(blob_key, %{
          payload_ref: payload_ref,
          encoded: encoded,
          metadata: metadata,
          status: :staged,
          staged_at: now,
          referenced_at: nil,
          deleted_at: nil
        })
        |> Map.merge(%{
          payload_ref: payload_ref,
          encoded: encoded,
          metadata: metadata,
          status: :staged,
          staged_at: now
        })

      put_in(state, [:claim_check_blobs, blob_key], blob)
    end)
  end

  @impl ClaimCheckStore
  def fetch_blob(payload_ref) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(:claim_check_blobs, %{})
      |> Map.get(claim_check_blob_key(payload_ref))
      |> case do
        %{encoded: encoded, status: status}
        when is_binary(encoded) and status != :deleted ->
          {:ok, encoded}

        _other ->
          :error
      end
    end)
  end

  @impl ClaimCheckStore
  def register_reference(payload_ref, attrs) when is_map(attrs) do
    Agent.update(__MODULE__, fn state ->
      put_claim_check_reference(state, payload_ref, attrs)
    end)
  end

  @impl ClaimCheckStore
  def fetch_blob_metadata(payload_ref) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(:claim_check_blobs, %{})
      |> Map.get(claim_check_blob_key(payload_ref))
      |> case do
        nil -> :error
        blob -> {:ok, Map.drop(blob, [:encoded])}
      end
    end)
  end

  @impl ClaimCheckStore
  def count_live_references(payload_ref) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(:claim_check_references, %{})
      |> Map.get(claim_check_blob_key(payload_ref), %{})
      |> map_size()
    end)
  end

  @impl ClaimCheckStore
  def sweep_staged_payloads(opts \\ []) do
    older_than_s = Keyword.get(opts, :older_than_s, 0)
    cutoff = DateTime.add(Contracts.now(), -older_than_s, :second)

    Agent.get_and_update(__MODULE__, fn state ->
      {next_blobs, deleted_count} =
        Enum.reduce(state.claim_check_blobs, {%{}, 0}, fn {blob_key, blob}, {acc, count} ->
          sweep_staged_payload_blob(state, blob_key, blob, cutoff, acc, count)
        end)

      result = {:ok, %{deleted_count: deleted_count}}
      {result, %{state | claim_check_blobs: next_blobs}}
    end)
  end

  @impl ClaimCheckStore
  def garbage_collect(opts \\ []) do
    older_than_s = Keyword.get(opts, :older_than_s, 0)
    cutoff = DateTime.add(Contracts.now(), -older_than_s, :second)

    Agent.get_and_update(__MODULE__, fn state ->
      {next_blobs, deleted_count, skipped_live_reference_count} =
        Enum.reduce(state.claim_check_blobs, {%{}, 0, 0}, fn {blob_key, blob},
                                                             {acc, deleted, skipped} ->
          live_refs = live_reference_count(state, blob_key)

          handle_blob_gc(blob_key, blob, live_refs, cutoff, acc, deleted, skipped)
        end)

      result =
        {:ok,
         %{
           deleted_count: deleted_count,
           skipped_live_reference_count: skipped_live_reference_count
         }}

      {result, %{state | claim_check_blobs: next_blobs}}
    end)
  end

  defp attempt_id(%Attempt{attempt_id: attempt_id}), do: attempt_id
  defp attempt_id(nil), do: nil

  defp attempt_number(%Attempt{attempt: attempt}), do: attempt
  defp attempt_number(nil), do: nil

  defp orphaned_staged_payload?(state, blob_key, blob, cutoff) do
    blob.status == :staged and older_than_cutoff?(blob.staged_at, cutoff) and
      live_reference_count(state, blob_key) == 0
  end

  defp sweep_staged_payload_blob(state, blob_key, blob, cutoff, acc, count) do
    if orphaned_staged_payload?(state, blob_key, blob, cutoff) do
      ClaimCheckTelemetry.orphaned_staged_payload(
        blob.payload_ref,
        blob.metadata,
        source_component: :run_ledger,
        store_backend: :run_ledger
      )

      {acc, count + 1}
    else
      {Map.put(acc, blob_key, blob), count}
    end
  end

  defp handle_blob_gc(blob_key, blob, live_refs, cutoff, acc, deleted, skipped) do
    cond do
      live_refs > 0 ->
        ClaimCheckTelemetry.blob_gc_skipped_live_reference(
          blob.payload_ref,
          blob.metadata,
          source_component: :run_ledger,
          store_backend: :run_ledger,
          live_reference_count: live_refs
        )

        {Map.put(acc, blob_key, blob), deleted, skipped + 1}

      older_than_cutoff?(blob.staged_at, cutoff) ->
        ClaimCheckTelemetry.blob_gc_deleted(
          blob.payload_ref,
          blob.metadata,
          source_component: :run_ledger,
          store_backend: :run_ledger
        )

        {acc, deleted + 1, skipped}

      true ->
        {Map.put(acc, blob_key, blob), deleted, skipped}
    end
  end

  defp older_than_cutoff?(%DateTime{} = value, %DateTime{} = cutoff) do
    DateTime.compare(value, cutoff) != :gt
  end

  defp install_profile_entry(state, entry) do
    case Map.fetch(state.profile_registry_entries, entry.profile_id) do
      {:ok, existing} when existing.profile_version != entry.profile_version ->
        {{:error, :concurrent_install_same_id_different_version}, state}

      {:ok, existing} ->
        {{:ok, existing}, state}

      :error ->
        {{:ok, entry}, put_in(state, [:profile_registry_entries, entry.profile_id], entry)}
    end
  end

  defp update_profile_entry(state, profile_id, profile, installed_scenarios, attrs) do
    case Map.fetch(state.profile_registry_entries, profile_id) do
      {:ok, current} ->
        current
        |> SimulationProfileRegistryEntry.update(profile, installed_scenarios, attrs)
        |> persist_updated_profile_entry(state)

      :error ->
        {{:error, :unknown_profile}, state}
    end
  end

  defp persist_updated_profile_entry({:ok, updated}, state) do
    {{:ok, updated}, put_in(state, [:profile_registry_entries, updated.profile_id], updated)}
  end

  defp persist_updated_profile_entry({:error, reason}, state), do: {{:error, reason}, state}

  defp remove_profile_entry(state, profile_id, attrs) do
    case Map.fetch(state.profile_registry_entries, profile_id) do
      {:ok, current} ->
        current
        |> remove_registry_entry(attrs)
        |> persist_removed_profile_entry(state, profile_id)

      :error ->
        {{:error, :unknown_profile}, state}
    end
  end

  defp persist_removed_profile_entry({:ok, removed, reply}, state, profile_id) do
    {reply, put_in(state, [:profile_registry_entries, profile_id], removed)}
  end

  defp persist_removed_profile_entry({:error, reason}, state, _profile_id) do
    {{:error, reason}, state}
  end

  defp remove_registry_entry(%SimulationProfileRegistryEntry{} = current, attrs) do
    removed = SimulationProfileRegistryEntry.remove!(current, attrs)

    reply =
      case removed.cleanup_status do
        :cleanup_failed -> {:error, :cleanup_failure}
        :removed -> {:ok, removed}
      end

    {:ok, removed, reply}
  rescue
    error in ArgumentError ->
      {:error, registry_failure_reason(error)}
  end

  defp registry_failure_reason(%ArgumentError{message: message}) do
    if String.contains?(message, "cleanup"), do: :cleanup_failure, else: :invalid_registry_entry
  end

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} -> Map.get(record, key) == value end)
    end)
  end

  defp profile_id_from(%ServiceSimulationProfile{} = profile), do: profile.profile_id

  defp profile_id_from(profile) when is_map(profile) or is_list(profile) do
    profile
    |> Map.new()
    |> Contracts.get(:profile_id)
  end

  defp profile_id_from(_profile), do: nil

  defp target_id(%Attempt{target_id: target_id}), do: target_id
  defp target_id(nil), do: nil

  defp persist_events(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, acc_state} ->
      event = sanitize_event(event)
      run_events = Map.get(acc_state.events, event.run_id, [])

      case Enum.find(run_events, &same_position?(&1, event)) do
        nil ->
          next_state =
            acc_state
            |> put_in([:events, event.run_id], run_events ++ [event])
            |> maybe_put_event_claim_check_reference(event)

          {:cont, {:ok, next_state}}

        ^event ->
          {:cont, {:ok, acc_state}}

        _existing ->
          {:halt, {:error, :event_conflict}}
      end
    end)
  end

  defp sanitize_run(run) do
    %{run | input: Redaction.redact(run.input), result: Redaction.redact(run.result)}
  end

  defp sanitize_attempt(attempt) do
    %{attempt | output: Redaction.redact(attempt.output)}
  end

  defp sanitize_event(event) do
    %{event | payload: Redaction.redact(event.payload)}
  end

  defp maybe_put_run_claim_check_reference(state, _run, _field, nil), do: state

  defp maybe_put_run_claim_check_reference(state, run, field, payload_ref) do
    put_claim_check_reference(state, payload_ref, %{
      ledger_kind: :run,
      ledger_id: run.run_id,
      payload_field: field,
      run_id: run.run_id
    })
  end

  defp maybe_put_attempt_claim_check_reference(state, _attempt, _field, nil), do: state

  defp maybe_put_attempt_claim_check_reference(state, attempt, field, payload_ref) do
    put_claim_check_reference(state, payload_ref, %{
      ledger_kind: :attempt,
      ledger_id: attempt.attempt_id,
      payload_field: field,
      run_id: attempt.run_id,
      attempt_id: attempt.attempt_id
    })
  end

  defp maybe_put_event_claim_check_reference(state, %Event{payload_ref: nil}), do: state

  defp maybe_put_event_claim_check_reference(state, %Event{} = event) do
    put_claim_check_reference(state, event.payload_ref, %{
      ledger_kind: :event,
      ledger_id: event.event_id,
      payload_field: :payload,
      run_id: event.run_id,
      attempt_id: event.attempt_id,
      event_id: event.event_id,
      trace_id: Contracts.get(event.trace, :trace_id)
    })
  end

  defp put_claim_check_reference(state, payload_ref, attrs) do
    blob_key = claim_check_blob_key(payload_ref)
    reference_key = claim_check_reference_key(attrs)
    now = Contracts.now()

    state
    |> update_in([:claim_check_references, blob_key], fn
      nil -> %{reference_key => Map.put(attrs, :inserted_at, now)}
      references -> Map.put_new(references, reference_key, Map.put(attrs, :inserted_at, now))
    end)
    |> update_in([:claim_check_blobs, blob_key], fn
      nil ->
        %{
          payload_ref: payload_ref,
          encoded: nil,
          metadata: %{},
          status: :referenced,
          staged_at: now,
          referenced_at: now,
          deleted_at: nil
        }

      blob ->
        %{blob | status: :referenced, referenced_at: blob.referenced_at || now, deleted_at: nil}
    end)
  end

  defp claim_check_blob_key(payload_ref), do: {payload_ref.store, payload_ref.key}

  defp claim_check_reference_key(attrs) do
    {
      attrs[:ledger_kind] || attrs["ledger_kind"],
      attrs[:ledger_id] || attrs["ledger_id"],
      attrs[:payload_field] || attrs["payload_field"]
    }
  end

  defp live_reference_count(state, blob_key) do
    state
    |> Map.get(:claim_check_references, %{})
    |> Map.get(blob_key, %{})
    |> map_size()
  end

  defp same_position?(left, right) do
    left.run_id == right.run_id and left.attempt_id == right.attempt_id and left.seq == right.seq
  end

  defp checkpoint_key(tenant_id, connector_id, trigger_id, partition_key) do
    {tenant_id, connector_id, trigger_id, partition_key}
  end

  defp dedupe_scope(tenant_id, connector_id, trigger_id, dedupe_key) do
    {tenant_id, connector_id, trigger_id, dedupe_key}
  end
end
