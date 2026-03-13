defmodule Jido.Integration.Auth.ServerTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Test.TelemetryHandler

  import Jido.Integration.Test.IsolatedSetup

  setup do
    {:ok, server} = start_isolated_auth_server()
    %{server: server}
  end

  # Block 4: Credential Operations

  describe "store_credential/4" do
    test "stores credential and returns auth_ref", %{server: server} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})

      assert {:ok, auth_ref} = Server.store_credential(server, "github", "org-123", cred)
      assert auth_ref == "auth:github:org-123"
    end

    test "overwrites existing credential at same ref", %{server: server} do
      {:ok, c1} = Credential.new(%{type: :api_key, key: "sk-old"})
      {:ok, c2} = Credential.new(%{type: :api_key, key: "sk-new"})

      {:ok, ref} = Server.store_credential(server, "github", "org-123", c1)
      {:ok, ^ref} = Server.store_credential(server, "github", "org-123", c2)

      {:ok, fetched} = Server.resolve_credential(server, ref, %{connector_id: "github"})
      assert fetched.key == "sk-new"
    end
  end

  describe "resolve_credential/3" do
    test "returns credential with matching scope", %{server: server} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc", scopes: ["read"]})
      {:ok, ref} = Server.store_credential(server, "github", "org-1", cred)

      assert {:ok, resolved} = Server.resolve_credential(server, ref, %{connector_id: "github"})
      assert resolved.key == "sk-abc"
    end

    test "returns scope_violation for mismatched connector_id", %{server: server} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      {:ok, ref} = Server.store_credential(server, "github", "org-1", cred)

      assert {:error, :scope_violation} =
               Server.resolve_credential(server, ref, %{connector_id: "linear"})
    end

    test "returns not_found for unknown ref", %{server: server} do
      assert {:error, :not_found} =
               Server.resolve_credential(server, "auth:nope:nope", %{connector_id: "nope"})
    end
  end

  describe "rotate_credential/3" do
    test "replaces credential at same auth_ref", %{server: server} do
      {:ok, old} = Credential.new(%{type: :api_key, key: "sk-old"})
      {:ok, new} = Credential.new(%{type: :api_key, key: "sk-new"})
      {:ok, ref} = Server.store_credential(server, "github", "org-1", old)

      assert :ok = Server.rotate_credential(server, ref, new)

      {:ok, resolved} = Server.resolve_credential(server, ref, %{connector_id: "github"})
      assert resolved.key == "sk-new"
    end

    test "rotate on unknown ref returns not_found", %{server: server} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-new"})
      assert {:error, :not_found} = Server.rotate_credential(server, "auth:nope:nope", cred)
    end
  end

  describe "revoke_credential/2" do
    test "removes credential", %{server: server} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      {:ok, ref} = Server.store_credential(server, "github", "org-1", cred)

      assert :ok = Server.revoke_credential(server, ref)

      assert {:error, :not_found} =
               Server.resolve_credential(server, ref, %{connector_id: "github"})
    end
  end

  describe "list_credentials/2" do
    test "lists credentials for connector type", %{server: server} do
      {:ok, c1} = Credential.new(%{type: :api_key, key: "sk-1"})
      {:ok, c2} = Credential.new(%{type: :api_key, key: "sk-2"})
      Server.store_credential(server, "github", "org-1", c1)
      Server.store_credential(server, "github", "org-2", c2)

      creds = Server.list_credentials(server, "github")
      assert length(creds) == 2
    end
  end

  describe "telemetry events for credentials" do
    test "store emits auth.install.succeeded", %{server: server} do
      attach_ref = "store-telemetry-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach(
          attach_ref,
          [:jido, :integration, :auth, :install, :succeeded],
          recipient: pid
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      Server.store_credential(server, "github", "org-1", cred)

      assert_receive {:telemetry, %{auth_ref: "auth:github:org-1", connector_id: "github"}}
    end

    test "revoke emits auth.revoked", %{server: server} do
      attach_ref = "revoke-telemetry-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach(
          attach_ref,
          [:jido, :integration, :auth, :revoked],
          recipient: pid
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      {:ok, auth_ref} = Server.store_credential(server, "github", "org-1", cred)
      Server.revoke_credential(server, auth_ref)

      assert_receive {:telemetry, %{auth_ref: "auth:github:org-1"}}
    end
  end

  # Block 5: Connection Lifecycle

  describe "create_connection/3" do
    test "creates connection in :new state", %{server: server} do
      assert {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      assert conn.connector_id == "github"
      assert conn.tenant_id == "tenant_1"
      assert conn.state == :new
    end
  end

  describe "get_connection/2" do
    test "returns stored connection", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      assert {:ok, fetched} = Server.get_connection(server, conn.id)
      assert fetched.id == conn.id
    end

    test "returns not_found for unknown id", %{server: server} do
      assert {:error, :not_found} = Server.get_connection(server, "conn_unknown")
    end
  end

  describe "transition_connection/4" do
    test "valid transition updates state", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      assert {:ok, conn2} = Server.transition_connection(server, conn.id, :installing, "user_1")
      assert conn2.state == :installing
    end

    test "invalid transition returns error", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      assert {:error, _} = Server.transition_connection(server, conn.id, :connected, "user_1")
    end

    test "transition persists in server state", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      {:ok, _} = Server.transition_connection(server, conn.id, :installing, "user_1")
      {:ok, fetched} = Server.get_connection(server, conn.id)
      assert fetched.state == :installing
    end
  end

  describe "check_connection_scopes/3" do
    test "passes when connection has required scopes", %{server: server} do
      {:ok, conn} =
        Server.create_connection(server, "github", "tenant_1", scopes: ["repo", "read:org"])

      assert :ok = Server.check_connection_scopes(server, conn.id, ["repo"])
    end

    test "fails with missing scopes", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1", scopes: ["read:org"])

      assert {:error, %{missing_scopes: missing}} =
               Server.check_connection_scopes(server, conn.id, ["repo", "read:org"])

      assert "repo" in missing
    end

    test "unknown connection returns not_found", %{server: server} do
      assert {:error, :not_found} =
               Server.check_connection_scopes(server, "conn_unknown", ["repo"])
    end

    test "blocked states are rejected", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1", scopes: ["repo"])
      {:ok, _} = Server.transition_connection(server, conn.id, :installing, "user_1")
      {:ok, _} = Server.transition_connection(server, conn.id, :connected, "system")
      {:ok, _} = Server.transition_connection(server, conn.id, :reauth_required, "system")

      assert {:error, {:blocked_state, :reauth_required}} =
               Server.check_connection_scopes(server, conn.id, ["repo"])
    end

    test "connector mismatches are rejected", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1", scopes: ["repo"])

      assert {:error, :connector_mismatch} =
               Server.check_connection_scopes(
                 server,
                 conn.id,
                 ["repo"],
                 connector_id: "scoped_test"
               )
    end
  end

  # Block 6: Token Refresh

  describe "resolve_credential with expired oauth2" do
    test "calls refresh callback and returns fresh token", %{server: server} do
      # Store expired oauth2 credential
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_expired",
          refresh_token: "ghr_valid",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second),
          scopes: ["repo"]
        })

      {:ok, ref} = Server.store_credential(server, "github", "org-refresh", cred)

      # Set refresh callback
      pid = self()

      refresh_fn = fn _auth_ref, refresh_token ->
        send(pid, {:refresh_called, refresh_token})

        {:ok,
         %{
           access_token: "gho_fresh",
           refresh_token: "ghr_new",
           expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
         }}
      end

      Server.set_refresh_callback(server, refresh_fn)

      # Resolve should trigger refresh
      assert {:ok, resolved} =
               Server.resolve_credential(server, ref, %{connector_id: "github"})

      assert resolved.access_token == "gho_fresh"
      assert_receive {:refresh_called, "ghr_valid"}
    end

    test "refresh failure transitions connection to reauth_required", %{server: server} do
      # Create connection + store expired credential
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      {:ok, _} = Server.transition_connection(server, conn.id, :installing, "u1")
      {:ok, _} = Server.transition_connection(server, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_expired",
          refresh_token: "ghr_invalid",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      {:ok, ref} = Server.store_credential(server, "github", "tenant_1", cred)

      # Link connection to auth_ref
      Server.link_connection(server, conn.id, ref)

      # Set failing refresh callback
      refresh_fn = fn _auth_ref, _refresh_token -> {:error, :invalid_grant} end
      Server.set_refresh_callback(server, refresh_fn)

      # Resolve should fail and transition connection
      assert {:error, :refresh_failed} =
               Server.resolve_credential(server, ref, %{connector_id: "github"})

      {:ok, updated_conn} = Server.get_connection(server, conn.id)
      assert updated_conn.state == :reauth_required
    end

    test "non-refreshable expired credential returns :expired", %{server: server} do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_expired",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      {:ok, ref} = Server.store_credential(server, "github", "org-norefresh", cred)

      assert {:error, :expired} =
               Server.resolve_credential(server, ref, %{connector_id: "github"})
    end

    test "transient refresh failures do not transition connection", %{server: server} do
      {:ok, conn} = Server.create_connection(server, "github", "tenant_1")
      {:ok, _} = Server.transition_connection(server, conn.id, :installing, "u1")
      {:ok, _} = Server.transition_connection(server, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_expired",
          refresh_token: "ghr_retryable",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      {:ok, ref} = Server.store_credential(server, "github", "tenant_1", cred)
      Server.link_connection(server, conn.id, ref)
      Server.set_refresh_callback(server, fn _auth_ref, _refresh_token -> {:error, :timeout} end)

      assert {:error, :refresh_retryable} =
               Server.resolve_credential(server, ref, %{connector_id: "github"})

      assert {:ok, updated_conn} = Server.get_connection(server, conn.id)
      assert updated_conn.state == :connected
    end

    test "refresh runs outside the main GenServer loop", %{server: server} do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_expired",
          refresh_token: "ghr_slow",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      {:ok, ref} = Server.store_credential(server, "github", "slow-refresh", cred)

      Server.set_refresh_callback(server, fn _auth_ref, _refresh_token ->
        Process.sleep(200)

        {:ok,
         %{
           access_token: "gho_fresh",
           refresh_token: "ghr_fresh",
           expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
         }}
      end)

      task =
        Task.async(fn -> Server.resolve_credential(server, ref, %{connector_id: "github"}) end)

      start = System.monotonic_time(:millisecond)
      assert [] = Server.list_credentials(server, "linear")
      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed < 100
      assert {:ok, %Credential{access_token: "gho_fresh"}} = Task.await(task, 1_000)
    end
  end

  describe "refresh telemetry" do
    test "emits auth.token.refreshed on success", %{server: server} do
      attach_ref = "refresh-ok-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach(
          attach_ref,
          [:jido, :integration, :auth, :token, :refreshed],
          recipient: pid
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_old",
          refresh_token: "ghr_ok",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      {:ok, ref} = Server.store_credential(server, "github", "org-tel", cred)

      refresh_fn = fn _ref, _rt ->
        {:ok,
         %{
           access_token: "gho_new",
           refresh_token: "ghr_new2",
           expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
         }}
      end

      Server.set_refresh_callback(server, refresh_fn)
      Server.resolve_credential(server, ref, %{connector_id: "github"})

      assert_receive {:telemetry, %{auth_ref: "auth:github:org-tel"}}
    end

    test "emits auth.token.refresh_failed on failure", %{server: server} do
      attach_ref = "refresh-fail-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach(
          attach_ref,
          [:jido, :integration, :auth, :token, :refresh_failed],
          recipient: pid
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_old",
          refresh_token: "ghr_fail",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      {:ok, ref} = Server.store_credential(server, "github", "org-telfail", cred)

      refresh_fn = fn _ref, _rt -> {:error, :invalid_grant} end
      Server.set_refresh_callback(server, refresh_fn)
      Server.resolve_credential(server, ref, %{connector_id: "github"})

      assert_receive {:telemetry,
                      %{
                        auth_ref: "auth:github:org-telfail",
                        reason: "invalid_grant",
                        failure_class: :terminal
                      }}
    end
  end

  describe "install lifecycle" do
    test "start_install creates an installing connection and returns session state", %{
      server: server
    } do
      assert {:ok, result} =
               Server.start_install(server, "github", "tenant_install",
                 scopes: ["repo", "read:org"],
                 actor_id: "user_1",
                 auth_base_url: "https://github.example/oauth"
               )

      assert result.auth_url =~ "state="
      assert result.auth_url =~ "tenant_install"
      assert is_binary(result.session_state["state"])
      assert result.session_state["connector_id"] == "github"

      assert {:ok, conn} = Server.get_connection(server, result.connection_id)
      assert conn.state == :installing
      assert conn.scopes == ["repo", "read:org"]
    end

    test "handle_callback validates state and persists the credential", %{server: server} do
      {:ok, install} =
        Server.start_install(server, "github", "tenant_install",
          scopes: ["repo", "read:org"],
          actor_id: "user_1"
        )

      params = %{
        "state" => install.session_state["state"],
        "credential" => %{
          access_token: "gho_live",
          refresh_token: "ghr_live",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        },
        "granted_scopes" => ["repo", "read:org", "admin:org"],
        "actor_id" => "system:callback"
      }

      assert {:ok, %{connection_id: connection_id, state: :connected, auth_ref: auth_ref}} =
               Server.handle_callback(server, "github", params, install.session_state)

      assert auth_ref == "auth:github:#{connection_id}"

      assert {:ok, conn} = Server.get_connection(server, connection_id)
      assert conn.state == :connected
      assert conn.auth_ref == auth_ref
      assert conn.scopes == ["repo", "read:org"]

      assert {:ok, resolved} =
               Server.resolve_credential(server, auth_ref, %{connector_id: "github"})

      assert resolved.access_token == "gho_live"
      assert resolved.scopes == ["repo", "read:org"]
    end

    test "handle_callback keeps auth refs unique across multiple installs for one tenant", %{
      server: server
    } do
      {:ok, install_one} = Server.start_install(server, "github", "tenant_install")
      {:ok, install_two} = Server.start_install(server, "github", "tenant_install")

      params_for = fn install, token ->
        %{
          "state" => install.session_state["state"],
          "credential" => %{
            access_token: token,
            refresh_token: "#{token}_refresh",
            expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
          }
        }
      end

      assert {:ok, %{connection_id: conn_one, auth_ref: ref_one}} =
               Server.handle_callback(
                 server,
                 "github",
                 params_for.(install_one, "gho_install_one"),
                 install_one.session_state
               )

      assert {:ok, %{connection_id: conn_two, auth_ref: ref_two}} =
               Server.handle_callback(
                 server,
                 "github",
                 params_for.(install_two, "gho_install_two"),
                 install_two.session_state
               )

      assert conn_one != conn_two
      assert ref_one == "auth:github:#{conn_one}"
      assert ref_two == "auth:github:#{conn_two}"
      refute ref_one == ref_two
    end

    test "handle_callback rejects reused or unknown state tokens", %{server: server} do
      {:ok, install} = Server.start_install(server, "github", "tenant_install")

      params = %{
        "state" => install.session_state["state"],
        "credential" => %{access_token: "gho_live"}
      }

      assert {:ok, _} = Server.handle_callback(server, "github", params, install.session_state)

      assert {:error, :invalid_state_token} =
               Server.handle_callback(server, "github", params, install.session_state)
    end
  end
end
