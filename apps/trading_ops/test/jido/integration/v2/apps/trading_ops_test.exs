defmodule Jido.Integration.V2.Apps.TradingOpsTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Apps.TradingOps
  alias Jido.Integration.V2.Connectors.CodexCli.ConformanceHarnessDriver
  alias Jido.Integration.V2.HarnessRuntime
  alias Jido.Integration.V2.TargetDescriptor

  setup do
    previous_runtime_drivers =
      Application.get_env(:jido_integration_v2_control_plane, :runtime_drivers)

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

    HarnessRuntime.reset!()
    ConformanceHarnessDriver.reset!()

    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      Map.put(previous_runtime_drivers || %{}, :asm, ConformanceHarnessDriver)
    )

    on_exit(fn ->
      case previous_runtime_drivers do
        nil ->
          Application.delete_env(:jido_integration_v2_control_plane, :runtime_drivers)

        runtime_drivers ->
          Application.put_env(
            :jido_integration_v2_control_plane,
            :runtime_drivers,
            runtime_drivers
          )
      end

      HarnessRuntime.reset!()
      ConformanceHarnessDriver.reset!()
    end)

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
    assert "asm" in packet.targets.market_data.features.feature_ids
    assert packet.targets.market_data.extensions == %{"runtime" => %{"driver" => "asm"}}
    assert "asm" in packet.targets.analyst.features.feature_ids
    assert packet.targets.analyst.extensions == %{"runtime" => %{"driver" => "asm"}}
    refute "integration_stream_bridge" in packet.targets.market_data.features.feature_ids
    refute "integration_session_bridge" in packet.targets.analyst.features.feature_ids

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

  test "selects the authored asm analyst target when a mismatched session target is also advertised" do
    assert {:ok, stack} =
             TradingOps.bootstrap_reference_stack(%{
               tenant_id: "tenant-trading-review",
               actor_id: "desk-operator"
             })

    assert :ok =
             V2.announce_target(
               TargetDescriptor.new!(%{
                 target_id: "a-target-trading-ops-analyst-session-jido",
                 capability_id: "codex.exec.session",
                 runtime_class: :session,
                 version: "1.0.0",
                 features: %{
                   feature_ids: ["jido_session", "codex.exec.session"],
                   runspec_versions: ["1.0.0"],
                   event_schema_versions: ["1.0.0"]
                 },
                 constraints: %{workspace_root: "/srv/trading_ops/analyst-jido"},
                 health: :healthy,
                 location: %{
                   mode: :beam,
                   region: "test",
                   workspace_root: "/srv/trading_ops/analyst-jido"
                 },
                 extensions: %{"runtime" => %{"driver" => "jido_session"}}
               })
             )

    assert {:ok, workflow} =
             TradingOps.run_market_review(stack, %{
               external_id: "alert-es-2",
               cursor: "cursor-es-2",
               last_event_id: "event-es-2",
               observed_at: ~U[2026-03-09 13:10:00Z],
               symbol: "ES",
               price: 5_089.25,
               threshold: 5_080.00,
               venue: "CME",
               issue_repo: "trading/ops-review",
               desk_note: "review before live routing"
             })

    assert workflow.analyst_session.run.target_id == "target-trading-ops-analyst-session"
    assert workflow.analyst_session.attempt.target_id == "target-trading-ops-analyst-session"
  end

  test "selects the authored asm market target when a mismatched stream bridge target is also advertised" do
    assert {:ok, stack} =
             TradingOps.bootstrap_reference_stack(%{
               tenant_id: "tenant-trading-review",
               actor_id: "desk-operator"
             })

    assert :ok =
             V2.announce_target(
               TargetDescriptor.new!(%{
                 target_id: "a-target-trading-ops-market-bridge",
                 capability_id: "market.ticks.pull",
                 runtime_class: :stream,
                 version: "1.0.0",
                 features: %{
                   feature_ids: ["integration_stream_bridge", "market.ticks.pull"],
                   runspec_versions: ["1.0.0"],
                   event_schema_versions: ["1.0.0"]
                 },
                 constraints: %{workspace_root: "/srv/trading_ops/market-bridge"},
                 health: :healthy,
                 location: %{
                   mode: :beam,
                   region: "test",
                   workspace_root: "/srv/trading_ops/market-bridge"
                 },
                 extensions: %{"runtime" => %{"driver" => "integration_stream_bridge"}}
               })
             )

    assert {:ok, workflow} =
             TradingOps.run_market_review(stack, %{
               external_id: "alert-es-3",
               cursor: "cursor-es-3",
               last_event_id: "event-es-3",
               observed_at: ~U[2026-03-09 13:15:00Z],
               symbol: "ES",
               price: 5_090.25,
               threshold: 5_080.00,
               venue: "CME",
               issue_repo: "trading/ops-review",
               desk_note: "review before live routing"
             })

    assert workflow.market_pull.run.target_id == "target-trading-ops-market-feed"
    assert workflow.market_pull.attempt.target_id == "target-trading-ops-market-feed"
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
