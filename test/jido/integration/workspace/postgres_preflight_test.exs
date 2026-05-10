defmodule Jido.Integration.Workspace.PostgresPreflightTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Workspace.PostgresPreflight

  test "loads the default Postgres-backed test target from env" do
    config = PostgresPreflight.from_env(%{})

    assert config.host == "127.0.0.1"
    assert config.port == 5432
    assert config.database == "jido_integration_v2_test"
    assert config.user == "postgres"
    assert config.socket_dir == nil
    assert config.timeout_ms == 1_000
  end

  test "loads default Postgres target from materialized application env" do
    previous_env = Application.get_env(:jido_integration_workspace, :env)

    Application.put_env(:jido_integration_workspace, :env, %{
      "JIDO_INTEGRATION_V2_DB_HOST" => "postgres.internal",
      "JIDO_INTEGRATION_V2_DB_NAME" => "materialized_test",
      "JIDO_INTEGRATION_V2_DB_PORT" => "5545",
      "JIDO_INTEGRATION_V2_DB_USER" => "jido",
      "JIDO_INTEGRATION_V2_DB_TIMEOUT_MS" => "3250"
    })

    try do
      config = PostgresPreflight.from_env()

      assert config.host == "postgres.internal"
      assert config.port == 5545
      assert config.database == "materialized_test"
      assert config.user == "jido"
      assert config.timeout_ms == 3_250
    after
      case previous_env do
        nil -> Application.delete_env(:jido_integration_workspace, :env)
        value -> Application.put_env(:jido_integration_workspace, :env, value)
      end
    end
  end

  test "builds pg_isready args for a tcp target" do
    config =
      PostgresPreflight.from_env(%{
        "JIDO_INTEGRATION_V2_DB_HOST" => "db.internal",
        "JIDO_INTEGRATION_V2_DB_PORT" => "5544",
        "JIDO_INTEGRATION_V2_DB_NAME" => "integration_test",
        "JIDO_INTEGRATION_V2_DB_USER" => "workspace",
        "JIDO_INTEGRATION_V2_DB_TIMEOUT_MS" => "2500"
      })

    assert PostgresPreflight.target_label(config) == "db.internal:5544"

    assert PostgresPreflight.pg_isready_args(config) == [
             "-h",
             "db.internal",
             "-p",
             "5544",
             "-d",
             "integration_test",
             "-U",
             "workspace",
             "-t",
             "3"
           ]
  end

  test "builds pg_isready args for a socket target" do
    config =
      PostgresPreflight.from_env(%{
        "JIDO_INTEGRATION_V2_DB_SOCKET_DIR" => "/var/run/postgresql",
        "JIDO_INTEGRATION_V2_DB_PORT" => "6432"
      })

    assert PostgresPreflight.target_label(config) == "/var/run/postgresql/.s.PGSQL.6432"

    assert PostgresPreflight.pg_isready_args(config) == [
             "-h",
             "/var/run/postgresql",
             "-p",
             "6432",
             "-d",
             "jido_integration_v2_test",
             "-U",
             "postgres",
             "-t",
             "1"
           ]
  end
end
