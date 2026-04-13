defmodule Jido.Integration.V2.Connectors.Linear do
  @moduledoc """
  Thin direct Linear connector package backed by `linear_sdk`.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.Linear.OperationCatalog
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "linear",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          management_modes: [:external_secret, :hosted, :manual],
          requested_scopes: requested_scopes(),
          durable_secret_fields: ["access_token", "api_key", "refresh_token"],
          lease_fields: ["access_token", "api_key"],
          default_profile: "api_key_user",
          supported_profiles: [
            %{
              id: "api_key_user",
              auth_type: :api_token,
              subject_kind: :user,
              install_required: true,
              grant_types: [:manual_token],
              callback_required: false,
              refresh_supported: false,
              revoke_supported: false,
              reauth_supported: false,
              external_secret_supported: true,
              durable_secret_fields: ["api_key"],
              lease_fields: ["api_key"],
              management_modes: [:external_secret, :manual],
              required_scopes: requested_scopes(),
              docs_refs: [
                "https://linear.app/docs/api/graphql/getting-started",
                "https://linear.app/docs/api/authentication"
              ],
              metadata: %{provider: :linear_sdk, token_kind: :api_key_user}
            },
            %{
              id: "oauth_user",
              auth_type: :oauth2,
              subject_kind: :user,
              install_required: true,
              grant_types: [:authorization_code, :refresh_token],
              callback_required: true,
              pkce_required: true,
              refresh_supported: true,
              revoke_supported: false,
              reauth_supported: true,
              external_secret_supported: true,
              durable_secret_fields: ["access_token", "refresh_token"],
              lease_fields: ["access_token"],
              management_modes: [:external_secret, :hosted, :manual],
              required_scopes: requested_scopes(),
              docs_refs: [
                "https://linear.app/docs/oauth/authentication",
                "https://linear.app/docs/oauth/scopes"
              ],
              metadata: %{provider: :linear_sdk, token_kind: :oauth_user}
            }
          ],
          install: %{
            required: true,
            profiles: ["api_key_user", "oauth_user"],
            hosted_callback_supported: true,
            callback_route_kind: "oauth_callback",
            state_required: true,
            pkce_supported: true,
            metadata: %{
              completion_modes: [:hosted_callback, :manual_callback],
              approval_by_profile: %{
                api_key_user: :manual_token_entry,
                oauth_user: :browser_oauth
              }
            }
          },
          reauth: %{
            supported: true,
            profiles: ["oauth_user"],
            hosted_callback_supported: true,
            state_required: true,
            pkce_supported: true,
            metadata: %{reuse_install_path: true}
          },
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Linear",
          description: "Linear issue workflows backed by linear_sdk",
          category: "developer_tools",
          tags: ["linear", "issues", "comments"],
          docs_refs: ["https://linear.app/docs/api/graphql/getting-started"],
          maturity: :beta,
          publication: :public
        }),
      operations: OperationCatalog.published_operations(),
      triggers: [],
      runtime_families: [:direct],
      metadata: %{
        provider_sdk: :linear_sdk,
        published_slice: :a0_issue_workflows
      }
    })
  end

  defp requested_scopes do
    OperationCatalog.published_operations()
    |> Enum.flat_map(& &1.permissions.permission_bundle)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
