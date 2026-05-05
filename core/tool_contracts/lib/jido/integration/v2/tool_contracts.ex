defmodule Jido.Integration.V2.ToolContracts do
  @moduledoc """
  Bounded ref-only tool contract descriptors.
  """

  @categories [
    :connector_tool,
    :host_tool,
    :mcp_external_tool,
    :operator_action,
    :product_action,
    :provider_native_tool,
    :read_only_observation,
    :synthetic_fixture_event
  ]

  @auth_sources [
    :authority_materialized,
    :connector_binding_ref,
    :none,
    :provider_native_assertion_ref,
    :read_only_ref
  ]

  @execution_authorities [
    :connector_operation,
    :host_runtime,
    :operator_control,
    :product_surface,
    :provider_native_runtime,
    :read_only_projection,
    :synthetic_fixture
  ]

  @redaction_classes [
    :event_metadata,
    :operator_metadata,
    :provider_tool_metadata,
    :ref_only,
    :synthetic_metadata
  ]

  @forbidden_keys [
    :api_key,
    :auth_root,
    :authorization_header,
    :command_secret,
    :config_root,
    :cwd,
    :env,
    :hidden_authority,
    :provider_payload,
    :raw_token,
    :target_credentials,
    :token,
    :token_file
  ]

  @enforce_keys [
    :contract_ref,
    :category,
    :auth_source,
    :execution_authority,
    :redaction_class,
    :allowed_payload_keys
  ]
  defstruct @enforce_keys ++ [metadata: %{}]

  @type t :: %__MODULE__{
          contract_ref: String.t(),
          category: atom(),
          auth_source: atom(),
          execution_authority: atom(),
          redaction_class: atom(),
          allowed_payload_keys: [String.t()],
          metadata: map()
        }

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec forbidden_keys() :: [atom()]
  def forbidden_keys, do: @forbidden_keys

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_forbidden(attrs),
         {:ok, category} <- enum_value(attrs, :category, @categories),
         {:ok, auth_source} <- enum_value(attrs, :auth_source, @auth_sources),
         {:ok, execution_authority} <-
           enum_value(attrs, :execution_authority, @execution_authorities),
         {:ok, redaction_class} <- enum_value(attrs, :redaction_class, @redaction_classes),
         {:ok, keys} <- allowed_payload_keys(value(attrs, :allowed_payload_keys)) do
      {:ok,
       %__MODULE__{
         contract_ref: string!(attrs, :contract_ref),
         category: category,
         auth_source: auth_source,
         execution_authority: execution_authority,
         redaction_class: redaction_class,
         allowed_payload_keys: keys,
         metadata: metadata(attrs)
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = contract) do
    %{
      contract_ref: contract.contract_ref,
      category: contract.category,
      auth_source: contract.auth_source,
      execution_authority: contract.execution_authority,
      redaction_class: contract.redaction_class,
      allowed_payload_keys: contract.allowed_payload_keys,
      metadata: contract.metadata
    }
  end

  defp normalize(attrs) when is_map(attrs), do: attrs
  defp normalize(attrs) when is_list(attrs), do: Map.new(attrs)

  defp reject_forbidden(attrs) do
    forbidden =
      @forbidden_keys
      |> Enum.filter(fn key -> has_key?(attrs, key) or has_key?(metadata(attrs), key) end)

    if forbidden == [] do
      :ok
    else
      {:error, {:forbidden_tool_contract_fields, forbidden}}
    end
  end

  defp enum_value(attrs, field, allowed) do
    current = value(attrs, field)

    if current in allowed do
      {:ok, current}
    else
      {:error, {:invalid_tool_contract_enum, field, current, allowed}}
    end
  end

  defp allowed_payload_keys(keys) when is_list(keys) do
    if Enum.all?(keys, &valid_payload_key?/1) do
      {:ok, keys}
    else
      {:error, {:invalid_allowed_payload_keys, keys}}
    end
  end

  defp allowed_payload_keys(keys), do: {:error, {:invalid_allowed_payload_keys, keys}}

  defp valid_payload_key?(key), do: is_binary(key) and key != ""

  defp string!(attrs, field) do
    case value(attrs, field) do
      current when is_binary(current) and current != "" ->
        current

      current ->
        raise ArgumentError, "#{field} must be a non-empty string, got: #{inspect(current)}"
    end
  end

  defp metadata(attrs) do
    case value(attrs, :metadata) do
      %{} = metadata -> metadata
      _other -> %{}
    end
  end

  defp value(attrs, field) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp has_key?(attrs, field) when is_map(attrs) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))
  end
end
