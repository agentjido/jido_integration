defmodule Jido.Integration.V2.ControlPlane.AttemptReconciler do
  @moduledoc """
  Supervised startup and periodic dispatcher for durable attempt recovery tasks.

  The worker is dormant until the host supplies an explicit observer module.
  """

  use GenServer

  alias Jido.Integration.V2.ControlPlane.{AttemptRecovery, RuntimeConfig}

  @name __MODULE__
  @option_keys [:now, :limit, :claim_ttl_ms, :retry_delay_ms, :max_retries]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: @name)

  @spec reconcile_now() :: {:ok, AttemptRecovery.summary()} | {:error, term()}
  def reconcile_now, do: GenServer.call(@name, :reconcile_now, 30_000)

  @impl true
  def init(_opts), do: {:ok, %{timer: nil}, {:continue, :reconcile_on_start}}

  @impl true
  def handle_continue(:reconcile_on_start, state) do
    {_result, state} = run_reconciliation(:startup, state)
    {:noreply, schedule(state)}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    {result, state} = run_reconciliation(:due, state)
    {:reply, result, schedule(state)}
  end

  @impl true
  def handle_info(:reconcile_due, state) do
    {_result, state} = run_reconciliation(:due, %{state | timer: nil})
    {:noreply, schedule(state)}
  end

  defp run_reconciliation(mode, state) do
    case configuration() do
      {:ok, observer, opts} ->
        result =
          case mode do
            :startup -> AttemptRecovery.reconcile_on_start(observer, opts)
            :due -> AttemptRecovery.reconcile_due(observer, opts)
          end

        {result, state}

      :disabled ->
        {{:ok, %{discovered: 0, reconciled: 0, deferred: 0, operator_required: 0}}, state}
    end
  end

  defp configuration do
    case RuntimeConfig.current().attempt_reconciliation do
      %{observer: observer} = config when is_atom(observer) ->
        {:ok, observer, reconciliation_opts(config)}

      %{"observer" => observer} = config when is_atom(observer) ->
        {:ok, observer, reconciliation_opts(config)}

      _missing ->
        :disabled
    end
  end

  defp schedule(%{timer: timer} = state) when is_reference(timer), do: state

  defp schedule(state) do
    case RuntimeConfig.current().attempt_reconciliation do
      config when is_map(config) ->
        case Map.get(config, :interval_ms) || Map.get(config, "interval_ms") do
          interval_ms when is_integer(interval_ms) and interval_ms > 0 ->
            %{state | timer: Process.send_after(self(), :reconcile_due, interval_ms)}

          _disabled ->
            state
        end

      _disabled ->
        state
    end
  end

  defp reconciliation_opts(config) do
    Enum.reduce(@option_keys, [], fn key, opts ->
      case Map.fetch(config, key) do
        {:ok, value} ->
          Keyword.put(opts, key, value)

        :error ->
          case Map.fetch(config, Atom.to_string(key)) do
            {:ok, value} -> Keyword.put(opts, key, value)
            :error -> opts
          end
      end
    end)
  end
end
