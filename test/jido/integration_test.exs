defmodule Jido.IntegrationTest do
  @moduledoc """
  Integration tests — end-to-end validation of the control plane.

  Tests the full flow: register adapter, look up, create envelope,
  execute operation, verify results.
  """
  use ExUnit.Case

  alias Jido.Integration
  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.{Operation, Registry}
  alias Jido.Integration.Test.{ScopedTestAdapter, TestAdapter}

  import Jido.Integration.Test.IsolatedSetup

  setup do
    registry = :"integration_registry_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Registry.start_link(name: registry)
    {:ok, auth} = start_isolated_auth_server()

    %{registry: registry, auth: auth}
  end

  describe "end-to-end: TestAdapter" do
    test "register, lookup, execute", %{registry: registry} do
      :ok = Registry.register(TestAdapter, server: registry)

      {:ok, adapter} = Registry.lookup("test_adapter", server: registry)
      assert adapter == TestAdapter

      envelope = Operation.Envelope.new("test.ping", %{"echo" => "hello"})
      assert envelope.operation_id == "test.ping"

      {:ok, result} = Integration.execute(adapter, envelope)
      assert result.status == :ok
      assert result.result["pong"] == true
    end

    test "rejects unknown operation", %{registry: registry} do
      :ok = Registry.register(TestAdapter, server: registry)
      {:ok, adapter} = Registry.lookup("test_adapter", server: registry)

      envelope = Operation.Envelope.new("unknown.operation")
      assert {:error, error} = Integration.execute(adapter, envelope)
      assert error.class == :invalid_request
    end
  end

  describe "end-to-end: ScopedTestAdapter" do
    test "executes a scoped operation via the auth server", %{registry: registry, auth: auth} do
      :ok = Registry.register(ScopedTestAdapter, server: registry)
      {:ok, adapter} = Registry.lookup("scoped_test", server: registry)

      {:ok, conn} =
        Server.create_connection(auth, ScopedTestAdapter.id(), "tenant_1", scopes: ["repo"])

      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user_1")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "scoped_token_123",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, auth_ref} = Server.store_credential(auth, ScopedTestAdapter.id(), conn.id, cred)
      :ok = Server.link_connection(auth, conn.id, auth_ref)

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "hello"})

      {:ok, result} =
        Integration.execute(adapter, envelope,
          auth_server: auth,
          connection_id: conn.id
        )

      assert result.status == :ok
      assert result.result["result"] == "hello"
      assert result.result["token_used"] == "scoped_token_123"
    end

    test "rejects execution when connection scopes are insufficient", %{
      registry: registry,
      auth: auth
    } do
      :ok = Registry.register(ScopedTestAdapter, server: registry)
      {:ok, adapter} = Registry.lookup("scoped_test", server: registry)

      {:ok, conn} =
        Server.create_connection(auth, ScopedTestAdapter.id(), "tenant_1", scopes: ["read:org"])

      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user_1")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "hello"})

      assert {:error, error} =
               Integration.execute(adapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert error.class == :auth_failed
      assert error.code == "auth.missing_scopes"
    end
  end

  describe "list_connectors/0" do
    test "lists registered connectors via default registry" do
      connectors = Integration.list_connectors()
      assert is_list(connectors)
    end
  end
end
