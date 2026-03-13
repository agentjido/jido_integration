defmodule Jido.Integration.Examples.HelloWorldTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.{Conformance, Operation, Registry}
  alias Jido.Integration.Examples.HelloWorld
  alias Jido.Integration.Test.TelemetryHandler

  describe "adapter contract" do
    test "id returns a string" do
      assert HelloWorld.id() == "example_ping"
    end

    test "manifest returns a valid Manifest struct" do
      manifest = HelloWorld.manifest()
      assert %Jido.Integration.Manifest{} = manifest
      assert manifest.id == "example_ping"
      assert manifest.domain == "protocol"
      assert manifest.quality_tier == "bronze"
      assert length(manifest.operations) == 1
      assert hd(manifest.operations).id == "ping"
    end

    test "validate_config accepts maps" do
      assert {:ok, %{"key" => "val"}} = HelloWorld.validate_config(%{"key" => "val"})
    end

    test "validate_config rejects non-maps" do
      assert {:error, _} = HelloWorld.validate_config("nope")
    end

    test "health returns healthy" do
      assert {:ok, %{status: :healthy}} = HelloWorld.health([])
    end
  end

  describe "ping operation" do
    test "echoes message with connector metadata" do
      {:ok, result} = HelloWorld.run("ping", %{"message" => "hello world"}, [])
      assert result["echo"] == "hello world"
      assert result["connector_id"] == "example_ping"
      assert result["tenant_id"] == "unknown"
    end

    test "includes tenant_id from opts" do
      {:ok, result} = HelloWorld.run("ping", %{"message" => "hi"}, tenant_id: "tenant_42")
      assert result["tenant_id"] == "tenant_42"
    end

    test "rejects unknown operations" do
      assert {:error, %Jido.Integration.Error{class: :unsupported}} =
               HelloWorld.run("nope", %{}, [])
    end
  end

  describe "execute pipeline" do
    test "full execute with valid envelope" do
      envelope = Operation.Envelope.new("ping", %{"message" => "test"})
      assert {:ok, result} = Jido.Integration.execute(HelloWorld, envelope)
      assert result.status == :ok
      assert result.result["echo"] == "test"
      assert result.result["connector_id"] == "example_ping"
    end

    test "execute rejects invalid input (missing message)" do
      envelope = Operation.Envelope.new("ping", %{})

      assert {:error, %Jido.Integration.Error{class: :invalid_request}} =
               Jido.Integration.execute(HelloWorld, envelope)
    end

    test "execute rejects unknown operation" do
      envelope = Operation.Envelope.new("nonexistent", %{})

      assert {:error, %Jido.Integration.Error{class: :invalid_request}} =
               Jido.Integration.execute(HelloWorld, envelope)
    end
  end

  describe "registry" do
    setup do
      {:ok, reg} = Registry.start_link(name: :"hello_world_reg_#{System.unique_integer()}")
      %{registry: reg}
    end

    test "register and lookup", %{registry: reg} do
      assert :ok = Registry.register(HelloWorld, server: reg)
      assert {:ok, HelloWorld} = Registry.lookup("example_ping", server: reg)
    end

    test "listed after registration", %{registry: reg} do
      :ok = Registry.register(HelloWorld, server: reg)
      entries = Registry.list(server: reg)
      assert length(entries) == 1
      assert hd(entries).id == "example_ping"
    end
  end

  describe "conformance" do
    test "passes mvp_foundation" do
      report = Conformance.run(HelloWorld, profile: :mvp_foundation)
      assert report.pass_fail == :pass
      assert report.connector_id == "example_ping"
      assert report.quality_tier_eligible == "bronze"
    end

    test "passes bronze" do
      report = Conformance.run(HelloWorld, profile: :bronze)
      assert report.pass_fail == :pass
    end

    test "passes silver" do
      report = Conformance.run(HelloWorld, profile: :silver)
      assert report.pass_fail == :pass
    end

    test "conformance report is JSON-serializable" do
      report = Conformance.run(HelloWorld, profile: :bronze)
      assert {:ok, json} = Jason.encode(report)
      assert is_binary(json)
      decoded = Jason.decode!(json)
      assert decoded["pass_fail"] == "pass"
      assert decoded["connector_id"] == "example_ping"
    end
  end

  describe "telemetry" do
    test "emits operation started and succeeded events" do
      attach_ref = "hello-world-test-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach_many(
          attach_ref,
          [
            [:jido, :integration, :operation, :started],
            [:jido, :integration, :operation, :succeeded]
          ],
          recipient: pid,
          include: [:event, :measurements, :metadata]
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      envelope = Operation.Envelope.new("ping", %{"message" => "telemetry test"})
      {:ok, _result} = Jido.Integration.execute(HelloWorld, envelope)

      assert_receive {:telemetry, [:jido, :integration, :operation, :started], _,
                      %{connector_id: "example_ping"}}

      assert_receive {:telemetry, [:jido, :integration, :operation, :succeeded], _,
                      %{connector_id: "example_ping"}}
    end
  end
end
