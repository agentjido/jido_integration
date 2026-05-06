defmodule Jido.Integration.Docs.PublishingDocsTest do
  use ExUnit.Case, async: true

  @docs [
    Path.expand("../../README.md", __DIR__),
    Path.expand("../../guides/index.md", __DIR__),
    Path.expand("../../guides/publishing.md", __DIR__)
  ]

  test "publication docs describe the bundle-first welded release flow" do
    Enum.each(@docs, fn path ->
      doc = path |> File.read!() |> normalize_whitespace()

      assert String.contains?(doc, "mix release.prepare"),
             "#{path} must describe bundle preparation explicitly"

      assert String.contains?(doc, "mix release.track"),
             "#{path} must describe projection tracking explicitly"

      assert String.contains?(doc, "mix release.publish"),
             "#{path} must describe publish-from-bundle explicitly"

      assert String.contains?(doc, "mix release.archive"),
             "#{path} must describe archive-after-publish explicitly"

      refute String.contains?(doc, "WELD_PATH"),
             "#{path} must not describe committed Weld path overrides anymore"

      refute String.contains?(doc, "WELD_GIT_REF"),
             "#{path} must not describe committed Weld git-ref overrides anymore"
    end)
  end

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")
end
