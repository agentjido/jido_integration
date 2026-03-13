defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector do
  @moduledoc false

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueHandler
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "github",
      capabilities: [
        Capability.new!(%{
          id: "github.issue.ingest",
          connector: "github",
          runtime_class: :direct,
          kind: :trigger,
          transport_profile: :webhook,
          handler: GitHubIssueHandler,
          metadata: %{
            required_scopes: []
          }
        })
      ]
    })
  end
end
