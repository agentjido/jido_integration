defmodule Jido.Integration.Examples.HarnessCoreLoopTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Examples.HarnessCore.{Dispatcher, RunAggregator, RunEvent, ShedPolicy}
  alias Jido.Integration.Examples.HelloWorld
  alias Jido.Integration.Operation
  alias Jido.Integration.Test.ScopedTestAdapter
  alias Jido.Integration.Test.TelemetryHandler

  import Jido.Integration.Test.IsolatedSetup

  setup do
    {:ok, agg} = RunAggregator.start_link()
    {:ok, auth} = start_isolated_auth_server()
    %{agg: agg, auth: auth}
  end

  describe "full pipeline: trigger -> dispatch -> succeed" do
    test "happy path produces dispatch_started + dispatch_succeeded", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "harness test"})

      assert {:ok, run_id, result} =
               Dispatcher.dispatch(HelloWorld, envelope, aggregator: agg)

      assert result.status == :ok
      assert result.result["echo"] == "harness test"

      # Verify run events in aggregator
      run = RunAggregator.get_run(agg, run_id)
      assert run.state == :succeeded
      assert length(run.events) == 2

      [started, succeeded] = run.events
      assert started.event_type == :dispatch_started
      assert started.seq == 1
      assert succeeded.event_type == :dispatch_succeeded
      assert succeeded.seq == 2

      # Both events share the same run_id and attempt_id
      assert started.run_id == run_id
      assert succeeded.run_id == run_id
      assert started.attempt_id == 1
      assert succeeded.attempt_id == 1
    end

    test "run reaches terminal state", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "terminal check"})
      {:ok, run_id, _result} = Dispatcher.dispatch(HelloWorld, envelope, aggregator: agg)

      assert RunAggregator.terminal?(agg, run_id)
    end
  end

  describe "run event dedup by (run_id, attempt_id, seq)" do
    test "duplicate events are rejected", %{agg: agg} do
      event =
        RunEvent.new(
          run_id: "dedup_test",
          attempt_id: 1,
          seq: 1,
          event_type: :dispatch_started,
          connector_id: "example_ping",
          operation_id: "ping"
        )

      assert :ok = RunAggregator.append_event(agg, event)
      assert :duplicate = RunAggregator.append_event(agg, event)

      run = RunAggregator.get_run(agg, "dedup_test")
      assert length(run.events) == 1
    end

    test "different seq numbers are accepted", %{agg: agg} do
      e1 =
        RunEvent.new(
          run_id: "seq_test",
          attempt_id: 1,
          seq: 1,
          event_type: :dispatch_started
        )

      e2 =
        RunEvent.new(
          run_id: "seq_test",
          attempt_id: 1,
          seq: 2,
          event_type: :dispatch_succeeded
        )

      assert :ok = RunAggregator.append_event(agg, e1)
      assert :ok = RunAggregator.append_event(agg, e2)

      run = RunAggregator.get_run(agg, "seq_test")
      assert length(run.events) == 2
      assert run.state == :succeeded
    end

    test "different attempt_ids are accepted", %{agg: agg} do
      e1 =
        RunEvent.new(
          run_id: "attempt_test",
          attempt_id: 1,
          seq: 1,
          event_type: :dispatch_started
        )

      e2 =
        RunEvent.new(
          run_id: "attempt_test",
          attempt_id: 2,
          seq: 1,
          event_type: :dispatch_started
        )

      assert :ok = RunAggregator.append_event(agg, e1)
      assert :ok = RunAggregator.append_event(agg, e2)

      run = RunAggregator.get_run(agg, "attempt_test")
      assert length(run.events) == 2
    end
  end

  describe "target compatibility rejection" do
    test "rejects target with version below required", %{agg: agg} do
      # HelloWorld manifest version is 0.1.0
      envelope = Operation.Envelope.new("ping", %{"message" => "version check"})

      assert {:rejected, run_id, reason} =
               Dispatcher.dispatch(HelloWorld, envelope,
                 aggregator: agg,
                 required_version: "1.0.0"
               )

      assert reason =~ "version"
      assert reason =~ "0.1.0"

      run = RunAggregator.get_run(agg, run_id)
      assert run.state == :rejected
      assert length(run.events) == 1
      assert hd(run.events).event_type == :target_rejected
    end

    test "accepts target with matching version", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "version ok"})

      assert {:ok, _run_id, _result} =
               Dispatcher.dispatch(HelloWorld, envelope,
                 aggregator: agg,
                 required_version: "0.1.0"
               )
    end

    test "accepts target with higher version", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "version higher ok"})

      assert {:ok, _run_id, _result} =
               Dispatcher.dispatch(HelloWorld, envelope,
                 aggregator: agg,
                 required_version: "0.0.1"
               )
    end

    test "rejects target missing required capabilities", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "cap check"})

      assert {:rejected, run_id, reason} =
               Dispatcher.dispatch(HelloWorld, envelope,
                 aggregator: agg,
                 required_capabilities: ["auth.oauth2", "triggers.webhook"]
               )

      assert reason =~ "capabilities"
      assert reason =~ "auth.oauth2"

      run = RunAggregator.get_run(agg, run_id)
      assert run.state == :rejected
      assert hd(run.events).event_type == :target_rejected
    end

    test "accepts target with matching capabilities", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "cap ok"})

      assert {:ok, _run_id, _result} =
               Dispatcher.dispatch(HelloWorld, envelope,
                 aggregator: agg,
                 required_capabilities: ["custom.protocol.ping"]
               )
    end
  end

  describe "policy denial with audit events" do
    test "shed policy blocks dispatch and produces policy_denied event", %{agg: agg} do
      envelope = Operation.Envelope.new("ping", %{"message" => "should be blocked"})

      assert {:rejected, run_id, reason} =
               Dispatcher.dispatch(HelloWorld, envelope,
                 aggregator: agg,
                 gateway_policies: [ShedPolicy]
               )

      assert reason =~ "shed"

      run = RunAggregator.get_run(agg, run_id)
      assert run.state == :rejected
      assert length(run.events) == 1

      event = hd(run.events)
      assert event.event_type == :policy_denied
      assert event.payload.reason =~ "shed"
      assert event.payload.connector_id == "example_ping"
      assert event.payload.operation_id == "ping"
    end

    test "policy denial emits telemetry audit event", %{agg: agg} do
      attach_ref = "policy-audit-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach(
          attach_ref,
          [:jido, :integration, :harness, :policy_denied],
          recipient: pid,
          include: [:event, :measurements, :metadata]
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      envelope = Operation.Envelope.new("ping", %{"message" => "audit test"})

      Dispatcher.dispatch(HelloWorld, envelope,
        aggregator: agg,
        gateway_policies: [ShedPolicy]
      )

      assert_receive {:telemetry, [:jido, :integration, :harness, :policy_denied], _,
                      %{connector_id: "example_ping", operation_id: "ping"}}
    end
  end

  describe "failed operation path" do
    test "unsupported operation produces dispatch_started + dispatch_failed", %{agg: agg} do
      envelope = Operation.Envelope.new("nonexistent_op", %{})

      # This will fail at the execute level (unknown operation)
      assert {:error, run_id, _error} =
               Dispatcher.dispatch(HelloWorld, envelope, aggregator: agg)

      # The dispatcher only emits events for steps it reaches.
      # Unknown operation fails at validate step in execute/3, before run/3.
      # So we get: no dispatch_started (execute fails before adapter.run is called)
      # Actually - the dispatcher emits dispatch_started BEFORE calling execute.
      # Then execute returns error, so we get dispatch_failed.
      run = RunAggregator.get_run(agg, run_id)
      assert run.state == :failed
      assert length(run.events) == 2

      [started, failed] = run.events
      assert started.event_type == :dispatch_started
      assert failed.event_type == :dispatch_failed
    end
  end

  describe "multiple concurrent runs" do
    test "tracks independent runs with separate state", %{agg: agg} do
      e1 = Operation.Envelope.new("ping", %{"message" => "run 1"})
      e2 = Operation.Envelope.new("ping", %{"message" => "run 2"})
      e3 = Operation.Envelope.new("ping", %{"message" => "run 3"})

      {:ok, id1, _} = Dispatcher.dispatch(HelloWorld, e1, aggregator: agg)
      {:ok, id2, _} = Dispatcher.dispatch(HelloWorld, e2, aggregator: agg)
      {:ok, id3, _} = Dispatcher.dispatch(HelloWorld, e3, aggregator: agg)

      # All three runs should be independent and succeeded
      assert RunAggregator.get_run(agg, id1).state == :succeeded
      assert RunAggregator.get_run(agg, id2).state == :succeeded
      assert RunAggregator.get_run(agg, id3).state == :succeeded

      runs = RunAggregator.list_runs(agg)
      assert length(runs) == 3
    end

    test "mixed outcomes: success + rejection + failure", %{agg: agg} do
      good = Operation.Envelope.new("ping", %{"message" => "works"})
      bad_version = Operation.Envelope.new("ping", %{"message" => "too old"})
      bad_policy = Operation.Envelope.new("ping", %{"message" => "blocked"})

      {:ok, id_good, _} = Dispatcher.dispatch(HelloWorld, good, aggregator: agg)

      {:rejected, id_version, _} =
        Dispatcher.dispatch(HelloWorld, bad_version,
          aggregator: agg,
          required_version: "99.0.0"
        )

      {:rejected, id_policy, _} =
        Dispatcher.dispatch(HelloWorld, bad_policy,
          aggregator: agg,
          gateway_policies: [ShedPolicy]
        )

      assert RunAggregator.get_run(agg, id_good).state == :succeeded
      assert RunAggregator.get_run(agg, id_version).state == :rejected
      assert RunAggregator.get_run(agg, id_policy).state == :rejected

      # All terminal
      assert RunAggregator.terminal?(agg, id_good)
      assert RunAggregator.terminal?(agg, id_version)
      assert RunAggregator.terminal?(agg, id_policy)
    end
  end

  describe "run event struct" do
    test "dedup_key returns the correct triple" do
      event = RunEvent.new(run_id: "r1", attempt_id: 2, seq: 3, event_type: :dispatch_started)
      assert RunEvent.dedup_key(event) == {"r1", 2, 3}
    end

    test "timestamp is set automatically" do
      event = RunEvent.new(run_id: "r1", attempt_id: 1, seq: 1, event_type: :dispatch_started)
      assert %DateTime{} = event.timestamp
    end
  end

  describe "dispatcher with Auth.Server credential resolution" do
    test "dispatches scoped operation with auth_server + resolved token", %{agg: agg, auth: auth} do
      # Set up connection with required scope
      {:ok, conn} = Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      # Store credential
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_harness_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["repo"]
        })

      {:ok, auth_ref} = Server.store_credential(auth, "scoped_test", conn.id, cred)
      :ok = Server.link_connection(auth, conn.id, auth_ref)

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "auth_dispatch"})

      assert {:ok, run_id, result} =
               Dispatcher.dispatch(ScopedTestAdapter, envelope,
                 aggregator: agg,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert result.result["result"] == "auth_dispatch"
      assert result.result["token_used"] == "gho_harness_token"

      run = RunAggregator.get_run(agg, run_id)
      assert run.state == :succeeded
    end

    test "dispatcher rejects scoped operation when scopes missing", %{agg: agg, auth: auth} do
      {:ok, conn} =
        Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["read:org"])

      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "blocked"})

      assert {:error, _run_id, error} =
               Dispatcher.dispatch(ScopedTestAdapter, envelope,
                 aggregator: agg,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert error.class == :auth_failed
    end
  end

  describe "aggregator state machine" do
    test "pending -> running -> succeeded", %{agg: agg} do
      e1 = RunEvent.new(run_id: "sm1", attempt_id: 1, seq: 1, event_type: :dispatch_started)
      e2 = RunEvent.new(run_id: "sm1", attempt_id: 1, seq: 2, event_type: :dispatch_succeeded)

      RunAggregator.append_event(agg, e1)
      assert RunAggregator.get_run(agg, "sm1").state == :running

      RunAggregator.append_event(agg, e2)
      assert RunAggregator.get_run(agg, "sm1").state == :succeeded
    end

    test "pending -> running -> failed", %{agg: agg} do
      e1 = RunEvent.new(run_id: "sm2", attempt_id: 1, seq: 1, event_type: :dispatch_started)
      e2 = RunEvent.new(run_id: "sm2", attempt_id: 1, seq: 2, event_type: :dispatch_failed)

      RunAggregator.append_event(agg, e1)
      RunAggregator.append_event(agg, e2)
      assert RunAggregator.get_run(agg, "sm2").state == :failed
    end

    test "pending -> rejected (policy)", %{agg: agg} do
      e1 = RunEvent.new(run_id: "sm3", attempt_id: 1, seq: 1, event_type: :policy_denied)

      RunAggregator.append_event(agg, e1)
      assert RunAggregator.get_run(agg, "sm3").state == :rejected
    end

    test "pending -> rejected (target)", %{agg: agg} do
      e1 = RunEvent.new(run_id: "sm4", attempt_id: 1, seq: 1, event_type: :target_rejected)

      RunAggregator.append_event(agg, e1)
      assert RunAggregator.get_run(agg, "sm4").state == :rejected
    end

    test "nonexistent run returns nil", %{agg: agg} do
      assert RunAggregator.get_run(agg, "does_not_exist") == nil
    end

    test "nonexistent run is not terminal", %{agg: agg} do
      refute RunAggregator.terminal?(agg, "does_not_exist")
    end
  end
end
