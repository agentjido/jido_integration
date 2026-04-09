defmodule Jido.Integration.Docs.RuntimeBasisDocsTest do
  use ExUnit.Case, async: true

  @absolute_checkout_prefix "/home/home/p/g/n/"

  @runtime_basis_docs [
    Path.expand("../../docs/architecture_overview.md", __DIR__),
    Path.expand("../../docs/connector_scaffolding.md", __DIR__),
    Path.expand("../../docs/connector_review_baseline.md", __DIR__),
    Path.expand("../../core/runtime_asm_bridge/README.md", __DIR__),
    Path.expand("../../connectors/codex_cli/README.md", __DIR__),
    Path.expand("../../connectors/market_data/README.md", __DIR__),
    Path.expand("../../core/platform/lib/jido/integration/v2.ex", __DIR__),
    Path.expand(
      "../../core/runtime_asm_bridge/lib/jido/integration/v2/runtime_asm_bridge/harness_driver.ex",
      __DIR__
    )
  ]

  test "runtime-basis docs cite the shared repo boundaries without machine-local checkout paths" do
    Enum.each(@runtime_basis_docs, fn path ->
      doc = File.read!(path)

      assert doc =~ "`jido_harness`", "#{path} must cite the Harness repo by name"
      assert doc =~ "`agent_session_manager`", "#{path} must cite the ASM repo by name"
      assert doc =~ "`cli_subprocess_core`", "#{path} must cite the CLI subprocess repo by name"
      refute doc =~ @absolute_checkout_prefix, "#{path} must not bake in a local checkout path"
    end)
  end
end
