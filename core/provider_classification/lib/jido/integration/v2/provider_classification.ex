defmodule Jido.Integration.V2.ProviderClassification do
  @moduledoc """
  Canonical provider and adapter classification vocabulary.

  This package is intentionally dependency-light so every repo can consume the
  same provider vocabulary without pulling runtime connector contracts into
  pure data packages.
  """

  @connector_categories [
    :official_connector,
    :companion_connector,
    :generated_sdk_client,
    :provider_cli_adapter,
    :app_connector
  ]

  @adapter_families [
    "cli",
    "http",
    "graphql",
    "realtime",
    "inference",
    "service_runtime",
    "app_server"
  ]

  @provider_ids [
    "amp",
    "claude",
    "codex",
    "gemini",
    "github",
    "linear",
    "notion",
    "openai",
    "pristine",
    "prismatic",
    "reqllm_next",
    "self_hosted_inference",
    "gemini_ex",
    "llama_cpp_sdk"
  ]

  @provider_account_statuses [
    :known,
    :asserted,
    :unknown,
    :unavailable,
    :revoked,
    :rotated
  ]

  @adapter_placements [
    :common,
    :provider_native,
    :sdk_native,
    :cli_native,
    :connector_facade,
    :event_only,
    :unsupported,
    :forbidden
  ]

  @public_vocabulary %{
    provider_account_ref: :authority_credential_identity_ref,
    provider_account_status: :authority_credential_identity_status,
    provider_pool_ref: :runtime_provider_pool_routing_ref,
    reassign_provider: :operator_runtime_pool_reassignment_command
  }

  @spec connector_categories() :: [atom()]
  def connector_categories, do: @connector_categories

  @spec adapter_families() :: [String.t()]
  def adapter_families, do: @adapter_families

  @spec provider_ids() :: [String.t()]
  def provider_ids, do: @provider_ids

  @spec provider_family_tokens() :: [String.t()]
  def provider_family_tokens, do: Enum.uniq(@adapter_families ++ @provider_ids)

  @spec provider_account_statuses() :: [atom()]
  def provider_account_statuses, do: @provider_account_statuses

  @spec adapter_placements() :: [atom()]
  def adapter_placements, do: @adapter_placements

  @spec public_vocabulary() :: %{atom() => atom()}
  def public_vocabulary, do: @public_vocabulary

  @spec public_vocabulary_classification(atom() | String.t()) :: {:ok, atom()} | {:error, term()}
  def public_vocabulary_classification(field) do
    field = normalize_atom(field)

    case Map.fetch(@public_vocabulary, field) do
      {:ok, classification} -> {:ok, classification}
      :error -> {:error, {:unclassified_provider_public_vocabulary, field}}
    end
  end

  @spec adapter_family?(term()) :: boolean()
  def adapter_family?(value), do: value in @adapter_families

  @spec provider_family_token?(term()) :: boolean()
  def provider_family_token?(value), do: value in provider_family_tokens()

  @spec provider_account_status?(term()) :: boolean()
  def provider_account_status?(value), do: value in @provider_account_statuses

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    @public_vocabulary
    |> Map.keys()
    |> Enum.find(&(&1 |> Atom.to_string() == value))
  end

  defp normalize_atom(_value), do: nil
end
