defmodule Jido.BoundaryBridge.RequestTranslatorTest do
  use ExUnit.Case, async: true

  alias Jido.BoundaryBridge.{AllocateBoundaryRequest, ReopenBoundaryRequest, RequestTranslator}

  test "translates allocate requests into adapter payloads and keeps policy_intent_echo lossy" do
    request =
      AllocateBoundaryRequest.new!(%{
        boundary_session_id: "bnd-translate-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git", "test.session.exec"],
          file_scope: "/workspace",
          policy_source: "Gateway.sandbox.authoritative"
        },
        refs: %{
          target_id: "target-build-1",
          lease_ref: "lease-123",
          surface_ref: "surface-123",
          runtime_ref: "asm-session-44",
          correlation_id: "corr-123",
          request_id: "req-123"
        },
        allocation_ttl_ms: 12_000,
        readiness_timeout_ms: 1_500,
        extensions: %{
          "jido.boundary_bridge.tracing" => %{
            traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
          }
        },
        metadata: %{purpose: "allocate"}
      })

    payload = RequestTranslator.to_allocate_payload(request)

    assert payload.boundary_session_id == "bnd-translate-1"
    assert payload.backend_kind == :microvm
    assert payload.attach.mode == :attachable
    assert payload.allocation_ttl_ms == 12_000
    assert payload.readiness_timeout_ms == 1_500

    assert payload.policy_intent == %{
             sandbox_level: :strict,
             egress: :restricted,
             approvals: :manual,
             allowed_tools: ["git", "test.session.exec"],
             file_scope: "/workspace"
           }

    refute get_in(payload, [:policy_intent, :policy_source])
  end

  test "translates reopen requests with checkpoint intent" do
    request =
      ReopenBoundaryRequest.new!(%{
        boundary_session_id: "bnd-reopen-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace"},
        policy_intent: %{sandbox_level: :strict},
        refs: %{correlation_id: "corr-reopen", request_id: "req-reopen"},
        checkpoint_id: "chk-123"
      })

    payload = RequestTranslator.to_reopen_payload(request)

    assert payload.boundary_session_id == "bnd-reopen-1"
    assert payload.checkpoint_id == "chk-123"
    assert payload.attach.mode == :attachable
  end
end
