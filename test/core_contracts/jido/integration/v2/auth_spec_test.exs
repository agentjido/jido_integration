defmodule Jido.Integration.V2.AuthSpecTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec

  test "normalizes profile-driven auth contracts and derives connector-level posture" do
    auth =
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
            required_scopes: ["notion.content.read", "notion.content.update"],
            docs_refs: ["notion_sdk/guides/oauth-and-auth-overrides.md"],
            metadata: %{provider: :notion_sdk}
          }
        ],
        install: %{
          required: true,
          hosted_callback_supported: false,
          state_required: true,
          pkce_supported: false
        },
        reauth: %{
          supported: true,
          hosted_callback_supported: false,
          state_required: true,
          pkce_supported: false
        },
        secret_names: []
      })

    assert auth.auth_type == :oauth2
    assert auth.default_profile == "workspace_oauth"
    assert auth.management_modes == [:manual]

    assert auth.requested_scopes == ["notion.content.read", "notion.content.update"]

    assert auth.durable_secret_fields == [
             "access_token",
             "bot_id",
             "refresh_token",
             "workspace_id",
             "workspace_name"
           ]

    assert auth.lease_fields == ["access_token", "bot_id", "workspace_id", "workspace_name"]
    assert auth.install.profiles == ["workspace_oauth"]
    assert auth.reauth.profiles == ["workspace_oauth"]

    assert [profile] = auth.supported_profiles
    assert profile.id == "workspace_oauth"
    assert profile.auth_type == :oauth2
    assert profile.subject_kind == :workspace
    assert profile.callback_required == true
    assert profile.pkce_required == false
    assert profile.refresh_supported == true
    assert profile.revoke_supported == true
    assert profile.reauth_supported == true
    assert profile.external_secret_supported == false
    assert profile.metadata.provider == :notion_sdk
  end

  test "normalizes the legacy auth shape into one default profile" do
    auth =
      AuthSpec.new!(%{
        binding_kind: :connection_id,
        auth_type: :api_token,
        install: %{required: true},
        reauth: %{supported: false},
        requested_scopes: ["repo"],
        lease_fields: ["access_token"],
        secret_names: []
      })

    assert auth.auth_type == :api_token
    assert auth.default_profile == "default"
    assert auth.management_modes == [:manual]
    assert auth.durable_secret_fields == ["access_token"]
    assert auth.install.profiles == ["default"]
    assert auth.reauth.profiles == []

    assert [profile] = auth.supported_profiles
    assert profile.id == "default"
    assert profile.auth_type == :api_token
    assert profile.subject_kind == :user
    assert profile.install_required == true
    assert profile.grant_types == [:manual_token]
    assert profile.management_modes == [:manual]
    assert profile.required_scopes == ["repo"]
  end

  test "rejects invalid profile posture" do
    assert_raise ArgumentError, ~r/pkce_required/, fn ->
      AuthSpec.new!(%{
        binding_kind: :connection_id,
        supported_profiles: [
          %{
            id: "broken",
            auth_type: :oauth2,
            subject_kind: :user,
            install_required: true,
            grant_types: [:refresh_token],
            callback_required: false,
            pkce_required: true,
            durable_secret_fields: ["access_token", "refresh_token"],
            lease_fields: ["access_token"],
            management_modes: [:manual]
          }
        ],
        default_profile: "broken",
        secret_names: []
      })
    end
  end

  test "allows explicit external-only lease fields for provider-managed refresh flows" do
    auth =
      AuthSpec.new!(%{
        binding_kind: :connection_id,
        default_profile: "provider_oauth",
        supported_profiles: [
          %{
            id: "provider_oauth",
            auth_type: :oauth2,
            subject_kind: :workspace,
            install_required: true,
            grant_types: [:authorization_code, :refresh_token],
            callback_required: true,
            refresh_supported: true,
            durable_secret_fields: ["workspace_id"],
            lease_fields: ["access_token", "refresh_token", "workspace_id"],
            external_secret_supported: true,
            external_secret_lease_fields: ["access_token", "refresh_token"],
            management_modes: [:provider_app]
          }
        ],
        secret_names: []
      })

    [profile] = auth.supported_profiles
    assert profile.external_secret_supported == true
    assert profile.external_secret_lease_fields == ["access_token", "refresh_token"]
  end
end
