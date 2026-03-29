defmodule Jido.Integration.Package.PublicSurfaceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.ControlPlane.Registry

  setup do
    Registry.reset!()
    on_exit(&Registry.reset!/0)
    :ok
  end

  test "the welded package exposes the unified public discovery surface" do
    for connector <- [GitHub, Notion] do
      assert :ok = V2.register_connector(connector)
    end

    assert Enum.map(V2.connectors(), & &1.connector) == ["github", "notion"]

    assert {:ok, github_manifest} = V2.fetch_connector("github")
    assert github_manifest.connector == "github"

    assert {:ok, capability} = V2.fetch_capability("github.issue.create")
    assert capability.runtime_class == :direct

    assert V2.projected_catalog_entries()
           |> Enum.map(& &1.connector_id)
           |> Enum.sort() == ["github", "notion"]
  end
end
