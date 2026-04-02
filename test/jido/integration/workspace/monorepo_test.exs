defmodule Jido.Integration.Workspace.BlitzWorkspaceTest do
  use ExUnit.Case, async: true

  test "enumerates the tooling-root projects in stable order" do
    assert Blitz.MixWorkspace.project_paths() == [
             ".",
             "core/auth",
             "core/conformance",
             "core/consumer_surfaces",
             "core/contracts",
             "core/control_plane",
             "core/direct_runtime",
             "core/dispatch_runtime",
             "core/harness_runtime",
             "core/ingress",
             "core/platform",
             "core/policy",
             "core/runtime_asm_bridge",
             "core/session_runtime",
             "core/store_local",
             "core/store_postgres",
             "core/webhook_router",
             "bridges/boundary_bridge",
             "connectors/codex_cli",
             "connectors/github",
             "connectors/market_data",
             "connectors/notion",
             "apps/devops_incident_response",
             "apps/inference_ops",
             "apps/trading_ops"
           ]
  end

  test "builds task args for each supported workspace task" do
    assert Blitz.MixWorkspace.task_args(Mix.Project.config(), :compile, []) == [
             "compile",
             "--warnings-as-errors"
           ]

    assert Blitz.MixWorkspace.task_args(Mix.Project.config(), :test, ["--seed", "0"]) == [
             "test",
             "--color",
             "--seed",
             "0"
           ]

    assert Blitz.MixWorkspace.task_args(Mix.Project.config(), :format, ["--check-formatted"]) == [
             "format",
             "--check-formatted"
           ]
  end

  test "uses env-specific build paths for child commands" do
    test_env =
      Map.new(Blitz.MixWorkspace.command_env(Mix.Project.config(), "connectors/github", :test))

    compile_env =
      Map.new(Blitz.MixWorkspace.command_env(Mix.Project.config(), "core/contracts", :compile))

    assert test_env["MIX_DEPS_PATH"] ==
             Path.expand("connectors/github/deps", Blitz.MixWorkspace.root_dir())

    assert test_env["MIX_BUILD_PATH"] ==
             Path.expand("connectors/github/_build/test", Blitz.MixWorkspace.root_dir())

    assert test_env["MIX_LOCKFILE"] ==
             Path.expand("connectors/github/mix.lock", Blitz.MixWorkspace.root_dir())

    assert compile_env["MIX_BUILD_PATH"] ==
             Path.expand("core/contracts/_build/dev", Blitz.MixWorkspace.root_dir())

    assert test_env["JIDO_INTEGRATION_V2_DB_NAME"] ==
             Blitz.MixWorkspace.hashed_project_name(
               "jido_integration_v2_test",
               "connectors/github",
               max_bytes: 63
             )

    refute Map.has_key?(compile_env, "JIDO_INTEGRATION_V2_DB_NAME")
  end

  test "extracts runner arguments without disturbing mix task arguments" do
    assert Blitz.MixWorkspace.split_runner_args(["--max-concurrency", "4", "--strict"]) ==
             {["--strict"], [max_concurrency: 4]}

    assert Blitz.MixWorkspace.split_runner_args(["-j", "2", "--seed", "0"]) ==
             {["--seed", "0"], [max_concurrency: 2]}

    assert Blitz.MixWorkspace.split_runner_args(["--max-concurrency=3", "--check-formatted"]) ==
             {["--check-formatted"], [max_concurrency: 3]}
  end

  test "uses auto machine scaling for workspace parallelism by default" do
    workspace_config = Mix.Project.config()[:blitz_workspace]

    assert workspace_config[:parallelism][:multiplier] == :auto
  end

  test "derives stable, package-specific test database names" do
    assert Blitz.MixWorkspace.hashed_project_name("jido_integration_v2_test", ".", max_bytes: 63) ==
             "jido_integration_v2_test_workspace_cdb4ee2a"

    assert Blitz.MixWorkspace.hashed_project_name(
             "jido_integration_v2_test",
             "core/dispatch_runtime",
             max_bytes: 63
           ) ==
             "jido_integration_v2_test_core_dispatch_runtime_7510d0e3"

    assert Blitz.MixWorkspace.hashed_project_name(
             "jido_integration_v2_test",
             "bridges/boundary_bridge",
             max_bytes: 63
           ) ==
             "jido_integration_v2_test_bridges_boundary_bridge_5c7d0993"

    assert Blitz.MixWorkspace.hashed_project_name(
             "jido_integration_v2_test",
             "apps/trading_ops",
             max_bytes: 63
           ) ==
             "jido_integration_v2_test_apps_trading_ops_57fc89c1"
  end
end
