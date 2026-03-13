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
             "core/ingress",
             "core/platform",
             "core/policy",
             "core/session_kernel",
             "core/store_local",
             "core/store_postgres",
             "core/stream_runtime",
             "connectors/codex_cli",
             "connectors/github",
             "connectors/market_data",
             "apps/trading_ops"
           ]
  end

  test "builds mix args for each supported task" do
    assert Monorepo.mix_args(:compile, []) == ["compile", "--warnings-as-errors"]
    assert Monorepo.mix_args(:test, ["--seed", "0"]) == ["test", "--seed", "0"]
    assert Monorepo.mix_args(:format, ["--check-formatted"]) == ["format", "--check-formatted"]
  end
end
