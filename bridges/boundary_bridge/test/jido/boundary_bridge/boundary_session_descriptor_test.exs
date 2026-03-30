defmodule Jido.BoundaryBridge.BoundarySessionDescriptorTest do
  use ExUnit.Case, async: true

  alias Jido.BoundaryBridge.BoundarySessionDescriptor
  alias Jido.BoundaryBridge.Extensions.Tracing

  test "accepts a kernel-neutral descriptor with no attach surface" do
    descriptor =
      BoundarySessionDescriptor.new!(%{
        descriptor_version: 1,
        boundary_session_id: "bnd-sidecar-1",
        backend_kind: :sprites,
        boundary_class: :sidecar,
        status: :running,
        attach_ready?: false,
        workspace: %{
          workspace_root: "/workspace",
          snapshot_ref: nil,
          artifact_namespace: "room-9"
        },
        attach: %{
          mode: :not_applicable,
          execution_surface: nil,
          working_directory: "/workspace"
        },
        checkpointing: %{supported?: false, last_checkpoint_id: nil},
        policy_intent_echo: %{
          sandbox_level: :standard,
          egress: :restricted,
          approvals: :auto,
          allowed_tools: ["room.publish"],
          file_scope: "/workspace"
        },
        refs: %{
          target_id: "hive-worker-3",
          lease_ref: nil,
          surface_ref: nil,
          runtime_ref: "jido-session-12",
          correlation_id: "corr-777",
          request_id: "req-777"
        },
        extensions: %{},
        metadata: %{}
      })

    assert descriptor.descriptor_version == 1
    assert descriptor.attach.mode == :not_applicable
    assert descriptor.attach.execution_surface == nil
    assert descriptor.attach_ready? == false
  end

  test "validates known extensions through typed accessors" do
    descriptor =
      BoundarySessionDescriptor.new!(%{
        descriptor_version: 1,
        boundary_session_id: "bnd-tracing-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        status: :ready,
        attach_ready?: true,
        workspace: %{
          workspace_root: "/workspace",
          snapshot_ref: "snap-1",
          artifact_namespace: "run-1"
        },
        attach: %{
          mode: :attachable,
          execution_surface: execution_surface("target-1"),
          working_directory: "/workspace"
        },
        checkpointing: %{supported?: true, last_checkpoint_id: nil},
        policy_intent_echo: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace"
        },
        refs: %{
          target_id: "target-1",
          lease_ref: "lease-1",
          surface_ref: "surface-1",
          runtime_ref: "asm-session-1",
          correlation_id: "corr-1",
          request_id: "req-1"
        },
        extensions: %{
          "jido.boundary_bridge.tracing" => %{
            traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
            tracestate: "rojo=00f067aa0ba902b7"
          }
        },
        metadata: %{}
      })

    assert %Tracing{} = BoundarySessionDescriptor.tracing_extension(descriptor)
    assert BoundarySessionDescriptor.tracing_extension(descriptor).traceparent =~ "4bf92f35"
  end

  test "fails closed on unsupported descriptor versions" do
    assert {:error, %ArgumentError{} = error} =
             BoundarySessionDescriptor.new(%{
               descriptor_version: 2,
               boundary_session_id: "bnd-version-1",
               backend_kind: :fake,
               status: :starting,
               attach_ready?: false,
               workspace: %{workspace_root: nil, snapshot_ref: nil, artifact_namespace: nil},
               attach: %{mode: :attachable, execution_surface: nil, working_directory: nil},
               checkpointing: %{supported?: false, last_checkpoint_id: nil},
               policy_intent_echo: policy_projection(:none),
               refs: %{correlation_id: "corr-version", request_id: "req-version"},
               extensions: %{},
               metadata: %{}
             })

    assert Exception.message(error) =~ "descriptor_version"
  end

  test "rejects invalid known extension payloads" do
    assert {:error, %ArgumentError{} = error} =
             BoundarySessionDescriptor.new(%{
               descriptor_version: 1,
               boundary_session_id: "bnd-tracing-invalid",
               backend_kind: :fake,
               status: :ready,
               attach_ready?: false,
               workspace: %{workspace_root: nil, snapshot_ref: nil, artifact_namespace: nil},
               attach: %{mode: :not_applicable, execution_surface: nil, working_directory: nil},
               checkpointing: %{supported?: false, last_checkpoint_id: nil},
               policy_intent_echo: policy_projection(:none),
               refs: %{correlation_id: "corr-invalid", request_id: "req-invalid"},
               extensions: %{"jido.boundary_bridge.tracing" => %{traceparent: 123}},
               metadata: %{}
             })

    assert Exception.message(error) =~ "traceparent"
  end

  defp execution_surface(target_id) do
    {:ok, surface} =
      CliSubprocessCore.ExecutionSurface.new(
        surface_kind: :guest_bridge,
        transport_options: [endpoint: %{kind: :unix_socket, path: "/tmp/#{target_id}.sock"}],
        target_id: target_id,
        lease_ref: "lease-1",
        surface_ref: "surface-1",
        boundary_class: :leased_cell,
        observability: %{}
      )

    surface
  end

  defp policy_projection(level) do
    %{sandbox_level: level}
  end
end
