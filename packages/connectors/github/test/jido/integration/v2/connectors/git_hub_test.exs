defmodule Jido.Integration.V2.Connectors.GitHubTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Connectors.GitHub

  test "publishes a direct capability manifest" do
    manifest = GitHub.manifest()
    [capability] = manifest.capabilities

    assert manifest.connector == "github"
    assert capability.id == "github.issue.create"
    assert capability.runtime_class == :direct
    assert capability.metadata.required_scopes == ["repo"]
    assert capability.metadata.policy.environment.allowed == [:prod, :staging]
    assert capability.metadata.policy.sandbox.allowed_tools == ["github.api.issue.create"]
  end
end
