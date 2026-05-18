defmodule Jido.Integration.V2.ProviderClassificationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ProviderClassification

  test "owns provider, adapter, and account status vocabularies" do
    assert "linear" in ProviderClassification.provider_ids()
    assert "graphql" in ProviderClassification.adapter_families()
    assert :asserted in ProviderClassification.provider_account_statuses()
    assert :connector_facade in ProviderClassification.adapter_placements()
    refute :shimmed in ProviderClassification.adapter_placements()
  end

  test "classifies public provider vocabulary by platform meaning" do
    assert {:ok, :authority_credential_identity_ref} =
             ProviderClassification.public_vocabulary_classification(:provider_account_ref)

    assert {:ok, :runtime_provider_pool_routing_ref} =
             ProviderClassification.public_vocabulary_classification("provider_pool_ref")

    assert {:error, {:unclassified_provider_public_vocabulary, :provider_secret_ref}} =
             ProviderClassification.public_vocabulary_classification(:provider_secret_ref)
  end
end
