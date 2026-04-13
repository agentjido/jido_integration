defmodule Jido.Integration.V2.Connectors.Notion.InstallBindingTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.InstallBinding
  alias Pristine.OAuth2.Token

  test "builds durable install attrs from an oauth token while keeping refresh off the lease" do
    profile =
      Notion.manifest().auth
      |> AuthSpec.default_profile()

    binding =
      InstallBinding.from_token(%Token{
        access_token: "secret-access",
        refresh_token: "secret-refresh",
        expires_at: 1_773_403_200,
        other_params: %{
          "workspace_id" => "workspace-acme",
          "workspace_name" => "Acme Workspace",
          "bot_id" => "bot-acme"
        }
      })

    assert binding.secret == %{
             access_token: "secret-access",
             refresh_token: "secret-refresh",
             workspace_id: "workspace-acme",
             workspace_name: "Acme Workspace",
             bot_id: "bot-acme"
           }

    assert binding.lease_fields == profile.lease_fields

    assert binding.metadata == %{
             workspace_id: "workspace-acme",
             workspace_name: "Acme Workspace",
             bot_id: "bot-acme"
           }

    assert binding.expires_at == ~U[2026-03-13 12:00:00Z]

    complete_install_attrs =
      InstallBinding.complete_install_attrs("workspace:acme", ["notion.content.read"], binding)

    assert complete_install_attrs.subject == "workspace:acme"
    assert complete_install_attrs.granted_scopes == ["notion.content.read"]
    assert complete_install_attrs.secret == binding.secret
    assert complete_install_attrs.lease_fields == binding.lease_fields
    assert complete_install_attrs.metadata == binding.metadata
    assert complete_install_attrs.expires_at == binding.expires_at
  end

  test "builds install attrs from package-local live env overrides when exchange is skipped" do
    profile =
      Notion.manifest().auth
      |> AuthSpec.default_profile()

    binding =
      InstallBinding.from_live_spec(%{
        access_token: "secret-access",
        refresh_token: "secret-refresh",
        workspace_id: "workspace-acme",
        workspace_name: "Acme Workspace",
        bot_id: "bot-acme"
      })

    assert binding.secret == %{
             access_token: "secret-access",
             refresh_token: "secret-refresh",
             workspace_id: "workspace-acme",
             workspace_name: "Acme Workspace",
             bot_id: "bot-acme"
           }

    assert binding.lease_fields == profile.lease_fields

    assert binding.metadata == %{
             workspace_id: "workspace-acme",
             workspace_name: "Acme Workspace",
             bot_id: "bot-acme"
           }

    assert binding.expires_at == nil
  end
end
