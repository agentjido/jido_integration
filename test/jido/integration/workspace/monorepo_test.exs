defmodule Jido.Integration.Workspace.BlitzWorkspaceTest do
  use ExUnit.Case, async: true

  Code.require_file("build_support/weld.exs", File.cwd!())

  alias Jido.Integration.Build.WeldContract
  alias Jido.Integration.Build.WorkspaceContract

  test "enumerates the tooling-root projects in stable order" do
    assert Blitz.MixWorkspace.project_paths() == [
             ".",
             "core/asm_runtime_bridge",
             "core/auth",
             "core/brain_ingress",
             "core/conformance",
             "core/conformance_contracts",
             "core/connector_admission_engine",
             "core/connector_registry",
             "core/consumer_surfaces",
             "core/contracts",
             "core/control_plane",
             "core/direct_runtime",
             "core/dispatch_runtime",
             "core/inference_operation_policy",
             "core/ingress",
             "core/model_provider_registry",
             "core/platform",
             "core/platform_cluster_runtime",
             "core/policy",
             "core/provider_feature_matrix",
             "core/runtime_control",
             "core/runtime_router",
             "core/session_runtime",
             "core/store_local",
             "core/store_postgres",
             "core/tool_contracts",
             "core/webhook_router",
             "scaffolds/connector_generator",
             "connectors/amp",
             "connectors/codex_cli",
             "connectors/github",
             "connectors/linear",
             "connectors/market_data",
             "connectors/notion",
             "apps/devops_incident_response",
             "apps/inference_ops"
           ]
  end

  test "default workspace graph contains only the active package families" do
    assert WorkspaceContract.active_project_globs() == [
             ".",
             "core/*",
             "scaffolds/*",
             "connectors/*",
             "apps/devops_incident_response",
             "apps/inference_ops"
           ]

    refute Enum.any?(Blitz.MixWorkspace.project_paths(), &String.starts_with?(&1, "bridges/"))
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
             Path.expand(
               "core/contracts/_build/#{System.get_env("MIX_ENV", "dev")}",
               Blitz.MixWorkspace.root_dir()
             )

    assert test_env["JIDO_INTEGRATION_V2_DB_NAME"] ==
             Blitz.MixWorkspace.hashed_project_name(
               "jido_integration_v2_test",
               "connectors/github",
               max_bytes: 63
             )

    refute Map.has_key?(compile_env, "JIDO_INTEGRATION_V2_DB_NAME")
  end

  test "workspace command env uses materialized application env" do
    previous_env = Application.get_env(:jido_integration_workspace, :env)

    Application.put_env(:jido_integration_workspace, :env, %{
      "JIDO_INTEGRATION_V2_DB_BASE_NAME" => "jido_custom_test",
      "PATH" => "/opt/elixir/bin:/usr/bin"
    })

    try do
      test_env =
        Map.new(Blitz.MixWorkspace.command_env(Mix.Project.config(), "connectors/github", :test))

      assert test_env["PATH"] ==
               Path.join(Blitz.MixWorkspace.root_dir(), "bin") <> ":/opt/elixir/bin:/usr/bin"

      assert test_env["JIDO_INTEGRATION_V2_DB_NAME"] ==
               Blitz.MixWorkspace.hashed_project_name(
                 "jido_custom_test",
                 "connectors/github",
                 max_bytes: 63
               )
    after
      case previous_env do
        nil -> Application.delete_env(:jido_integration_workspace, :env)
        value -> Application.put_env(:jido_integration_workspace, :env, value)
      end
    end
  end

  test "fallback workspace PATH keeps Erlang available for child Mix commands" do
    previous_env = Application.get_env(:jido_integration_workspace, :env)
    Application.put_env(:jido_integration_workspace, :env, %{})

    try do
      command_env =
        Mix.Project.config()
        |> Blitz.MixWorkspace.command_env("connectors/github", :test)
        |> Map.new()

      path_entries = String.split(command_env["PATH"], ":", trim: true)

      assert Path.join(Blitz.MixWorkspace.root_dir(), "bin") in path_entries
      assert Enum.any?(path_entries, &String.ends_with?(&1, "/bin"))
      assert Enum.any?(path_entries, &String.contains?(&1, "/erts-"))
    after
      case previous_env do
        nil -> Application.delete_env(:jido_integration_workspace, :env)
        value -> Application.put_env(:jido_integration_workspace, :env, value)
      end
    end
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

  test "weld monolith skips Hex build while generated dependencies include git sources" do
    verify_config = WeldContract.artifact()[:verify]

    assert verify_config[:hex_build] == false
    assert verify_config[:hex_publish] == false
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
  end
end
