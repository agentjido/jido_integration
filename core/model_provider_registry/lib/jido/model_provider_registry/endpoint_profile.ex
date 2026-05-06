defmodule Jido.ModelProviderRegistry.EndpointProfile do
  @moduledoc """
  Ref-only endpoint identity contract for remote and local model endpoints.
  """

  @required_fields [
    :tenant_ref,
    :endpoint_profile_ref,
    :endpoint_descriptor_ref,
    :provider_ref,
    :provider_account_ref,
    :local_service_identity_ref,
    :target_ref,
    :attach_grant_ref,
    :startup_kind,
    :management_mode,
    :readiness_ref,
    :health_ref,
    :endpoint_lease_ref
  ]

  @forbidden_material [
    :api_key,
    :authorization_header,
    :default_client,
    :endpoint_auth,
    :env,
    :headers,
    :provider_payload,
    :raw_provider_payload,
    :raw_secret,
    :raw_token,
    :root_url,
    :token,
    :token_file
  ]

  defstruct @required_fields ++ [raw_material_present?: false]

  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_material(attrs),
         :ok <- require_fields(attrs),
         :ok <- validate_distinct_identities(attrs) do
      {:ok, struct!(__MODULE__, Map.take(attrs, @required_fields))}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    candidates = @required_fields ++ @forbidden_material
    Enum.find(candidates, key, &(Atom.to_string(&1) == key))
  end

  defp reject_material(attrs) do
    rejected = Enum.filter(@forbidden_material, &Map.has_key?(attrs, &1))
    if rejected == [], do: :ok, else: {:error, {:raw_material_rejected, rejected}}
  end

  defp require_fields(attrs) do
    missing = Enum.reject(@required_fields, &present?(Map.get(attrs, &1)))
    if missing == [], do: :ok, else: {:error, {:missing_endpoint_refs, missing}}
  end

  defp validate_distinct_identities(attrs) do
    comparisons = [
      {:endpoint_profile_ref, :provider_account_ref},
      {:endpoint_descriptor_ref, :provider_account_ref},
      {:local_service_identity_ref, :provider_account_ref},
      {:local_service_identity_ref, :endpoint_profile_ref}
    ]

    rejected =
      Enum.filter(comparisons, fn {left, right} ->
        Map.fetch!(attrs, left) == Map.fetch!(attrs, right)
      end)

    if rejected == [], do: :ok, else: {:error, {:identity_conflation_rejected, rejected}}
  end

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_atom(value), do: true
  defp present?(value), do: not is_nil(value)
end
