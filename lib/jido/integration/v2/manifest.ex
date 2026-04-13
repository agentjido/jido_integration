defmodule Jido.Integration.V2.Manifest do
  @moduledoc """
  Connector-level authored contract plus derived executable projection.
  """

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.TriggerSpec

  @runtime_order %{direct: 0, session: 1, stream: 2}

  @schema Zoi.struct(
            __MODULE__,
            %{
              connector: Contracts.non_empty_string_schema("manifest.connector"),
              auth: AuthSpec.schema(),
              catalog: CatalogSpec.schema(),
              operations: Zoi.list(OperationSpec.schema()) |> Zoi.default([]),
              triggers: Zoi.list(TriggerSpec.schema()) |> Zoi.default([]),
              runtime_families:
                Zoi.list(
                  Contracts.enumish_schema(
                    [:direct, :session, :stream],
                    "manifest.runtime_families"
                  )
                )
                |> Zoi.default([]),
              capabilities: Zoi.list(Capability.schema()) |> Zoi.default([]),
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
  def new(%__MODULE__{} = manifest), do: validate(manifest)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: Map.new(attrs)

    with :ok <- reject_manual_capability_authoring(attrs),
         {:ok, manifest} <- Schema.new(__MODULE__, @schema, attrs),
         {:ok, manifest} <- validate(manifest) do
      {:ok, manifest}
    else
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = manifest) do
    case validate(manifest) do
      {:ok, validated} -> validated
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, manifest} -> manifest
      {:error, %ArgumentError{} = error} -> raise error
    end
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

  defp validate(%__MODULE__{} = manifest) do
    operations = manifest.operations |> Enum.sort_by(& &1.operation_id)
    triggers = manifest.triggers |> Enum.sort_by(& &1.trigger_id)

    runtime_families =
      manifest.runtime_families
      |> normalize_runtime_families!()
      |> maybe_use_derived_runtime_families(operations, triggers)

    derived_runtime_families = derive_runtime_families(operations, triggers)
    capabilities = derive_capabilities(manifest.connector, operations, triggers)

    with :ok <- ensure_authored_entries_present!(operations, triggers),
         :ok <- validate_auth_requested_scopes!(manifest.auth, operations, triggers),
         :ok <- validate_auth_secret_names!(manifest.auth, triggers),
         :ok <- validate_runtime_families!(runtime_families, derived_runtime_families),
         :ok <- ensure_unique_capability_ids!(capabilities) do
      {:ok,
       %__MODULE__{
         manifest
         | operations: operations,
           triggers: triggers,
           runtime_families: runtime_families,
           capabilities: Enum.sort_by(capabilities, & &1.id)
       }}
    end
  end

  defp reject_manual_capability_authoring(attrs) do
    if Map.has_key?(attrs, :capabilities) or Map.has_key?(attrs, "capabilities") do
      error(
        "manual capability authoring is retired; author auth, catalog, operations, and triggers instead"
      )
    else
      :ok
    end
  end

  defp ensure_authored_entries_present!([], []) do
    error("connector manifests must declare at least one authored operation or trigger")
  end

  defp ensure_authored_entries_present!(_operations, _triggers), do: :ok

  defp validate_auth_requested_scopes!(
         %AuthSpec{requested_scopes: requested_scopes},
         operations,
         triggers
       ) do
    missing_scopes =
      (Enum.flat_map(operations, &required_scopes(&1.permissions)) ++
         Enum.flat_map(triggers, &required_scopes(&1.permissions)))
      |> Enum.uniq()
      |> Enum.sort()
      |> Kernel.--(Enum.uniq(requested_scopes))

    if missing_scopes == [] do
      :ok
    else
      error(
        "auth.requested_scopes must cover all authored required_scopes, missing #{inspect(missing_scopes)}"
      )
    end
  end

  defp validate_auth_secret_names!(%AuthSpec{secret_names: secret_names}, triggers) do
    missing_secret_names =
      triggers
      |> Enum.flat_map(&trigger_secret_names/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Kernel.--(Enum.uniq(secret_names))

    if missing_secret_names == [] do
      :ok
    else
      error(
        "auth.secret_names must declare all authored trigger secrets, missing #{inspect(missing_secret_names)}"
      )
    end
  end

  defp normalize_runtime_families!(values) when is_list(values) do
    values
    |> Enum.map(&Contracts.validate_runtime_class!/1)
    |> Enum.uniq()
    |> Enum.sort_by(&Map.fetch!(@runtime_order, &1))
  end

  defp normalize_runtime_families!(values) do
    raise ArgumentError, "manifest.runtime_families must be a list, got: #{inspect(values)}"
  end

  defp maybe_use_derived_runtime_families([], operations, triggers),
    do: derive_runtime_families(operations, triggers)

  defp maybe_use_derived_runtime_families(runtime_families, _operations, _triggers),
    do: runtime_families

  defp derive_runtime_families(operations, triggers) do
    (Enum.map(operations, & &1.runtime_class) ++ Enum.map(triggers, & &1.runtime_class))
    |> Enum.uniq()
    |> Enum.sort_by(&Map.fetch!(@runtime_order, &1))
  end

  defp validate_runtime_families!(runtime_families, derived_runtime_families) do
    if runtime_families == derived_runtime_families do
      :ok
    else
      error(
        "manifest.runtime_families must match authored specs, got #{inspect(runtime_families)} expected #{inspect(derived_runtime_families)}"
      )
    end
  end

  defp derive_capabilities(connector, operations, triggers) do
    Enum.map(operations, &Capability.from_operation!(connector, &1)) ++
      Enum.map(triggers, &Capability.from_trigger!(connector, &1))
  end

  defp ensure_unique_capability_ids!(capabilities) do
    capability_ids = Enum.map(capabilities, & &1.id)

    if capability_ids == Enum.uniq(capability_ids) do
      :ok
    else
      error("derived executable capability ids must be unique within a manifest")
    end
  end

  defp required_scopes(permissions) do
    permissions
    |> Contracts.get(:required_scopes, [])
    |> Contracts.normalize_string_list!("authored permissions required_scopes")
  end

  defp trigger_secret_names(trigger) do
    verification_secret_name =
      trigger.verification
      |> Contracts.get(:secret_name)
      |> normalize_optional_secret_name!()

    trigger.secret_requirements ++ verification_secret_name
  end

  defp normalize_optional_secret_name!(nil), do: []

  defp normalize_optional_secret_name!(secret_name) do
    [
      Contracts.validate_non_empty_string!(
        secret_name,
        "trigger.verification.secret_name"
      )
    ]
  end

  defp error(message), do: {:error, ArgumentError.exception(message)}
end
