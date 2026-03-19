defmodule Jido.Integration.V2.OperationSpec do
  @moduledoc """
  Authored operation contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [
    :operation_id,
    :name,
    :runtime_class,
    :transport_mode,
    :handler,
    :input_schema,
    :output_schema,
    :permissions,
    :policy,
    :upstream,
    :jido
  ]
  defstruct [
    :operation_id,
    :name,
    :display_name,
    :description,
    :runtime_class,
    :transport_mode,
    :handler,
    :input_schema,
    :output_schema,
    :permissions,
    :runtime,
    :policy,
    :upstream,
    :jido,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          operation_id: String.t(),
          name: String.t(),
          display_name: String.t(),
          description: String.t() | nil,
          runtime_class: Contracts.runtime_class(),
          transport_mode: atom(),
          handler: module(),
          input_schema: Contracts.zoi_schema(),
          output_schema: Contracts.zoi_schema(),
          permissions: map(),
          runtime: map(),
          policy: map(),
          upstream: map(),
          jido: map(),
          metadata: map()
        }

  @spec new!(map() | t()) :: t()
  def new!(%__MODULE__{} = operation_spec), do: operation_spec

  def new!(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    name = Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :name), "operation.name")

    struct!(__MODULE__, %{
      operation_id:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(attrs, :operation_id),
          "operation.operation_id"
        ),
      name: name,
      display_name:
        Contracts.validate_non_empty_string!(
          Map.get(attrs, :display_name, name),
          "operation.display_name"
        ),
      description: Map.get(attrs, :description),
      runtime_class: Contracts.validate_runtime_class!(Contracts.fetch!(attrs, :runtime_class)),
      transport_mode:
        Contracts.normalize_atomish!(
          Contracts.fetch!(attrs, :transport_mode),
          "operation.transport_mode"
        ),
      handler: Contracts.validate_module!(Contracts.fetch!(attrs, :handler), "operation.handler"),
      input_schema:
        Contracts.validate_zoi_schema!(
          Contracts.fetch!(attrs, :input_schema),
          "input_schema"
        ),
      output_schema:
        Contracts.validate_zoi_schema!(
          Contracts.fetch!(attrs, :output_schema),
          "output_schema"
        ),
      permissions:
        Contracts.validate_map!(Contracts.fetch!(attrs, :permissions), "operation.permissions"),
      runtime: Contracts.validate_map!(Map.get(attrs, :runtime, %{}), "operation.runtime"),
      policy: Contracts.validate_map!(Contracts.fetch!(attrs, :policy), "operation.policy"),
      upstream: Contracts.validate_map!(Contracts.fetch!(attrs, :upstream), "operation.upstream"),
      jido: Contracts.validate_map!(Contracts.fetch!(attrs, :jido), "operation.jido"),
      metadata: Contracts.validate_map!(Map.get(attrs, :metadata, %{}), "operation.metadata")
    })
  end

  def new!(attrs) do
    raise ArgumentError, "operation spec must be a map, got: #{inspect(attrs)}"
  end
end
