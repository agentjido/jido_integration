defmodule Jido.Integration.Auth.InstallSessionStore.ETS do
  @moduledoc """
  ETS-backed install-session store for explicit local development mode.
  """

  use GenServer

  alias Jido.Integration.Auth.InstallSession

  @behaviour Jido.Integration.Auth.InstallSessionStore

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Auth.InstallSessionStore
  def put(server, %InstallSession{} = session), do: GenServer.call(server, {:put, session})

  @impl Jido.Integration.Auth.InstallSessionStore
  def fetch(server, state_token, opts \\ []),
    do: GenServer.call(server, {:fetch, state_token, opts})

  @impl Jido.Integration.Auth.InstallSessionStore
  def consume(server, state_token), do: GenServer.call(server, {:consume, state_token})

  @impl Jido.Integration.Auth.InstallSessionStore
  def delete(server, state_token), do: GenServer.call(server, {:delete, state_token})

  @impl Jido.Integration.Auth.InstallSessionStore
  def list(server), do: GenServer.call(server, :list)

  @impl GenServer
  def init(_opts) do
    {:ok, %{table: :ets.new(:auth_install_session_store, [:set, :private])}}
  end

  @impl GenServer
  def handle_call({:put, %InstallSession{} = session}, _from, state) do
    :ets.insert(state.table, {session.state_token, session})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:fetch, state_token, opts}, _from, state) do
    result =
      case :ets.lookup(state.table, state_token) do
        [{^state_token, %InstallSession{} = session}] -> validate_fetch(session, opts)
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:consume, state_token}, _from, state) do
    case :ets.lookup(state.table, state_token) do
      [{^state_token, %InstallSession{} = session}] ->
        case validate_consume(session) do
          {:ok, consumed} ->
            :ets.insert(state.table, {state_token, consumed})
            {:reply, {:ok, consumed}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:delete, state_token}, _from, state) do
    case :ets.lookup(state.table, state_token) do
      [{^state_token, _session}] ->
        :ets.delete(state.table, state_token)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, state.table |> :ets.tab2list() |> Enum.map(&elem(&1, 1)), state}
  end

  defp validate_fetch(%InstallSession{} = session, opts) do
    if Keyword.get(opts, :allow_expired, false) or not InstallSession.expired?(session) do
      {:ok, session}
    else
      {:error, :expired}
    end
  end

  defp validate_consume(%InstallSession{} = session) do
    cond do
      InstallSession.consumed?(session) ->
        {:error, :already_consumed}

      InstallSession.expired?(session) ->
        {:error, :expired}

      true ->
        {:ok, InstallSession.consume(session)}
    end
  end
end
