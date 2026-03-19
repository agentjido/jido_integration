defmodule Jido.Integration.V2.Capability do
  @moduledoc """
  Derived executable projection used by the control plane.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.TriggerSpec

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Contracts.non_empty_string_schema("capability.id"),
              connector: Contracts.non_empty_string_schema("capability.connector"),
              runtime_class:
                Contracts.enumish_schema([:direct, :session, :stream], "capability.runtime_class"),
              kind: Contracts.atomish_schema("capability.kind"),
              transport_profile: Contracts.atomish_schema("capability.transport_profile"),
              handler: Contracts.module_schema("capability.handler"),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = capability), do: {:ok, capability}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = capability), do: capability
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)

  @spec required_scopes(t()) :: [String.t()]
  def required_scopes(%__MODULE__{metadata: metadata}) do
    Map.get(metadata, :required_scopes, [])
  end

  @spec from_operation!(String.t(), OperationSpec.t()) :: t()
  def from_operation!(connector_id, %OperationSpec{} = operation_spec) do
    required_scopes =
      operation_spec.permissions
      |> Contracts.get(:required_scopes, [])
      |> Contracts.normalize_string_list!("operation.permissions.required_scopes")

    permission_bundle =
      operation_spec.permissions
      |> Contracts.get(:permission_bundle, required_scopes)
      |> Contracts.normalize_string_list!("operation.permissions.permission_bundle")

    new!(%{
      id: operation_spec.operation_id,
      connector: connector_id,
      runtime_class: operation_spec.runtime_class,
      kind: :operation,
      transport_profile: operation_spec.transport_mode,
      handler: operation_spec.handler,
      metadata:
        operation_spec.metadata
        |> Map.merge(%{
          name: operation_spec.name,
          display_name: operation_spec.display_name,
          description: operation_spec.description,
          input_schema: operation_spec.input_schema,
          output_schema: operation_spec.output_schema,
          permission_bundle: permission_bundle,
          required_scopes: required_scopes,
          runtime: operation_spec.runtime,
          policy: operation_spec.policy,
          upstream: operation_spec.upstream,
          consumer_surface: operation_spec.consumer_surface,
          schema_policy: operation_spec.schema_policy,
          jido: operation_spec.jido
        })
    })
  end

  @spec from_trigger!(String.t(), TriggerSpec.t()) :: t()
  def from_trigger!(connector_id, %TriggerSpec{} = trigger_spec) do
    required_scopes =
      trigger_spec.permissions
      |> Contracts.get(:required_scopes, [])
      |> Contracts.normalize_string_list!("trigger.permissions.required_scopes")

    new!(%{
      id: trigger_spec.trigger_id,
      connector: connector_id,
      runtime_class: trigger_spec.runtime_class,
      kind: :trigger,
      transport_profile: trigger_spec.delivery_mode,
      handler: trigger_spec.handler,
      metadata:
        trigger_spec.metadata
        |> Map.merge(%{
          name: trigger_spec.name,
          display_name: trigger_spec.display_name,
          description: trigger_spec.description,
          config_schema: trigger_spec.config_schema,
          signal_schema: trigger_spec.signal_schema,
          required_scopes: required_scopes,
          checkpoint: trigger_spec.checkpoint,
          dedupe: trigger_spec.dedupe,
          verification: trigger_spec.verification,
          policy: trigger_spec.policy,
          consumer_surface: trigger_spec.consumer_surface,
          schema_policy: trigger_spec.schema_policy,
          jido: trigger_spec.jido,
          secret_requirements: trigger_spec.secret_requirements
        })
    })
  end
end
