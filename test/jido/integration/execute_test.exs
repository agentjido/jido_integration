defmodule Jido.Integration.Test.BackoffPolicy do
  @moduledoc false
  @behaviour Jido.Integration.Gateway.Policy

  @impl true
  def partition_key(_envelope), do: :default

  @impl true
  def capacity(_partition), do: {:tokens, 1}

  @impl true
  def on_pressure(_partition, _pressure), do: :backoff
end

defmodule Jido.Integration.ExecuteTest do
  use ExUnit.Case, async: true

  alias Jido.Integration
  alias Jido.Integration.Operation.Envelope

  alias Jido.Integration.Test.{
    BackoffPolicy,
    BadResultAdapter,
    CrashyAdapter,
    ScopedAdapter,
    TestAuthBridge
  }

  setup do
    Process.delete(:scoped_adapter_ran)
    :ok
  end

  describe "execute/3" do
    test "validates input against the manifest schema before invoking the adapter" do
      envelope = Envelope.new("scoped.read", %{})

      assert {:error, error} =
               Integration.execute(ScopedAdapter, envelope,
                 auth_bridge: TestAuthBridge,
                 connection_id: "conn_1"
               )

      assert error.class == :invalid_request
      refute Process.get(:scoped_adapter_ran)
    end

    test "rejects scoped operations without auth context" do
      envelope = Envelope.new("scoped.read", %{"resource_id" => "res_1"})

      assert {:error, error} = Integration.execute(ScopedAdapter, envelope)
      assert error.class == :auth_failed
    end

    test "normalizes scope denials into taxonomy errors" do
      Process.put(:test_scopes, [])

      envelope = Envelope.new("scoped.read", %{"resource_id" => "res_1"})

      assert {:error, error} =
               Integration.execute(ScopedAdapter, envelope,
                 auth_bridge: TestAuthBridge,
                 connection_id: "conn_1"
               )

      assert error.class == :auth_failed
      assert error.upstream_context["missing_scopes"] == ["repo"]
    end

    test "applies gateway policies before invoking the adapter" do
      Process.put(:test_scopes, ["repo"])
      envelope = Envelope.new("scoped.read", %{"resource_id" => "res_1"})

      assert {:error, error} =
               Integration.execute(ScopedAdapter, envelope,
                 auth_bridge: TestAuthBridge,
                 connection_id: "conn_1",
                 gateway_policies: [BackoffPolicy]
               )

      assert error.class == :rate_limited
      refute Process.get(:scoped_adapter_ran)
    end

    test "normalizes adapter exceptions into internal errors" do
      envelope = Envelope.new("crashy.run", %{})

      assert {:error, error} = Integration.execute(CrashyAdapter, envelope)
      assert error.class == :internal
      assert error.code == "connector.execution_failed"
    end

    test "validates adapter results against the manifest output schema" do
      envelope = Envelope.new("bad_result.run", %{})

      assert {:error, error} = Integration.execute(BadResultAdapter, envelope)
      assert error.class == :internal
      assert error.code == "connector.invalid_result"
    end
  end
end
