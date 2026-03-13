defmodule Jido.Integration.V2.Apps.TradingOpsTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Apps.TradingOps

  setup do
    ensure_started(
      [Jido.Integration.V2.ControlPlane.Registry, Jido.Integration.V2.ControlPlane.RunLedger],
      Jido.Integration.V2.ControlPlane.Supervisor,
      Jido.Integration.V2.ControlPlane.Application
    )

    ensure_started(
      [Jido.Integration.V2.Auth.Store],
      Jido.Integration.V2.Auth.Supervisor,
      Jido.Integration.V2.Auth.Application
    )

    ensure_started(
      [Jido.Integration.V2.SessionKernel.SessionStore],
      Jido.Integration.V2.SessionKernel.Supervisor,
      Jido.Integration.V2.SessionKernel.Application
    )

    ensure_started(
      [Jido.Integration.V2.StreamRuntime.Store],
      Jido.Integration.V2.StreamRuntime.Supervisor,
      Jido.Integration.V2.StreamRuntime.Application
    )

    V2.reset!()
    :ok
  end

  test "builds one reviewable operator workflow from trigger ingress through all runtime families" do
    assert {:ok, stack} =
             TradingOps.bootstrap_reference_stack(%{
               tenant_id: "tenant-trading-review",
               actor_id: "desk-operator"
             })

    assert stack.installs.market_data.state == :completed
    assert stack.installs.analyst.state == :completed
    assert stack.installs.operator.state == :completed
    assert stack.connections.market_data.connection.state == :connected
    assert stack.connections.analyst.connection.state == :connected
    assert stack.connections.operator.connection.state == :connected

    assert {:ok, workflow} =
             TradingOps.run_market_review(stack, %{
               external_id: "alert-es-1",
               cursor: "cursor-es-1",
               last_event_id: "event-es-1",
               observed_at: ~U[2026-03-09 13:05:00Z],
               symbol: "ES",
               price: 5_088.25,
               threshold: 5_080.00,
               venue: "CME",
               issue_repo: "trading/ops-review",
               desk_note: "review before live routing"
             })

    assert workflow.trigger.status == :accepted
    assert workflow.trigger.trigger.signal["type"] == "trading_ops.market.alert"
    assert workflow.market_pull.run.runtime_class == :stream
    assert workflow.analyst_session.run.runtime_class == :session
    assert workflow.escalation_issue.run.runtime_class == :direct

    assert {:ok, packet} = TradingOps.review_packet(workflow)

    assert packet.targets.market_data.target_id == "target-trading-ops-market-feed"
    assert packet.targets.analyst.target_id == "target-trading-ops-analyst-session"
    assert packet.targets.operator.target_id == "target-trading-ops-operator-saas"

    assert packet.runs.market_pull.run.target_id == "target-trading-ops-market-feed"
    assert packet.runs.market_pull.attempt.target_id == "target-trading-ops-market-feed"

    assert Enum.any?(
             packet.runs.market_pull.events,
             &(&1.target_id == "target-trading-ops-market-feed")
           )

    assert packet.runs.analyst_session.run.target_id == "target-trading-ops-analyst-session"
    assert packet.runs.analyst_session.attempt.target_id == "target-trading-ops-analyst-session"

    assert Enum.any?(
             packet.runs.analyst_session.events,
             &(&1.target_id == "target-trading-ops-analyst-session")
           )

    assert packet.runs.escalation_issue.run.target_id == "target-trading-ops-operator-saas"
    assert packet.runs.escalation_issue.attempt.target_id == "target-trading-ops-operator-saas"

    assert Enum.any?(
             packet.runs.escalation_issue.events,
             &(&1.target_id == "target-trading-ops-operator-saas")
           )

    assert packet.connections.market_data.state == :connected
    assert packet.connections.analyst.state == :connected
    assert packet.connections.operator.state == :connected

    assert [%{artifact_type: :log}] = packet.runs.market_pull.artifacts
    assert [%{artifact_type: :event_log}] = packet.runs.analyst_session.artifacts
    assert [%{artifact_type: :tool_output}] = packet.runs.escalation_issue.artifacts
    assert workflow.escalation_issue.output.title == "ES alert review for trading ops"
  end

  defp ensure_started(required_processes, supervisor_name, application_module) do
    if Enum.all?(required_processes, &Process.whereis/1) do
      :ok
    else
      if pid = Process.whereis(supervisor_name) do
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _reason -> :ok
        end
      end

      case application_module.start(:normal, []) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          raise "failed to start #{inspect(supervisor_name)}: #{inspect(reason)}"
      end
    end
  end
end
