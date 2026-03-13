defmodule Jido.Integration.Auth.BridgeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Test.TestAuthBridge

  describe "start_install/3" do
    test "returns the runtime-shaped install response" do
      assert {:ok, result} = TestAuthBridge.start_install("github", "tenant_1", %{})
      assert is_binary(result.auth_url)
      assert result.auth_url =~ "github"
      assert is_binary(result.connection_id)
      assert String.starts_with?(result.connection_id, "conn_")
      assert is_map(result.session_state)
      assert result.session_state["connector_id"] == "github"
      assert result.session_state["tenant_id"] == "tenant_1"
      assert result.session_state["connection_id"] == result.connection_id
    end
  end

  describe "handle_callback/3" do
    test "returns the runtime-shaped callback result" do
      {:ok, %{session_state: state}} =
        TestAuthBridge.start_install("github", "tenant_1", %{})

      assert {:ok, result} =
               TestAuthBridge.handle_callback("github", %{"code" => "abc123"}, state)

      assert is_binary(result.connection_id)
      assert result.connection_id == state["connection_id"]
      assert result.state == :connected
      assert result.auth_ref == "auth:github:#{state["connection_id"]}"
    end

    test "fails without code" do
      assert {:error, :missing_code} =
               TestAuthBridge.handle_callback("github", %{}, %{})
    end
  end

  describe "get_token/1" do
    test "returns an opaque handle for a runtime-managed connection" do
      assert {:ok, result} = TestAuthBridge.get_token("conn_test")
      assert result.auth_ref == "auth:test:conn_test"
      assert is_binary(result.token_ref)
      assert result.token_ref == result.auth_ref
      assert %DateTime{} = result.expires_at
    end
  end

  describe "revoke/2" do
    test "revokes successfully" do
      assert :ok = TestAuthBridge.revoke("conn_test", "test revocation")
    end
  end

  describe "connection_health/1" do
    test "returns healthy status" do
      assert {:ok, result} = TestAuthBridge.connection_health("conn_test")
      assert result.status == :healthy
    end
  end

  describe "check_scopes/2" do
    test "passes when scopes are available" do
      Process.put(:test_scopes, ["repo", "read:org"])
      assert :ok = TestAuthBridge.check_scopes("conn_test", ["repo"])
    end

    test "fails when scopes are missing" do
      Process.put(:test_scopes, ["read:org"])

      assert {:error, %{missing_scopes: missing}} =
               TestAuthBridge.check_scopes("conn_test", ["repo", "read:org"])

      assert "repo" in missing
    end
  end
end
