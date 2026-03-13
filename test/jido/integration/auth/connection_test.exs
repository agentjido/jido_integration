defmodule Jido.Integration.Auth.ConnectionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.Connection

  describe "new/1" do
    test "creates a connection in :new state" do
      conn = Connection.new("github", "tenant_1")
      assert conn.connector_id == "github"
      assert conn.tenant_id == "tenant_1"
      assert conn.state == :new
      assert conn.revision == 0
      assert conn.actor_trail == []
      assert is_binary(conn.id)
    end

    test "accepts optional id" do
      conn = Connection.new("github", "tenant_1", id: "conn_custom")
      assert conn.id == "conn_custom"
    end
  end

  describe "valid transitions" do
    test "new -> installing" do
      conn = Connection.new("github", "t1")
      assert {:ok, conn2} = Connection.transition(conn, :installing, "user_1")
      assert conn2.state == :installing
    end

    test "installing -> connected" do
      conn = Connection.new("github", "t1")
      {:ok, conn} = Connection.transition(conn, :installing, "user_1")
      assert {:ok, conn2} = Connection.transition(conn, :connected, "system")
      assert conn2.state == :connected
    end

    test "connected -> degraded" do
      conn = build_connected()
      assert {:ok, conn2} = Connection.transition(conn, :degraded, "system")
      assert conn2.state == :degraded
    end

    test "degraded -> connected (recovery)" do
      conn = build_connected()
      {:ok, conn} = Connection.transition(conn, :degraded, "system")
      assert {:ok, conn2} = Connection.transition(conn, :connected, "system")
      assert conn2.state == :connected
    end

    test "connected -> reauth_required" do
      conn = build_connected()
      assert {:ok, conn2} = Connection.transition(conn, :reauth_required, "system")
      assert conn2.state == :reauth_required
    end

    test "reauth_required -> installing (re-consent)" do
      conn = build_connected()
      {:ok, conn} = Connection.transition(conn, :reauth_required, "system")
      assert {:ok, conn2} = Connection.transition(conn, :installing, "user_1")
      assert conn2.state == :installing
    end

    test "any state -> revoked" do
      for state <- [:installing, :connected, :degraded, :reauth_required] do
        conn = build_in_state(state)
        assert {:ok, conn2} = Connection.transition(conn, :revoked, "system")
        assert conn2.state == :revoked
      end
    end

    test "any state -> disabled" do
      for state <- [:connected, :degraded, :reauth_required, :revoked] do
        conn = build_in_state(state)
        assert {:ok, conn2} = Connection.transition(conn, :disabled, "admin_1")
        assert conn2.state == :disabled
      end
    end

    test "revoked -> installing (re-install)" do
      conn = build_in_state(:revoked)
      assert {:ok, conn2} = Connection.transition(conn, :installing, "user_1")
      assert conn2.state == :installing
    end

    test "disabled -> installing (recovery)" do
      conn = build_in_state(:disabled)
      assert {:ok, conn2} = Connection.transition(conn, :installing, "admin_1")
      assert conn2.state == :installing
    end
  end

  describe "invalid transitions" do
    test "connected -> installing is invalid" do
      conn = build_connected()
      assert {:error, msg} = Connection.transition(conn, :installing, "user_1")
      assert msg =~ "Invalid transition"
    end

    test "revoked -> connected is invalid" do
      conn = build_in_state(:revoked)
      assert {:error, msg} = Connection.transition(conn, :connected, "system")
      assert msg =~ "Invalid transition"
    end

    test "new -> connected is invalid (must install first)" do
      conn = Connection.new("github", "t1")
      assert {:error, _} = Connection.transition(conn, :connected, "system")
    end

    test "degraded -> disabled is valid" do
      conn = build_in_state(:degraded)
      assert {:ok, _} = Connection.transition(conn, :disabled, "admin")
    end
  end

  describe "revision tracking" do
    test "revision increments on each transition" do
      conn = Connection.new("github", "t1")
      assert conn.revision == 0

      {:ok, conn} = Connection.transition(conn, :installing, "user_1")
      assert conn.revision == 1

      {:ok, conn} = Connection.transition(conn, :connected, "system")
      assert conn.revision == 2

      {:ok, conn} = Connection.transition(conn, :degraded, "system")
      assert conn.revision == 3
    end
  end

  describe "actor audit trail" do
    test "records actor, from_state, to_state, timestamp on each transition" do
      conn = Connection.new("github", "t1")

      {:ok, conn} = Connection.transition(conn, :installing, "user_42")
      assert length(conn.actor_trail) == 1

      [entry] = conn.actor_trail
      assert entry.actor_id == "user_42"
      assert entry.from_state == :new
      assert entry.to_state == :installing
      assert %DateTime{} = entry.timestamp
    end

    test "trail accumulates across transitions" do
      conn = Connection.new("github", "t1")
      {:ok, conn} = Connection.transition(conn, :installing, "user_1")
      {:ok, conn} = Connection.transition(conn, :connected, "system")
      {:ok, conn} = Connection.transition(conn, :degraded, "monitor")

      assert length(conn.actor_trail) == 3
      actors = Enum.map(conn.actor_trail, & &1.actor_id)
      assert actors == ["user_1", "system", "monitor"]
    end
  end

  describe "terminal?/1" do
    test "revoked and disabled are terminal" do
      assert Connection.terminal?(build_in_state(:revoked))
      assert Connection.terminal?(build_in_state(:disabled))
    end

    test "other states are not terminal" do
      refute Connection.terminal?(Connection.new("g", "t"))
      refute Connection.terminal?(build_in_state(:installing))
      refute Connection.terminal?(build_connected())
      refute Connection.terminal?(build_in_state(:degraded))
    end
  end

  # Helpers

  defp build_connected do
    conn = Connection.new("github", "t1")
    {:ok, conn} = Connection.transition(conn, :installing, "u1")
    {:ok, conn} = Connection.transition(conn, :connected, "system")
    conn
  end

  defp build_in_state(:installing) do
    conn = Connection.new("github", "t1")
    {:ok, conn} = Connection.transition(conn, :installing, "u1")
    conn
  end

  defp build_in_state(:connected), do: build_connected()

  defp build_in_state(:degraded) do
    conn = build_connected()
    {:ok, conn} = Connection.transition(conn, :degraded, "system")
    conn
  end

  defp build_in_state(:reauth_required) do
    conn = build_connected()
    {:ok, conn} = Connection.transition(conn, :reauth_required, "system")
    conn
  end

  defp build_in_state(:revoked) do
    conn = build_connected()
    {:ok, conn} = Connection.transition(conn, :revoked, "system")
    conn
  end

  defp build_in_state(:disabled) do
    conn = build_connected()
    {:ok, conn} = Connection.transition(conn, :disabled, "admin")
    conn
  end
end
