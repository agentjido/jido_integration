defmodule Jido.Integration.V2.Connectors.GitHub.NoEnvContractTest do
  use ExUnit.Case, async: true

  @forbidden [
    "System." <> "get_env",
    "System." <> "fetch_env",
    "System." <> "fetch_env!",
    "System." <> "put_env",
    "System." <> "delete_env",
    "JIDO_INTEGRATION" <> "_V2_GITHUB_"
  ]

  @globs [
    "lib/**/*.ex",
    "test/**/*.exs",
    "examples/**/*.exs",
    "scripts/*",
    "README.md",
    "docs/**/*.md"
  ]

  test "package code, scripts, examples, tests, and docs do not define env-var contracts" do
    package_root = File.cwd!()

    offenders =
      @globs
      |> Enum.flat_map(&Path.wildcard(Path.join(package_root, &1)))
      |> Enum.reject(&File.dir?/1)
      |> Enum.flat_map(fn path ->
        body = File.read!(path)

        for forbidden <- @forbidden,
            String.contains?(body, forbidden) do
          "#{Path.relative_to(path, package_root)} contains #{forbidden}"
        end
      end)

    assert offenders == []
  end
end
