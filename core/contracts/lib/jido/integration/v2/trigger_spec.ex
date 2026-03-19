defmodule Jido.Integration.V2.TriggerSpec do
  @moduledoc """
  Authored trigger contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [
    :trigger_id,
    :name,
    :runtime_class,
    :delivery_mode,
    :handler,
    :config_schema,
    :signal_schema,
    :permissions,
    :checkpoint,
    :dedupe,
    :verification,
    :jido
  ]
  defstruct [
    :trigger_id,
    :name,
    :display_name,
    :description,
    :runtime_class,
    :delivery_mode,
    :handler,
    :config_schema,
    :signal_schema,
    :permissions,
    :checkpoint,
    :dedupe,
    :verification,
    :policy,
    :jido,
    secret_requirements: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          trigger_id: String.t(),
          name: String.t(),
          display_name: String.t(),
          description: String.t() | nil,
          runtime_class: Contracts.runtime_class(),
          delivery_mode: Contracts.trigger_source(),
          handler: module(),
          config_schema: Contracts.zoi_schema(),
          signal_schema: Contracts.zoi_schema(),
          permissions: map(),
          checkpoint: map(),
          dedupe: map(),
          verification: map(),
          policy: map(),
          jido: map(),
          secret_requirements: [String.t()],
          metadata: map()
        }

  @spec new!(map() | t()) :: t()
  def new!(%__MODULE__{} = trigger_spec), do: trigger_spec

  def new!(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    name = Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :name), "trigger.name")

    struct!(__MODULE__, %{
      trigger_id:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(attrs, :trigger_id),
          "trigger.trigger_id"
        ),
      name: name,
      display_name:
        Contracts.validate_non_empty_string!(
          Map.get(attrs, :display_name, name),
          "trigger.display_name"
        ),
      description: Map.get(attrs, :description),
      runtime_class: Contracts.validate_runtime_class!(Contracts.fetch!(attrs, :runtime_class)),
      delivery_mode: Contracts.validate_trigger_source!(Contracts.fetch!(attrs, :delivery_mode)),
      handler: Contracts.validate_module!(Contracts.fetch!(attrs, :handler), "trigger.handler"),
      config_schema:
        Contracts.validate_zoi_schema!(Contracts.fetch!(attrs, :config_schema), "config_schema"),
      signal_schema:
        Contracts.validate_zoi_schema!(Contracts.fetch!(attrs, :signal_schema), "signal_schema"),
      permissions:
        Contracts.validate_map!(Contracts.fetch!(attrs, :permissions), "trigger.permissions"),
      checkpoint:
        Contracts.validate_map!(Contracts.fetch!(attrs, :checkpoint), "trigger.checkpoint"),
      dedupe: Contracts.validate_map!(Contracts.fetch!(attrs, :dedupe), "trigger.dedupe"),
      verification:
        Contracts.validate_map!(Contracts.fetch!(attrs, :verification), "trigger.verification"),
      policy: Contracts.validate_map!(Map.get(attrs, :policy, %{}), "trigger.policy"),
      jido: Contracts.validate_map!(Contracts.fetch!(attrs, :jido), "trigger.jido"),
      secret_requirements:
        Contracts.normalize_string_list!(
          Map.get(attrs, :secret_requirements, []),
          "trigger.secret_requirements"
        ),
      metadata: Contracts.validate_map!(Map.get(attrs, :metadata, %{}), "trigger.metadata")
    })
  end

  def new!(attrs) do
    raise ArgumentError, "trigger spec must be a map, got: #{inspect(attrs)}"
  end
end
