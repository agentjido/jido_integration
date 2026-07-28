defmodule Jido.Integration.V2.ControlPlane.RuntimeConfig do
  @moduledoc """
  Supervised runtime dependency owner for control-plane adapters.
  """

  use GenServer

  @name __MODULE__
  @keys [:self_hosted_endpoint_provider, :non_direct_runtime_adapter, :attempt_reconciliation]
  @empty_state %{
    self_hosted_endpoint_provider: nil,
    non_direct_runtime_adapter: nil,
    attempt_reconciliation: nil
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec current() :: map()
  def current do
    case Process.whereis(@name) do
      nil -> @empty_state
      _pid -> GenServer.call(@name, :current)
    end
  end

  @spec put(atom(), term()) :: :ok | {:error, :not_started}
  def put(key, value) when key in @keys do
    case Process.whereis(@name) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(@name, {:put, key, value})
    end
  end

  @spec reset() :: :ok | {:error, :not_started}
  def reset do
    case Process.whereis(@name) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(@name, :reset)
    end
  end

  @impl true
  def init(opts) when is_list(opts) do
    state =
      Enum.reduce(@keys, @empty_state, fn key, state ->
        case Keyword.fetch(opts, key) do
          {:ok, value} -> Map.put(state, key, value)
          :error -> state
        end
      end)

    {:ok, state}
  end

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state, state}

  def handle_call({:put, key, value}, _from, state) when key in @keys do
    {:reply, :ok, Map.put(state, key, value)}
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, @empty_state}
end
