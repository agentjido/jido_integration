defmodule Jido.Integration.Workspace.MonorepoTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Workspace.Monorepo

  test "enumerates the tooling-root projects in stable order" do
    assert Monorepo.project_paths() == [
             ".",
             "core/auth",
             "core/conformance",
             "core/contracts",
             "core/control_plane",
             "core/direct_runtime",
             "core/dispatch_runtime",
             "core/ingress",
             "core/platform",
             "core/policy",
             "core/runtime_asm_bridge",
             "core/session_kernel",
             "core/store_local",
             "core/store_postgres",
             "core/stream_runtime",
             "core/webhook_router",
             "connectors/codex_cli",
             "connectors/github",
             "connectors/market_data",
             "connectors/notion",
             "apps/devops_incident_response",
             "apps/trading_ops"
           ]
  end

  test "builds mix args for each supported task" do
    assert Monorepo.mix_args(:compile, []) == ["compile", "--warnings-as-errors"]
    assert Monorepo.mix_args(:test, ["--seed", "0"]) == ["test", "--seed", "0"]
    assert Monorepo.mix_args(:format, ["--check-formatted"]) == ["format", "--check-formatted"]
  end

  test "uses env-specific build paths for child commands" do
    test_env = Map.new(Monorepo.command_env("connectors/github", :test))
    compile_env = Map.new(Monorepo.command_env("core/contracts", :compile))

    assert test_env["MIX_DEPS_PATH"] ==
             Path.expand("connectors/github/deps", Monorepo.root_dir())

    assert test_env["MIX_BUILD_PATH"] ==
             Path.expand("connectors/github/_build/test", Monorepo.root_dir())

    assert test_env["MIX_LOCKFILE"] ==
             Path.expand("connectors/github/mix.lock", Monorepo.root_dir())

    assert compile_env["MIX_BUILD_PATH"] ==
             Path.expand("core/contracts/_build/dev", Monorepo.root_dir())
  end
end
