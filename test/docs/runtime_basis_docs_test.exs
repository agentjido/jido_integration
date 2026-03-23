defmodule Jido.Integration.Docs.RuntimeBasisDocsTest do
  use ExUnit.Case, async: true

  @harness_repo "/home/home/p/g/n/jido_harness"
  @asm_repo "/home/home/p/g/n/agent_session_manager"
  @cli_repo "/home/home/p/g/n/cli_subprocess_core"

  @runtime_basis_docs [
    Path.expand("../../docs/architecture_overview.md", __DIR__),
    Path.expand("../../docs/connector_scaffolding.md", __DIR__),
    Path.expand("../../docs/connector_review_baseline.md", __DIR__),
    Path.expand("../../core/runtime_asm_bridge/README.md", __DIR__),
    Path.expand("../../connectors/codex_cli/README.md", __DIR__),
    Path.expand("../../connectors/market_data/README.md", __DIR__)
  ]

  test "runtime-basis docs cite the shared repo boundaries with absolute paths" do
    Enum.each(@runtime_basis_docs, fn path ->
      doc = File.read!(path)

      assert doc =~ @harness_repo, "#{path} must cite the Harness repo with an absolute path"
      assert doc =~ @asm_repo, "#{path} must cite the ASM repo with an absolute path"
      assert doc =~ @cli_repo, "#{path} must cite the CLI subprocess repo with an absolute path"
    end)
  end
end
