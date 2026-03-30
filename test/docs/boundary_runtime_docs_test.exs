defmodule Jido.Integration.Docs.BoundaryRuntimeDocsTest do
  use ExUnit.Case, async: true

  @docs [
    Path.expand("../../README.md", __DIR__),
    Path.expand("../../guides/runtime_model.md", __DIR__),
    Path.expand("../../core/harness_runtime/README.md", __DIR__),
    Path.expand("../../core/session_runtime/README.md", __DIR__)
  ]

  test "runtime docs describe the authored baseline and runtime-merged live capability view" do
    Enum.each(@docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~ "authored baseline",
             "#{path} must name the authored baseline boundary capability contract"

      assert doc =~ "runtime-merged live capability",
             "#{path} must name the runtime-merged live capability view"
    end)
  end

  test "runtime docs describe boundary-backed asm and jido_session as peer lanes" do
    Enum.each(@docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~ "boundary-backed `asm`",
             "#{path} must describe the boundary-backed asm lane explicitly"

      assert doc =~ "boundary-backed `jido_session`",
             "#{path} must describe the boundary-backed jido_session lane explicitly"
    end)
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
