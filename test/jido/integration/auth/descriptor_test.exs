defmodule Jido.Integration.Auth.DescriptorTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.Descriptor

  @valid_oauth2 %{
    "id" => "oauth2",
    "type" => "oauth2",
    "display_name" => "GitHub OAuth2",
    "secret_refs" => ["client_id", "client_secret"],
    "scopes" => ["repo", "read:org"],
    "token_semantics" => "bearer",
    "rotation_policy" => %{"required" => false, "interval_days" => nil},
    "tenant_binding" => "tenant_only",
    "health_check" => %{"enabled" => true, "interval_s" => 3600},
    "oauth" => %{
      "grant_type" => "authorization_code",
      "auth_url" => "https://github.com/login/oauth/authorize",
      "token_url" => "https://github.com/login/oauth/access_token",
      "pkce_required" => false,
      "refresh_supported" => true
    }
  }

  @valid_api_key %{
    "id" => "api_key",
    "type" => "api_key",
    "display_name" => "API Key",
    "secret_refs" => ["api_key"],
    "scopes" => [],
    "token_semantics" => "none"
  }

  @valid_none %{
    "id" => "none",
    "type" => "none",
    "display_name" => "No Auth"
  }

  describe "new/1" do
    test "creates OAuth2 descriptor" do
      assert {:ok, desc} = Descriptor.new(@valid_oauth2)
      assert desc.id == "oauth2"
      assert desc.type == "oauth2"
      assert desc.display_name == "GitHub OAuth2"
      assert desc.secret_refs == ["client_id", "client_secret"]
      assert desc.scopes == ["repo", "read:org"]
      assert desc.oauth != nil
    end

    test "creates API key descriptor" do
      assert {:ok, desc} = Descriptor.new(@valid_api_key)
      assert desc.type == "api_key"
      assert desc.secret_refs == ["api_key"]
    end

    test "creates no-auth descriptor" do
      assert {:ok, desc} = Descriptor.new(@valid_none)
      assert desc.type == "none"
      assert desc.secret_refs == []
    end

    test "sets defaults for optional fields" do
      {:ok, desc} = Descriptor.new(@valid_none)
      assert desc.rotation_policy == %{"required" => false, "interval_days" => nil}
      assert desc.tenant_binding == "tenant_only"
      assert desc.health_check == %{"enabled" => false, "interval_s" => 3600}
    end

    test "rejects missing required fields" do
      assert {:error, error} = Descriptor.new(%{})
      assert error.class == :invalid_request
      assert error.message =~ "missing"
    end

    test "rejects invalid auth type" do
      attrs = Map.put(@valid_none, "type", "bearer_token")
      assert {:error, error} = Descriptor.new(attrs)
      assert error.message =~ "Invalid auth type"
    end
  end

  describe "valid_types/0" do
    test "returns all five auth types" do
      types = Descriptor.valid_types()
      assert "api_key" in types
      assert "oauth2" in types
      assert "service_account" in types
      assert "session_token" in types
      assert "none" in types
      assert length(types) == 5
    end
  end

  describe "to_map/1" do
    test "round-trips OAuth2 descriptor" do
      {:ok, desc} = Descriptor.new(@valid_oauth2)
      map = Descriptor.to_map(desc)
      assert map["id"] == "oauth2"
      assert map["type"] == "oauth2"
      assert map["oauth"] != nil
    end

    test "excludes nil oauth from map" do
      {:ok, desc} = Descriptor.new(@valid_none)
      map = Descriptor.to_map(desc)
      refute Map.has_key?(map, "oauth")
    end
  end
end
