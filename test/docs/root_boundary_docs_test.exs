defmodule Jido.Integration.Docs.RootBoundaryDocsTest do
  use ExUnit.Case, async: true

  @root_docs [
    Path.expand("../../README.md", __DIR__),
    Path.expand("../../docs/architecture_overview.md", __DIR__)
  ]

  test "root docs freeze the direct-vs-runtime split explicitly" do
    Enum.each(@root_docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~ "GitHub, Linear, and Notion stay on the direct provider-SDK path",
             "#{path} must keep direct connectors on the direct path explicitly"

      assert doc =~ "do not inherit session or stream runtime-kernel coupling",
             "#{path} must reject runtime-kernel coupling for direct connectors"

      assert doc =~
               "Only actual `:session` and `:stream` capabilities use `jido_harness` via `Jido.Harness`.",
             "#{path} must keep Jido.Harness scoped to actual non-direct capabilities"

      refute doc =~ "/home/home/p/g/n/",
             "#{path} must not bake in a machine-local checkout path"
    end)
  end

  test "root docs describe the bridge packages as removed cleanup targets" do
    Enum.each(@root_docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~
               "Phase 6A removed the old `core/session_kernel` and `core/stream_runtime` bridge packages. They are not part of the repo or the target runtime architecture.",
             "#{path} must describe the bridge packages as removed"
    end)
  end

  test "root docs describe both supported non-direct runtime targets explicitly" do
    Enum.each(@root_docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~
               "`asm` routes through `core/runtime_asm_bridge` into `agent_session_manager` and `cli_subprocess_core`, while `jido_session` routes through `core/session_runtime` via `Jido.Session.HarnessDriver`.",
             "#{path} must describe both supported non-direct runtime targets explicitly"
    end)
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
