defmodule Jido.Integration.V2.Connectors.GitHub.InstallBindingTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.InstallBinding
  alias Pristine.OAuth2.Token

  test "builds durable install attrs from a personal access token" do
    profile =
      GitHub.manifest().auth
      |> AuthSpec.fetch_profile("personal_access_token")

    binding = InstallBinding.from_personal_access_token("ghp_demo_pat")

    assert binding.profile_id == "personal_access_token"
    assert binding.secret == %{access_token: "ghp_demo_pat"}
    assert binding.lease_fields == profile.lease_fields

    assert binding.metadata == %{
             profile_id: "personal_access_token",
             token_kind: :personal_access_token
           }

    assert binding.expires_at == nil

    complete_install_attrs =
      InstallBinding.complete_install_attrs("octocat", ["repo"], binding)

    assert complete_install_attrs.subject == "octocat"
    assert complete_install_attrs.granted_scopes == ["repo"]
    assert complete_install_attrs.secret == %{access_token: "ghp_demo_pat"}
    assert complete_install_attrs.lease_fields == ["access_token"]
    assert complete_install_attrs.metadata.profile_id == "personal_access_token"
  end

  test "builds durable install attrs from an oauth token while keeping refresh off the lease" do
    profile =
      GitHub.manifest().auth
      |> AuthSpec.fetch_profile("oauth_user")

    binding =
      InstallBinding.from_oauth_token(%Token{
        access_token: "gho_oauth",
        refresh_token: "ghr_oauth",
        expires_at: 1_773_403_200
      })

    assert binding.profile_id == "oauth_user"
    assert binding.secret == %{access_token: "gho_oauth", refresh_token: "ghr_oauth"}
    assert binding.lease_fields == profile.lease_fields
    assert binding.metadata == %{profile_id: "oauth_user", token_kind: :oauth_user}
    assert binding.expires_at == ~U[2026-03-13 12:00:00Z]
  end
end
