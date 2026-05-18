defmodule Jido.Integration.Secrets.ProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Secrets.Broker
  alias Jido.Integration.Secrets.EnvProvider
  alias Jido.Integration.Secrets.EphemeralProvider
  alias Jido.Integration.Secrets.KeyringProvider

  test "env provider materializes a scoped handle and keeps receipts redacted" do
    assert {:ok, result} =
             Broker.with_materialized(
               EnvProvider,
               "lease://linear/live/1",
               %{env_var: "LINEAR_API_KEY", secret_key: :api_key},
               fn material, public_ref ->
                 assert material == %{api_key: "lin_api_secret"}
                 refute inspect(public_ref) =~ "lin_api_secret"
                 {:ok, Broker.public_receipt(public_ref, :used)}
               end,
               env: %{"LINEAR_API_KEY" => "lin_api_secret"}
             )

    assert result.secret_material_redacted? == true
    assert result.provider_ref == "env://LINEAR_API_KEY"
    refute inspect(result) =~ "lin_api_secret"
  end

  test "ephemeral provider keeps stdin material inside the broker callback" do
    materializer = fn -> %{api_key: "stdin-secret"} end

    assert {:ok, :called} =
             Broker.with_materialized(
               EphemeralProvider,
               "lease://linear/stdin/1",
               %{provider_ref: "ephemeral://stdin", secret_key: :api_key},
               fn material, public_ref ->
                 assert material.api_key == "stdin-secret"
                 refute inspect(public_ref) =~ "stdin-secret"
                 {:ok, :called}
               end,
               secret_materializer: materializer
             )
  end

  test "keyring provider fails closed for dev keys in production" do
    keyring = %{entries: %{"dev-local-1" => %{api_key: "secret"}}}

    assert {:error, {:dev_local_key_rejected, "dev-local-1"}} =
             KeyringProvider.materialize(
               "lease://prod/1",
               %{key_id: "dev-local-1"},
               keyring: keyring,
               runtime_env: :prod
             )
  end

  test "keyring provider emits rotation, revocation, and audit refs without material" do
    keyring = %{
      entries: %{"kms-prod-1" => %{api_key: "prod-secret"}},
      rotation_posture_by_key_id: %{"kms-prod-1" => :kms_managed}
    }

    assert {:ok, result} =
             Broker.with_materialized(
               KeyringProvider,
               "lease://prod/2",
               %{key_id: "kms-prod-1"},
               fn material, public_ref ->
                 assert material.api_key == "prod-secret"
                 {:ok, Broker.public_receipt(public_ref, :used)}
               end,
               keyring: keyring,
               runtime_env: :prod
             )

    assert result.provider_ref == "keyring://kms-prod-1"
    refute inspect(result) =~ "prod-secret"

    assert {:ok, %{status: :rotation_requested, next_key_id: "kms-prod-2"}} =
             KeyringProvider.rotate("binding://linear/main", next_key_id: "kms-prod-2")

    assert {:ok, %{status: :revoked, recovery_owner: :secrets_operator}} =
             KeyringProvider.revoke("lease://prod/2", key_id: "kms-prod-1")
  end
end
