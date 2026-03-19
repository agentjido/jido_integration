defmodule Jido.Integration.V2.Connectors.GitHub do
  @moduledoc """
  Thin direct GitHub connector package backed by `github_ex`.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.GitHub.OperationCatalog
  alias Jido.Integration.V2.Manifest

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
          requested_scopes: ["repo"],
          lease_fields: ["access_token"],
          secret_names: ["webhook_secret"]
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "GitHub",
          description: "GitHub issue and comment workflows backed by github_ex",
          category: "developer_tools",
          tags: ["github", "issues", "comments"],
          docs_refs: ["https://docs.github.com/rest/issues"],
          maturity: :beta,
          publication: :public
        }),
      operations: OperationCatalog.published_operations(),
      triggers: [],
      runtime_families: [:direct],
      metadata: %{
        provider_sdk: :github_ex,
        published_slice: :a0_issue_workflows
      }
    })
  end
end
