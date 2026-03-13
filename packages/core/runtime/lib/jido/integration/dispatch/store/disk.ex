defmodule Jido.Integration.Dispatch.Store.Disk do
  @moduledoc """
  File-backed dispatch-record store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Dispatch.Record
  alias Jido.Integration.Runtime.Persistence

  @behaviour Jido.Integration.Dispatch.Store

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Dispatch.Store
  def put(server, %Record{} = record), do: GenServer.call(server, {:put, record})

  @impl Jido.Integration.Dispatch.Store
  def fetch(server, dispatch_id), do: GenServer.call(server, {:fetch, dispatch_id})

  @impl Jido.Integration.Dispatch.Store
  def list(server), do: GenServer.call(server, :list)

  @impl Jido.Integration.Dispatch.Store
  def list(server, opts), do: GenServer.call(server, {:list, opts})

  @impl Jido.Integration.Dispatch.Store
  def delete(server, dispatch_id), do: GenServer.call(server, {:delete, dispatch_id})

  @impl GenServer
  def init(opts) do
    path = Persistence.default_path("dispatches", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:put, %Record{} = record}, _from, state) do
    entries = Map.put(state.entries, record.dispatch_id, record)
    :ok = Persistence.persist(state.path, entries)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_call({:fetch, dispatch_id}, _from, state) do
    result =
      case Map.get(state.entries, dispatch_id) do
        %Record{} = record -> {:ok, record}
        nil -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.entries), state}
  end

  @impl GenServer
  def handle_call({:list, opts}, _from, state) do
    {:reply, state.entries |> Map.values() |> filter_records(opts), state}
  end

  @impl GenServer
  def handle_call({:delete, dispatch_id}, _from, state) do
    if Map.has_key?(state.entries, dispatch_id) do
      entries = Map.delete(state.entries, dispatch_id)
      :ok = Persistence.persist(state.path, entries)
      {:reply, :ok, %{state | entries: entries}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  defp filter_records(records, opts) do
    Enum.filter(records, fn record ->
      matches_filter?(record.status, Keyword.get(opts, :status), Keyword.get(opts, :statuses)) and
        matches_value?(record.tenant_id, Keyword.get(opts, :tenant_id)) and
        matches_value?(record.connector_id, Keyword.get(opts, :connector_id)) and
        matches_value?(record.trigger_id, Keyword.get(opts, :trigger_id)) and
        matches_value?(record.workflow_selector, Keyword.get(opts, :workflow_selector)) and
        matches_value?(record.idempotency_key, Keyword.get(opts, :idempotency_key)) and
        matches_value?(record.dispatch_id, Keyword.get(opts, :dispatch_id)) and
        matches_value?(record.run_id, Keyword.get(opts, :run_id))
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
