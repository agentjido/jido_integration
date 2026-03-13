defmodule Jido.Integration.Auth.InstallSessionStore.Disk do
  @moduledoc """
  File-backed install-session store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Auth.InstallSession
  alias Jido.Integration.Runtime.Persistence

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
  def init(opts) do
    path = Persistence.default_path("install-sessions", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:put, %InstallSession{} = session}, _from, state) do
    entries = Map.put(state.entries, session.state_token, session)
    :ok = Persistence.persist(state.path, entries)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_call({:fetch, state_token, opts}, _from, state) do
    result =
      case Map.get(state.entries, state_token) do
        %InstallSession{} = session -> validate_fetch(session, opts)
        nil -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:consume, state_token}, _from, state) do
    case Map.get(state.entries, state_token) do
      %InstallSession{} = session ->
        case validate_consume(session) do
          {:ok, consumed} ->
            entries = Map.put(state.entries, state_token, consumed)
            :ok = Persistence.persist(state.path, entries)
            {:reply, {:ok, consumed}, %{state | entries: entries}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:delete, state_token}, _from, state) do
    if Map.has_key?(state.entries, state_token) do
      entries = Map.delete(state.entries, state_token)
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
