defmodule Jido.Integration.V2.StoreLocal.Server do
  @moduledoc false

  use GenServer

  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.State

  @type mutation_fun :: (State.t() -> {term(), State.t()})
  @type read_fun :: (State.t() -> term())

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: State.t()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec read(read_fun()) :: term()
  def read(fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:read, fun})
  end

  @spec mutate(mutation_fun()) :: term()
  def mutate(fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:mutate, fun}, :infinity)
  end

  @spec replace_state(State.t()) :: :ok
  def replace_state(%State{} = state) do
    GenServer.call(__MODULE__, {:replace_state, state}, :infinity)
  end

  @spec reset!() :: :ok
  def reset! do
    replace_state(State.new())
  end

  @spec storage_path() :: String.t()
  def storage_path do
    GenServer.call(__MODULE__, :storage_path)
  end

  @impl true
  def init(_opts) do
    path = StoreLocal.storage_path()
    File.mkdir_p!(Path.dirname(path))
    {:ok, %{path: path, state: load_state(path)}}
  end

  @impl true
  def handle_call(:snapshot, _from, %{state: state} = server_state) do
    {:reply, state, server_state}
  end

  def handle_call({:read, fun}, _from, %{state: state} = server_state) do
    {:reply, fun.(state), server_state}
  end

  def handle_call({:mutate, fun}, _from, %{state: state} = server_state) do
    {reply, next_state} = fun.(state)
    {:reply, reply, maybe_persist(server_state, next_state)}
  end

  def handle_call({:replace_state, %State{} = next_state}, _from, server_state) do
    {:reply, :ok, maybe_persist(server_state, next_state)}
  end

  def handle_call(:storage_path, _from, %{path: path} = server_state) do
    {:reply, path, server_state}
  end

  defp maybe_persist(%{state: state} = server_state, %State{} = next_state)
       when next_state == state do
    server_state
  end

  defp maybe_persist(%{path: path} = server_state, %State{} = next_state) do
    persist_state!(path, next_state)
    %{server_state | state: next_state}
  end

  defp load_state(path) do
    case File.read(path) do
      {:ok, binary} ->
        :erlang.binary_to_term(binary, [:safe])

      {:error, :enoent} ->
        State.new()

      {:error, reason} ->
        raise "unable to load store_local state from #{path}: #{inspect(reason)}"
    end
  end

  defp persist_state!(path, %State{} = state) do
    tmp_path = "#{path}.tmp"
    File.write!(tmp_path, :erlang.term_to_binary(state), [:binary])

    case File.rename(tmp_path, path) do
      :ok ->
        :ok

      {:error, _reason} ->
        File.rm(path)

        case File.rename(tmp_path, path) do
          :ok ->
            :ok

          {:error, reason} ->
            raise "unable to persist store_local state to #{path}: #{inspect(reason)}"
        end
    end
  end
end
