defmodule Jido.Integration.V2.Connectors.Notion do
  @moduledoc """
  Thin direct Notion connector package backed by `notion_sdk`.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.Notion.OperationCatalog
  alias Jido.Integration.V2.Connectors.Notion.TriggerCatalog
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "notion",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          default_profile: "workspace_oauth",
          supported_profiles: [
            %{
              id: "workspace_oauth",
              auth_type: :oauth2,
              subject_kind: :workspace,
              install_required: true,
              grant_types: [:authorization_code, :refresh_token],
              callback_required: true,
              pkce_required: false,
              refresh_supported: true,
              revoke_supported: true,
              reauth_supported: true,
              durable_secret_fields: [
                "access_token",
                "refresh_token",
                "workspace_id",
                "workspace_name",
                "bot_id"
              ],
              lease_fields: ["access_token", "workspace_id", "workspace_name", "bot_id"],
              management_modes: [:manual],
              required_scopes: requested_scopes(),
              docs_refs: ["https://developers.notion.com/docs/authorization"],
              metadata: %{provider: :notion_sdk, install_surface: :browser_oauth}
            }
          ],
          install: %{
            required: true,
            profiles: ["workspace_oauth"],
            hosted_callback_supported: false,
            state_required: true,
            pkce_supported: false,
            metadata: %{approval: :browser_oauth}
          },
          reauth: %{
            supported: true,
            profiles: ["workspace_oauth"],
            hosted_callback_supported: false,
            state_required: true,
            pkce_supported: false,
            metadata: %{reuse_install_path: true}
          },
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Notion",
          description: "Notion content workflows backed by notion_sdk",
          category: "knowledge_management",
          tags: ["notion", "pages", "comments"],
          docs_refs: ["https://developers.notion.com/reference/intro"],
          maturity: :beta,
          publication: :public
        }),
      operations: OperationCatalog.published_operations(),
      triggers: TriggerCatalog.published_triggers(),
      runtime_families: [:direct],
      metadata: %{
        provider_sdk: :notion_sdk,
        published_slice: :a0_content_publishing,
        published_trigger_slice: :recent_page_edits
      }
    })
  end

  defp requested_scopes do
    operations =
      OperationCatalog.published_operations()
      |> Enum.flat_map(& &1.permissions.permission_bundle)

    triggers =
      TriggerCatalog.published_triggers()
      |> Enum.flat_map(&Contracts.get(&1.permissions, :required_scopes, []))

    (operations ++ triggers)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
