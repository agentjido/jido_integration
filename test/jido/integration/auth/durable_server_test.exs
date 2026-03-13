defmodule Jido.Integration.Auth.DurableServerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Jido.Integration.Auth.Server

  test "callback succeeds after Auth.Server restart", %{tmp_dir: tmp_dir} do
    opts = durable_auth_opts(tmp_dir)

    {:ok, server} = Server.start_link(opts)

    {:ok, install} =
      Server.start_install(server, "github", "tenant_restart",
        scopes: ["repo", "read:org"],
        actor_id: "user_restart"
      )

    restart_server!(server, opts)

    {:ok, restarted} = Server.start_link(opts)

    params = %{
      "state" => install.session_state["state"],
      "credential" => %{
        access_token: "gho_restart",
        refresh_token: "ghr_restart",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      },
      "granted_scopes" => ["repo", "read:org", "admin:org"],
      "actor_id" => "system:callback"
    }

    assert {:ok, %{connection_id: connection_id, state: :connected, auth_ref: auth_ref}} =
             Server.handle_callback(restarted, "github", params, install.session_state)

    assert auth_ref == "auth:github:#{connection_id}"

    assert {:ok, connection} = Server.get_connection(restarted, connection_id)
    assert connection.state == :connected
    assert connection.auth_ref == auth_ref

    assert {:ok, resolved} =
             Server.resolve_credential(restarted, auth_ref, %{connector_id: "github"})

    assert resolved.access_token == "gho_restart"
    assert resolved.scopes == ["repo", "read:org"]
  end

  test "duplicate callback is rejected after the first successful consume", %{tmp_dir: tmp_dir} do
    opts = durable_auth_opts(tmp_dir)

    {:ok, server} = Server.start_link(opts)

    {:ok, install} =
      Server.start_install(server, "github", "tenant_duplicate",
        scopes: ["repo"],
        actor_id: "user_duplicate"
      )

    params = %{
      "state" => install.session_state["state"],
      "credential" => %{
        access_token: "gho_duplicate",
        refresh_token: "ghr_duplicate",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      },
      "granted_scopes" => ["repo"],
      "actor_id" => "system:callback"
    }

    assert {:ok, %{connection_id: connection_id, state: :connected}} =
             Server.handle_callback(server, "github", params, install.session_state)

    restart_server!(server, opts)

    {:ok, restarted} = Server.start_link(opts)

    assert {:error, :invalid_state_token} =
             Server.handle_callback(restarted, "github", params, install.session_state)

    assert {:ok, connection} = Server.get_connection(restarted, connection_id)
    assert connection.state == :connected
  end

  test "expired state token is rejected", %{tmp_dir: tmp_dir} do
    opts = durable_auth_opts(tmp_dir, install_session_ttl_ms: 5)

    {:ok, server} = Server.start_link(opts)

    {:ok, install} =
      Server.start_install(server, "github", "tenant_expired",
        scopes: ["repo"],
        actor_id: "user_expired"
      )

    Process.sleep(20)

    params = %{
      "state" => install.session_state["state"],
      "credential" => %{access_token: "gho_expired"},
      "granted_scopes" => ["repo"]
    }

    assert {:error, :state_expired} =
             Server.handle_callback(server, "github", params, install.session_state)
  end

  test "connector mismatch is rejected", %{tmp_dir: tmp_dir} do
    opts = durable_auth_opts(tmp_dir)

    {:ok, server} = Server.start_link(opts)

    {:ok, install} =
      Server.start_install(server, "github", "tenant_connector",
        scopes: ["repo"],
        actor_id: "user_connector"
      )

    params = %{
      "state" => install.session_state["state"],
      "credential" => %{access_token: "gho_connector"},
      "granted_scopes" => ["repo"]
    }

    assert {:error, :connector_mismatch} =
             Server.handle_callback(server, "linear", params, install.session_state)
  end

  test "PKCE mismatch is rejected", %{tmp_dir: tmp_dir} do
    opts = durable_auth_opts(tmp_dir)

    {:ok, server} = Server.start_link(opts)

    {:ok, install} =
      Server.start_install(server, "github", "tenant_pkce",
        scopes: ["repo"],
        actor_id: "user_pkce",
        pkce_required: true
      )

    params = %{
      "state" => install.session_state["state"],
      "credential" => %{access_token: "gho_pkce"},
      "granted_scopes" => ["repo"]
    }

    bad_session_state = Map.put(install.session_state, "code_verifier", "wrong_verifier")

    assert {:error, :pkce_verification_failed} =
             Server.handle_callback(server, "github", params, bad_session_state)
  end

  defp durable_auth_opts(tmp_dir, extra_opts \\ []) do
    Keyword.merge(
      [
        name: nil,
        store_module: Jido.Integration.Auth.Store.Disk,
        connection_store_module: Jido.Integration.Auth.ConnectionStore.Disk,
        install_session_store_module: Jido.Integration.Auth.InstallSessionStore.Disk,
        store_opts: [name: store_name(tmp_dir, :credential), dir: tmp_dir],
        connection_store_opts: [name: store_name(tmp_dir, :connection), dir: tmp_dir],
        install_session_store_opts: [name: store_name(tmp_dir, :install_session), dir: tmp_dir]
      ],
      extra_opts
    )
  end

  defp restart_server!(server, opts) do
    ref = Process.monitor(server)
    Process.unlink(server)
    Process.exit(server, :kill)

    receive do
      {:DOWN, ^ref, :process, ^server, _reason} -> :ok
    after
      5_000 -> flunk("Auth.Server did not terminate")
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
        if pid = Process.whereis(name) do
          ref = Process.monitor(pid)

          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            5_000 -> flunk("store #{inspect(name)} did not terminate")
          end
        else
          :ok
        end
    end
  end

  defp store_name(tmp_dir, suffix) do
    String.to_atom("auth_durable_#{suffix}_#{:erlang.phash2(tmp_dir)}")
  end
end
