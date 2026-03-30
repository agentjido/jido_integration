defmodule Jido.BoundaryBridge.TestAdapter do
  @moduledoc false
  @behaviour Jido.BoundaryBridge.Adapter

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn ->
      %{
        descriptors: %{},
        status_scripts: %{},
        stop_outcomes: %{},
        stop_calls: []
      }
    end)
  end

  def put_status_script(store, boundary_session_id, descriptors) do
    Agent.update(store, fn state ->
      put_in(
        state,
        [:status_scripts, boundary_session_id],
        Enum.map(descriptors, &to_raw_descriptor/1)
      )
    end)
  end

  def put_stop_outcome(store, boundary_session_id, outcome) do
    Agent.update(store, fn state ->
      put_in(state, [:stop_outcomes, boundary_session_id], outcome)
    end)
  end

  @impl true
  def allocate(payload, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      boundary_session_id = payload.boundary_session_id

      descriptor =
        Map.get_lazy(state.descriptors, boundary_session_id, fn ->
          payload
          |> ensure_descriptor_payload()
          |> default_raw_descriptor()
        end)

      {{:ok, descriptor}, put_in(state, [:descriptors, boundary_session_id], descriptor)}
    end)
  end

  @impl true
  def reopen(payload, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      boundary_session_id = payload.boundary_session_id

      descriptor =
        Map.get_lazy(state.descriptors, boundary_session_id, fn ->
          payload
          |> ensure_descriptor_payload()
          |> default_raw_descriptor()
        end)

      {{:ok, descriptor}, put_in(state, [:descriptors, boundary_session_id], descriptor)}
    end)
  end

  @impl true
  def fetch_status(boundary_session_id, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      case get_in(state, [:status_scripts, boundary_session_id]) do
        [next | rest] ->
          {{:ok, next}, put_in(state, [:status_scripts, boundary_session_id], rest)}

        [] ->
          descriptor = get_in(state, [:descriptors, boundary_session_id])
          {{:ok, descriptor}, state}

        nil ->
          descriptor = get_in(state, [:descriptors, boundary_session_id])
          {{:ok, descriptor}, state}
      end
    end)
  end

  @impl true
  def stop(boundary_session_id, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      outcome = Map.get(state.stop_outcomes, boundary_session_id, :ok)
      next_state = update_in(state.stop_calls, &[boundary_session_id | &1])
      {outcome, next_state}
    end)
  end

  defp ensure_descriptor_payload(%{policy_intent_echo: _} = payload), do: payload

  defp ensure_descriptor_payload(payload) do
    Map.put(payload, :policy_intent_echo, Map.get(payload, :policy_intent, %{}))
  end

  defp to_raw_descriptor(%Jido.BoundaryBridge.BoundarySessionDescriptor{} = descriptor),
    do: descriptor |> Map.from_struct() |> Map.update!(:attach, &Map.from_struct/1)

  defp to_raw_descriptor(descriptor), do: descriptor

  defp default_raw_descriptor(payload) do
    attach_mode = get_in(payload, [:attach, :mode]) || :attachable
    target_id = get_in(payload, [:refs, :target_id])
    lease_ref = get_in(payload, [:refs, :lease_ref])
    surface_ref = get_in(payload, [:refs, :surface_ref])
    boundary_class = Map.get(payload, :boundary_class)

    %{
      descriptor_version: 1,
      boundary_session_id: payload.boundary_session_id,
      backend_kind: payload.backend_kind,
      boundary_class: boundary_class,
      status: if(attach_mode == :attachable, do: :ready, else: :running),
      attach_ready?: attach_mode == :attachable,
      workspace: %{
        workspace_root: get_in(payload, [:attach, :working_directory]),
        snapshot_ref: Map.get(payload, :checkpoint_id),
        artifact_namespace: get_in(payload, [:refs, :request_id])
      },
      attach: %{
        mode: attach_mode,
        execution_surface:
          if(
            attach_mode == :attachable,
            do:
              execution_surface(
                target_id || "target-#{payload.boundary_session_id}",
                lease_ref,
                surface_ref,
                boundary_class
              ),
            else: nil
          ),
        working_directory: get_in(payload, [:attach, :working_directory])
      },
      checkpointing: %{
        supported?: Map.has_key?(payload, :checkpoint_id),
        last_checkpoint_id: Map.get(payload, :checkpoint_id)
      },
      policy_intent_echo: Map.get(payload, :policy_intent_echo, %{}),
      refs: Map.get(payload, :refs, %{}),
      extensions: Map.get(payload, :extensions, %{}),
      metadata: Map.get(payload, :metadata, %{})
    }
  end

  defp execution_surface(target_id, lease_ref, surface_ref, boundary_class) do
    {:ok, surface} =
      CliSubprocessCore.ExecutionSurface.new(
        surface_kind: :guest_bridge,
        transport_options: [endpoint: %{kind: :unix_socket, path: "/tmp/#{target_id}.sock"}],
        target_id: target_id,
        lease_ref: lease_ref,
        surface_ref: surface_ref,
        boundary_class: normalize_boundary_class(boundary_class),
        observability: %{}
      )

    surface
  end

  defp normalize_boundary_class(boundary_class) when is_atom(boundary_class), do: boundary_class

  defp normalize_boundary_class(boundary_class) when is_binary(boundary_class),
    do: String.to_atom(boundary_class)

  defp normalize_boundary_class(_boundary_class), do: nil
end
