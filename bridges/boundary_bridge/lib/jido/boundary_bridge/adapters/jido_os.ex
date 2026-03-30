defmodule Jido.BoundaryBridge.Adapters.JidoOs do
  @moduledoc """
  Lower-boundary adapter that projects bridge requests through
  `Jido.Os.Sandbox.Service`.
  """

  @behaviour Jido.BoundaryBridge.Adapter

  alias Jido.BoundaryBridge.Error
  alias Jido.Os.Sandbox.Service, as: SandboxService

  @default_actor_id "system:boundary_bridge"
  @service_retry_attempts 50
  @service_retry_sleep_ms 10

  @impl true
  def allocate(payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           with_service_retry(fn ->
             SandboxService.start_session(
               instance_id,
               allocate_payload(payload),
               request_context(payload, opts)
             )
           end) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def reopen(payload, opts) do
    context = request_context(payload, opts)

    with {:ok, instance_id} <- fetch_instance_id(opts) do
      reopen_boundary(instance_id, payload, context)
    end
  end

  @impl true
  def fetch_status(boundary_session_id, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           with_service_retry(fn ->
             SandboxService.get_session_status(
               instance_id,
               %{session_id: boundary_session_id},
               request_context(%{boundary_session_id: boundary_session_id}, opts)
             )
           end) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def claim(boundary_session_id, payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           with_service_retry(fn ->
             SandboxService.claim_boundary_session(
               instance_id,
               Map.put(payload, :session_id, boundary_session_id),
               request_context(%{refs: payload}, opts)
             )
           end) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def heartbeat(boundary_session_id, payload, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           with_service_retry(fn ->
             SandboxService.heartbeat_boundary_session(
               instance_id,
               Map.put(payload, :session_id, boundary_session_id),
               request_context(%{refs: payload}, opts)
             )
           end) do
      unwrap_descriptor(response)
    end
  end

  @impl true
  def stop(boundary_session_id, opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, response} <-
           with_service_retry(fn ->
             SandboxService.stop_session(
               instance_id,
               %{session_id: boundary_session_id},
               request_context(%{boundary_session_id: boundary_session_id}, opts)
             )
           end) do
      case response do
        %{outcome: "ok"} -> :ok
        %{outcome: "error", error: error} -> {:error, error}
      end
    end
  end

  defp reopen_boundary(instance_id, payload, context) do
    if checkpoint_present?(payload) do
      instance_id
      |> SandboxService.resume_session(reopen_payload(payload), context)
      |> unwrap_descriptor()
    else
      reopen_live_boundary(instance_id, payload, context)
    end
  end

  defp reopen_live_boundary(instance_id, payload, context) do
    case fetch_live_boundary(instance_id, payload, context) do
      {:ok, descriptor} ->
        {:ok, descriptor}

      {:error, error} ->
        if session_not_found?(error) do
          allocate_reopened_boundary(instance_id, payload, context)
        else
          {:error, error}
        end
    end
  end

  defp fetch_live_boundary(instance_id, payload, context) do
    session_id = Map.fetch!(payload, :boundary_session_id)

    with {:ok, response} <-
           with_service_retry(fn ->
             SandboxService.get_session_status(instance_id, %{session_id: session_id}, context)
           end),
         {:ok, descriptor} <- unwrap_descriptor(response),
         :ok <- ensure_reopen_descriptor_matches(payload, descriptor) do
      {:ok, descriptor}
    end
  end

  defp allocate_reopened_boundary(instance_id, payload, context) do
    case with_service_retry(fn ->
           SandboxService.start_session(instance_id, allocate_payload(payload), context)
         end) do
      {:ok, response} ->
        unwrap_descriptor(response)

      {:error, error} ->
        if session_already_exists?(error) do
          fetch_live_boundary(instance_id, payload, context)
        else
          {:error, error}
        end
    end
  end

  defp ensure_reopen_descriptor_matches(payload, descriptor) do
    mismatches =
      []
      |> maybe_add_mismatch(
        :backend_kind,
        normalize_value(Map.get(payload, :backend_kind)),
        normalize_value(get_key(descriptor, :backend_kind))
      )
      |> maybe_add_mismatch(
        :boundary_class,
        normalize_value(Map.get(payload, :boundary_class)),
        normalize_value(get_key(descriptor, :boundary_class))
      )
      |> maybe_add_mismatch(
        :target_id,
        get_key(Map.get(payload, :refs, %{}), :target_id),
        descriptor |> get_key(:refs) |> get_key(:target_id)
      )
      |> maybe_add_mismatch(
        :attach_mode,
        normalize_value(get_key(Map.get(payload, :attach, %{}), :mode)),
        descriptor |> get_key(:attach) |> get_key(:mode) |> normalize_value()
      )
      |> maybe_add_mismatch(
        :working_directory,
        get_key(Map.get(payload, :attach, %{}), :working_directory),
        descriptor |> get_key(:attach) |> get_key(:working_directory)
      )

    if mismatches == [] do
      :ok
    else
      {:error,
       Error.invalid_request(
         "Boundary reopen request does not match the existing live boundary session",
         reason: "boundary_reopen_request_mismatch",
         retryable: false,
         correlation_id: payload |> Map.get(:refs, %{}) |> get_key(:correlation_id),
         request_id: payload |> Map.get(:refs, %{}) |> get_key(:request_id),
         details: %{
           boundary_session_id: Map.get(payload, :boundary_session_id),
           mismatches: Enum.reverse(mismatches)
         }
       )}
    end
  end

  defp maybe_add_mismatch(mismatches, _field, nil, _actual), do: mismatches
  defp maybe_add_mismatch(mismatches, _field, "", _actual), do: mismatches
  defp maybe_add_mismatch(mismatches, _field, expected, expected), do: mismatches

  defp maybe_add_mismatch(mismatches, field, expected, actual) do
    [%{field: field, expected: expected, actual: actual} | mismatches]
  end

  defp checkpoint_present?(payload) do
    checkpoint_id = Map.get(payload, :checkpoint_id)
    is_binary(checkpoint_id) and checkpoint_id != ""
  end

  defp session_not_found?(error), do: error_code(error) == "sandbox_session_not_found"
  defp session_already_exists?(error), do: error_code(error) == "sandbox_session_already_exists"

  defp error_code(error) when is_map(error) do
    Map.get(error, :error_code) || Map.get(error, "error_code")
  end

  defp error_code(_error), do: nil

  defp with_service_retry(fun, attempts_left \\ @service_retry_attempts)

  defp with_service_retry(fun, attempts_left) when attempts_left > 1 do
    case fun.() do
      {:error, error} ->
        if pending_core_readiness?(error) do
          Process.sleep(@service_retry_sleep_ms)
          with_service_retry(fun, attempts_left - 1)
        else
          {:error, error}
        end

      other ->
        other
    end
  end

  defp with_service_retry(fun, _attempts_left), do: fun.()

  defp pending_core_readiness?(error) do
    error_code(error) == "sandbox_service_unavailable" and
      error |> get_key(:details) |> get_key(:runtime_status) == "pending_core_readiness"
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

  defp get_key(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp get_key(_map, _key), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(_value), do: %{}

  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value
end
