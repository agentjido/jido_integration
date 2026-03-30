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
        policy_intent_echo: %{sandbox_level: :strict, approvals: :manual},
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
end
