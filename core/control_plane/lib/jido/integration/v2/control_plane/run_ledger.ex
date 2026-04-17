defmodule Jido.Integration.V2.ControlPlane.RunLedger do
  @moduledoc false

  use Agent

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @behaviour Jido.Integration.V2.ControlPlane.RunStore
  @behaviour Jido.Integration.V2.ControlPlane.AttemptStore
  @behaviour Jido.Integration.V2.ControlPlane.EventStore
  @behaviour Jido.Integration.V2.ControlPlane.ArtifactStore
  @behaviour Jido.Integration.V2.ControlPlane.TargetStore
  @behaviour Jido.Integration.V2.ControlPlane.IngressStore

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          runs: %{},
          attempts: %{},
          events: %{},
          artifacts: %{},
          run_artifacts: %{},
          targets: %{},
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
    Agent.update(__MODULE__, fn state -> put_in(state, [:runs, run.run_id], sanitize_run(run)) end)
  end

  @impl Jido.Integration.V2.ControlPlane.AttemptStore
  def put_attempt(attempt) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:attempts, attempt.attempt_id], sanitize_attempt(attempt))
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
        targets: %{},
        triggers: %{},
        run_triggers: %{},
        checkpoints: %{},
        dedupe: %{}
      }
    end)
  end

  defp attempt_id(%Attempt{attempt_id: attempt_id}), do: attempt_id
  defp attempt_id(nil), do: nil

  defp attempt_number(%Attempt{attempt: attempt}), do: attempt
  defp attempt_number(nil), do: nil

  defp target_id(%Attempt{target_id: target_id}), do: target_id
  defp target_id(nil), do: nil

  defp persist_events(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, acc_state} ->
      event = sanitize_event(event)
      run_events = Map.get(acc_state.events, event.run_id, [])

      case Enum.find(run_events, &same_position?(&1, event)) do
        nil ->
          {:cont, {:ok, put_in(acc_state, [:events, event.run_id], run_events ++ [event])}}

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
