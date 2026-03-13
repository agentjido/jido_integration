defmodule Jido.Integration.Dispatch.RunStore.Disk do
  @moduledoc """
  File-backed run-record store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Dispatch.Run
  alias Jido.Integration.Runtime.Persistence

  @behaviour Jido.Integration.Dispatch.RunStore

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Dispatch.RunStore
  def put(server, %Run{} = run), do: GenServer.call(server, {:put, run})

  @impl Jido.Integration.Dispatch.RunStore
  def fetch(server, run_id), do: GenServer.call(server, {:fetch, run_id})

  @impl Jido.Integration.Dispatch.RunStore
  def fetch_by_idempotency(server, idempotency_key),
    do: GenServer.call(server, {:fetch_by_idempotency, idempotency_key})

  @impl Jido.Integration.Dispatch.RunStore
  def list(server), do: GenServer.call(server, :list)

  @impl Jido.Integration.Dispatch.RunStore
  def list(server, opts), do: GenServer.call(server, {:list, opts})

  @impl Jido.Integration.Dispatch.RunStore
  def delete(server, run_id), do: GenServer.call(server, {:delete, run_id})

  @impl GenServer
  def init(opts) do
    path = Persistence.default_path("runs", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:put, %Run{} = run}, _from, state) do
    case conflicting_run_id(state.entries, run) do
      nil ->
        entries = Map.put(state.entries, run.run_id, run)
        :ok = Persistence.persist(state.path, entries)
        {:reply, :ok, %{state | entries: entries}}

      existing_run_id ->
        {:reply, {:error, {:idempotency_conflict, existing_run_id}}, state}
    end
  end

  @impl GenServer
  def handle_call({:fetch, run_id}, _from, state) do
    result =
      case Map.get(state.entries, run_id) do
        %Run{} = run -> {:ok, run}
        nil -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.entries), state}
  end

  @impl GenServer
  def handle_call({:fetch_by_idempotency, idempotency_key}, _from, state) do
    result =
      state.entries
      |> Map.values()
      |> Enum.find(&(&1.idempotency_key == idempotency_key))
      |> case do
        %Run{} = run -> {:ok, run}
        nil -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:list, opts}, _from, state) do
    {:reply, state.entries |> Map.values() |> filter_runs(opts), state}
  end

  @impl GenServer
  def handle_call({:delete, run_id}, _from, state) do
    if Map.has_key?(state.entries, run_id) do
      entries = Map.delete(state.entries, run_id)
      :ok = Persistence.persist(state.path, entries)
      {:reply, :ok, %{state | entries: entries}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  defp conflicting_run_id(entries, %Run{} = run) do
    entries
    |> Map.values()
    |> Enum.find(fn existing ->
      existing.idempotency_key == run.idempotency_key and existing.run_id != run.run_id
    end)
    |> case do
      %Run{run_id: existing_run_id} -> existing_run_id
      nil -> nil
    end
  end

  defp filter_runs(runs, opts) do
    Enum.filter(runs, fn run ->
      matches_filter?(run.status, Keyword.get(opts, :status), Keyword.get(opts, :statuses)) and
        matches_value?(run.tenant_id, Keyword.get(opts, :tenant_id)) and
        matches_value?(run.connector_id, Keyword.get(opts, :connector_id)) and
        matches_value?(run.trigger_id, Keyword.get(opts, :trigger_id)) and
        matches_value?(run.callback_id, Keyword.get(opts, :callback_id)) and
        matches_value?(run.dispatch_id, Keyword.get(opts, :dispatch_id)) and
        matches_value?(run.idempotency_key, Keyword.get(opts, :idempotency_key))
    end)
  end

  defp matches_filter?(_value, nil, nil), do: true
  defp matches_filter?(value, expected, nil), do: value == expected
  defp matches_filter?(value, nil, expected_values), do: value in expected_values

  defp matches_filter?(value, expected, expected_values),
    do: value == expected and value in expected_values

  defp matches_value?(_value, nil), do: true
  defp matches_value?(value, expected), do: value == expected
end
