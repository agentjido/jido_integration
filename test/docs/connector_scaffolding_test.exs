defmodule Jido.Integration.Docs.ConnectorScaffoldingTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/connector_scaffolding.md", __DIR__)

  test "documents explicit runtime-driver selection for non-direct scaffolds" do
    guide = File.read!(@guide_path)

    assert guide =~ "--runtime-driver"
    assert guide =~ "`asm` or `jido_session`"

    assert guide =~
             "mix jido.integration.new analyst_cli --runtime-class session --runtime-driver asm"

    assert guide =~
             "mix jido.integration.new market_feed --runtime-class stream --runtime-driver asm"

    assert guide =~ "never generate `integration_session_bridge` or `integration_stream_bridge`"
    assert guide =~ "There is no implicit `asm` fallback for `:session` or `:stream` routing."
    refute guide =~ "The workspace scaffold currently supports direct connectors only."
  end

  test "documents the authored-vs-generated boundary and package-local proof ownership" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~ "## Generated Versus Authored Checklist"
    assert guide =~ "## Proof Code Homes"

    assert guide =~
             "The scaffold output is the starting contract, not the finished connector package."

    assert guide =~
             "Keep deterministic fixtures, companion modules, examples, scripts, and live acceptance inside the connector package."

    assert guide =~
             "Do not move connector proof code into the workspace root."
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
