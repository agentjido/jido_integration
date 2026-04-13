defmodule Jido.RuntimeControl.ReadmeTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../../README.md", __DIR__)

  test "readme keeps boundary metadata carriage explicit and runtime-neutral" do
    readme = @readme_path |> File.read!() |> normalize_whitespace()

    assert readme =~ "runtime-driver seam",
           "#{@readme_path} must describe the retained runtime-driver scope"

    assert readme =~ "boundary-backed",
           "#{@readme_path} must describe boundary-backed runtime carriage"

    assert readme =~ "`metadata[\"boundary\"]`",
           "#{@readme_path} must name the boundary metadata namespace"

    assert readme =~ "does not own sandbox policy",
           "#{@readme_path} must keep sandbox policy ownership outside Runtime Control"

    refute readme =~ ":providers",
           "#{@readme_path} must not describe the removed provider-adapter config"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
