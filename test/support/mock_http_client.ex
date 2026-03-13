defmodule Jido.Integration.Test.MockHttpClient do
  @moduledoc """
  Mock HTTP client for testing connectors without live network calls.

  Expectations are scoped to the calling test process, but child tasks can
  consume them by walking the caller/ancestor chain. That keeps tests isolated
  while still working across simple process boundaries.
  """

  @table :jido_integration_mock_http_client

  @doc "Set the response for the next GET request."
  def expect_get(response) do
    enqueue(:get, response)
  end

  @doc "Set the response for the next POST request."
  def expect_post(response) do
    enqueue(:post, response)
  end

  @doc "Perform a mocked GET request."
  def get(_url, _headers) do
    dequeue(:get)
  end

  @doc "Perform a mocked POST request."
  def post(_url, _body, _headers) do
    dequeue(:post)
  end

  defp enqueue(method, response) do
    table = ensure_table()
    key = {self(), method}
    queue = lookup_queue(table, key)
    :ets.insert(table, {key, :queue.in(response, queue)})
    :ok
  end

  defp dequeue(method) do
    table = ensure_table()

    case Enum.find(candidate_pids(), &queued?(table, {&1, method})) do
      nil ->
        {:error, :no_mock_configured}

      owner_pid ->
        key = {owner_pid, method}

        case :queue.out(lookup_queue(table, key)) do
          {{:value, response}, queue} ->
            persist_queue(table, key, queue)
            response

          {:empty, _queue} ->
            {:error, :no_mock_configured}
        end
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set])

      table ->
        table
    end
  end

  defp candidate_pids do
    [self() | Process.get(:"$callers", []) ++ Process.get(:"$ancestors", [])]
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end

  defp queued?(table, key) do
    case :ets.lookup(table, key) do
      [{^key, queue}] -> not :queue.is_empty(queue)
      [] -> false
    end
  end

  defp lookup_queue(table, key) do
    case :ets.lookup(table, key) do
      [{^key, queue}] -> queue
      [] -> :queue.new()
    end
  end

  defp persist_queue(table, key, queue) do
    if :queue.is_empty(queue) do
      :ets.delete(table, key)
    else
      :ets.insert(table, {key, queue})
    end
  end
end
