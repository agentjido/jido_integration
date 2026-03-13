defmodule Jido.Integration.V2.MonorepoTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Monorepo

  test "enumerates the thin-root projects in stable order" do
    assert Monorepo.project_paths() == [
             ".",
             "packages/core/auth",
             "packages/core/contracts",
             "packages/core/control_plane",
             "packages/core/direct_runtime",
             "packages/core/ingress",
             "packages/core/policy",
             "packages/core/session_kernel",
             "packages/core/store_postgres",
             "packages/core/stream_runtime",
             "packages/connectors/codex_cli",
             "packages/connectors/github",
             "packages/connectors/market_data",
             "packages/apps/trading_ops"
           ]
  end

  test "builds mix args for each supported task" do
    assert Monorepo.mix_args(:compile, []) == ["compile", "--warnings-as-errors"]
    assert Monorepo.mix_args(:test, ["--seed", "0"]) == ["test", "--seed", "0"]
    assert Monorepo.mix_args(:format, ["--check-formatted"]) == ["format", "--check-formatted"]
  end
end
