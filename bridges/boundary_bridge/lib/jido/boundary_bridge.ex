defmodule Jido.BoundaryBridge do
  @moduledoc """
  Public package root for the lower-boundary sandbox bridge.

  The bridge is a stateless translation seam between authored runtime intent
  above and sandbox-kernel lifecycle below. It owns typed public IO, request
  translation, readiness waiting, descriptor normalization, and bridge-facing
  error normalization.
  """

  alias Jido.BoundaryBridge.{
    AllocateBoundaryRequest,
    BoundarySessionDescriptor,
    DescriptorNormalizer,
    Error,
    ErrorNormalizer,
    ReadinessWaiter,
    ReopenBoundaryRequest,
    RequestTranslator,
    UnconfiguredAdapter
  }

  @doc """
  Returns the package role for this child package.
  """
  @spec role() :: :lower_boundary_bridge
  def role, do: :lower_boundary_bridge

  @doc """
  Allocates one boundary through the configured lower-boundary adapter.
  """
  @spec allocate(AllocateBoundaryRequest.t() | map() | keyword(), keyword()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def allocate(request, opts \\ []) do
    adapter = adapter_module(opts)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    with {:ok, request} <- AllocateBoundaryRequest.new(request),
         payload <- RequestTranslator.to_allocate_payload(request),
         {:ok, raw_descriptor} <- adapter.allocate(payload, adapter_opts),
         {:ok, descriptor} <- DescriptorNormalizer.normalize(raw_descriptor),
         {:ok, descriptor} <-
           maybe_wait_for_attach(descriptor, request, adapter, adapter_opts, opts) do
      {:ok, descriptor}
    else
      {:error, error} -> {:error, ErrorNormalizer.normalize(error)}
    end
  end

  @doc """
  Reopens one boundary through the configured lower-boundary adapter.
  """
  @spec reopen(ReopenBoundaryRequest.t() | map() | keyword(), keyword()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def reopen(request, opts \\ []) do
    adapter = adapter_module(opts)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    with {:ok, request} <- ReopenBoundaryRequest.new(request),
         payload <- RequestTranslator.to_reopen_payload(request),
         {:ok, raw_descriptor} <- adapter.reopen(payload, adapter_opts),
         {:ok, descriptor} <- DescriptorNormalizer.normalize(raw_descriptor),
         {:ok, descriptor} <-
           maybe_wait_for_attach(descriptor, request, adapter, adapter_opts, opts) do
      {:ok, descriptor}
    else
      {:error, error} -> {:error, ErrorNormalizer.normalize(error)}
    end
  end

  @doc """
  Waits until an attachable boundary becomes ready, fails, or times out.
  """
  @spec await_readiness(BoundarySessionDescriptor.t() | map(), keyword()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def await_readiness(descriptor, opts \\ []) do
    adapter = adapter_module(opts)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    with {:ok, descriptor} <- DescriptorNormalizer.normalize(descriptor),
         {:ok, descriptor} <- ReadinessWaiter.await(descriptor, adapter, adapter_opts, opts) do
      {:ok, descriptor}
    else
      {:error, error} -> {:error, ErrorNormalizer.normalize(error)}
    end
  end

  @doc """
  Claims one boundary session for runtime ownership after readiness.
  """
  @spec claim(BoundarySessionDescriptor.t() | map(), keyword()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def claim(descriptor, opts \\ []) do
    adapter = adapter_module(opts)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    with {:ok, descriptor} <- DescriptorNormalizer.normalize(descriptor),
         {:ok, raw_descriptor} <-
           adapter.claim(
             descriptor.boundary_session_id,
             runtime_control_payload(opts),
             adapter_opts
           ),
         {:ok, descriptor} <- DescriptorNormalizer.normalize(raw_descriptor) do
      {:ok, descriptor}
    else
      {:error, error} -> {:error, ErrorNormalizer.normalize(error)}
    end
  end

  @doc """
  Records one runtime heartbeat for a claimed or claiming boundary session.
  """
  @spec heartbeat(BoundarySessionDescriptor.t() | map(), keyword()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def heartbeat(descriptor, opts \\ []) do
    adapter = adapter_module(opts)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    with {:ok, descriptor} <- DescriptorNormalizer.normalize(descriptor),
         {:ok, raw_descriptor} <-
           adapter.heartbeat(
             descriptor.boundary_session_id,
             runtime_control_payload(opts),
             adapter_opts
           ),
         {:ok, descriptor} <- DescriptorNormalizer.normalize(raw_descriptor) do
      {:ok, descriptor}
    else
      {:error, error} -> {:error, ErrorNormalizer.normalize(error)}
    end
  end

  @doc """
  Projects attach metadata for consumers such as ASM when attach semantics apply.
  """
  @spec project_attach_metadata(BoundarySessionDescriptor.t() | map()) ::
          {:ok,
           %{
             boundary_session_id: String.t(),
             execution_surface: CliSubprocessCore.ExecutionSurface.t(),
             working_directory: String.t() | nil,
             refs: map(),
             attach_grant: map(),
             boundary_metadata: map()
           }
           | nil}
          | {:error, Exception.t()}
  def project_attach_metadata(descriptor) do
    case DescriptorNormalizer.normalize(descriptor) do
      {:ok, descriptor} ->
        case descriptor.attach.mode do
          :not_applicable ->
            {:ok, nil}

          :attachable
          when descriptor.attach_ready? and not is_nil(descriptor.attach.execution_surface) ->
            boundary_metadata = project_boundary_metadata!(descriptor)

            {:ok,
             %{
               boundary_session_id: descriptor.boundary_session_id,
               execution_surface: descriptor.attach.execution_surface,
               working_directory: descriptor.attach.working_directory,
               refs: Map.from_struct(descriptor.refs),
               attach_grant: Map.get(boundary_metadata, "attach_grant", %{}),
               boundary_metadata: boundary_metadata
             }}

          :attachable ->
            {:error,
             Error.resource_unavailable(
               "Attach metadata is not ready for this boundary session",
               reason: "boundary_attach_not_ready",
               retryable: true,
               correlation_id: descriptor.refs.correlation_id,
               request_id: descriptor.refs.request_id,
               details: %{
                 boundary_session_id: descriptor.boundary_session_id,
                 status: descriptor.status
               }
             )}
        end

      {:error, error} ->
        {:error, ErrorNormalizer.normalize(error)}
    end
  end

  @doc """
  Projects explicit durable boundary metadata for facade and session-kernel consumers.
  """
  @spec project_boundary_metadata(BoundarySessionDescriptor.t() | map()) ::
          {:ok, map()} | {:error, Exception.t()}
  def project_boundary_metadata(descriptor) do
    case DescriptorNormalizer.normalize(descriptor) do
      {:ok, descriptor} ->
        {:ok, project_boundary_metadata!(descriptor)}

      {:error, error} ->
        {:error, ErrorNormalizer.normalize(error)}
    end
  end

  defp maybe_wait_for_attach(descriptor, request, adapter, adapter_opts, opts) do
    if descriptor.attach.mode == :attachable and not descriptor.attach_ready? do
      ReadinessWaiter.await(
        descriptor,
        adapter,
        adapter_opts,
        Keyword.merge(opts, readiness_timeout_ms: request.readiness_timeout_ms)
      )
    else
      {:ok, descriptor}
    end
  end

  defp adapter_module(opts) do
    Keyword.get(
      opts,
      :adapter,
      Application.get_env(
        :jido_integration_v2_boundary_bridge,
        :adapter,
        UnconfiguredAdapter
      )
    )
  end

  defp runtime_control_payload(opts) do
    %{
      runtime_owner: Keyword.get(opts, :runtime_owner) || "runtime",
      runtime_ref: Keyword.get(opts, :runtime_ref)
    }
  end

  defp project_boundary_metadata!(%BoundarySessionDescriptor{} = descriptor) do
    %{}
    |> maybe_put_metadata("descriptor", descriptor_metadata(descriptor))
    |> maybe_put_metadata("route", route_metadata(descriptor))
    |> maybe_put_metadata("attach_grant", attach_grant_metadata(descriptor))
    |> maybe_put_metadata("replay", replay_metadata(descriptor))
    |> maybe_put_metadata("approval", approval_metadata(descriptor))
    |> maybe_put_metadata("callback", callback_metadata(descriptor))
    |> maybe_put_metadata("identity", identity_metadata(descriptor))
  end

  defp descriptor_metadata(%BoundarySessionDescriptor{} = descriptor) do
    %{
      "descriptor_version" => descriptor.descriptor_version,
      "boundary_session_id" => descriptor.boundary_session_id,
      "backend_kind" => Atom.to_string(descriptor.backend_kind),
      "boundary_class" => maybe_atom_string(descriptor.boundary_class),
      "status" => Atom.to_string(descriptor.status),
      "attach_ready?" => descriptor.attach_ready?
    }
    |> reject_nil_values()
  end

  defp route_metadata(%BoundarySessionDescriptor{refs: refs}) do
    %{
      "decision_id" => Map.get(refs, :decision_id),
      "route_id" => Map.get(refs, :route_id),
      "idempotency_key" => Map.get(refs, :idempotency_key)
    }
    |> reject_nil_values()
  end

  defp attach_grant_metadata(%BoundarySessionDescriptor{} = descriptor) do
    if descriptor.attach.mode == :attachable and descriptor.attach_ready? do
      %{
        "boundary_session_id" => descriptor.boundary_session_id,
        "attach_mode" => Atom.to_string(descriptor.attach.mode),
        "working_directory" => descriptor.attach.working_directory,
        "expires_at" => Map.get(descriptor.attach, :expires_at),
        "granted_capabilities" => Map.get(descriptor.attach, :granted_capabilities, [])
      }
      |> reject_nil_values()
      |> reject_empty_lists()
    else
      %{}
    end
  end

  defp replay_metadata(%BoundarySessionDescriptor{} = descriptor) do
    %{
      "supported?" => descriptor.checkpointing.supported?,
      "last_checkpoint_id" => descriptor.checkpointing.last_checkpoint_id,
      "replayable?" => Map.get(descriptor.checkpointing, :replayable?),
      "recovery_class" => Map.get(descriptor.checkpointing, :recovery_class)
    }
    |> reject_nil_values()
    |> reject_false_defaults()
  end

  defp approval_metadata(%BoundarySessionDescriptor{} = descriptor) do
    %{
      "approval_mode" => maybe_atom_string(Map.get(descriptor.policy_intent_echo, :approvals)),
      "approval_refs" => Map.get(descriptor.refs, :approval_refs, [])
    }
    |> reject_nil_values()
    |> reject_empty_lists()
  end

  defp callback_metadata(%BoundarySessionDescriptor{} = descriptor) do
    %{
      "callback_ref" => Map.get(descriptor.callback, :callback_ref),
      "state" => maybe_atom_string(Map.get(descriptor.callback, :state)),
      "last_received_at" => Map.get(descriptor.callback, :last_received_at)
    }
    |> reject_nil_values()
    |> reject_default_state("not_applicable")
  end

  defp identity_metadata(%BoundarySessionDescriptor{} = descriptor) do
    lease_refs =
      [Map.get(descriptor.refs, :lease_ref) | Map.get(descriptor.refs, :lease_refs, [])]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %{
      "lease_refs" => lease_refs,
      "credential_handle_refs" => Map.get(descriptor.refs, :credential_handle_refs, [])
    }
    |> reject_empty_lists()
  end

  defp maybe_put_metadata(map, _key, value) when map_size(value) == 0, do: map
  defp maybe_put_metadata(map, key, value), do: Map.put(map, key, value)

  defp reject_nil_values(map) do
    Enum.reject(map, fn {_key, value} -> is_nil(value) end) |> Map.new()
  end

  defp reject_empty_lists(map) do
    Enum.reject(map, fn {_key, value} -> is_list(value) and value == [] end) |> Map.new()
  end

  defp reject_false_defaults(map) do
    Enum.reject(map, fn {_key, value} -> value == false end) |> Map.new()
  end

  defp reject_default_state(map, default_state) do
    Enum.reject(map, fn
      {"state", ^default_state} -> true
      _other -> false
    end)
    |> Map.new()
  end

  defp maybe_atom_string(nil), do: nil
  defp maybe_atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_string(value), do: value
end
