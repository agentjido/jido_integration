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
          management_modes: [:external_secret, :hosted, :manual],
          requested_scopes: ["repo"],
          durable_secret_fields: ["access_token", "refresh_token"],
          lease_fields: ["access_token"],
          default_profile: "personal_access_token",
          supported_profiles: [
            %{
              id: "oauth_user",
              auth_type: :oauth2,
              subject_kind: :user,
              install_required: true,
              grant_types: [:authorization_code, :refresh_token],
              callback_required: true,
              refresh_supported: true,
              revoke_supported: true,
              reauth_supported: true,
              external_secret_supported: true,
              durable_secret_fields: ["access_token", "refresh_token"],
              lease_fields: ["access_token"],
              management_modes: [:external_secret, :hosted, :manual],
              required_scopes: ["repo"],
              docs_refs: [
                "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps",
                "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps"
              ],
              metadata: %{token_kind: :oauth_user}
            },
            %{
              id: "personal_access_token",
              auth_type: :api_token,
              subject_kind: :user,
              install_required: true,
              grant_types: [:manual_token],
              external_secret_supported: true,
              durable_secret_fields: ["access_token"],
              lease_fields: ["access_token"],
              management_modes: [:external_secret, :manual],
              required_scopes: ["repo"],
              docs_refs: [
                "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens"
              ],
              metadata: %{token_kind: :personal_access_token}
            }
          ],
          install: %{
            required: true,
            profiles: ["oauth_user", "personal_access_token"],
            hosted_callback_supported: true,
            callback_route_kind: "oauth_callback",
            state_required: true,
            pkce_supported: false,
            metadata: %{
              completion_modes: [:hosted_callback, :manual_callback],
              approval_by_profile: %{
                oauth_user: :browser_oauth,
                personal_access_token: :manual_token_entry
              }
            }
          },
          reauth: %{
            supported: true,
            profiles: ["oauth_user"],
            hosted_callback_supported: true,
            state_required: true,
            pkce_supported: false,
            metadata: %{reuse_install_path: true}
          },
          secret_names: []
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
