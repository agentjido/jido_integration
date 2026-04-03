defmodule Jido.Integration.V2.Connectors.Linear.InstallBindingTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Connectors.Linear.InstallBinding
  alias Prismatic.OAuth2.Token

  test "builds durable install attrs from a Linear API key" do
    profile =
      Linear.manifest().auth
      |> AuthSpec.fetch_profile("api_key_user")

    binding = InstallBinding.from_api_key("lin_api_demo")

    assert binding.profile_id == "api_key_user"
    assert binding.secret == %{api_key: "lin_api_demo"}
    assert binding.lease_fields == profile.lease_fields

    assert binding.metadata == %{
             profile_id: "api_key_user",
             provider: :linear_sdk,
             token_kind: :api_key_user
           }

    assert binding.expires_at == nil

    complete_install_attrs =
      InstallBinding.complete_install_attrs("usr-linear-viewer", ["read", "write"], binding)

    assert complete_install_attrs.subject == "usr-linear-viewer"
    assert complete_install_attrs.granted_scopes == ["read", "write"]
    assert complete_install_attrs.secret == %{api_key: "lin_api_demo"}
    assert complete_install_attrs.lease_fields == ["api_key"]
    assert complete_install_attrs.metadata.profile_id == "api_key_user"
  end

  test "builds durable install attrs from an oauth token while keeping refresh off the lease" do
    profile =
      Linear.manifest().auth
      |> AuthSpec.fetch_profile("oauth_user")

    binding =
      InstallBinding.from_oauth_token(%Token{
        access_token: "lin_oauth_demo",
        refresh_token: "lin_refresh_demo",
        expires_at: 1_773_403_200
      })

    assert binding.profile_id == "oauth_user"
    assert binding.secret == %{access_token: "lin_oauth_demo", refresh_token: "lin_refresh_demo"}
    assert binding.lease_fields == profile.lease_fields

    assert binding.metadata == %{
             profile_id: "oauth_user",
             provider: :linear_sdk,
             token_kind: :oauth_user
           }

    assert binding.expires_at == ~U[2026-03-13 12:00:00Z]
  end
end
