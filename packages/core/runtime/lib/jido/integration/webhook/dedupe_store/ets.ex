defmodule Jido.Integration.Webhook.DedupeStore.ETS do
  @moduledoc """
  ETS-backed dedupe store for explicit local development mode.
  """

  use GenServer

  @behaviour Jido.Integration.Webhook.DedupeStore

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Webhook.DedupeStore
  def put(server, key, expires_at_ms), do: GenServer.call(server, {:put, key, expires_at_ms})

  @impl Jido.Integration.Webhook.DedupeStore
  def fetch(server, key, opts \\ []), do: GenServer.call(server, {:fetch, key, opts})

  @impl Jido.Integration.Webhook.DedupeStore
  def delete(server, key), do: GenServer.call(server, {:delete, key})

  @impl Jido.Integration.Webhook.DedupeStore
  def list(server), do: GenServer.call(server, :list)

  @impl GenServer
  def init(_opts) do
    {:ok, %{table: :ets.new(:webhook_dedupe_store, [:set, :private])}}
  end

  @impl GenServer
  def handle_call({:put, key, expires_at_ms}, _from, state) do
    :ets.insert(state.table, {key, %{key: key, expires_at_ms: expires_at_ms}})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:fetch, key, opts}, _from, state) do
    result =
      case :ets.lookup(state.table, key) do
        [{^key, entry}] -> validate_fetch(entry, opts)
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, _entry}] ->
        :ets.delete(state.table, key)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, state.table |> :ets.tab2list() |> Enum.map(&elem(&1, 1)), state}
  end

  defp validate_fetch(entry, opts) do
    if Keyword.get(opts, :allow_expired, false) or
         entry.expires_at_ms > System.system_time(:millisecond) do
      {:ok, entry}
    else
      {:error, :expired}
    end
  end
end
