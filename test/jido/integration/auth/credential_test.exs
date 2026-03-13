defmodule Jido.Integration.Auth.CredentialTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.Credential

  describe "new/1 for oauth2" do
    test "creates oauth2 credential with required fields" do
      assert {:ok, cred} =
               Credential.new(%{
                 type: :oauth2,
                 access_token: "gho_abc123",
                 refresh_token: "ghr_xyz789",
                 expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
                 scopes: ["repo", "read:org"],
                 token_semantics: "bearer"
               })

      assert cred.type == :oauth2
      assert cred.access_token == "gho_abc123"
      assert cred.refresh_token == "ghr_xyz789"
      assert cred.scopes == ["repo", "read:org"]
      assert cred.token_semantics == "bearer"
    end

    test "oauth2 without refresh_token is valid" do
      assert {:ok, cred} =
               Credential.new(%{
                 type: :oauth2,
                 access_token: "gho_abc123",
                 expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
               })

      assert cred.refresh_token == nil
    end

    test "oauth2 requires access_token" do
      assert {:error, error} =
               Credential.new(%{
                 type: :oauth2,
                 expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
               })

      assert error.class == :invalid_request
      assert error.message =~ "access_token"
    end
  end

  describe "new/1 for api_key" do
    test "creates api_key credential" do
      assert {:ok, cred} =
               Credential.new(%{
                 type: :api_key,
                 key: "sk-abc123",
                 scopes: ["read", "write"]
               })

      assert cred.type == :api_key
      assert cred.key == "sk-abc123"
      assert cred.scopes == ["read", "write"]
    end

    test "api_key requires key" do
      assert {:error, error} = Credential.new(%{type: :api_key})
      assert error.message =~ "key"
    end
  end

  describe "new/1 for service_account" do
    test "creates service_account credential" do
      assert {:ok, cred} =
               Credential.new(%{
                 type: :service_account,
                 key: "sa-cred-json",
                 scopes: ["admin"]
               })

      assert cred.type == :service_account
      assert cred.key == "sa-cred-json"
    end
  end

  describe "new/1 for session_token" do
    test "creates session_token credential" do
      assert {:ok, cred} =
               Credential.new(%{
                 type: :session_token,
                 access_token: "sess_abc",
                 expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
               })

      assert cred.type == :session_token
      assert cred.access_token == "sess_abc"
    end
  end

  describe "new/1 for webhook_secret" do
    test "creates webhook_secret credential" do
      assert {:ok, cred} =
               Credential.new(%{
                 type: :webhook_secret,
                 key: "whsec_abc123"
               })

      assert cred.type == :webhook_secret
      assert cred.key == "whsec_abc123"
    end
  end

  describe "new/1 validation" do
    test "rejects unknown type" do
      assert {:error, error} = Credential.new(%{type: :magic_token})
      assert error.message =~ "type"
    end

    test "rejects missing type" do
      assert {:error, error} = Credential.new(%{access_token: "abc"})
      assert error.message =~ "type"
    end
  end

  describe "expired?/1" do
    test "returns false when expires_at is in the future" do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_abc",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      refute Credential.expired?(cred)
    end

    test "returns true when expires_at is in the past" do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_abc",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      assert Credential.expired?(cred)
    end

    test "returns false when no expires_at (api_key)" do
      {:ok, cred} =
        Credential.new(%{
          type: :api_key,
          key: "sk-abc"
        })

      refute Credential.expired?(cred)
    end
  end

  describe "refreshable?/1" do
    test "oauth2 with refresh_token is refreshable" do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_abc",
          refresh_token: "ghr_xyz",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert Credential.refreshable?(cred)
    end

    test "oauth2 without refresh_token is not refreshable" do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_abc",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      refute Credential.refreshable?(cred)
    end

    test "api_key is not refreshable" do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      refute Credential.refreshable?(cred)
    end
  end

  describe "redact/1" do
    test "redacts sensitive fields from oauth2 credential" do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_abc123secret",
          refresh_token: "ghr_xyz789secret",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["repo"]
        })

      redacted = Credential.redact(cred)
      assert redacted.access_token == "***REDACTED***"
      assert redacted.refresh_token == "***REDACTED***"
      assert redacted.scopes == ["repo"]
      assert redacted.type == :oauth2
    end

    test "redacts key from api_key credential" do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-secret123"})
      redacted = Credential.redact(cred)
      assert redacted.key == "***REDACTED***"
    end
  end
end
