defmodule Jido.Integration.V2.Auth.RuntimeConfig do
  @moduledoc """
  Supervised runtime dependency owner for auth handlers.
  """

  use GenServer

  @name __MODULE__
  @keys [
    :refresh_handler,
    :external_secret_resolver,
    :keyring,
    :runtime_env,
    :managed_account_store,
    :credential_materializers
  ]
  @empty_state %{
    refresh_handler: nil,
    external_secret_resolver: nil,
    keyring: nil,
    runtime_env: nil,
    managed_account_store: nil,
    credential_materializers: %{}
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, @empty_state, name: @name)
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
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state, state}

  def handle_call({:put, key, value}, _from, state) when key in @keys do
    {:reply, :ok, Map.put(state, key, value)}
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, @empty_state}
end
