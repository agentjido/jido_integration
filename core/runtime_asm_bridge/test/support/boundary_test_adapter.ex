defmodule Jido.Integration.V2.RuntimeAsmBridge.TestSupport.BoundaryTestAdapter do
  @moduledoc false
  @behaviour Jido.BoundaryBridge.Adapter

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{descriptors: %{}} end)
  end

  def put_descriptor(store, boundary_session_id, descriptor) do
    Agent.update(store, fn state ->
      put_in(state, [:descriptors, boundary_session_id], descriptor)
    end)
  end

  @impl true
  def allocate(payload, opts), do: resolve_descriptor(payload, opts)

  @impl true
  def reopen(payload, opts), do: resolve_descriptor(payload, opts)

  @impl true
  def fetch_status(boundary_session_id, opts) do
    store = Keyword.fetch!(opts, :store)

    case Agent.get(store, &get_in(&1, [:descriptors, boundary_session_id])) do
      nil -> {:error, %{message: "unknown boundary_session_id"}}
      descriptor -> {:ok, descriptor}
    end
  end

  @impl true
  def claim(boundary_session_id, _payload, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      case get_in(state, [:descriptors, boundary_session_id]) do
        nil ->
          {{:error, %{message: "unknown boundary_session_id"}}, state}

        descriptor ->
          claimed = claimed_descriptor(descriptor)
          {{:ok, claimed}, put_in(state, [:descriptors, boundary_session_id], claimed)}
      end
    end)
  end

  @impl true
  def heartbeat(boundary_session_id, payload, opts) do
    claim(boundary_session_id, payload, opts)
  end

  @impl true
  def stop(_boundary_session_id, _opts), do: :ok

  defp resolve_descriptor(payload, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      boundary_session_id = Map.fetch!(payload, :boundary_session_id)

      descriptor =
        Map.get_lazy(state.descriptors, boundary_session_id, fn ->
          default_descriptor(payload)
        end)

      {{:ok, descriptor}, put_in(state, [:descriptors, boundary_session_id], descriptor)}
    end)
  end

  defp claimed_descriptor(%{attach: %{mode: :attachable}} = descriptor) do
    descriptor
    |> Map.put(:status, :ready)
    |> Map.put(:attach_ready?, true)
  end

  defp claimed_descriptor(descriptor) do
    descriptor
    |> Map.put(:status, :running)
    |> Map.put(:attach_ready?, false)
  end

  defp default_descriptor(payload) do
    attach = Map.get(payload, :attach, %{})
    attach_mode = Map.get(attach, :mode, :not_applicable)
    working_directory = Map.get(attach, :working_directory)

    %{
      descriptor_version: 1,
      boundary_session_id: payload.boundary_session_id,
      backend_kind: payload.backend_kind,
      boundary_class: payload.boundary_class,
      status: if(attach_mode == :attachable, do: :ready, else: :running),
      attach_ready?: attach_mode == :attachable,
      workspace: %{
        workspace_root: working_directory,
        snapshot_ref: Map.get(payload, :checkpoint_id),
        artifact_namespace: get_in(payload, [:refs, :request_id])
      },
      attach: %{
        mode: attach_mode,
        execution_surface: execution_surface(payload, attach_mode),
        working_directory: working_directory
      },
      checkpointing: %{
        supported?: is_binary(Map.get(payload, :checkpoint_id)),
        last_checkpoint_id: Map.get(payload, :checkpoint_id)
      },
      policy_intent_echo: Map.get(payload, :policy_intent, %{}),
      refs: Map.get(payload, :refs, %{}),
      extensions: Map.get(payload, :extensions, %{}),
      metadata: Map.get(payload, :metadata, %{})
    }
  end

  defp execution_surface(_payload, :not_applicable), do: nil

  defp execution_surface(payload, :attachable) do
    target_id = get_in(payload, [:refs, :target_id]) || "target-#{payload.boundary_session_id}"
    lease_ref = get_in(payload, [:refs, :lease_ref])
    surface_ref = get_in(payload, [:refs, :surface_ref])

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
        lease_ref: lease_ref,
        surface_ref: surface_ref,
        boundary_class: normalize_boundary_class(Map.get(payload, :boundary_class)),
        observability: %{}
      )

    surface
  end

  defp normalize_boundary_class(value) when is_atom(value), do: value
  defp normalize_boundary_class(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_boundary_class(_value), do: nil
end
