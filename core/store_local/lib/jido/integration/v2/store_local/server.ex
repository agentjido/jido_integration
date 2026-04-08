defmodule Jido.Integration.V2.StoreLocal.Server do
  @moduledoc false

  use GenServer

  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Application, as: StoreLocalApplication
  alias Jido.Integration.V2.StoreLocal.State

  @type mutation_fun :: (State.t() -> {term(), State.t()})
  @type read_fun :: (State.t() -> term())

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: State.t()
  def snapshot do
    call!(:snapshot)
  end

  @spec read(read_fun()) :: term()
  def read(fun) when is_function(fun, 1) do
    call!({:read, fun})
  end

  @spec mutate(mutation_fun()) :: term()
  def mutate(fun) when is_function(fun, 1) do
    call!({:mutate, fun}, :infinity)
  end

  @spec replace_state(State.t()) :: :ok
  def replace_state(%State{} = state) do
    call!({:replace_state, state}, :infinity)
  end

  @spec reset!() :: :ok
  def reset! do
    replace_state(State.new())
  end

  @spec storage_path() :: String.t()
  def storage_path do
    call!(:storage_path)
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
    File.mkdir_p!(Path.dirname(path))
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

  defp ensure_started! do
    case Process.whereis(__MODULE__) do
      nil ->
        ensure_server_started!()

      _pid ->
        :ok
    end
  end

  defp ensure_server_started! do
    case Process.whereis(StoreLocalApplication) do
      nil -> start_store_local_application!()
      _pid -> restart_store_local_server!()
    end

    wait_for_process!(__MODULE__, "store_local server")
  end

  defp start_store_local_application! do
    case StoreLocalApplication.start(:normal, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise("store_local application did not start: #{inspect(reason)}")
    end
  end

  defp restart_store_local_server! do
    case Supervisor.restart_child(StoreLocalApplication, __MODULE__) do
      {:ok, _child} -> :ok
      {:ok, _child, _info} -> :ok
      {:error, :already_present} -> :ok
      {:error, :running} -> :ok
      {:error, reason} -> raise("store_local server did not restart: #{inspect(reason)}")
    end
  end

  defp call!(message, timeout \\ 5_000, attempts \\ 2)

  defp call!(message, timeout, attempts) do
    ensure_started!()

    GenServer.call(__MODULE__, message, timeout)
  catch
    :exit, {:noproc, _reason} ->
      retry_call!(message, timeout, attempts)

    :exit, {{:shutdown, _reason}, _stack} ->
      retry_call!(message, timeout, attempts)

    :exit, {:shutdown, _reason} ->
      retry_call!(message, timeout, attempts)
  end

  defp retry_call!(_message, _timeout, 1) do
    raise "store_local server call failed after restart retry"
  end

  defp retry_call!(message, timeout, attempts) do
    Process.sleep(50)
    call!(message, timeout, attempts - 1)
  end

  defp wait_for_process!(name, label, attempts \\ 40)

  defp wait_for_process!(_name, label, 0), do: raise("#{label} did not start")

  defp wait_for_process!(name, label, attempts) do
    case Process.whereis(name) do
      nil ->
        Process.sleep(50)
        wait_for_process!(name, label, attempts - 1)

      _pid ->
        :ok
    end
  end
end
