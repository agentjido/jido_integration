defmodule Jido.Integration.Webhook.Dedupe do
  @moduledoc """
  Webhook deduplication store — prevents duplicate webhook processing.

  Uses ETS with TTL-based expiry. Entries are swept periodically to
  reclaim memory. Default TTL is 7 days (matching GitHub's replay window).
  """

  use GenServer

  alias Jido.Integration.Runtime.Persistence
  alias Jido.Integration.Webhook.DedupeStore

  @default_ttl_ms 7 * 24 * 60 * 60 * 1000
  @default_sweep_ms 60_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Check if a delivery_id has been seen."
  @spec seen?(GenServer.server(), String.t()) :: boolean()
  def seen?(server, delivery_id) do
    GenServer.call(server, {:seen?, delivery_id})
  end

  @doc "Mark a delivery_id as seen."
  @spec mark_seen(GenServer.server(), String.t(), keyword()) :: :ok
  def mark_seen(server, delivery_id, opts \\ []) do
    GenServer.call(server, {:mark_seen, delivery_id, opts})
  end

  # Server

  @impl GenServer
  def init(opts) do
    store_module = Keyword.get(opts, :store_module, DedupeStore.Disk)

    {:ok, store} =
      store_module.start_link(Keyword.put_new(Keyword.get(opts, :store_opts, []), :name, nil))

    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    sweep_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_ms)

    schedule_sweep(sweep_ms)

    {:ok, %{store_module: store_module, store: store, ttl_ms: ttl_ms, sweep_ms: sweep_ms}}
  end

  @impl GenServer
  def handle_call({:seen?, delivery_id}, _from, state) do
    result =
      case state.store_module.fetch(state.store, delivery_id) do
        {:ok, _entry} ->
          true

        {:error, :expired} ->
          :ok = state.store_module.delete(state.store, delivery_id)
          false

        {:error, :not_found} ->
          false
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:mark_seen, delivery_id, opts}, _from, state) do
    ttl_ms = Keyword.get(opts, :ttl_ms, state.ttl_ms)
    :ok = state.store_module.put(state.store, delivery_id, Persistence.now_ms() + ttl_ms)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    now = Persistence.now_ms()

    state.store_module.list(state.store)
    |> Enum.each(fn %{key: key, expires_at_ms: expires_at_ms} ->
      if expires_at_ms <= now do
        :ok = state.store_module.delete(state.store, key)
      end
    end)

    schedule_sweep(state.sweep_ms)
    {:noreply, state}
  end

  defp schedule_sweep(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end
end
