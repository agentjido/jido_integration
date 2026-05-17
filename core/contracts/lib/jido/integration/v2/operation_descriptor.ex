defmodule Jido.Integration.V2.OperationDescriptor do
  @moduledoc """
  Resolved, credential-free operation descriptor used by hot-path binding dispatch.
  """

  alias Jido.Integration.V2.Contracts

  @required_fields [
    :operation_manifest_ref,
    :connector_ref,
    :manifest_ref,
    :operation_ref,
    :operation_role,
    :operation_class,
    :binding_kind,
    :side_effect_class,
    :input_schema_ref,
    :output_schema_ref,
    :credential_scope_ref,
    :runtime_family,
    :manifest_digest,
    :required_scopes
  ]

  @enforce_keys @required_fields
  defstruct @required_fields ++
              [
                provider_family: nil,
                provider_operation_id: nil,
                connector_version: nil,
                adapter_ref: nil,
                handler_ref: nil,
                metadata: %{}
              ]

  @type t :: %__MODULE__{
          operation_manifest_ref: String.t(),
          connector_ref: String.t(),
          manifest_ref: String.t(),
          operation_ref: String.t(),
          operation_role: atom(),
          operation_class: atom(),
          binding_kind: atom(),
          side_effect_class: atom(),
          input_schema_ref: String.t(),
          output_schema_ref: String.t(),
          credential_scope_ref: String.t(),
          runtime_family: Contracts.runtime_class(),
          manifest_digest: String.t(),
          required_scopes: [String.t()],
          provider_family: String.t() | nil,
          provider_operation_id: String.t() | nil,
          connector_version: String.t() | nil,
          adapter_ref: String.t() | nil,
          handler_ref: String.t() | nil,
          metadata: map()
        }

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = descriptor), do: normalize(descriptor)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    descriptor =
      struct!(
        __MODULE__,
        Enum.into(@required_fields, %{}, fn field ->
          {field, Contracts.fetch_required!(attrs, field, field_name(field))}
        end)
        |> Map.put(:provider_family, Contracts.get(attrs, :provider_family))
        |> Map.put(:provider_operation_id, Contracts.get(attrs, :provider_operation_id))
        |> Map.put(:connector_version, Contracts.get(attrs, :connector_version))
        |> Map.put(:adapter_ref, Contracts.get(attrs, :adapter_ref))
        |> Map.put(:handler_ref, Contracts.get(attrs, :handler_ref))
        |> Map.put(:metadata, Contracts.get(attrs, :metadata, %{}))
      )

    normalize(descriptor)
  rescue
    error in [ArgumentError, KeyError] -> {:error, error}
  end

  def new(attrs),
    do:
      {:error,
       ArgumentError.exception("operation descriptor must be a map, got: #{inspect(attrs)}")}

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, descriptor} -> descriptor
      {:error, %ArgumentError{} = error} -> raise error
      {:error, %KeyError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = descriptor) do
    {:ok,
     %__MODULE__{
       descriptor
       | operation_manifest_ref:
           non_empty!(descriptor.operation_manifest_ref, "operation_manifest_ref"),
         connector_ref: non_empty!(descriptor.connector_ref, "connector_ref"),
         manifest_ref: non_empty!(descriptor.manifest_ref, "manifest_ref"),
         operation_ref: non_empty!(descriptor.operation_ref, "operation_ref"),
         operation_role: atomish!(descriptor.operation_role, "operation_role"),
         operation_class: atomish!(descriptor.operation_class, "operation_class"),
         binding_kind: atomish!(descriptor.binding_kind, "binding_kind"),
         side_effect_class: atomish!(descriptor.side_effect_class, "side_effect_class"),
         input_schema_ref: non_empty!(descriptor.input_schema_ref, "input_schema_ref"),
         output_schema_ref: non_empty!(descriptor.output_schema_ref, "output_schema_ref"),
         credential_scope_ref:
           non_empty!(descriptor.credential_scope_ref, "credential_scope_ref"),
         runtime_family: Contracts.validate_runtime_class!(descriptor.runtime_family),
         manifest_digest: non_empty!(descriptor.manifest_digest, "manifest_digest"),
         required_scopes:
           Contracts.normalize_string_list!(descriptor.required_scopes, "required_scopes"),
         provider_family: optional_non_empty(descriptor.provider_family, "provider_family"),
         provider_operation_id:
           optional_non_empty(descriptor.provider_operation_id, "provider_operation_id"),
         connector_version: optional_non_empty(descriptor.connector_version, "connector_version"),
         adapter_ref: optional_non_empty(descriptor.adapter_ref, "adapter_ref"),
         handler_ref: optional_non_empty(descriptor.handler_ref, "handler_ref"),
         metadata: map!(descriptor.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp non_empty!(value, field_name), do: Contracts.validate_non_empty_string!(value, field_name)

  defp optional_non_empty(nil, _field_name), do: nil
  defp optional_non_empty(value, field_name), do: non_empty!(value, field_name)

  defp atomish!(value, _field_name) when is_atom(value), do: value

  defp atomish!(value, field_name) when is_binary(value) do
    value
    |> Contracts.validate_non_empty_string!(field_name)
    |> String.to_existing_atom()
  rescue
    ArgumentError ->
      reraise ArgumentError,
              [message: "#{field_name} must use a known atom value, got: #{inspect(value)}"],
              __STACKTRACE__
  end

  defp atomish!(value, field_name) do
    raise ArgumentError,
          "#{field_name} must be an atom or known atom string, got: #{inspect(value)}"
  end

  defp map!(value, _field_name) when is_map(value), do: Map.new(value)

  defp map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end

  defp field_name(field), do: "operation_descriptor.#{field}"
end
