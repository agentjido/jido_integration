defmodule Jido.Integration.Docs.SidecarBoundaryHandoffDocsTest do
  use ExUnit.Case, async: true

  @root_docs [
    Path.expand("../../README.md", __DIR__),
    Path.expand("../../docs/architecture_overview.md", __DIR__)
  ]

  @contracts_doc Path.expand("../../core/contracts/README.md", __DIR__)

  test "root docs make the Phase 8 sidecar seam and Phase 9 handoff explicit" do
    Enum.each(@root_docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~
               "higher-order sidecars such as `jido_memory`, `jido_skill`, and `jido_eval` stay on the `core/contracts` seam and may persist only derived state",
             "#{path} must keep higher-order repos on the contracts seam"

      assert doc =~
               "Phase 9 provider-factory work builds on that already-correct ownership split instead of reopening control-plane, catalog, or review authority in those repos",
             "#{path} must keep the Phase 9 handoff explicit"
    end)
  end

  test "contracts docs freeze the sidecar seam as the Phase 9 foundation" do
    doc = @contracts_doc |> File.read!() |> normalize_whitespace()

    assert doc =~
             "`core/contracts` is the only intended shared dependency seam for higher-order repos such as `jido_memory`, `jido_skill`, and `jido_eval`",
           "#{@contracts_doc} must name the contracts seam explicitly"

    assert doc =~
             "provider-factory work in Phase 9 scales on top of that seam instead of widening those repos into platform, control-plane, or store-postgres dependencies",
           "#{@contracts_doc} must make the Phase 9 handoff explicit"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
