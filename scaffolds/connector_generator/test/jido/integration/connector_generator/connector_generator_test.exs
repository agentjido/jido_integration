defmodule Jido.Integration.ConnectorGeneratorTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.ConnectorGenerator

  test "builds an external companion skeleton with conformance tests and docs" do
    files = Map.new(ConnectorGenerator.external_companion_files("safe-companion"))

    assert Map.has_key?(files, "README.md")
    assert Map.has_key?(files, "mix.exs")
    assert Map.has_key?(files, "lib/external_companions/safe_companion.ex")
    assert Map.has_key?(files, "test/external_companions/safe_companion_conformance_test.exs")

    readme = Map.fetch!(files, "README.md")
    connector = Map.fetch!(files, "lib/external_companions/safe_companion.ex")

    conformance_test =
      Map.fetch!(files, "test/external_companions/safe_companion_conformance_test.exs")

    assert String.contains?(readme, "explicit host app config")
    assert String.contains?(readme, "No provider token")
    assert String.contains?(connector, "contract_version: \"connector-sdk.v1\"")
    assert String.contains?(connector, "tenant_scope: :tenant_scoped")
    assert String.contains?(conformance_test, "ConformanceContracts.Case")

    refute String.contains?(connector, "System.get_env")
    refute String.contains?(connector, "authorization_header")
  end

  test "rejects unsafe connector names without pattern engines" do
    assert_raise ArgumentError, fn ->
      ConnectorGenerator.external_companion_files("Unsafe Name")
    end
  end
end
