defmodule Jido.Integration.V2.Connectors.Notion.LiveEnvTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Notion.LiveEnv

  @env LiveEnv.env_names()

  test "defaults to deterministic offline mode when live env vars are absent" do
    spec = LiveEnv.spec(%{})

    refute spec.live_enabled?
    refute spec.write_enabled?
    assert spec.client_id == nil
    assert spec.client_secret == nil
    assert spec.redirect_uri == nil
    assert spec.auth_code == nil
    assert spec.callback_url == nil
    assert spec.access_token == nil
    assert spec.refresh_token == nil
    assert spec.read_page_id == nil
    assert spec.write_parent_data_source_id == nil
    assert spec.write_title_property == "Name"
    assert spec.workspace_id == nil
    assert spec.workspace_name == nil
    assert spec.bot_id == nil
    assert spec.subject == "notion-live-proof"
    assert spec.actor_id == "notion-live-proof"
    assert spec.tenant_id == "tenant-notion-live"
    assert spec.write_page_title == "Jido live acceptance page"
    assert spec.api_base_url == nil
    assert spec.timeout_ms == nil
  end

  test "auth validation requires the live gate and oauth client settings" do
    assert {:error, missing} = LiveEnv.validate(:auth, %{})
    assert missing == [@env.live, @env.client_id, @env.client_secret, @env.redirect_uri]

    assert :ok =
             LiveEnv.validate(:auth, %{
               @env.live => "1",
               @env.client_id => "client-id",
               @env.client_secret => "client-secret",
               @env.redirect_uri => "https://example.test/notion/callback"
             })
  end

  test "read validation requires a live token and read page id" do
    assert {:error, missing} =
             LiveEnv.validate(:read, %{
               @env.live => "1"
             })

    assert missing == [@env.access_token, @env.read_page_id]
  end

  test "write validation requires the separate write gate and a parent data source id" do
    assert {:error, missing} =
             LiveEnv.validate(:write, %{
               @env.live => "1",
               @env.access_token => "secret-token",
               @env.read_page_id => "00000000-0000-0000-0000-000000000010"
             })

    assert missing == [@env.live_write, @env.write_parent_data_source_id]
  end

  test "normalizes live settings and optional overrides" do
    spec =
      LiveEnv.spec(%{
        @env.live => "true",
        @env.live_write => "yes",
        @env.client_id => "client-id",
        @env.client_secret => "client-secret",
        @env.redirect_uri => "https://example.test/notion/callback",
        @env.auth_code => "temporary-code",
        @env.callback_url => "https://example.test/notion/callback?code=temporary-code",
        @env.access_token => "secret-token",
        @env.refresh_token => "refresh-token",
        @env.read_page_id => "00000000-0000-0000-0000-000000000010",
        @env.write_parent_data_source_id => "00000000-0000-0000-0000-000000000020",
        @env.write_title_property => "Title",
        @env.workspace_id => "workspace-acme",
        @env.workspace_name => "Acme Workspace",
        @env.bot_id => "bot-acme",
        @env.subject => "workspace:acme",
        @env.actor_id => "operator-1",
        @env.tenant_id => "tenant-1",
        @env.write_page_title => "Ship live proof",
        @env.api_base_url => "https://api.notion.test",
        @env.timeout_ms => "20000"
      })

    assert spec.live_enabled?
    assert spec.write_enabled?
    assert spec.client_id == "client-id"
    assert spec.client_secret == "client-secret"
    assert spec.redirect_uri == "https://example.test/notion/callback"
    assert spec.auth_code == "temporary-code"
    assert spec.callback_url == "https://example.test/notion/callback?code=temporary-code"
    assert spec.access_token == "secret-token"
    assert spec.refresh_token == "refresh-token"
    assert spec.read_page_id == "00000000-0000-0000-0000-000000000010"
    assert spec.write_parent_data_source_id == "00000000-0000-0000-0000-000000000020"
    assert spec.write_title_property == "Title"
    assert spec.workspace_id == "workspace-acme"
    assert spec.workspace_name == "Acme Workspace"
    assert spec.bot_id == "bot-acme"
    assert spec.subject == "workspace:acme"
    assert spec.actor_id == "operator-1"
    assert spec.tenant_id == "tenant-1"
    assert spec.write_page_title == "Ship live proof"
    assert spec.api_base_url == "https://api.notion.test"
    assert spec.timeout_ms == 20_000
  end
end
