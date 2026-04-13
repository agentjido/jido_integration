defmodule Jido.Integration.V2.StoreLocal.EventStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.EventStore

  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def next_seq(run_id, attempt_id) do
    Storage.read(&State.next_seq(&1, run_id, attempt_id))
  end

  @impl true
  def append_events(events, opts \\ [])

  def append_events([], _opts), do: :ok

  def append_events(events, opts) do
    Storage.mutate(fn state ->
      sanitized_events = Enum.map(events, &ensure_event!/1)
      State.append_events(state, sanitized_events, opts)
    end)
  end

  @impl true
  def list_events(run_id) do
    Storage.read(&State.list_events(&1, run_id))
  end

  def reset! do
    Storage.mutate(&State.reset_events/1)
  end

  defp ensure_event!(%Event{} = event), do: event
end
