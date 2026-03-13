defmodule Jido.Integration.Webhook.DedupeStore.Disk do
  @moduledoc """
  File-backed dedupe store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Runtime.Persistence

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
  def init(opts) do
    path = Persistence.default_path("dedupe", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:put, key, expires_at_ms}, _from, state) do
    entries = Map.put(state.entries, key, %{key: key, expires_at_ms: expires_at_ms})
    :ok = Persistence.persist(state.path, entries)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_call({:fetch, key, opts}, _from, state) do
    result =
      case Map.get(state.entries, key) do
        nil -> {:error, :not_found}
        entry -> validate_fetch(entry, opts)
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, key}, _from, state) do
    if Map.has_key?(state.entries, key) do
      entries = Map.delete(state.entries, key)
      :ok = Persistence.persist(state.path, entries)
      {:reply, :ok, %{state | entries: entries}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.entries), state}
  end

  defp validate_fetch(entry, opts) do
    if Keyword.get(opts, :allow_expired, false) or entry.expires_at_ms > Persistence.now_ms() do
      {:ok, entry}
    else
      {:error, :expired}
    end
  end
end
