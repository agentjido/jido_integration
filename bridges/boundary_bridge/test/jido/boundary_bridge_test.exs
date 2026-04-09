defmodule Jido.BoundaryBridgeTest do
  use ExUnit.Case, async: true

  alias Jido.BoundaryBridge.{
    AllocateBoundaryRequest,
    BoundarySessionDescriptor,
    ReopenBoundaryRequest
  }

  alias Jido.BoundaryBridge.Error.TimeoutError
  alias Jido.BoundaryBridge.TestAdapter

  doctest Jido.BoundaryBridge

  setup do
    {:ok, store} = start_supervised(TestAdapter)
    %{store: store}
  end

  test "exposes the package role" do
    assert Jido.BoundaryBridge.role() == :lower_boundary_bridge
  end

  test "allocate is idempotent for the same deterministic boundary_session_id", %{store: store} do
    request = allocate_request("bnd-idempotent-1")

    assert {:ok, %BoundarySessionDescriptor{} = first} =
             Jido.BoundaryBridge.allocate(
               request,
               adapter: TestAdapter,
               adapter_opts: [store: store]
             )

    assert {:ok, %BoundarySessionDescriptor{} = second} =
             Jido.BoundaryBridge.allocate(
               request,
               adapter: TestAdapter,
               adapter_opts: [store: store]
             )

    assert first == second
  end

  test "reopen is idempotent for the same deterministic boundary_session_id", %{store: store} do
    request = reopen_request("bnd-reopen-idempotent-1")

    assert {:ok, %BoundarySessionDescriptor{} = first} =
             Jido.BoundaryBridge.reopen(
               request,
               adapter: TestAdapter,
               adapter_opts: [store: store]
             )

    assert {:ok, %BoundarySessionDescriptor{} = second} =
             Jido.BoundaryBridge.reopen(
               request,
               adapter: TestAdapter,
               adapter_opts: [store: store]
             )

    assert first == second
  end

  test "await_readiness polls until an attachable descriptor is ready", %{store: store} do
    descriptor = scripted_descriptor("bnd-await-ready", false)

    TestAdapter.put_status_script(
      store,
      descriptor.boundary_session_id,
      [
        %{descriptor | status: :starting, attach_ready?: false},
        %{
          descriptor
          | status: :ready,
            attach_ready?: true,
            attach: %{
              descriptor.attach
              | execution_surface: execution_surface(descriptor.boundary_session_id)
            }
        }
      ]
    )

    assert {:ok, %BoundarySessionDescriptor{} = ready} =
             Jido.BoundaryBridge.await_readiness(
               descriptor,
               adapter: TestAdapter,
               adapter_opts: [store: store],
               readiness_timeout_ms: 200,
               poll_interval_ms: 5
             )

    assert ready.status == :ready
    assert ready.attach_ready? == true
  end

  test "await_readiness returns a timeout error with cleanup_outcome cleaned_up", %{store: store} do
    descriptor = scripted_descriptor("bnd-await-timeout-clean", false)

    TestAdapter.put_status_script(
      store,
      descriptor.boundary_session_id,
      List.duplicate(%{descriptor | status: :starting, attach_ready?: false}, 8)
    )

    TestAdapter.put_stop_outcome(store, descriptor.boundary_session_id, :ok)

    assert {:error, %TimeoutError{} = error} =
             Jido.BoundaryBridge.await_readiness(
               descriptor,
               adapter: TestAdapter,
               adapter_opts: [store: store],
               readiness_timeout_ms: 20,
               poll_interval_ms: 5
             )

    assert error.boundary_session_id == descriptor.boundary_session_id
    assert error.cleanup_outcome == :cleaned_up
  end

  test "await_readiness returns a timeout error with cleanup_outcome unknown when stop is indeterminate",
       %{store: store} do
    descriptor = scripted_descriptor("bnd-await-timeout-unknown", false)

    TestAdapter.put_status_script(
      store,
      descriptor.boundary_session_id,
      List.duplicate(%{descriptor | status: :starting, attach_ready?: false}, 8)
    )

    TestAdapter.put_stop_outcome(
      store,
      descriptor.boundary_session_id,
      {:error, %{error_code: "sandbox_stop_unknown"}}
    )

    assert {:error, %TimeoutError{} = error} =
             Jido.BoundaryBridge.await_readiness(
               descriptor,
               adapter: TestAdapter,
               adapter_opts: [store: store],
               readiness_timeout_ms: 20,
               poll_interval_ms: 5
             )

    assert error.boundary_session_id == descriptor.boundary_session_id
    assert error.cleanup_outcome == :unknown
  end

  test "claim moves an attach-ready descriptor into runtime-owned state", %{store: store} do
    descriptor = scripted_descriptor("bnd-claim-ready", true)
    TestAdapter.put_descriptor(store, descriptor.boundary_session_id, descriptor)

    assert {:ok, %BoundarySessionDescriptor{} = claimed} =
             Jido.BoundaryBridge.claim(
               descriptor,
               adapter: TestAdapter,
               adapter_opts: [store: store],
               runtime_owner: "asm",
               runtime_ref: "asm-runtime-bnd-claim-ready"
             )

    assert claimed.status == :ready
    assert claimed.attach_ready? == true
    assert claimed.metadata.runtime_owner == "asm"
    assert claimed.metadata.runtime_ref == "asm-runtime-bnd-claim-ready"
  end

  test "heartbeat is idempotent for an already-claimed descriptor", %{store: store} do
    descriptor = scripted_descriptor("bnd-heartbeat-ready", true)
    TestAdapter.put_descriptor(store, descriptor.boundary_session_id, descriptor)

    assert {:ok, %BoundarySessionDescriptor{} = heartbeat} =
             Jido.BoundaryBridge.heartbeat(
               descriptor,
               adapter: TestAdapter,
               adapter_opts: [store: store],
               runtime_owner: "asm",
               runtime_ref: "asm-runtime-bnd-heartbeat-ready"
             )

    assert heartbeat.status == :ready
    assert heartbeat.attach_ready? == true
  end

  test "project_attach_metadata returns nil for kernel-neutral descriptors" do
    descriptor =
      BoundarySessionDescriptor.new!(%{
        descriptor_version: 1,
        boundary_session_id: "bnd-sidecar-projection",
        backend_kind: :sprites,
        boundary_class: :sidecar,
        status: :running,
        attach_ready?: false,
        workspace: %{
          workspace_root: "/workspace",
          snapshot_ref: nil,
          artifact_namespace: "room-1"
        },
        attach: %{mode: :not_applicable, execution_surface: nil, working_directory: "/workspace"},
        checkpointing: %{supported?: false, last_checkpoint_id: nil},
        policy_intent_echo: policy_projection(:standard),
        refs: %{correlation_id: "corr-sidecar", request_id: "req-sidecar"},
        extensions: %{},
        metadata: %{}
      })

    assert {:ok, nil} = Jido.BoundaryBridge.project_attach_metadata(descriptor)
  end

  test "project_boundary_metadata makes durable route replay approval callback and identity semantics explicit" do
    descriptor =
      BoundarySessionDescriptor.new!(%{
        descriptor_version: 1,
        boundary_session_id: "bnd-boundary-metadata-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        status: :ready,
        attach_ready?: true,
        workspace: %{
          workspace_root: "/workspace",
          snapshot_ref: "snap-boundary-metadata-1",
          artifact_namespace: "run-boundary-metadata-1"
        },
        attach: %{
          mode: :attachable,
          execution_surface: execution_surface("bnd-boundary-metadata-1"),
          working_directory: "/workspace",
          expires_at: "2026-04-10T12:10:00Z",
          granted_capabilities: ["attach.read", "attach.write"]
        },
        checkpointing: %{
          supported?: true,
          last_checkpoint_id: "chk-boundary-metadata-1",
          replayable?: true,
          recovery_class: "session_resume"
        },
        policy_intent_echo:
          policy_projection(:strict, :restricted, :manual, ["git"], "/workspace"),
        callback: %{
          callback_ref: "callback://boundary-metadata-1",
          state: :completed,
          last_received_at: "2026-04-10T12:03:00Z"
        },
        refs: %{
          target_id: "target-bnd-boundary-metadata-1",
          lease_ref: "lease-bnd-boundary-metadata-1",
          surface_ref: "surface-bnd-boundary-metadata-1",
          runtime_ref: "asm-bnd-boundary-metadata-1",
          correlation_id: "corr-bnd-boundary-metadata-1",
          request_id: "req-bnd-boundary-metadata-1",
          decision_id: "decision-bnd-boundary-metadata-1",
          route_id: "route-bnd-boundary-metadata-1",
          idempotency_key: "idem-bnd-boundary-metadata-1",
          lease_refs: ["lease-bnd-boundary-metadata-1"],
          approval_refs: ["approval-bnd-boundary-metadata-1"],
          artifact_refs: ["artifact-bnd-boundary-metadata-1"],
          credential_handle_refs: ["credential-handle://tenant-1/workload/boundary-1"]
        },
        extensions: %{},
        metadata: %{}
      })

    assert {:ok, metadata} = Jido.BoundaryBridge.project_boundary_metadata(descriptor)

    assert metadata["descriptor"]["boundary_session_id"] == "bnd-boundary-metadata-1"
    assert metadata["route"]["route_id"] == "route-bnd-boundary-metadata-1"
    assert metadata["route"]["idempotency_key"] == "idem-bnd-boundary-metadata-1"
    assert metadata["attach_grant"]["granted_capabilities"] == ["attach.read", "attach.write"]
    assert metadata["replay"]["replayable?"] == true
    assert metadata["replay"]["recovery_class"] == "session_resume"
    assert metadata["approval"]["approval_refs"] == ["approval-bnd-boundary-metadata-1"]
    assert metadata["callback"]["callback_ref"] == "callback://boundary-metadata-1"

    assert metadata["identity"]["credential_handle_refs"] == [
             "credential-handle://tenant-1/workload/boundary-1"
           ]

    assert {:ok, attach_projection} = Jido.BoundaryBridge.project_attach_metadata(descriptor)
    assert attach_projection.attach_grant == metadata["attach_grant"]
    assert attach_projection.boundary_metadata == metadata
  end

  defp allocate_request(boundary_session_id) do
    AllocateBoundaryRequest.new!(%{
      boundary_session_id: boundary_session_id,
      backend_kind: :microvm,
      boundary_class: :leased_cell,
      attach: %{mode: :attachable, working_directory: "/workspace"},
      policy_intent: %{
        sandbox_level: :strict,
        egress: :restricted,
        approvals: :manual,
        allowed_tools: ["git"],
        file_scope: "/workspace"
      },
      refs: %{
        target_id: "target-#{boundary_session_id}",
        lease_ref: "lease-#{boundary_session_id}",
        surface_ref: "surface-#{boundary_session_id}",
        runtime_ref: "asm-#{boundary_session_id}",
        correlation_id: "corr-#{boundary_session_id}",
        request_id: "req-#{boundary_session_id}"
      },
      allocation_ttl_ms: 15_000
    })
  end

  defp reopen_request(boundary_session_id) do
    ReopenBoundaryRequest.new!(%{
      boundary_session_id: boundary_session_id,
      backend_kind: :microvm,
      boundary_class: :leased_cell,
      attach: %{mode: :attachable, working_directory: "/workspace"},
      checkpoint_id: "chk-#{boundary_session_id}",
      policy_intent: %{
        sandbox_level: :strict,
        egress: :restricted,
        approvals: :manual,
        allowed_tools: ["git"],
        file_scope: "/workspace"
      },
      refs: %{
        target_id: "target-#{boundary_session_id}",
        correlation_id: "corr-#{boundary_session_id}",
        request_id: "req-#{boundary_session_id}"
      }
    })
  end

  defp scripted_descriptor(boundary_session_id, attach_ready?) do
    BoundarySessionDescriptor.new!(%{
      descriptor_version: 1,
      boundary_session_id: boundary_session_id,
      backend_kind: :microvm,
      boundary_class: :leased_cell,
      status: if(attach_ready?, do: :ready, else: :starting),
      attach_ready?: attach_ready?,
      workspace: %{workspace_root: "/workspace", snapshot_ref: nil, artifact_namespace: "run-1"},
      attach: %{
        mode: :attachable,
        execution_surface:
          if(attach_ready?, do: execution_surface(boundary_session_id), else: nil),
        working_directory: "/workspace"
      },
      checkpointing: %{supported?: true, last_checkpoint_id: nil},
      policy_intent_echo: policy_projection(:strict, :restricted, :manual, ["git"], "/workspace"),
      refs: %{
        target_id: "target-#{boundary_session_id}",
        lease_ref: "lease-#{boundary_session_id}",
        surface_ref: "surface-#{boundary_session_id}",
        runtime_ref: "asm-#{boundary_session_id}",
        correlation_id: "corr-#{boundary_session_id}",
        request_id: "req-#{boundary_session_id}"
      },
      extensions: %{},
      metadata: %{}
    })
  end

  defp execution_surface(target_id) do
    {:ok, surface} =
      CliSubprocessCore.ExecutionSurface.new(
        surface_kind: :guest_bridge,
        transport_options: [
          endpoint: %{kind: :unix_socket, path: "/tmp/#{target_id}.sock"},
          bridge_ref: "bridge-#{target_id}",
          bridge_profile: "core_cli_transport",
          supported_protocol_versions: [1]
        ],
        target_id: target_id,
        lease_ref: "lease-#{target_id}",
        surface_ref: "surface-#{target_id}",
        boundary_class: :leased_cell,
        observability: %{}
      )

    surface
  end

  defp policy_projection(
         level,
         egress \\ nil,
         approvals \\ nil,
         allowed_tools \\ [],
         file_scope \\ nil
       ) do
    %{}
    |> maybe_put(:sandbox_level, level)
    |> maybe_put(:egress, egress)
    |> maybe_put(:approvals, approvals)
    |> maybe_put(:allowed_tools, allowed_tools)
    |> maybe_put(:file_scope, file_scope)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
