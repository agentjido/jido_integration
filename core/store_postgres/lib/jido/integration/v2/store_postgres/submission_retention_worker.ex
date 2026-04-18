defmodule Jido.Integration.V2.StorePostgres.SubmissionRetentionWorker do
  @moduledoc false

  use GenServer

  alias Jido.Integration.V2.StorePostgres.SubmissionLedger

  @default_interval_ms :timer.hours(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms:
        Keyword.get(
          opts,
          :interval_ms,
          Application.get_env(
            :jido_integration_v2_store_postgres,
            :submission_retention_interval_ms,
            @default_interval_ms
          )
        )
    }

    schedule(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:expire_submissions, state) do
    _ = SubmissionLedger.expire_submissions(now: DateTime.utc_now())
    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp schedule(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :expire_submissions, interval_ms)
  end
end
