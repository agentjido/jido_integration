defmodule Jido.Integration.V2.Connectors.CodexCli.NoEnvContractTest do
  use ExUnit.Case, async: true

  @package_root Path.expand("../../../../../..", __DIR__)
  @forbidden [
    "System." <> "get_env",
    "System." <> "fetch_env",
    "System." <> "fetch_env!",
    "System." <> "put_env",
    "System." <> "delete_env",
    "MIX" <> "_ENV",
    "JIDO_INTEGRATION" <> "_WORKSPACE"
  ]

  test "package docs do not define process-env live contracts" do
    paths = [Path.join(@package_root, "README.md")]

    offenders =
      for path <- paths,
          text = File.read!(path),
          forbidden <- @forbidden,
          String.contains?(text, forbidden) do
        {Path.relative_to(path, @package_root), forbidden}
      end

    assert offenders == []
  end
end
