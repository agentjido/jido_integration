defmodule Jido.BoundaryBridge.ReadinessWaiter do
  @moduledoc """
  Bounded readiness waiting for attachable boundary descriptors.
  """

  alias Jido.BoundaryBridge.{BoundarySessionDescriptor, DescriptorNormalizer, Error}

  @default_poll_interval_ms 50
  @default_readiness_timeout_ms 5_000

  @spec await(BoundarySessionDescriptor.t(), module(), keyword(), keyword()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def await(%BoundarySessionDescriptor{} = descriptor, _adapter, _adapter_opts, _opts)
      when descriptor.attach.mode == :not_applicable or descriptor.attach_ready? or
             descriptor.status == :failed do
    {:ok, descriptor}
  end

  def await(%BoundarySessionDescriptor{} = descriptor, adapter, adapter_opts, opts) do
    timeout_ms = Keyword.get(opts, :readiness_timeout_ms, @default_readiness_timeout_ms)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    task =
      Task.async(fn ->
        poll_until_ready(descriptor.boundary_session_id, adapter, adapter_opts, poll_interval_ms)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, descriptor}} ->
        {:ok, descriptor}

      {:ok, {:error, error}} ->
        {:error, error}

      nil ->
        cleanup_outcome =
          case adapter.stop(descriptor.boundary_session_id, adapter_opts) do
            :ok -> :cleaned_up
            {:error, _reason} -> :unknown
          end

        {:error,
         Error.timeout("Boundary readiness timed out",
           reason: "boundary_readiness_timeout",
           retryable: true,
           boundary_session_id: descriptor.boundary_session_id,
           cleanup_outcome: cleanup_outcome,
           correlation_id: descriptor.refs.correlation_id,
           request_id: descriptor.refs.request_id,
           details: %{status: descriptor.status}
         )}
    end
  end

  defp poll_until_ready(boundary_session_id, adapter, adapter_opts, poll_interval_ms) do
    Process.sleep(poll_interval_ms)

    with {:ok, raw_descriptor} <- adapter.fetch_status(boundary_session_id, adapter_opts),
         {:ok, descriptor} <- DescriptorNormalizer.normalize(raw_descriptor) do
      cond do
        descriptor.attach.mode == :not_applicable ->
          {:ok, descriptor}

        descriptor.status == :failed ->
          {:ok, descriptor}

        descriptor.attach_ready? ->
          {:ok, descriptor}

        true ->
          poll_until_ready(boundary_session_id, adapter, adapter_opts, poll_interval_ms)
      end
    end
  end
end
