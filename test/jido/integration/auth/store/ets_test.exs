defmodule Jido.Integration.Auth.Store.ETSTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.{Credential, Store.ETS}

  setup do
    {:ok, store} = ETS.start_link(name: :"ets_store_#{System.unique_integer([:positive])}")
    %{store: store}
  end

  describe "store/3 and fetch/2" do
    test "roundtrip: store and fetch credential", %{store: store} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      auth_ref = "auth:github:org-123"

      assert :ok = ETS.store(store, auth_ref, cred)
      assert {:ok, fetched} = ETS.fetch(store, auth_ref)
      assert fetched.type == :api_key
      assert fetched.key == "sk-abc"
    end

    test "store overwrites existing credential (upsert)", %{store: store} do
      {:ok, cred1} = Credential.new(%{type: :api_key, key: "sk-old"})
      {:ok, cred2} = Credential.new(%{type: :api_key, key: "sk-new"})
      auth_ref = "auth:github:org-123"

      :ok = ETS.store(store, auth_ref, cred1)
      :ok = ETS.store(store, auth_ref, cred2)

      {:ok, fetched} = ETS.fetch(store, auth_ref)
      assert fetched.key == "sk-new"
    end

    test "fetch returns :not_found for unknown auth_ref", %{store: store} do
      assert {:error, :not_found} = ETS.fetch(store, "auth:nope:nope")
    end
  end

  describe "fetch with scope enforcement" do
    test "fetch with matching connector_id succeeds", %{store: store} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      :ok = ETS.store(store, "auth:github:org-123", cred)

      assert {:ok, _} = ETS.fetch(store, "auth:github:org-123", connector_id: "github")
    end

    test "fetch with mismatched connector_id returns scope_violation", %{store: store} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      :ok = ETS.store(store, "auth:github:org-123", cred)

      assert {:error, :scope_violation} =
               ETS.fetch(store, "auth:github:org-123", connector_id: "linear")
    end

    test "fetch without connector_id context skips scope check", %{store: store} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      :ok = ETS.store(store, "auth:github:org-123", cred)

      assert {:ok, _} = ETS.fetch(store, "auth:github:org-123")
    end
  end

  describe "delete/2" do
    test "removes a stored credential", %{store: store} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-abc"})
      :ok = ETS.store(store, "auth:github:org-123", cred)

      assert :ok = ETS.delete(store, "auth:github:org-123")
      assert {:error, :not_found} = ETS.fetch(store, "auth:github:org-123")
    end

    test "delete unknown ref returns :not_found", %{store: store} do
      assert {:error, :not_found} = ETS.delete(store, "auth:nope:nope")
    end
  end

  describe "list/2" do
    test "lists all credentials for a connector type", %{store: store} do
      {:ok, c1} = Credential.new(%{type: :api_key, key: "sk-1"})
      {:ok, c2} = Credential.new(%{type: :api_key, key: "sk-2"})
      {:ok, c3} = Credential.new(%{type: :api_key, key: "sk-3"})

      :ok = ETS.store(store, "auth:github:org-1", c1)
      :ok = ETS.store(store, "auth:github:org-2", c2)
      :ok = ETS.store(store, "auth:linear:ws-1", c3)

      github_creds = ETS.list(store, "github")
      assert length(github_creds) == 2

      assert Enum.all?(github_creds, fn {ref, _cred} ->
               String.starts_with?(ref, "auth:github:")
             end)

      linear_creds = ETS.list(store, "linear")
      assert length(linear_creds) == 1
    end

    test "list returns empty for unknown connector", %{store: store} do
      assert ETS.list(store, "nope") == []
    end
  end

  describe "TTL expiry" do
    test "expired credential returns :expired", %{store: store} do
      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_old",
          expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      :ok = ETS.store(store, "auth:github:org-expired", cred)

      assert {:error, :expired} = ETS.fetch(store, "auth:github:org-expired")
    end

    test "non-expiring credential never expires", %{store: store} do
      {:ok, cred} = Credential.new(%{type: :api_key, key: "sk-forever"})
      :ok = ETS.store(store, "auth:github:org-forever", cred)

      assert {:ok, _} = ETS.fetch(store, "auth:github:org-forever")
    end
  end
end
