defmodule Jido.Session.Store do
  @moduledoc false

  use GenServer

  alias Jido.Session.Runtime.{Run, Session}

  @type state :: %{
          sessions: %{optional(String.t()) => Session.t()},
          runs: %{optional(String.t()) => Run.t()}
        }

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec put_session(Session.t()) :: :ok | {:error, term()}
  def put_session(%Session{} = session), do: GenServer.call(__MODULE__, {:put_session, session})

  @spec fetch_session(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def fetch_session(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:fetch_session, session_id})
  end

  @spec delete_session(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def delete_session(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:delete_session, session_id})
  end

  @spec put_run(Run.t()) :: :ok
  def put_run(%Run{} = run), do: GenServer.call(__MODULE__, {:put_run, run})

  @spec fetch_run(String.t()) :: {:ok, Run.t()} | {:error, :not_found}
  def fetch_run(run_id) when is_binary(run_id),
    do: GenServer.call(__MODULE__, {:fetch_run, run_id})

  @impl true
  def init(_opts) do
    {:ok, %{sessions: %{}, runs: %{}}}
  end

  @impl true
  def handle_call({:put_session, %Session{} = session}, _from, state) do
    {:reply, :ok, put_in(state, [:sessions, session.session_id], session)}
  end

  def handle_call({:fetch_session, session_id}, _from, state) do
    reply =
      case Map.fetch(state.sessions, session_id) do
        {:ok, %Session{} = session} -> {:ok, session}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:delete_session, session_id}, _from, state) do
    case Map.pop(state.sessions, session_id) do
      {nil, _sessions} ->
        {:reply, {:error, :not_found}, state}

      {%Session{} = session, sessions} ->
        {:reply, {:ok, session}, %{state | sessions: sessions}}
    end
  end

  def handle_call({:put_run, %Run{} = run}, _from, state) do
    {:reply, :ok, put_in(state, [:runs, run.run_id], run)}
  end

  def handle_call({:fetch_run, run_id}, _from, state) do
    reply =
      case Map.fetch(state.runs, run_id) do
        {:ok, %Run{} = run} -> {:ok, run}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end
end
