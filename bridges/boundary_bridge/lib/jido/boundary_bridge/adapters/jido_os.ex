defmodule Jido.BoundaryBridge.Adapters.JidoOs do
  @moduledoc """
  Lower-boundary adapter that projects bridge requests through
  `Jido.Os.Sandbox.Service`.
  """

  @behaviour Jido.BoundaryBridge.Adapter

  alias Jido.Os.Sandbox.Service, as: SandboxService

  @default_actor_id "system:boundary_bridge"

  @impl true
  def allocate(payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           SandboxService.start_session(
             instance_id,
             allocate_payload(payload),
             request_context(payload, opts)
           ) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def reopen(payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <- reopen_boundary(instance_id, payload, opts) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def fetch_status(boundary_session_id, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           SandboxService.get_session_status(
             instance_id,
             %{session_id: boundary_session_id},
             request_context(%{boundary_session_id: boundary_session_id}, opts)
           ) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def claim(boundary_session_id, payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           SandboxService.claim_boundary_session(
             instance_id,
             Map.put(payload, :session_id, boundary_session_id),
             request_context(%{refs: payload}, opts)
           ) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def heartbeat(boundary_session_id, payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           SandboxService.heartbeat_boundary_session(
             instance_id,
             Map.put(payload, :session_id, boundary_session_id),
             request_context(%{refs: payload}, opts)
           ) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def stop(boundary_session_id, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           SandboxService.stop_session(
             instance_id,
             %{session_id: boundary_session_id},
             request_context(%{boundary_session_id: boundary_session_id}, opts)
           ) do
      case response do
        %{outcome: "ok"} -> :ok
        %{outcome: "error", error: error} -> {:error, error}
      end
    end
  end

  defp reopen_boundary(instance_id, payload, opts) do
    if is_binary(Map.get(payload, :checkpoint_id)) and Map.get(payload, :checkpoint_id) != "" do
      SandboxService.resume_session(
        instance_id,
        reopen_payload(payload),
        request_context(payload, opts)
      )
    else
      SandboxService.start_session(
        instance_id,
        allocate_payload(payload),
        request_context(payload, opts)
      )
    end
  end

  defp allocate_payload(payload) do
    %{
      session_id: Map.get(payload, :boundary_session_id),
      backend_kind: normalize_value(Map.get(payload, :backend_kind)),
      target_id: get_in(payload, [:refs, :target_id]),
      descriptor_version: 1,
      boundary_class: normalize_value(Map.get(payload, :boundary_class)),
      attach: normalize_map(Map.get(payload, :attach, %{})),
      policy_intent: normalize_map(Map.get(payload, :policy_intent, %{})),
      refs: normalize_map(Map.get(payload, :refs, %{})),
      allocation_ttl_ms: Map.get(payload, :allocation_ttl_ms),
      extensions: normalize_map(Map.get(payload, :extensions, %{})),
      metadata: normalize_map(Map.get(payload, :metadata, %{})),
      owner: "boundary_bridge"
    }
  end

  defp reopen_payload(payload) do
    allocate_payload(payload)
    |> Map.put(:checkpoint_id, Map.get(payload, :checkpoint_id))
    |> Map.put(:source_session_id, Map.get(payload, :boundary_session_id))
  end

  defp unwrap_descriptor(%{outcome: "ok", payload: %{descriptor: descriptor}}),
    do: {:ok, descriptor}

  defp unwrap_descriptor(%{outcome: "error", error: error}), do: {:error, error}

  defp unwrap_descriptor(other) do
    {:error,
     RuntimeError.exception(
       "jido_os boundary adapter received an invalid response: #{inspect(other)}"
     )}
  end

  defp fetch_instance_id(opts) do
    case Keyword.get(opts, :instance_id) do
      instance_id when is_binary(instance_id) and instance_id != "" -> {:ok, instance_id}
      _other -> {:error, ArgumentError.exception("boundary adapter requires :instance_id")}
    end
  end

  defp request_context(payload, opts) do
    attrs =
      opts
      |> Keyword.get(:attrs, %{})
      |> normalize_map()
      |> Map.put_new(:actor_id, Keyword.get(opts, :actor_id, @default_actor_id))

    refs = normalize_map(Map.get(payload, :refs, %{}))

    attrs
    |> maybe_put(:correlation_id, Map.get(refs, :correlation_id))
    |> maybe_put(:request_id, Map.get(refs, :request_id))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put_new(map, key, value)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(_value), do: %{}

  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value
end
