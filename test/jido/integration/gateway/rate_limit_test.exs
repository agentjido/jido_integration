defmodule Jido.Integration.Gateway.RateLimitTest do
  use ExUnit.Case

  alias Jido.Integration.Gateway.Policy.RateLimit

  setup do
    name = :"rate_limit_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      RateLimit.start_link(
        name: name,
        max_tokens: 10,
        refill_rate: 5,
        refill_interval_ms: 100_000
      )

    %{server: name, pid: pid}
  end

  describe "try_acquire/2" do
    test "admits when tokens available", %{server: server} do
      assert RateLimit.try_acquire(server, :test_partition) == :admit
    end

    test "sheds when tokens exhausted", %{server: server} do
      # Exhaust all 10 tokens
      for _ <- 1..10 do
        RateLimit.try_acquire(server, :exhaust)
      end

      assert RateLimit.try_acquire(server, :exhaust) == :shed
    end

    test "backoffs when tokens are low", %{server: server} do
      # Max is 10, backoff threshold is < 1 (10 / 10)
      # Consume 9 tokens to get to 1 remaining
      for _ <- 1..9 do
        RateLimit.try_acquire(server, :low)
      end

      # 1 token left, which is < 10/10 = 1, so it should be backoff
      assert RateLimit.try_acquire(server, :low) == :backoff
    end

    test "tracks partitions independently", %{server: server} do
      # Exhaust partition A
      for _ <- 1..10 do
        RateLimit.try_acquire(server, :partition_a)
      end

      # Partition B should still have tokens
      assert RateLimit.try_acquire(server, :partition_b) == :admit
    end
  end

  describe "policy behaviour" do
    test "partition_key extracts connector_id" do
      assert RateLimit.partition_key(%{connector_id: "github"}) == "github"
    end

    test "partition_key defaults to :default" do
      assert RateLimit.partition_key(%{}) == :default
    end

    test "on_pressure decides based on remaining tokens" do
      assert RateLimit.on_pressure(:test, %{remaining_tokens: 100}) == :admit
      assert RateLimit.on_pressure(:test, %{remaining_tokens: 5}) == :backoff
      assert RateLimit.on_pressure(:test, %{remaining_tokens: 0}) == :shed
    end
  end
end
