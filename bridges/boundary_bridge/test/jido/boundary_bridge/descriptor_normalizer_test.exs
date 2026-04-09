defmodule Jido.BoundaryBridge.DescriptorNormalizerTest do
  use ExUnit.Case, async: true

  alias Jido.BoundaryBridge.{BoundarySessionDescriptor, DescriptorNormalizer, PolicyIntent}

  test "normalizes raw descriptor payloads into the public contract" do
    {:ok, surface} =
      CliSubprocessCore.ExecutionSurface.new(
        surface_kind: :guest_bridge,
        transport_options: [endpoint: %{kind: :unix_socket, path: "/tmp/normalize.sock"}],
        target_id: "target-normalize-1",
        lease_ref: "lease-normalize-1",
        surface_ref: "surface-normalize-1",
        boundary_class: :leased_cell,
        observability: %{}
      )

    assert {:ok, %BoundarySessionDescriptor{} = descriptor} =
             DescriptorNormalizer.normalize(%{
               descriptor_version: 1,
               boundary_session_id: "bnd-normalize-1",
               backend_kind: "microvm",
               boundary_class: "leased_cell",
               status: "ready",
               attach_ready?: true,
               workspace: %{
                 workspace_root: "/workspace",
                 snapshot_ref: "snap-1",
                 artifact_namespace: "run-1"
               },
               attach: %{
                 mode: "attachable",
                 execution_surface: surface,
                 working_directory: "/workspace"
               },
               checkpointing: %{supported?: true, last_checkpoint_id: "chk-1"},
               policy_intent_echo: %{
                 sandbox_level: "strict",
                 egress: "restricted",
                 approvals: "manual",
                 allowed_tools: ["git"],
                 file_scope: "/workspace",
                 policy_source: "Gateway.sandbox"
               },
               refs: %{
                 target_id: "target-normalize-1",
                 lease_ref: "lease-normalize-1",
                 surface_ref: "surface-normalize-1",
                 runtime_ref: "asm-session-1",
                 correlation_id: "corr-normalize-1",
                 request_id: "req-normalize-1"
               },
               extensions: %{},
               metadata: %{source: "raw"}
             })

    assert descriptor.backend_kind == :microvm
    assert descriptor.status == :ready

    assert PolicyIntent.to_map(descriptor.policy_intent_echo) == %{
             sandbox_level: :strict,
             egress: :restricted,
             approvals: :manual,
             allowed_tools: ["git"],
             file_scope: "/workspace"
           }
  end

  test "accepts raw descriptor maps that still carry nested public structs" do
    descriptor =
      BoundarySessionDescriptor.new!(%{
        descriptor_version: 1,
        boundary_session_id: "bnd-struct-shaped-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        status: :ready,
        attach_ready?: true,
        workspace: %{
          workspace_root: "/workspace",
          snapshot_ref: "snap-2",
          artifact_namespace: "run-2"
        },
        attach: %{
          mode: :attachable,
          execution_surface: execution_surface("target-struct-shaped-1"),
          working_directory: "/workspace"
        },
        checkpointing: %{supported?: true, last_checkpoint_id: "chk-2"},
        policy_intent_echo: policy_projection(:strict, :manual),
        refs: %{correlation_id: "corr-struct-shaped-1", request_id: "req-struct-shaped-1"},
        extensions: %{},
        metadata: %{source: "struct-shaped"}
      })

    assert {:ok, %BoundarySessionDescriptor{} = normalized} =
             descriptor
             |> Map.from_struct()
             |> DescriptorNormalizer.normalize()

    assert normalized.boundary_session_id == "bnd-struct-shaped-1"
    assert normalized.attach.execution_surface.target_id == "target-struct-shaped-1"
  end

  test "normalizes explicit route replay callback and identity metadata from session payloads" do
    assert {:ok, %BoundarySessionDescriptor{} = descriptor} =
             DescriptorNormalizer.normalize(%{
               session: %{
                 session_id: "bnd-session-payload-1",
                 status: :ready,
                 last_checkpoint_id: "chk-session-payload-1",
                 backend: %{backend_kind: :microvm},
                 target: %{target_id: "target-session-payload-1"},
                 metadata: %{
                   attach_ready?: true,
                   workspace_root: "/workspace",
                   snapshot_ref: "snap-session-payload-1",
                   artifact_namespace: "run-session-payload-1",
                   attach: %{
                     mode: :attachable,
                     execution_surface: execution_surface("target-session-payload-1"),
                     working_directory: "/workspace"
                   },
                   attach_grant: %{
                     expires_at: "2026-04-10T12:10:00Z",
                     granted_capabilities: ["attach.read"]
                   },
                   checkpoint_supported?: true,
                   replay: %{replayable?: true, recovery_class: "checkpoint_resume"},
                   callback: %{
                     callback_ref: "callback://session-payload-1",
                     state: :pending,
                     last_received_at: "2026-04-10T12:01:00Z"
                   },
                   refs: %{
                     route_id: "route-session-payload-1",
                     decision_id: "decision-session-payload-1",
                     idempotency_key: "idem-session-payload-1",
                     approval_refs: ["approval-session-payload-1"],
                     lease_refs: ["lease-session-payload-1"],
                     artifact_refs: ["artifact-session-payload-1"],
                     credential_handle_refs: [
                       "credential-handle://tenant-1/workload/session-payload-1"
                     ]
                   },
                   correlation_id: "corr-session-payload-1",
                   request_id: "req-session-payload-1"
                 }
               }
             })

    assert Map.get(descriptor.refs, :route_id) == "route-session-payload-1"
    assert Map.get(descriptor.refs, :decision_id) == "decision-session-payload-1"
    assert Map.get(descriptor.refs, :idempotency_key) == "idem-session-payload-1"
    assert Map.get(descriptor.refs, :approval_refs) == ["approval-session-payload-1"]
    assert Map.get(descriptor.attach, :expires_at) == "2026-04-10T12:10:00Z"
    assert Map.get(descriptor.attach, :granted_capabilities) == ["attach.read"]
    assert Map.get(descriptor.checkpointing, :replayable?) == true
    assert Map.get(descriptor.checkpointing, :recovery_class) == "checkpoint_resume"
    assert Map.get(descriptor.callback, :callback_ref) == "callback://session-payload-1"
    assert Map.get(descriptor.callback, :state) == :pending
  end

  defp execution_surface(target_id) do
    {:ok, surface} =
      CliSubprocessCore.ExecutionSurface.new(
        surface_kind: :guest_bridge,
        transport_options: [endpoint: %{kind: :unix_socket, path: "/tmp/#{target_id}.sock"}],
        target_id: target_id,
        lease_ref: "lease-#{target_id}",
        surface_ref: "surface-#{target_id}",
        boundary_class: :leased_cell,
        observability: %{}
      )

    surface
  end

  defp policy_projection(level, approvals) do
    %{sandbox_level: level, approvals: approvals}
  end
end
