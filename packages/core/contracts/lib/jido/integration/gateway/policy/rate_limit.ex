defmodule Jido.Integration.Gateway.Policy.RateLimit do
  @moduledoc """
  Token-bucket rate limiting policy.

  Tracks token consumption per partition and makes admit/backoff/shed
  decisions based on remaining capacity.
  """

  use GenServer

  @behaviour Jido.Integration.Gateway.Policy

  defstruct [:max_tokens, :refill_rate, :refill_interval_ms]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    max_tokens = Keyword.get(opts, :max_tokens, 100)
    refill_rate = Keyword.get(opts, :refill_rate, 10)
    refill_interval_ms = Keyword.get(opts, :refill_interval_ms, 1_000)

    GenServer.start_link(
      __MODULE__,
      %{
        max_tokens: max_tokens,
        refill_rate: refill_rate,
        refill_interval_ms: refill_interval_ms
      },
      name: name
    )
  end

  @impl Jido.Integration.Gateway.Policy
  def partition_key(envelope) do
    Map.get(envelope, :connector_id, :default)
  end

  @impl Jido.Integration.Gateway.Policy
  def capacity(_partition) do
    {:tokens, 100}
  end

  @impl Jido.Integration.Gateway.Policy
  def on_pressure(_partition, pressure) do
    remaining = Map.get(pressure, :remaining_tokens, 100)

    cond do
      remaining <= 0 -> :shed
      remaining < 10 -> :backoff
      true -> :admit
    end
  end

  @doc "Try to consume a token for a partition. Returns the decision."
  @spec try_acquire(GenServer.server(), term()) :: :admit | :backoff | :shed
  def try_acquire(server \\ __MODULE__, partition) do
    GenServer.call(server, {:try_acquire, partition})
  end

  # Server

  @impl GenServer
  def init(config) do
    schedule_refill(config.refill_interval_ms)
    {:ok, %{config: config, buckets: %{}}}
  end

  @impl GenServer
  def handle_call({:try_acquire, partition}, _from, state) do
    bucket = Map.get(state.buckets, partition, state.config.max_tokens)

    backoff_threshold = max(div(state.config.max_tokens, 5), 2)

    {decision, new_bucket} =
      cond do
        bucket <= 0 -> {:shed, 0}
        bucket <= backoff_threshold -> {:backoff, bucket - 1}
        true -> {:admit, bucket - 1}
      end

    new_state = put_in(state.buckets[partition], new_bucket)
    {:reply, decision, new_state}
  end

  @impl GenServer
  def handle_info(:refill, state) do
    new_buckets =
      Map.new(state.buckets, fn {partition, tokens} ->
        {partition, min(tokens + state.config.refill_rate, state.config.max_tokens)}
      end)

    schedule_refill(state.config.refill_interval_ms)
    {:noreply, %{state | buckets: new_buckets}}
  end

  defp schedule_refill(interval_ms) do
    Process.send_after(self(), :refill, interval_ms)
  end
end
