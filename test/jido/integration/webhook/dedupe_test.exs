defmodule Jido.Integration.Webhook.DedupeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Webhook.Dedupe

  setup do
    {:ok, dedupe} =
      Dedupe.start_link(
        name: :"dedupe_#{System.unique_integer([:positive])}",
        ttl_ms: 5_000
      )

    %{dedupe: dedupe}
  end

  describe "seen?/2 and mark_seen/2" do
    test "new delivery_id is not seen", %{dedupe: dedupe} do
      refute Dedupe.seen?(dedupe, "delivery_1")
    end

    test "marked delivery_id is seen", %{dedupe: dedupe} do
      assert :ok = Dedupe.mark_seen(dedupe, "delivery_1")
      assert Dedupe.seen?(dedupe, "delivery_1")
    end

    test "different delivery_ids are independent", %{dedupe: dedupe} do
      Dedupe.mark_seen(dedupe, "delivery_1")
      refute Dedupe.seen?(dedupe, "delivery_2")
    end
  end

  describe "idempotent marking" do
    test "marking twice is fine", %{dedupe: dedupe} do
      assert :ok = Dedupe.mark_seen(dedupe, "delivery_1")
      assert :ok = Dedupe.mark_seen(dedupe, "delivery_1")
      assert Dedupe.seen?(dedupe, "delivery_1")
    end
  end

  describe "TTL cleanup" do
    test "entries expire after TTL", %{dedupe: _dedupe} do
      # Start a dedupe with very short TTL for testing.
      # seen?/2 checks TTL inline, so we only need to wait for the TTL
      # to elapse — the background sweep is just for cleanup.
      {:ok, fast_dedupe} =
        Dedupe.start_link(
          name: :"dedupe_fast_#{System.unique_integer([:positive])}",
          ttl_ms: 30,
          sweep_interval_ms: 100_000
        )

      Dedupe.mark_seen(fast_dedupe, "ephemeral")
      assert Dedupe.seen?(fast_dedupe, "ephemeral")

      # Wait well past the 30ms TTL. seen?/2 does an inline expiry check.
      Process.sleep(100)

      refute Dedupe.seen?(fast_dedupe, "ephemeral")
    end
  end
end
