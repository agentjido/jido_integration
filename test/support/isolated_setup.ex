defmodule Jido.Integration.Test.IsolatedSetup do
  @moduledoc """
  Test helpers for starting runtime components with in-memory (ETS) stores.

  Disk-backed stores persist to `/tmp/jido_integration/` and can load stale
  data from previous test runs when `System.unique_integer` values overlap
  across VM restarts. Using ETS stores eliminates this cross-run pollution
  entirely — each store gets a private ETS table that dies with its process.

  `wait_for_run/4` is generic and can be used with any `Consumer`, including
  disk-backed durability tests.

  ## Usage

      import Jido.Integration.Test.IsolatedSetup

      setup do
        {:ok, router} = start_isolated_router()
        {:ok, consumer} = start_isolated_consumer(max_attempts: 3)
        {:ok, auth} = start_isolated_auth_server()
        %{router: router, consumer: consumer, auth: auth}
      end
  """

  alias Jido.Integration.Auth.{ConnectionStore, InstallSessionStore, Server}
  alias Jido.Integration.Dispatch.{Consumer, RunStore}
  alias Jido.Integration.Webhook.{Dedupe, DedupeStore, Router, RouteStore}

  @doc "Start a Router with an ETS-backed route store."
  def start_isolated_router(extra_opts \\ []) do
    opts =
      Keyword.merge(
        [name: unique_name("router"), store_module: RouteStore.ETS],
        extra_opts
      )

    Router.start_link(opts)
  end

  @doc "Start a Consumer with ETS-backed dispatch and run stores."
  def start_isolated_consumer(extra_opts \\ []) do
    opts =
      Keyword.merge(
        [
          name: nil,
          dispatch_store_module: Jido.Integration.Dispatch.Store.ETS,
          run_store_module: RunStore.ETS
        ],
        extra_opts
      )

    Consumer.start_link(opts)
  end

  @doc "Start a Dedupe store with an ETS-backed persistence adapter."
  def start_isolated_dedupe(extra_opts \\ []) do
    opts =
      Keyword.merge(
        [name: unique_name("dedupe"), store_module: DedupeStore.ETS],
        extra_opts
      )

    Dedupe.start_link(opts)
  end

  @doc "Start an Auth.Server with ETS-backed credential and connection stores."
  def start_isolated_auth_server(extra_opts \\ []) do
    opts =
      Keyword.merge(
        [
          name: unique_name("auth"),
          store_module: Jido.Integration.Auth.Store.ETS,
          connection_store_module: ConnectionStore.ETS,
          install_session_store_module: InstallSessionStore.ETS
        ],
        extra_opts
      )

    Server.start_link(opts)
  end

  @doc "Deadline-based wait for a run to reach a predicate. No attempt-count brittleness."
  def wait_for_run(consumer, run_id, predicate) do
    wait_for_run(consumer, run_id, predicate, 2_000)
  end

  def wait_for_run(consumer, run_id, predicate, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_run(consumer, run_id, predicate, deadline)
  end

  defp do_wait_for_run(consumer, run_id, predicate, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      ExUnit.Assertions.flunk("Timed out waiting for run #{run_id}")
    end

    case Consumer.get_run(consumer, run_id) do
      {:ok, run} ->
        if predicate.(run), do: run, else: retry(consumer, run_id, predicate, deadline)

      {:error, :not_found} ->
        retry(consumer, run_id, predicate, deadline)
    end
  end

  defp retry(consumer, run_id, predicate, deadline) do
    Process.sleep(10)
    do_wait_for_run(consumer, run_id, predicate, deadline)
  end

  defp unique_name(prefix) do
    :"#{prefix}_isolated_#{System.unique_integer([:positive, :monotonic])}"
  end
end
