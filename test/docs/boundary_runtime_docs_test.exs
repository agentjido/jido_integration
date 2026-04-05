defmodule Jido.Integration.Docs.BoundaryRuntimeDocsTest do
  use ExUnit.Case, async: true

  @docs [
    Path.expand("../../README.md", __DIR__),
    Path.expand("../../guides/runtime_model.md", __DIR__),
    Path.expand("../../core/harness_runtime/README.md", __DIR__),
    Path.expand("../../core/session_runtime/README.md", __DIR__)
  ]

  test "runtime docs describe asm and jido_session as the two harness-backed lanes" do
    Enum.each(@docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert doc =~ "`asm`",
             "#{path} must name the asm runtime lane explicitly"

      assert doc =~ "`jido_session`",
             "#{path} must name the jido_session runtime lane explicitly"

      refute doc =~ "boundary-backed `asm`",
             "#{path} must not describe asm as boundary-backed anymore"

      refute doc =~ "boundary-backed `jido_session`",
             "#{path} must not describe jido_session as boundary-backed anymore"
    end)
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
