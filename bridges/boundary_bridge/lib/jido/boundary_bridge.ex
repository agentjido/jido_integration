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
  Projects attach metadata for consumers such as ASM when attach semantics apply.
  """
  @spec project_attach_metadata(BoundarySessionDescriptor.t() | map()) ::
          {:ok,
           %{
             boundary_session_id: String.t(),
             execution_surface: CliSubprocessCore.ExecutionSurface.t(),
             working_directory: String.t() | nil,
             refs: map()
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
            {:ok,
             %{
               boundary_session_id: descriptor.boundary_session_id,
               execution_surface: descriptor.attach.execution_surface,
               working_directory: descriptor.attach.working_directory,
               refs: Map.from_struct(descriptor.refs)
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
end
