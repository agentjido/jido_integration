defmodule Jido.Integration.V2.Manifest do
  @moduledoc """
  Connector-level authored contract plus derived executable projection.
  """

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.TriggerSpec

  @contract_version "connector-sdk.v1"
  @runtime_order %{direct: 0, session: 1, stream: 2}
  @forbidden_external_keys [
    "authorization_header",
    "auth_header",
    "memory_body",
    "prompt_body",
    "provider_payload",
    "raw_secret",
    "raw_token",
    "runtime_module_ref",
    "secret_metadata"
  ]
  @runtime_internal_module_prefixes [
    "AppKit.",
    "Citadel.",
    "ExecutionPlane.",
    "GroundPlane.",
    "Mezzanine.",
    "Jido.Integration.V2.ControlPlane",
    "Jido.Integration.V2.DirectRuntime",
    "Jido.Integration.V2.DispatchRuntime",
    "Jido.Integration.V2.RuntimeRouter"
  ]

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

  @spec contract_version(t()) :: String.t()
  def contract_version(%__MODULE__{metadata: metadata}) do
    case Contracts.get(metadata, :contract_version) do
      value when is_binary(value) and value != "" -> value
      _other -> @contract_version
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = manifest) do
    %{
      "connector" => manifest.connector,
      "contract_version" => contract_version(manifest),
      "auth" => dump_auth(manifest.auth),
      "catalog" => dump_catalog(manifest.catalog),
      "operations" => Enum.map(manifest.operations, &dump_operation/1),
      "triggers" => Enum.map(manifest.triggers, &dump_trigger/1),
      "runtime_families" => Enum.map(manifest.runtime_families, &Atom.to_string/1),
      "capabilities" => Enum.map(manifest.capabilities, &dump_capability/1),
      "metadata" => safe_json_map(manifest.metadata)
    }
  end

  @spec load_dump(map()) :: {:ok, map()} | {:error, term()}
  def load_dump(attrs) when is_map(attrs) do
    case require_dump_fields(attrs) do
      :ok -> CanonicalJson.normalize(attrs)
      {:error, _reason} = error -> error
    end
  end

  def load_dump(_attrs), do: {:error, :invalid_manifest_dump}

  @spec canonical_hash(t() | map()) :: String.t()
  def canonical_hash(%__MODULE__{} = manifest),
    do: manifest |> dump() |> CanonicalJson.checksum!()

  def canonical_hash(%{} = manifest_dump), do: CanonicalJson.checksum!(manifest_dump)

  @spec external_safety_errors(t()) :: [term()]
  def external_safety_errors(%__MODULE__{} = manifest) do
    dump = dump(manifest)

    forbidden_key_errors(dump, []) ++
      scope_posture_errors(manifest) ++
      runtime_internal_dependency_errors(manifest)
  end

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
         :ok <- validate_auth_default_profile!(manifest.auth),
         :ok <- validate_auth_requested_scopes!(manifest.auth, operations, triggers),
         :ok <- validate_auth_secret_names!(manifest.auth, triggers),
         :ok <- validate_runtime_families!(runtime_families, derived_runtime_families),
         :ok <- ensure_unique_operation_ids!(operations),
         :ok <- ensure_unique_trigger_ids!(triggers),
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

  defp validate_auth_default_profile!(%AuthSpec{
         default_profile: nil,
         supported_profiles: _profiles
       }),
       do: :ok

  defp validate_auth_default_profile!(%AuthSpec{
         default_profile: default_profile,
         supported_profiles: profiles
       }) do
    profile_ids =
      profiles
      |> Enum.map(&Contracts.get(&1, :id))
      |> Enum.reject(&is_nil/1)

    if default_profile in profile_ids do
      :ok
    else
      error(
        "auth.default_profile must refer to a declared supported_profile, got: #{inspect(default_profile)}"
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

  defp ensure_unique_operation_ids!(operations) do
    operation_ids = Enum.map(operations, & &1.operation_id)

    if operation_ids == Enum.uniq(operation_ids) do
      :ok
    else
      error("authored operation ids must be unique within a manifest")
    end
  end

  defp ensure_unique_trigger_ids!(triggers) do
    trigger_ids = Enum.map(triggers, & &1.trigger_id)

    if trigger_ids == Enum.uniq(trigger_ids) do
      :ok
    else
      error("authored trigger ids must be unique within a manifest")
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

  defp dump_auth(%AuthSpec{} = auth) do
    %{
      "binding_kind" => Atom.to_string(auth.binding_kind),
      "auth_type" => auth.auth_type && Atom.to_string(auth.auth_type),
      "supported_profiles" => safe_json_list(auth.supported_profiles),
      "default_profile" => auth.default_profile,
      "install" => safe_json_map(auth.install),
      "reauth" => safe_json_map(auth.reauth),
      "management_modes" => Enum.map(auth.management_modes, &Atom.to_string/1),
      "requested_scopes" => auth.requested_scopes,
      "durable_secret_fields" => auth.durable_secret_fields,
      "lease_fields" => auth.lease_fields,
      "secret_names" => auth.secret_names,
      "metadata" => safe_json_map(auth.metadata)
    }
  end

  defp dump_catalog(%CatalogSpec{} = catalog) do
    %{
      "display_name" => catalog.display_name,
      "description" => catalog.description,
      "category" => catalog.category,
      "tags" => catalog.tags,
      "docs_refs" => catalog.docs_refs,
      "maturity" => Atom.to_string(catalog.maturity),
      "publication" => Atom.to_string(catalog.publication),
      "metadata" => safe_json_map(catalog.metadata)
    }
  end

  defp dump_operation(%OperationSpec{} = operation) do
    %{
      "operation_id" => operation.operation_id,
      "name" => operation.name,
      "display_name" => operation.display_name,
      "description" => operation.description,
      "runtime_class" => Atom.to_string(operation.runtime_class),
      "transport_mode" => Atom.to_string(operation.transport_mode),
      "handler" => Atom.to_string(operation.handler),
      "input_schema_ref" => schema_ref(operation.input_schema),
      "output_schema_ref" => schema_ref(operation.output_schema),
      "permissions" => safe_json_map(operation.permissions),
      "runtime" => safe_json_map(operation.runtime),
      "policy" => safe_json_map(operation.policy),
      "upstream" => safe_json_map(operation.upstream),
      "consumer_surface" => safe_json_map(operation.consumer_surface),
      "schema_policy" => safe_json_map(operation.schema_policy),
      "jido" => safe_json_map(operation.jido),
      "metadata" => safe_json_map(operation.metadata)
    }
  end

  defp dump_trigger(%TriggerSpec{} = trigger) do
    %{
      "trigger_id" => trigger.trigger_id,
      "name" => trigger.name,
      "display_name" => trigger.display_name,
      "description" => trigger.description,
      "runtime_class" => Atom.to_string(trigger.runtime_class),
      "delivery_mode" => Atom.to_string(trigger.delivery_mode),
      "handler" => Atom.to_string(trigger.handler),
      "config_schema_ref" => schema_ref(trigger.config_schema),
      "signal_schema_ref" => schema_ref(trigger.signal_schema),
      "polling" => safe_json_value(trigger.polling),
      "permissions" => safe_json_map(trigger.permissions),
      "checkpoint" => safe_json_map(trigger.checkpoint),
      "dedupe" => safe_json_map(trigger.dedupe),
      "verification" => safe_json_map(trigger.verification),
      "policy" => safe_json_map(trigger.policy),
      "consumer_surface" => safe_json_map(trigger.consumer_surface),
      "schema_policy" => safe_json_map(trigger.schema_policy),
      "jido" => safe_json_map(trigger.jido),
      "secret_requirements" => trigger.secret_requirements,
      "metadata" => safe_json_map(trigger.metadata)
    }
  end

  defp dump_capability(%Capability{} = capability) do
    %{
      "id" => capability.id,
      "connector" => capability.connector,
      "runtime_class" => Atom.to_string(capability.runtime_class),
      "kind" => Atom.to_string(capability.kind),
      "transport_profile" => Atom.to_string(capability.transport_profile),
      "handler" => Atom.to_string(capability.handler),
      "metadata" =>
        capability.metadata
        |> Map.drop([:input_schema, :output_schema, :config_schema, :signal_schema])
        |> safe_json_map()
    }
  end

  defp schema_ref(schema) do
    digest =
      schema
      |> inspect(limit: :infinity)
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "schema://sha256:#{digest}"
  end

  defp safe_json_map(nil), do: %{}
  defp safe_json_map(value) when is_map(value), do: safe_json_value(value)

  defp safe_json_list(values) when is_list(values), do: Enum.map(values, &safe_json_value/1)

  defp safe_json_value(value) do
    value
    |> Contracts.dump_json_safe!()
    |> CanonicalJson.normalize!()
  end

  defp require_dump_fields(attrs) do
    required = [
      "connector",
      "contract_version",
      "auth",
      "catalog",
      "operations",
      "triggers",
      "runtime_families",
      "capabilities",
      "metadata"
    ]

    missing = Enum.reject(required, &Map.has_key?(attrs, &1))

    if missing == [] do
      :ok
    else
      {:error, {:missing_manifest_dump_fields, missing}}
    end
  end

  defp forbidden_key_errors(%{} = map, path) do
    Enum.flat_map(map, fn {key, value} ->
      normalized_key = key_name(key)
      next_path = path ++ [normalized_key]
      nested = forbidden_key_errors(value, next_path)

      if normalized_key in @forbidden_external_keys do
        [{:forbidden_manifest_key, Enum.join(next_path, ".")} | nested]
      else
        nested
      end
    end)
  end

  defp forbidden_key_errors(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      forbidden_key_errors(value, path ++ [Integer.to_string(index)])
    end)
  end

  defp forbidden_key_errors(_value, _path), do: []

  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(key), do: inspect(key)

  defp scope_posture_errors(%__MODULE__{} = manifest) do
    operation_errors =
      Enum.flat_map(manifest.operations, fn operation ->
        if tenant_scoped?(operation.metadata) do
          []
        else
          [{:unsafe_scope_posture, operation.operation_id}]
        end
      end)

    trigger_errors =
      Enum.flat_map(manifest.triggers, fn trigger ->
        if tenant_scoped?(trigger.metadata) do
          []
        else
          [{:unsafe_scope_posture, trigger.trigger_id}]
        end
      end)

    operation_errors ++ trigger_errors
  end

  defp tenant_scoped?(metadata) do
    metadata
    |> Contracts.get(:scope_posture, %{})
    |> Contracts.get(:tenant_scope)
    |> case do
      :tenant_scoped -> true
      "tenant_scoped" -> true
      _other -> false
    end
  end

  defp runtime_internal_dependency_errors(%__MODULE__{} = manifest) do
    manifest.operations
    |> Enum.map(&{&1.operation_id, module_name(&1.handler)})
    |> Kernel.++(Enum.map(manifest.triggers, &{&1.trigger_id, module_name(&1.handler)}))
    |> Enum.flat_map(fn {id, module_name} ->
      if runtime_internal_module?(module_name) do
        [{:runtime_internal_dependency, id, module_name}]
      else
        []
      end
    end)
  end

  defp runtime_internal_module?(module_name) do
    Enum.any?(@runtime_internal_module_prefixes, &String.starts_with?(module_name, &1))
  end

  defp module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end
end
