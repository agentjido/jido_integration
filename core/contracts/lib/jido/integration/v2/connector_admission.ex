defmodule Jido.Integration.V2.ConnectorAdmission do
  @moduledoc """
  Connector admission and duplicate-detection evidence.

  Contract: `Platform.ConnectorAdmission.v1`.
  """

  @contract_name "Platform.ConnectorAdmission.v1"
  @contract_version "1.0.0"
  @statuses [:admitted, :rejected_duplicate, :rejected_signature, :rejected_schema]
  @base_required_binary_fields [
    :tenant_ref,
    :installation_ref,
    :workspace_ref,
    :project_ref,
    :environment_ref,
    :resource_ref,
    :authority_packet_ref,
    :permission_decision_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :release_manifest_ref,
    :connector_ref,
    :pack_ref,
    :signature_ref,
    :schema_ref,
    :admission_idempotency_key
  ]
  @optional_binary_fields [:principal_ref, :system_actor_ref, :duplicate_of_ref]

  defstruct [
    :contract_name,
    :contract_version,
    :tenant_ref,
    :installation_ref,
    :workspace_ref,
    :project_ref,
    :environment_ref,
    :principal_ref,
    :system_actor_ref,
    :resource_ref,
    :authority_packet_ref,
    :permission_decision_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :release_manifest_ref,
    :connector_ref,
    :pack_ref,
    :signature_ref,
    :schema_ref,
    :admission_idempotency_key,
    :duplicate_of_ref,
    :status
  ]

  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @spec new(map() | keyword()) ::
          {:ok, t()}
          | {:error, {:missing_required_fields, [atom()]}}
          | {:error, :invalid_connector_admission}
  def new(attrs) do
    with {:ok, attrs} <- normalize_attrs(attrs),
         [] <- missing_required_fields(attrs),
         true <- optional_binary_fields?(attrs),
         {:ok, status} <- enum_atom(Map.get(attrs, :status), @statuses),
         :ok <- validate_duplicate(status, attrs) do
      {:ok,
       struct!(
         __MODULE__,
         Map.merge(attrs, %{
           contract_name: @contract_name,
           contract_version: @contract_version,
           status: status
         })
       )}
    else
      fields when is_list(fields) -> {:error, {:missing_required_fields, fields}}
      _error -> {:error, :invalid_connector_admission}
    end
  end

  defp validate_duplicate(:rejected_duplicate, attrs) do
    if present_binary?(Map.get(attrs, :duplicate_of_ref)), do: :ok, else: :error
  end

  defp validate_duplicate(_status, _attrs), do: :ok

  defp missing_required_fields(attrs) do
    binary_missing =
      @base_required_binary_fields
      |> Enum.reject(fn field -> present_binary?(Map.get(attrs, field)) end)

    actor_missing =
      if present_binary?(Map.get(attrs, :principal_ref)) or
           present_binary?(Map.get(attrs, :system_actor_ref)) do
        []
      else
        [:principal_ref_or_system_actor_ref]
      end

    status_missing =
      if Map.has_key?(attrs, :status), do: [], else: [:status]

    binary_missing ++ actor_missing ++ status_missing
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: {:ok, Map.new(attrs)}

  defp normalize_attrs(attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :__struct__) do
      {:ok, Map.from_struct(attrs)}
    else
      {:ok, attrs}
    end
  end

  defp normalize_attrs(_attrs), do: {:error, :invalid_attrs}

  defp optional_binary_fields?(attrs) do
    Enum.all?(@optional_binary_fields, fn field ->
      value = Map.get(attrs, field)
      is_nil(value) or present_binary?(value)
    end)
  end

  defp enum_atom(value, allowed) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: :error
  end

  defp enum_atom(value, allowed) when is_binary(value) do
    allowed
    |> Enum.find(&(Atom.to_string(&1) == value))
    |> case do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  defp enum_atom(_value, _allowed), do: :error

  defp present_binary?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0
end
