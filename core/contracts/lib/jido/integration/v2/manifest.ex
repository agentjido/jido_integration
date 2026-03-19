defmodule Jido.Integration.V2.Manifest do
  @moduledoc """
  Connector-level authored contract plus derived executable projection.
  """

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  @runtime_order %{direct: 0, session: 1, stream: 2}

  @enforce_keys [
    :connector,
    :auth,
    :catalog,
    :operations,
    :triggers,
    :runtime_families,
    :capabilities
  ]
  defstruct [
    :connector,
    :auth,
    :catalog,
    :operations,
    :triggers,
    :runtime_families,
    :capabilities,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          connector: String.t(),
          auth: AuthSpec.t(),
          catalog: CatalogSpec.t(),
          operations: [OperationSpec.t()],
          triggers: [TriggerSpec.t()],
          runtime_families: [Contracts.runtime_class()],
          capabilities: [Capability.t()],
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    reject_manual_capability_authoring!(attrs)

    connector =
      Contracts.validate_non_empty_string!(Map.fetch!(attrs, :connector), "manifest.connector")

    auth = AuthSpec.new!(Map.fetch!(attrs, :auth))
    catalog = CatalogSpec.new!(Map.fetch!(attrs, :catalog))
    operations = normalize_operations(attrs)
    triggers = normalize_triggers(attrs)
    ensure_authored_entries_present!(operations, triggers)

    runtime_families =
      attrs
      |> Map.get(:runtime_families, derive_runtime_families(operations, triggers))
      |> normalize_runtime_families!()

    derived_runtime_families = derive_runtime_families(operations, triggers)
    validate_runtime_families!(runtime_families, derived_runtime_families)

    capabilities = derive_capabilities(connector, operations, triggers)
    ensure_unique_capability_ids!(capabilities)

    struct!(__MODULE__, %{
      connector: connector,
      auth: auth,
      catalog: catalog,
      operations: operations,
      triggers: triggers,
      runtime_families: runtime_families,
      capabilities: capabilities,
      metadata: Contracts.validate_map!(Map.get(attrs, :metadata, %{}), "manifest.metadata")
    })
  end

  @spec capabilities(t()) :: [Capability.t()]
  def capabilities(%__MODULE__{capabilities: capabilities}), do: capabilities

  @spec fetch_operation(t(), String.t()) :: OperationSpec.t() | nil
  def fetch_operation(%__MODULE__{} = manifest, operation_id) when is_binary(operation_id) do
    Enum.find(manifest.operations, &(&1.operation_id == operation_id))
  end

  @spec fetch_trigger(t(), String.t()) :: TriggerSpec.t() | nil
  def fetch_trigger(%__MODULE__{} = manifest, trigger_id) when is_binary(trigger_id) do
    Enum.find(manifest.triggers, &(&1.trigger_id == trigger_id))
  end

  @spec fetch_capability(t(), String.t()) :: Capability.t() | nil
  def fetch_capability(%__MODULE__{} = manifest, capability_id) when is_binary(capability_id) do
    Enum.find(capabilities(manifest), &(&1.id == capability_id))
  end

  defp reject_manual_capability_authoring!(attrs) do
    if Map.has_key?(attrs, :capabilities) or Map.has_key?(attrs, "capabilities") do
      raise ArgumentError,
            "manual capability authoring is retired; author auth, catalog, operations, and triggers instead"
    end
  end

  defp normalize_operations(attrs) do
    attrs
    |> Map.get(:operations, [])
    |> normalize_spec_list!("manifest.operations", &OperationSpec.new!/1)
    |> Enum.sort_by(& &1.operation_id)
  end

  defp normalize_triggers(attrs) do
    attrs
    |> Map.get(:triggers, [])
    |> normalize_spec_list!("manifest.triggers", &TriggerSpec.new!/1)
    |> Enum.sort_by(& &1.trigger_id)
  end

  defp normalize_spec_list!(values, field_name, builder) when is_list(values) do
    Enum.map(values, builder)
  rescue
    error ->
      reraise(
        ArgumentError.exception(
          "#{field_name} contains an invalid authored spec: #{Exception.message(error)}"
        ),
        __STACKTRACE__
      )
  end

  defp normalize_spec_list!(values, field_name, _builder) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  defp ensure_authored_entries_present!([], []) do
    raise ArgumentError,
          "connector manifests must declare at least one authored operation or trigger"
  end

  defp ensure_authored_entries_present!(_operations, _triggers), do: :ok

  defp normalize_runtime_families!(values) when is_list(values) do
    values
    |> Enum.map(&Contracts.validate_runtime_class!/1)
    |> Enum.uniq()
    |> Enum.sort_by(&Map.fetch!(@runtime_order, &1))
  end

  defp normalize_runtime_families!(values) do
    raise ArgumentError, "manifest.runtime_families must be a list, got: #{inspect(values)}"
  end

  defp derive_runtime_families(operations, triggers) do
    (Enum.map(operations, & &1.runtime_class) ++ Enum.map(triggers, & &1.runtime_class))
    |> Enum.uniq()
    |> Enum.sort_by(&Map.fetch!(@runtime_order, &1))
  end

  defp validate_runtime_families!(runtime_families, derived_runtime_families) do
    if runtime_families == derived_runtime_families do
      :ok
    else
      raise ArgumentError,
            "manifest.runtime_families must match authored specs, got #{inspect(runtime_families)} expected #{inspect(derived_runtime_families)}"
    end
  end

  defp derive_capabilities(connector, operations, triggers) do
    (Enum.map(operations, &Capability.from_operation!(connector, &1)) ++
       Enum.map(triggers, &Capability.from_trigger!(connector, &1)))
    |> Enum.sort_by(& &1.id)
  end

  defp ensure_unique_capability_ids!(capabilities) do
    capability_ids = Enum.map(capabilities, & &1.id)

    if capability_ids == Enum.uniq(capability_ids) do
      :ok
    else
      raise ArgumentError, "derived executable capability ids must be unique within a manifest"
    end
  end
end
