defmodule Jido.BoundaryBridge.AllocateBoundaryRequestTest do
  use ExUnit.Case, async: true

  alias Jido.BoundaryBridge.AllocateBoundaryRequest

  test "normalizes the startup TTL and keeps the public request kernel-neutral" do
    request =
      AllocateBoundaryRequest.new!(%{
        boundary_session_id: "bnd-allocate-1",
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :not_applicable, working_directory: "/workspace"},
        policy_intent: %{
          sandbox_level: :standard,
          egress: :restricted,
          approvals: :auto,
          allowed_tools: ["room.publish"],
          file_scope: "/workspace"
        },
        refs: %{
          target_id: "target-1",
          correlation_id: "corr-1",
          request_id: "req-1"
        },
        allocation_ttl_ms: 15_000
      })

    assert request.allocation_ttl_ms == 15_000
    assert request.attach.mode == :not_applicable
    refute request.attach |> Map.from_struct() |> Map.has_key?(:execution_surface)
    refute request |> Map.from_struct() |> Map.has_key?(:caller_pid)
    refute request |> Map.from_struct() |> Map.has_key?(:monitor_ref)
  end

  test "rejects a non-positive startup TTL" do
    assert {:error, %ArgumentError{} = error} =
             AllocateBoundaryRequest.new(%{
               boundary_session_id: "bnd-allocate-2",
               backend_kind: :sprites,
               attach: %{mode: :attachable},
               policy_intent: %{sandbox_level: :strict},
               refs: %{correlation_id: "corr-2", request_id: "req-2"},
               allocation_ttl_ms: 0
             })

    assert Exception.message(error) =~ "allocation_ttl_ms"
  end
end
