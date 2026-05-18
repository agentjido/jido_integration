defmodule Jido.Integration.V2.OperationLookupRequest do
  @moduledoc """
  Credential-free request for resolving a pack binding operation against a connector manifest.
  """

  alias Jido.Integration.V2.Contracts

  @required_fields [
    :connector_ref,
    :manifest_ref,
    :operation_ref,
    :operation_role,
    :operation_class,
    :binding_kind,
    :required_runtime_family,
    :binding_ref,
    :pack_ref,
    :pack_revision,
    :credential_scope_ref
  ]

  @operation_roles [
    :source_read,
    :source_publish,
    :runtime_session,
    :runtime_tool,
    :evidence_collection,
    :resource_effect
  ]
  @operation_classes [
    :source_read,
    :source_publish,
    :source_write,
    :runtime_session,
    :runtime_tool_invocation,
    :evidence_collection,
    :connector_operation,
    :resource_effect
  ]
  @binding_kinds [
    :connection_id,
    :provider_account,
    :tenant,
    :none,
    :source,
    :source_publication,
    :runtime,
    :runtime_tool,
    :evidence,
    :resource_effect
  ]

  @enforce_keys @required_fields
  defstruct @required_fields ++
              [
                compiled_manifest_hash: nil,
                trace_ref: nil,
                metadata: %{}
              ]

  @type t :: %__MODULE__{
          connector_ref: String.t(),
          manifest_ref: String.t(),
          operation_ref: String.t(),
          operation_role: atom(),
          operation_class: atom(),
          binding_kind: atom(),
          required_runtime_family: Contracts.runtime_class(),
          binding_ref: String.t(),
          pack_ref: String.t(),
          pack_revision: String.t(),
          credential_scope_ref: String.t(),
          compiled_manifest_hash: String.t() | nil,
          trace_ref: String.t() | nil,
          metadata: map()
        }

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = request), do: normalize(request)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    request =
      struct!(
        __MODULE__,
        Enum.into(@required_fields, %{}, fn field ->
          {field, Contracts.fetch_required!(attrs, field, field_name(field))}
        end)
        |> Map.put(:compiled_manifest_hash, Contracts.get(attrs, :compiled_manifest_hash))
        |> Map.put(:trace_ref, Contracts.get(attrs, :trace_ref))
        |> Map.put(:metadata, Contracts.get(attrs, :metadata, %{}))
      )

    normalize(request)
  rescue
    error in [ArgumentError, KeyError] -> {:error, error}
  end

  def new(attrs),
    do: {:error, ArgumentError.exception("lookup request must be a map, got: #{inspect(attrs)}")}

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, %ArgumentError{} = error} -> raise error
      {:error, %KeyError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = request) do
    {:ok,
     %__MODULE__{
       request
       | connector_ref: non_empty!(request.connector_ref, "connector_ref"),
         manifest_ref: non_empty!(request.manifest_ref, "manifest_ref"),
         operation_ref: non_empty!(request.operation_ref, "operation_ref"),
         operation_role:
           enum_atomish!(request.operation_role, @operation_roles, "operation_role"),
         operation_class:
           enum_atomish!(request.operation_class, @operation_classes, "operation_class"),
         binding_kind: enum_atomish!(request.binding_kind, @binding_kinds, "binding_kind"),
         required_runtime_family:
           Contracts.validate_runtime_class!(request.required_runtime_family),
         binding_ref: non_empty!(request.binding_ref, "binding_ref"),
         pack_ref: non_empty!(request.pack_ref, "pack_ref"),
         pack_revision: non_empty!(request.pack_revision, "pack_revision"),
         credential_scope_ref: non_empty!(request.credential_scope_ref, "credential_scope_ref"),
         compiled_manifest_hash:
           optional_non_empty(request.compiled_manifest_hash, "compiled_manifest_hash"),
         trace_ref: optional_non_empty(request.trace_ref, "trace_ref"),
         metadata: map!(request.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp non_empty!(value, field_name), do: Contracts.validate_non_empty_string!(value, field_name)

  defp optional_non_empty(nil, _field_name), do: nil
  defp optional_non_empty(value, field_name), do: non_empty!(value, field_name)

  defp enum_atomish!(value, valid_values, field_name) do
    Contracts.validate_enum_atomish!(value, valid_values, field_name)
  end

  defp map!(value, _field_name) when is_map(value), do: Map.new(value)

  defp map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end

  defp field_name(field), do: "operation_lookup_request.#{field}"
end
