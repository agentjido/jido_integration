defmodule Jido.ModelProviderRegistry.ProviderPool do
  @moduledoc """
  Provider-pool materialization contract for governed adaptive routing.
  """

  @required_fields [
    :provider_pool_ref,
    :tenant_ref,
    :authority_ref,
    :operation_policy_ref,
    :slots
  ]

  @slot_forbidden_material [
    :api_key,
    :authorization_header,
    :default_client,
    :direct_provider_sdk,
    :env,
    :provider_payload,
    :raw_provider_payload,
    :raw_secret,
    :raw_token,
    :standalone_auth,
    :token,
    :token_file
  ]

  @slot_required_fields [
    :slot_ref,
    :model_profile_ref,
    :governed_adapter_ref,
    :inference_adapter_ref
  ]

  @spec materialize(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def materialize(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- require_fields(attrs),
         {:ok, slots} <- normalize_slots(Map.fetch!(attrs, :slots)) do
      {:ok,
       %{
         provider_pool_ref: Map.fetch!(attrs, :provider_pool_ref),
         tenant_ref: Map.fetch!(attrs, :tenant_ref),
         authority_ref: Map.fetch!(attrs, :authority_ref),
         operation_policy_ref: Map.fetch!(attrs, :operation_policy_ref),
         slots: slots,
         raw_material_present?: false
       }}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    candidates = @required_fields ++ @slot_required_fields ++ @slot_forbidden_material
    Enum.find(candidates, key, &(Atom.to_string(&1) == key))
  end

  defp require_fields(attrs) do
    missing = Enum.reject(@required_fields, &present?(Map.get(attrs, &1)))
    if missing == [], do: :ok, else: {:error, {:missing_provider_pool_refs, missing}}
  end

  defp normalize_slots(slots) when is_list(slots) do
    normalized = Enum.map(slots, &normalize/1)

    rejected =
      normalized
      |> Enum.reject(&governed_slot?/1)
      |> Enum.map(&Map.get(&1, :slot_ref, "unknown-slot"))

    case rejected do
      [] -> {:ok, Enum.map(normalized, &Map.take(&1, @slot_required_fields))}
      slots -> {:error, {:ungoverned_provider_slots, slots}}
    end
  end

  defp normalize_slots(_slots), do: {:error, {:missing_provider_pool_refs, [:slots]}}

  defp governed_slot?(slot) do
    no_forbidden_material? =
      Enum.all?(@slot_forbidden_material, fn field -> not Map.has_key?(slot, field) end)

    no_forbidden_material? and Enum.all?(@slot_required_fields, &present?(Map.get(slot, &1)))
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)
end
