defmodule Jido.Integration.ProviderMaterializer do
  @moduledoc """
  Provider-local projection of redeemed Jido material into transient runtime authority.

  The public return value is transient and must remain inside
  `Jido.Integration.V2.Auth.with_materialized_credential/4`. Durable callers use
  `authority_refs/1`, which contains references and generation fences only.
  """

  alias Gemini.GovernedAuthority
  alias Gemini.GovernedAuthority.MaterializationRequest, as: GeminiMaterializationRequest
  alias Gemini.GovernedAuthority.SecretMaterial, as: GeminiSecretMaterial
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.SecretMaterial

  @required_binding_fields [
    :base_url,
    :provider_ref,
    :model_account_ref,
    :credential_handle_ref,
    :operation_policy_ref,
    :materialization_request
  ]

  @type binding :: %{
          required(:base_url) => String.t(),
          required(:provider_ref) => String.t(),
          required(:model_account_ref) => String.t(),
          required(:credential_handle_ref) => String.t(),
          required(:operation_policy_ref) => String.t(),
          required(:materialization_request) => MaterializationRequest.t(),
          optional(:redaction_ref) => String.t()
        }

  @spec materialize(SecretMaterial.t(), binding()) ::
          {:ok, GovernedAuthority.t()} | {:error, term()}
  def materialize(%SecretMaterial{} = material, %{} = binding) do
    with :ok <- validate_binding(binding),
         %MaterializationRequest{} = request <- value(binding, :materialization_request),
         :ok <- validate_exact_agreement(material, request, binding),
         {:ok, api_key} <- api_key(material),
         {:ok, %GovernedAuthority{} = authority} <-
           build_authority(material, request, binding, api_key) do
      {:ok, authority}
    end
  rescue
    error in ArgumentError -> {:error, {:invalid_gemini_authority, Exception.message(error)}}
  end

  def materialize(_material, _binding), do: {:error, :invalid_provider_materialization}

  @spec authority_refs(GovernedAuthority.t()) :: {:ok, map()}
  def authority_refs(%GovernedAuthority{} = authority),
    do: {:ok, GovernedAuthority.refs(authority)}

  def authority_refs(_authority), do: {:error, :invalid_provider_authority}

  defp validate_binding(binding) do
    missing = Enum.reject(@required_binding_fields, &present?(value(binding, &1)))

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_provider_materialization_binding, fields}}
    end
  end

  defp validate_exact_agreement(material, request, binding) do
    account = request.account

    expected = [
      {material.materialization_ref, request.materialization_ref, :materialization_ref},
      {material.provider_family, account.provider_family, :provider_family},
      {material.account_ref, account.account_ref, :provider_account_ref},
      {material.generation, account.generation, :generation},
      {value(binding, :model_account_ref), account.account_ref, :model_account_ref},
      {value(binding, :endpoint_ref, request.endpoint_ref), request.endpoint_ref, :endpoint_ref},
      {value(binding, :authority_ref, request.authority_ref), request.authority_ref,
       :authority_ref},
      {value(binding, :operation_ref, request.operation_ref), request.operation_ref,
       :operation_ref},
      {value(binding, :target_ref, request.target_ref), request.target_ref, :target_ref},
      {value(binding, :fence, account.fence), account.fence, :fence}
    ]

    case Enum.find(expected, fn {actual, wanted, _field} -> actual != wanted end) do
      nil -> :ok
      {_actual, _wanted, field} -> {:error, {:provider_materialization_mismatch, field}}
    end
  end

  defp api_key(%SecretMaterial{payload: payload}) do
    case Map.get(payload, :api_key, Map.get(payload, "api_key")) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :gemini_api_key_material_missing}
    end
  end

  defp build_authority(material, request, binding, api_key) do
    provider_request =
      GeminiMaterializationRequest.new!(%{
        materialization_ref: request.materialization_ref,
        lease_id: request.lease_id,
        account: Map.from_struct(request.account),
        effect_ref: request.effect_ref,
        operation_ref: request.operation_ref,
        authority_ref: request.authority_ref,
        endpoint_ref: request.endpoint_ref,
        target_ref: request.target_ref,
        issued_at: request.issued_at,
        expires_at: request.expires_at
      })

    provider_secret =
      GeminiSecretMaterial.new!(%{
        materialization_ref: material.materialization_ref,
        provider_family: material.provider_family,
        account_ref: material.account_ref,
        generation: material.generation,
        payload: %{headers: %{}, query_params: [{"key", api_key}]}
      })

    authority =
      GovernedAuthority.new!(%{
        base_url: value(binding, :base_url),
        provider_ref: value(binding, :provider_ref),
        model_account_ref: value(binding, :model_account_ref),
        credential_handle_ref: value(binding, :credential_handle_ref),
        operation_policy_ref: value(binding, :operation_policy_ref),
        redaction_ref: value(binding, :redaction_ref),
        headers: %{},
        materialization_request: provider_request,
        secret_material: provider_secret
      })

    {:ok, authority}
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp present?(%MaterializationRequest{}), do: true
  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false
end
