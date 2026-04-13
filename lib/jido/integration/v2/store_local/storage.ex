defmodule Jido.Integration.V2.StoreLocal.Storage do
  @moduledoc false

  alias Jido.Integration.V2.StoreLocal.Server
  alias Jido.Integration.V2.StoreLocal.State

  @transaction_key {__MODULE__, :transaction_state}

  @type mutation_fun :: (State.t() -> {term(), State.t()})
  @type read_fun :: (State.t() -> term())

  @spec read(read_fun()) :: term()
  def read(fun) when is_function(fun, 1) do
    case Process.get(@transaction_key) do
      %State{} = state -> fun.(state)
      nil -> Server.read(fun)
    end
  end

  @spec mutate(mutation_fun()) :: term()
  def mutate(fun) when is_function(fun, 1) do
    case Process.get(@transaction_key) do
      %State{} = state ->
        {reply, next_state} = fun.(state)
        Process.put(@transaction_key, next_state)
        reply

      nil ->
        Server.mutate(fun)
    end
  end

  @spec transaction((-> term())) :: term()
  def transaction(fun) when is_function(fun, 0) do
    case Process.get(@transaction_key) do
      %State{} ->
        fun.()

      nil ->
        snapshot = Server.snapshot()
        Process.put(@transaction_key, snapshot)

        try do
          result = fun.()
          :ok = Server.replace_state(Process.get(@transaction_key))
          result
        catch
          {:store_local_rollback, reason} ->
            {:error, reason}
        after
          Process.delete(@transaction_key)
        end
    end
  end

  @spec rollback(term()) :: no_return()
  def rollback(reason) do
    throw({:store_local_rollback, reason})
  end
end
