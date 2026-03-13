defmodule Jido.Integration.Examples.GitHubAuthLifecycle do
  @moduledoc """
  Live example: Full GitHub OAuth credential lifecycle.

  Demonstrates the complete auth flow using real tokens:

  1. Create connection for tenant
  2. Transition through install states (new -> installing -> connected)
  3. Store real OAuth credential with scope enforcement
  4. Resolve credential at operation time (with scope check)
  5. Verify manifest contract
  6. Handle token expiry with transparent refresh
  7. Handle refresh failure -> reauth_required transition
  8. Prove restart-safe callback recovery with consume-once semantics

  ## Running

      cd packages/connectors/github
      MIX_ENV=test mix run -e "
        {:ok, auth} = Jido.Integration.Auth.Server.start_link(name: nil)
        Jido.Integration.Examples.GitHubAuthLifecycle.run(auth)
        |> IO.inspect(label: :result)
      "

  No mocks. Uses real tokens from `gh auth token` or GITHUB_TOKEN.

  This example talks directly to `Auth.Server` because it proves the canonical
  lifecycle engine in isolation. In a production host app, `Auth.Bridge` would
  own the browser or callback boundary and delegate into the same server calls.
  The callback correlation state itself lives in the install-session store, so
  successful callback handling does not depend on the original server process
  staying alive.
  """

  alias Jido.Integration.Auth.{ConnectionStore, Credential, InstallSessionStore, Server, Store}
  alias Jido.Integration.Connectors.GitHub

  @doc """
  Resolve a GitHub token from GITHUB_TOKEN env var or `gh auth token`.
  """
  def resolve_token! do
    case System.get_env("GITHUB_TOKEN") do
      token when is_binary(token) and token != "" ->
        token

      _ ->
        case System.cmd("gh", ["auth", "token"], stderr_to_stdout: true) do
          {token, 0} -> String.trim(token)
          _ -> raise "No GitHub token. Set GITHUB_TOKEN or run `gh auth login`."
        end
    end
  end

  @doc """
  Run the full lifecycle demo against a dedicated Auth.Server instance.
  Uses a real GitHub token and returns the same lifecycle artifacts a host
  bridge would surface from the runtime. The returned `session_state` is just
  the host-visible callback payload for a durable install-session record.
  """
  def run(auth_server) do
    token = resolve_token!()

    {:ok, install} =
      Server.start_install(auth_server, "github", "acme-corp",
        scopes: ["repo", "read:org"],
        actor_id: "admin@acme.com"
      )

    {:ok, %{connection_id: connection_id, auth_ref: auth_ref}} =
      Server.handle_callback(
        auth_server,
        "github",
        %{
          "state" => install.session_state["state"],
          "credential" => %{
            access_token: token,
            expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
          },
          "granted_scopes" => ["repo", "read:org", "admin:org"],
          "actor_id" => "system:callback"
        },
        install.session_state
      )

    {:ok, conn} = Server.get_connection(auth_server, connection_id)
    {:ok, resolved} = Server.resolve_credential(auth_server, auth_ref, %{connector_id: "github"})

    {:error, :scope_violation} =
      Server.resolve_credential(auth_server, auth_ref, %{connector_id: "linear"})

    :ok = Server.check_connection_scopes(auth_server, conn.id, ["repo"])

    {:error, %{missing_scopes: _}} =
      Server.check_connection_scopes(auth_server, conn.id, ["admin"])

    manifest = GitHub.manifest()

    %{
      connection_id: conn.id,
      connection_state: conn.state,
      auth_ref: auth_ref,
      resolved_token_type: resolved.type,
      manifest_id: manifest.id,
      scopes: resolved.scopes,
      connection_revision: conn.revision,
      audit_trail_length: length(conn.actor_trail)
    }
  end

  @doc """
  Demonstrate restart-safe callback recovery and duplicate callback rejection.

  This boots a disk-backed `Auth.Server`, starts install, kills the server,
  restarts it against the same store files, completes the callback, and proves
  the same callback cannot be consumed twice.
  """
  def demo_restart_recovery(tmp_dir) do
    token = resolve_token!()
    opts = durable_auth_opts(tmp_dir)

    {:ok, auth_server} = Server.start_link(opts)

    {:ok, install} =
      Server.start_install(auth_server, "github", "restart-demo",
        scopes: ["repo", "read:org"],
        actor_id: "admin@acme.com"
      )

    restart_server!(auth_server, opts)
    {:ok, restarted} = Server.start_link(opts)

    params = %{
      "state" => install.session_state["state"],
      "credential" => %{
        access_token: token,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      },
      "granted_scopes" => ["repo", "read:org"],
      "actor_id" => "system:callback"
    }

    {:ok, %{connection_id: connection_id, auth_ref: auth_ref, state: connection_state}} =
      Server.handle_callback(restarted, "github", params, install.session_state)

    duplicate_callback_result =
      Server.handle_callback(restarted, "github", params, install.session_state)

    {:ok, conn} = Server.get_connection(restarted, connection_id)

    %{
      connection_id: connection_id,
      connection_state: connection_state,
      auth_ref: auth_ref,
      callback_recovered_after_restart: true,
      duplicate_callback_result: duplicate_callback_result,
      audit_trail_length: length(conn.actor_trail)
    }
  end

  @doc """
  Demonstrate token refresh flow.

  Stores an expired credential, sets a refresh callback that returns
  the real token (in production this would call GitHub's OAuth token
  endpoint), and verifies the Auth.Server transparently refreshes.
  """
  def demo_refresh(auth_server) do
    token = resolve_token!()

    {:ok, cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: "expired_placeholder",
        refresh_token: "refresh_placeholder",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    {:ok, auth_ref} = Server.store_credential(auth_server, "github", "refresh-demo", cred)

    Server.set_refresh_callback(auth_server, fn _ref, _refresh_token ->
      {:ok,
       %{
         access_token: token,
         refresh_token: "refreshed_rt",
         expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
       }}
    end)

    {:ok, fresh} = Server.resolve_credential(auth_server, auth_ref, %{connector_id: "github"})

    %{
      original_token: "expired_placeholder",
      refreshed_token: fresh.access_token,
      refresh_worked: fresh.access_token == token,
      new_expiry: fresh.expires_at
    }
  end

  @doc """
  Demonstrate refresh failure -> reauth_required transition.
  """
  def demo_refresh_failure(auth_server) do
    {:ok, conn} = Server.create_connection(auth_server, "github", "fail-demo")
    {:ok, _} = Server.transition_connection(auth_server, conn.id, :installing, "user")
    {:ok, _} = Server.transition_connection(auth_server, conn.id, :connected, "system")

    {:ok, cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: "will_fail",
        refresh_token: "will_fail",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    {:ok, auth_ref} = Server.store_credential(auth_server, "github", "fail-demo", cred)
    :ok = Server.link_connection(auth_server, conn.id, auth_ref)

    Server.set_refresh_callback(auth_server, fn _ref, _rt -> {:error, :invalid_grant} end)

    {:error, :refresh_failed} =
      Server.resolve_credential(auth_server, auth_ref, %{connector_id: "github"})

    {:ok, updated} = Server.get_connection(auth_server, conn.id)

    %{
      connection_state: updated.state,
      requires_reauth: updated.state == :reauth_required,
      audit_trail:
        Enum.map(updated.actor_trail, fn e ->
          "#{e.from_state} -> #{e.to_state} by #{e.actor_id}"
        end)
    }
  end

  defp durable_auth_opts(tmp_dir) do
    [
      name: nil,
      store_module: Store.Disk,
      connection_store_module: ConnectionStore.Disk,
      install_session_store_module: InstallSessionStore.Disk,
      store_opts: [name: store_name(tmp_dir, :credential), dir: tmp_dir],
      connection_store_opts: [name: store_name(tmp_dir, :connection), dir: tmp_dir],
      install_session_store_opts: [name: store_name(tmp_dir, :install_session), dir: tmp_dir]
    ]
  end

  defp restart_server!(server, opts) do
    ref = Process.monitor(server)
    Process.unlink(server)
    Process.exit(server, :kill)

    receive do
      {:DOWN, ^ref, :process, ^server, _reason} -> :ok
    after
      5_000 -> raise "Auth.Server did not terminate during restart demo"
    end

    wait_for_store_shutdown(Keyword.get(opts, :store_opts, []))
    wait_for_store_shutdown(Keyword.get(opts, :connection_store_opts, []))
    wait_for_store_shutdown(Keyword.get(opts, :install_session_store_opts, []))
  end

  defp wait_for_store_shutdown(store_opts) do
    case Keyword.get(store_opts, :name) do
      nil ->
        :ok

      name ->
        case Process.whereis(name) do
          nil ->
            :ok

          pid ->
            ref = Process.monitor(pid)

            receive do
              {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
            after
              5_000 -> raise "store #{inspect(name)} did not terminate during restart demo"
            end
        end
    end
  end

  defp store_name(tmp_dir, suffix) do
    String.to_atom("github_auth_example_#{suffix}_#{:erlang.phash2(tmp_dir)}")
  end
end
