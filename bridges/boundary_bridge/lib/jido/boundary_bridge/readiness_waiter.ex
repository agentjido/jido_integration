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
        {:ok, waiter} =
          WaitLoop.start_link(
            boundary_session_id: descriptor.boundary_session_id,
            adapter: adapter,
            adapter_opts: adapter_opts,
            poll_interval_ms: poll_interval_ms
          )

        try do
          WaitLoop.await(waiter, timeout_ms + poll_interval_ms)
        after
          GenServer.stop(waiter, :normal)
        end
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

  defmodule WaitLoop do
    @moduledoc false
    use GenServer

    alias Jido.BoundaryBridge.DescriptorNormalizer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    def await(pid, timeout_ms), do: GenServer.call(pid, :await, timeout_ms)

    @impl true
    def init(opts) do
      state = %{
        boundary_session_id: Keyword.fetch!(opts, :boundary_session_id),
        adapter: Keyword.fetch!(opts, :adapter),
        adapter_opts: Keyword.get(opts, :adapter_opts, []),
        poll_interval_ms: Keyword.fetch!(opts, :poll_interval_ms),
        caller: nil,
        result: nil
      }

      {:ok, state, {:continue, :poll}}
    end

    @impl true
    def handle_call(:await, from, %{result: nil} = state) do
      {:noreply, %{state | caller: from}}
    end

    def handle_call(:await, _from, %{result: result} = state) do
      {:reply, result, state}
    end

    @impl true
    def handle_continue(:poll, state) do
      {:noreply, poll(state)}
    end

    @impl true
    def handle_info(:poll, state) do
      {:noreply, poll(state)}
    end

    defp poll(state) do
      result =
        with {:ok, raw_descriptor} <-
               state.adapter.fetch_status(state.boundary_session_id, state.adapter_opts),
             {:ok, descriptor} <- DescriptorNormalizer.normalize(raw_descriptor) do
          cond do
            descriptor.attach.mode == :not_applicable ->
              {:ok, descriptor}

            descriptor.status == :failed ->
              {:ok, descriptor}

            descriptor.attach_ready? ->
              {:ok, descriptor}

            true ->
              nil
          end
        end

      case result do
        nil ->
          Process.send_after(self(), :poll, state.poll_interval_ms)
          state

        {:ok, _descriptor} = ready ->
          reply(state, ready)

        {:error, _error} = error ->
          reply(state, error)
      end
    end

    defp reply(%{caller: nil} = state, result), do: %{state | result: result}

    defp reply(%{caller: caller} = state, result) do
      GenServer.reply(caller, result)
      %{state | caller: nil, result: result}
    end
  end
end
