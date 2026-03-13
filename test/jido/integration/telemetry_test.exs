defmodule Jido.Integration.TelemetryTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Telemetry

  describe "standard_events/0" do
    test "returns non-empty list" do
      events = Telemetry.standard_events()
      assert [_ | _] = events
    end

    test "all events follow naming standard" do
      for event <- Telemetry.standard_events() do
        assert Telemetry.valid_event?(event), "Event #{event} should be valid"
      end
    end

    test "includes operation events" do
      events = Telemetry.standard_events()
      assert "jido.integration.operation.started" in events
      assert "jido.integration.operation.succeeded" in events
      assert "jido.integration.operation.failed" in events
    end

    test "includes auth events" do
      events = Telemetry.standard_events()
      assert "jido.integration.auth.install.started" in events
      assert "jido.integration.auth.install.succeeded" in events
      assert "jido.integration.auth.revoked" in events
    end

    test "includes webhook events" do
      events = Telemetry.standard_events()
      assert "jido.integration.webhook.received" in events
      assert "jido.integration.webhook.routed" in events
      assert "jido.integration.webhook.signature_failed" in events
    end

    test "includes registry events" do
      events = Telemetry.standard_events()
      assert "jido.integration.registry.registered" in events
    end

    test "includes gateway events" do
      events = Telemetry.standard_events()
      assert "jido.integration.gateway.admitted" in events
      assert "jido.integration.gateway.shed" in events
    end

    test "includes canonical dispatch transport and run execution events" do
      events = Telemetry.standard_events()

      assert "jido.integration.dispatch.enqueued" in events
      assert "jido.integration.dispatch.delivered" in events
      assert "jido.integration.dispatch.retry" in events
      assert "jido.integration.dispatch.dead_lettered" in events
      assert "jido.integration.dispatch.replayed" in events

      assert "jido.integration.run.accepted" in events
      assert "jido.integration.run.started" in events
      assert "jido.integration.run.succeeded" in events
      assert "jido.integration.run.failed" in events
      assert "jido.integration.run.dead_lettered" in events
    end

    test "does not treat legacy dispatch_stub events as the public standard contract" do
      refute "jido.integration.dispatch_stub.accepted" in Telemetry.standard_events()
    end
  end

  describe "valid_event?/1" do
    test "accepts events with valid prefixes" do
      assert Telemetry.valid_event?("jido.integration.operation.custom")
      assert Telemetry.valid_event?("jido.integration.auth.custom")
      assert Telemetry.valid_event?("jido.integration.webhook.custom")
      assert Telemetry.valid_event?("jido.integration.dispatch.custom")
      assert Telemetry.valid_event?("jido.integration.run.custom")
      assert Telemetry.valid_event?("jido.integration.dispatch_stub.accepted")
    end

    test "rejects events outside namespace" do
      refute Telemetry.valid_event?("jido.core.something")
      refute Telemetry.valid_event?("other.namespace.event")
      refute Telemetry.valid_event?("jido.integration")
    end
  end

  describe "standard_event?/1" do
    test "recognizes standard events" do
      assert Telemetry.standard_event?("jido.integration.operation.started")
      assert Telemetry.standard_event?("jido.integration.dispatch.enqueued")
      assert Telemetry.standard_event?("jido.integration.run.accepted")
    end

    test "rejects non-standard events" do
      refute Telemetry.standard_event?("jido.integration.operation.custom_thing")
      refute Telemetry.standard_event?("jido.integration.dispatch_stub.accepted")
    end
  end

  describe "emit/3" do
    test "emits standard events safely" do
      handler_id = "telemetry-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:jido, :integration, :operation, :started],
          &__MODULE__.handle_operation_started/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok =
               Telemetry.emit("jido.integration.operation.started", %{count: 1}, %{
                 connector_id: "x"
               })

      assert_receive {:telemetry_event, [:jido, :integration, :operation, :started], %{count: 1},
                      %{connector_id: "x"}}
    end

    test "accepts transitional legacy dispatch_stub alias events for migration" do
      handler_id = "legacy-telemetry-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:jido, :integration, :dispatch_stub, :accepted],
          &__MODULE__.handle_operation_started/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok =
               Telemetry.emit("jido.integration.dispatch_stub.accepted", %{}, %{
                 dispatch_id: "d_legacy"
               })

      assert_receive {:telemetry_event, [:jido, :integration, :dispatch_stub, :accepted], %{},
                      %{dispatch_id: "d_legacy"}}
    end

    test "rejects invalid event names without creating telemetry events" do
      assert {:error, error} = Telemetry.emit("jido.integration.operation.dynamic.user_input")
      assert error.class == :invalid_request
    end
  end

  def handle_operation_started(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end
end
