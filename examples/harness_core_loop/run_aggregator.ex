defmodule Jido.Integration.Examples.HarnessCore.RunAggregator do
  @moduledoc """
  Run aggregator — collects run events, deduplicates, and determines terminal state.

  Deduplicates events by `(run_id, attempt_id, seq)`. Tracks run state
  through the lifecycle: `pending -> running -> succeeded | failed | rejected`.

  ## Usage

      {:ok, agg} = RunAggregator.start_link()
      :ok = RunAggregator.append_event(agg, event)
      %{state: :succeeded, events: [...]} = RunAggregator.get_run(agg, run_id)
  """

  use Agent

  alias Jido.Integration.Examples.HarnessCore.RunEvent

  @type run_state :: :pending | :running | :succeeded | :failed | :rejected

  @type run :: %{
          state: run_state(),
          events: [RunEvent.t()],
          seen_keys: MapSet.t()
        }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Append a run event. Returns `:ok` if accepted, `:duplicate` if already seen.
  """
  @spec append_event(GenServer.server(), RunEvent.t()) :: :ok | :duplicate
  def append_event(server, %RunEvent{} = event) do
    key = RunEvent.dedup_key(event)

    Agent.get_and_update(server, fn runs ->
      run =
        Map.get(runs, event.run_id, %{
          state: :pending,
          events: [],
          seen_keys: MapSet.new()
        })

      if MapSet.member?(run.seen_keys, key) do
        {:duplicate, runs}
      else
        new_run = %{
          state: next_state(run.state, event.event_type),
          events: run.events ++ [event],
          seen_keys: MapSet.put(run.seen_keys, key)
        }

        {:ok, Map.put(runs, event.run_id, new_run)}
      end
    end)
  end

  @doc "Get the current state and events for a run."
  @spec get_run(GenServer.server(), String.t()) :: run() | nil
  def get_run(server, run_id) do
    Agent.get(server, fn runs -> Map.get(runs, run_id) end)
  end

  @doc "Check if a run has reached terminal state."
  @spec terminal?(GenServer.server(), String.t()) :: boolean()
  def terminal?(server, run_id) do
    case get_run(server, run_id) do
      %{state: state} when state in [:succeeded, :failed, :rejected] -> true
      _ -> false
    end
  end

  @doc "List all tracked run IDs."
  @spec list_runs(GenServer.server()) :: [String.t()]
  def list_runs(server) do
    Agent.get(server, fn runs -> Map.keys(runs) end)
  end

  # State machine transitions

  defp next_state(:pending, :dispatch_started), do: :running
  defp next_state(:running, :dispatch_succeeded), do: :succeeded
  defp next_state(:running, :dispatch_failed), do: :failed
  defp next_state(:pending, :policy_denied), do: :rejected
  defp next_state(:pending, :target_rejected), do: :rejected
  defp next_state(current, _event_type), do: current
end
