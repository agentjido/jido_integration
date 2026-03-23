defmodule Jido.Integration.Docs.ContractsReadmeTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../core/contracts/README.md", __DIR__)

  test "documents target descriptors as compatibility ads over authored capability ids" do
    readme = @readme_path |> File.read!() |> normalize_whitespace()

    refute readme =~
             "TargetDescriptor uses a separate target-capability namespace from connector capabilities"

    assert readme =~
             "`TargetDescriptor` matches against authored capability ids while remaining a compatibility and location advertisement rather than a second override plane"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
