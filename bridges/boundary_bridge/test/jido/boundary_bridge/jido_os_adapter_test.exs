defmodule Jido.BoundaryBridge.JidoOsAdapterTest do
  use ExUnit.Case, async: false

  alias Jido.BoundaryBridge.{Adapters.JidoOs, AllocateBoundaryRequest, ReopenBoundaryRequest}
  alias Jido.Os.AgentService.RegistryService, as: AgentServiceRegistry
  alias Jido.Os.Policy.Runtime, as: PolicyRuntime
  alias Jido.Os.Runtime.AgentServicesSupervisor
  alias Jido.Os.Runtime.CallerBoundary
  alias Jido.Os.Runtime.Events
  alias Jido.Os.Sandbox.Adapters.Sprites.FakeClient, as: FakeSpritesClient
  alias Jido.Os.Sandbox.Service, as: SandboxService
  alias Jido.Os.Scope.Registry, as: ScopeRegistry
  alias Jido.Os.SystemInstanceSupervisor
  alias Jido.Os.SystemInstanceSupervisor.Instance

  setup do
    restart_runtime()
    Events.clear()

    nonce = System.unique_integer([:positive, :monotonic])
    base_dir = Path.join(System.tmp_dir!(), "boundary_bridge_jido_os_#{nonce}")
    File.rm_rf!(base_dir)
    File.mkdir_p!(base_dir)

    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})

    Application.put_env(
      :jido_os,
      :managed_service_opts,
      put_sandbox_service_opts(previous_service_opts,
        sprites_client_module: FakeSpritesClient,
        fake_base_dir: base_dir
      )
    )

    on_exit(fn ->
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
      File.rm_rf(base_dir)
    end)

    base_context =
      CallerBoundary.mark_test_harness(%{
        actor_id: "actor-bridge-jido-os",
        correlation_id: "bridge-jido-os-c#{nonce}",
        request_id: "bridge-jido-os-r#{nonce}",
        session_id: "bridge-jido-os-#{nonce}",
        project_id: "project-bridge-jido-os",
        workspace_id: "workspace-bridge-jido-os"
      })

    %{base_context: base_context, nonce: nonce}
  end

  test "allocate waits for readiness through the live jido_os projection", %{
    base_context: base_context,
    nonce: nonce
  } do
    instance_id = "bridge-allocate-instance-#{nonce}"
    boundary_session_id = "bridge-allocate-session-#{nonce}"
    target_id = "bridge-allocate-target-#{nonce}"

    start_instance(instance_id, base_context)
    context = request_context(base_context, "allocate")

    allow_boundary_actions(instance_id, context)
    register_boundary_target(instance_id, context, target_id)

    request =
      AllocateBoundaryRequest.new!(%{
        boundary_session_id: boundary_session_id,
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace/#{target_id}"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace/#{target_id}"
        },
        refs: %{
          target_id: target_id,
          lease_ref: "lease-#{boundary_session_id}",
          surface_ref: "surface-#{boundary_session_id}",
          runtime_ref: "runtime-#{boundary_session_id}",
          correlation_id: context.correlation_id,
          request_id: context.request_id
        },
        allocation_ttl_ms: 250
      })

    assert {:ok, descriptor} =
             Jido.BoundaryBridge.allocate(
               request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert descriptor.descriptor_version == 1
    assert descriptor.boundary_session_id == boundary_session_id
    assert descriptor.status == :ready
    assert descriptor.attach_ready? == true
    assert descriptor.attach.execution_surface.surface_kind == :guest_bridge
  end

  test "deterministic allocate and reopen requests stay retry-safe on the same live boundary_session_id",
       %{
         base_context: base_context,
         nonce: nonce
       } do
    instance_id = "bridge-idempotent-instance-#{nonce}"
    boundary_session_id = "bridge-idempotent-session-#{nonce}"
    target_id = "bridge-idempotent-target-#{nonce}"

    start_instance(instance_id, base_context)
    context = request_context(base_context, "idempotent")

    allow_boundary_actions(instance_id, context)
    register_boundary_target(instance_id, context, target_id)

    allocate_request =
      AllocateBoundaryRequest.new!(%{
        boundary_session_id: boundary_session_id,
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace/#{target_id}"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace/#{target_id}"
        },
        refs: %{
          target_id: target_id,
          lease_ref: "lease-#{boundary_session_id}",
          surface_ref: "surface-#{boundary_session_id}",
          runtime_ref: "runtime-#{boundary_session_id}",
          correlation_id: context.correlation_id,
          request_id: context.request_id
        },
        allocation_ttl_ms: 250
      })

    reopen_request =
      ReopenBoundaryRequest.new!(%{
        boundary_session_id: boundary_session_id,
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace/#{target_id}"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace/#{target_id}"
        },
        refs: %{
          target_id: target_id,
          correlation_id: context.correlation_id,
          request_id: context.request_id
        }
      })

    assert {:ok, first} =
             Jido.BoundaryBridge.allocate(
               allocate_request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert {:ok, second} =
             Jido.BoundaryBridge.allocate(
               allocate_request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert {:ok, reopened} =
             Jido.BoundaryBridge.reopen(
               reopen_request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert first.boundary_session_id == second.boundary_session_id
    assert second.boundary_session_id == reopened.boundary_session_id

    service_state = :sys.get_state(sandbox_service_pid(instance_id, context))
    assert map_size(service_state.sessions) == 1
  end

  test "reopen creates a live boundary session when the deterministic boundary_session_id is absent",
       %{
         base_context: base_context,
         nonce: nonce
       } do
    instance_id = "bridge-reopen-create-instance-#{nonce}"
    boundary_session_id = "bridge-reopen-create-session-#{nonce}"
    target_id = "bridge-reopen-create-target-#{nonce}"

    start_instance(instance_id, base_context)
    context = request_context(base_context, "reopen_create")

    allow_boundary_actions(instance_id, context)
    register_boundary_target(instance_id, context, target_id)

    reopen_request =
      ReopenBoundaryRequest.new!(%{
        boundary_session_id: boundary_session_id,
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace/#{target_id}"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace/#{target_id}"
        },
        refs: %{
          target_id: target_id,
          correlation_id: context.correlation_id,
          request_id: context.request_id
        }
      })

    assert {:ok, descriptor} =
             Jido.BoundaryBridge.reopen(
               reopen_request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert descriptor.boundary_session_id == boundary_session_id
    assert descriptor.status == :ready
    assert descriptor.attach_ready? == true

    service_state = :sys.get_state(sandbox_service_pid(instance_id, context))
    assert map_size(service_state.sessions) == 1
  end

  test "reopen rejects a deterministic boundary_session_id when the live boundary conflicts with the request",
       %{
         base_context: base_context,
         nonce: nonce
       } do
    instance_id = "bridge-reopen-mismatch-instance-#{nonce}"
    boundary_session_id = "bridge-reopen-mismatch-session-#{nonce}"
    initial_target_id = "bridge-reopen-mismatch-target-#{nonce}"
    conflicting_target_id = "bridge-reopen-conflict-target-#{nonce}"

    start_instance(instance_id, base_context)
    context = request_context(base_context, "reopen_mismatch")

    allow_boundary_actions(instance_id, context)
    register_boundary_target(instance_id, context, initial_target_id)
    register_boundary_target(instance_id, context, conflicting_target_id)

    allocate_request =
      AllocateBoundaryRequest.new!(%{
        boundary_session_id: boundary_session_id,
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace/#{initial_target_id}"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace/#{initial_target_id}"
        },
        refs: %{
          target_id: initial_target_id,
          lease_ref: "lease-#{boundary_session_id}",
          surface_ref: "surface-#{boundary_session_id}",
          runtime_ref: "runtime-#{boundary_session_id}",
          correlation_id: context.correlation_id,
          request_id: context.request_id
        },
        allocation_ttl_ms: 250
      })

    conflicting_reopen_request =
      ReopenBoundaryRequest.new!(%{
        boundary_session_id: boundary_session_id,
        backend_kind: :sprites,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/workspace/#{conflicting_target_id}"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git"],
          file_scope: "/workspace/#{conflicting_target_id}"
        },
        refs: %{
          target_id: conflicting_target_id,
          correlation_id: context.correlation_id,
          request_id: context.request_id
        }
      })

    assert {:ok, _descriptor} =
             Jido.BoundaryBridge.allocate(
               allocate_request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert {:error, %Jido.BoundaryBridge.Error.InvalidRequestError{} = error} =
             Jido.BoundaryBridge.reopen(
               conflicting_reopen_request,
               adapter: JidoOs,
               adapter_opts: [
                 instance_id: instance_id,
                 attrs: context
               ]
             )

    assert error.reason == "boundary_reopen_request_mismatch"
    assert Enum.any?(error.details.mismatches, &(&1.field == :target_id))
  end

  defp allow_boundary_actions(instance_id, context) do
    Enum.each(
      [
        "scope_registry_register",
        "sandbox_session_start",
        "sandbox_session_read",
        "sandbox_session_runtime_control"
      ],
      &allow_policy(instance_id, context, &1)
    )
  end

  defp register_boundary_target(instance_id, context, target_id) do
    assert {:ok, _target} =
             ScopeRegistry.register_shell_execution_target(
               instance_id,
               %{
                 target_id: target_id,
                 target_kind: "remote_scope",
                 scope_kind: "project",
                 scope_id: context.project_id,
                 backend_module: inspect(FakeSpritesClient),
                 backend_reference: "sprites.remote.#{target_id}",
                 backend_config: %{
                   workspace_root: "/workspace/#{target_id}",
                   guest_bridge: %{
                     endpoint: %{kind: "unix_socket", path: "/tmp/#{target_id}.sock"},
                     bridge_ref: "bridge-#{target_id}",
                     bridge_profile: "core_cli_transport",
                     supported_protocol_versions: [1]
                   }
                 },
                 privilege_model: "remote_sprite_session",
                 available: true
               },
               context
             )
  end

  defp allow_policy(instance_id, context, action) do
    assert {:ok, _rule} =
             PolicyRuntime.set_policy(
               instance_id,
               "instance",
               %{effect: "allow", action: action, resource: "*", reason_code: "allow_#{action}"},
               context
             )

    assert {:ok, _} =
             PolicyRuntime.invalidate_cache(instance_id, "bridge_policy_update", context)
  end

  defp sandbox_service_pid(instance_id, context) do
    {:ok, pid} =
      AgentServicesSupervisor.extension_service_pid(
        instance_id,
        SandboxService.runtime_service_key(),
        request_context(context, "sandbox-service-pid")
      )

    pid
  end

  defp start_instance(instance_id, context) do
    assert {:ok, _pid} = SystemInstanceSupervisor.start_instance(instance_id, context)
    assert wait_until(fn -> Instance.ready?(instance_id) end)
    assert wait_until(fn -> AgentServicesSupervisor.core_services_ready?(instance_id) end)
    assert wait_until(fn -> sandbox_running?(instance_id, context) end)
  end

  defp sandbox_running?(instance_id, base_context) do
    match?(
      {:ok, %{outcome: "ok", payload: %{runtime_status: "running"}}},
      AgentServiceRegistry.get_agent_service(
        instance_id,
        %{service_key: SandboxService.runtime_service_key()},
        request_context(base_context, "wait-sandbox")
      )
    )
  end

  defp request_context(base_context, suffix) do
    CallerBoundary.mark_test_harness(%{
      actor_id: base_context.actor_id,
      session_id: "#{base_context.session_id}-#{suffix}",
      project_id: base_context.project_id,
      workspace_id: base_context.workspace_id,
      correlation_id: "#{base_context.correlation_id}-#{suffix}",
      request_id: "#{base_context.request_id}-#{suffix}"
    })
  end

  defp put_sandbox_service_opts(previous_service_opts, opts) do
    existing =
      previous_service_opts
      |> Map.get(SandboxService, [])
      |> case do
        value when is_list(value) -> value
        value when is_map(value) -> Enum.to_list(value)
        _other -> []
      end

    Map.put(previous_service_opts, SandboxService, Keyword.merge(existing, opts))
  end

  defp restart_runtime do
    Application.stop(:jido_os)
    Application.ensure_all_started(:jido_os)
  end

  defp wait_until(fun, timeout_ms \\ 5_000) do
    wait_until(fun, System.monotonic_time(:millisecond) + timeout_ms, 10)
  end

  defp wait_until(fun, deadline, interval_ms) do
    cond do
      fun.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(interval_ms)
        wait_until(fun, deadline, interval_ms)
    end
  end
end
