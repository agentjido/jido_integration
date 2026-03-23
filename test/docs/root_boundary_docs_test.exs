defmodule Jido.Integration.Docs.RootBoundaryDocsTest do
  use ExUnit.Case, async: true

  @root_docs [
    Path.expand("../../README.md", __DIR__),
    Path.expand("../../docs/architecture_overview.md", __DIR__)
  ]

  test "root docs freeze the direct-vs-runtime split explicitly" do
    Enum.each(@root_docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~ "GitHub and Notion stay on the direct provider-SDK path",
             "#{path} must keep direct connectors on the direct path explicitly"

      assert doc =~ "do not inherit session or stream runtime-kernel coupling",
             "#{path} must reject runtime-kernel coupling for direct connectors"

      assert doc =~
               "Only actual `:session` and `:stream` capabilities use `/home/home/p/g/n/jido_harness` via `Jido.Harness`.",
             "#{path} must keep Jido.Harness scoped to actual non-direct capabilities"
    end)
  end

  test "root docs describe bridge packages as residue rather than target architecture" do
    Enum.each(@root_docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~
               "`core/session_kernel` and `core/stream_runtime` still exist only as bridge-era residue slated for Phase 6A removal; they are not part of the target runtime architecture.",
             "#{path} must describe the bridge packages as residue"
    end)
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
