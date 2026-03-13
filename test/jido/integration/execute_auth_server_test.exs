defmodule Jido.Integration.ExecuteAuthServerTest do
  @moduledoc """
  Execution-path tests for Auth.Server integration.
  """
  use ExUnit.Case, async: true

  defmodule CredentialAwareAdapter do
    @behaviour Jido.Integration.Adapter

    alias Jido.Integration.{Error, Manifest}

    @impl true
    def id, do: "credential_aware"

    @impl true
    def manifest do
      Manifest.new!(%{
        "id" => id(),
        "display_name" => "Credential Aware Adapter",
        "vendor" => "Test",
        "domain" => "saas",
        "version" => "0.1.0",
        "quality_tier" => "bronze",
        "telemetry_namespace" => "jido.integration.credential_aware",
        "auth" => [
          %{
            "id" => "api_key",
            "type" => "api_key",
            "display_name" => "API Key",
            "secret_refs" => [],
            "scopes" => ["repo"],
            "rotation_policy" => %{"required" => false, "interval_days" => nil},
            "tenant_binding" => "tenant_only",
            "health_check" => %{"enabled" => false, "interval_s" => 0}
          }
        ],
        "operations" => [
          %{
            "id" => "credential_op",
            "summary" => "Echo resolved credential details",
            "input_schema" => %{
              "type" => "object",
              "required" => ["data"],
              "properties" => %{"data" => %{"type" => "string"}}
            },
            "output_schema" => %{
              "type" => "object",
              "required" => ["result", "token_used", "credential_type"],
              "properties" => %{
                "result" => %{"type" => "string"},
                "token_used" => %{"type" => "string"},
                "credential_type" => %{"type" => "string"}
              }
            },
            "errors" => [],
            "idempotency" => "none",
            "timeout_ms" => 5_000,
            "rate_limit" => "gateway_default",
            "required_scopes" => ["repo"]
          }
        ]
      })
    end

    @impl true
    def validate_config(config), do: {:ok, config}

    @impl true
    def health(_opts), do: {:ok, %{status: :healthy}}

    @impl true
    def run("credential_op", %{"data" => data}, opts) do
      credential = Keyword.fetch!(opts, :credential)

      {:ok,
       %{
         "result" => data,
         "token_used" => Keyword.get(opts, :token, "missing"),
         "credential_type" => credential.type |> to_string()
       }}
    end

    def run(op, _args, _opts) do
      {:error, Error.new(:unsupported, "Unknown operation: #{op}")}
    end
  end

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Operation
  alias Jido.Integration.Test.{ScopedTestAdapter, TestAuthBridge}

  import Jido.Integration.Test.IsolatedSetup

  setup do
    {:ok, auth} = start_isolated_auth_server()
    %{auth: auth}
  end

  describe "execute/3 with auth_server option" do
    test "uses Auth.Server for scope checking when connection has scopes", %{auth: auth} do
      {:ok, conn} = Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "hello"})

      assert {:ok, result} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert result.result["result"] == "hello"
    end

    test "blocks operation when scopes missing via Auth.Server", %{auth: auth} do
      {:ok, conn} =
        Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["read:org"])

      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "hello"})

      assert {:error, error} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert error.class == :auth_failed
      assert error.message =~ "Missing required scopes"
    end

    test "blocks execution for revoked connections", %{auth: auth} do
      {:ok, conn} = Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")
      {:ok, _} = Server.transition_connection(auth, conn.id, :revoked, "user")

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "blocked"})

      assert {:error, error} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert error.class == :auth_failed
      assert error.code == "auth.connection_blocked"
    end

    test "rejects connector mismatches before dispatch", %{auth: auth} do
      {:ok, conn} = Server.create_connection(auth, "github", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "wrong_connector"})

      assert {:error, error} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert error.class == :auth_failed
      assert error.code == "auth.connector_mismatch"
    end

    test "resolves token from envelope.auth_ref and passes it to run/3", %{auth: auth} do
      {:ok, conn} = Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_resolved_token_xyz",
          refresh_token: "ghr_refresh",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["repo"]
        })

      {:ok, auth_ref} = Server.store_credential(auth, "scoped_test", "tenant_1", cred)

      envelope =
        Operation.Envelope.new("scoped_op", %{"data" => "with_token"}, auth_ref: auth_ref)

      assert {:ok, result} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert result.result["result"] == "with_token"
      assert result.result["token_used"] == "gho_resolved_token_xyz"
    end

    test "resolves auth_ref from the linked connection when the caller omits it", %{auth: auth} do
      {:ok, conn} = Server.create_connection(auth, "scoped_test", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_connected_token",
          refresh_token: "ghr_refresh",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["repo"]
        })

      {:ok, auth_ref} = Server.store_credential(auth, "scoped_test", conn.id, cred)
      :ok = Server.link_connection(auth, conn.id, auth_ref)

      envelope = Operation.Envelope.new("scoped_op", %{"data" => "from_connection"})

      assert {:ok, result} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert result.result["result"] == "from_connection"
      assert result.result["token_used"] == "gho_connected_token"
    end

    test "normalizes non-oauth credentials through Credential.secret_value/1", %{auth: auth} do
      {:ok, conn} =
        Server.create_connection(auth, "credential_aware", "tenant_1", scopes: ["repo"])

      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :api_key,
          key: "api_key_live_123",
          scopes: ["repo"]
        })

      {:ok, auth_ref} = Server.store_credential(auth, "credential_aware", conn.id, cred)
      :ok = Server.link_connection(auth, conn.id, auth_ref)

      envelope = Operation.Envelope.new("credential_op", %{"data" => "with_api_key"})

      assert {:ok, result} =
               Jido.Integration.execute(CredentialAwareAdapter, envelope,
                 auth_server: auth,
                 connection_id: conn.id
               )

      assert result.result["token_used"] == "api_key_live_123"
      assert result.result["credential_type"] == "api_key"
    end

    test "unscoped operation skips auth entirely even with auth_server present", %{auth: auth} do
      envelope = Operation.Envelope.new("unscoped_op", %{"data" => "no_auth_needed"})

      assert {:ok, result} =
               Jido.Integration.execute(ScopedTestAdapter, envelope, auth_server: auth)

      assert result.result["result"] == "no_auth_needed"
    end

    test "returns error when connection_id missing for scoped operation with auth_server", %{
      auth: auth
    } do
      envelope = Operation.Envelope.new("scoped_op", %{"data" => "missing_conn"})

      assert {:error, error} =
               Jido.Integration.execute(ScopedTestAdapter, envelope, auth_server: auth)

      assert error.class == :auth_failed
      assert error.code == "auth.context_required"
    end
  end

  describe "auth option validation" do
    test "rejects auth_server and auth_bridge together", %{auth: auth} do
      envelope = Operation.Envelope.new("unscoped_op", %{"data" => "bad_opts"})

      assert {:error, error} =
               Jido.Integration.execute(ScopedTestAdapter, envelope,
                 auth_server: auth,
                 auth_bridge: TestAuthBridge
               )

      assert error.class == :invalid_request
      assert error.code == "auth.conflicting_context"
    end
  end
end
