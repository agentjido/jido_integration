defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector do
  @moduledoc false

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueHandler
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.TriggerSpec

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "github",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: [],
          lease_fields: ["access_token"],
          secret_names: ["webhook_secret"]
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "GitHub Incident Trigger",
          description: "Hosted webhook trigger for GitHub issue events",
          category: "developer_tools",
          tags: ["github", "webhook"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [],
      triggers: [
        TriggerSpec.new!(%{
          trigger_id: "github.issue.ingest",
          name: "issue_ingest",
          display_name: "Issue ingest",
          description: "Receives hosted GitHub issue webhooks",
          runtime_class: :direct,
          delivery_mode: :webhook,
          handler: GitHubIssueHandler,
          config_schema: Zoi.map(description: "Webhook config"),
          signal_schema: Zoi.map(description: "Webhook signal"),
          permissions: %{required_scopes: []},
          checkpoint: %{},
          dedupe: %{},
          verification: %{secret_name: "webhook_secret"},
          jido: %{sensor: %{name: "github_issue_ingest"}}
        })
      ],
      runtime_families: [:direct]
    })
  end
end
