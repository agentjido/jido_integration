defmodule Jido.Integration.V2.LowerEffectReceiptTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Lanes.LowerEffectReceipt

  test "normalizes complete lower effect receipts and serializes for Mezzanine" do
    completed_at = ~U[2026-05-20 20:10:00Z]

    receipt =
      LowerEffectReceipt.new!(%{
        receipt_ref: "receipt://effect/diagnostic/001",
        effect_ref: "effect://tenant-1/diagnostic/001",
        status: "success",
        lower_receipt_ref: "lower-receipt://diagnostic/001",
        lower_facts: %{"diagnostic_result" => %{"status" => "ok"}},
        projection_updates: [%{"kind" => "diagnostic_completed"}],
        evidence_refs: ["aitrace://trace-1/diagnostic/001"],
        trace_ref: "trace://tenant-1/diagnostic/001",
        completed_at: completed_at
      })

    assert receipt.status == :success
    assert receipt.completed_at == completed_at

    encoded = receipt |> LowerEffectReceipt.to_map() |> Jason.encode!() |> Jason.decode!()

    assert encoded["receipt_ref"] == "receipt://effect/diagnostic/001"
    assert encoded["effect_ref"] == "effect://tenant-1/diagnostic/001"
    assert encoded["status"] == "success"
    assert encoded["completed_at"] == DateTime.to_iso8601(completed_at)

    assert {:ok, reloaded} = LowerEffectReceipt.new(encoded)
    assert reloaded.receipt_ref == receipt.receipt_ref
    assert reloaded.completed_at == completed_at
  end

  test "rejects missing effect refs and raw credential material" do
    missing_effect_ref =
      assert_raise ArgumentError, fn ->
        receipt_attrs()
        |> Map.delete(:effect_ref)
        |> LowerEffectReceipt.new!()
      end

    assert String.contains?(Exception.message(missing_effect_ref), "effect_ref")

    raw_secret =
      assert_raise ArgumentError, fn ->
        receipt_attrs()
        |> Map.put(:lower_facts, %{"access_token" => "secret"})
        |> LowerEffectReceipt.new!()
      end

    assert String.contains?(Exception.message(raw_secret), "raw credential material")
  end

  defp receipt_attrs do
    %{
      receipt_ref: "receipt://effect/diagnostic/001",
      effect_ref: "effect://tenant-1/diagnostic/001",
      status: :success,
      lower_receipt_ref: "lower-receipt://diagnostic/001",
      lower_facts: %{},
      projection_updates: [],
      evidence_refs: ["aitrace://trace-1/diagnostic/001"],
      trace_ref: "trace://tenant-1/diagnostic/001",
      completed_at: ~U[2026-05-20 20:10:00Z]
    }
  end
end
