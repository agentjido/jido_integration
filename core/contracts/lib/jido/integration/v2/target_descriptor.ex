defmodule Jido.Integration.V2.TargetDescriptor do
  @moduledoc """
  Stable public descriptor for an execution target.

  A target is an execution environment advertisement, not a connector
  identity. Compatibility is explicit through runtime class, target
  capability, semantic versioning, and protocol version negotiation.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @known_keys [
    :target_id,
    :capability_id,
    :runtime_class,
    :version,
    :features,
    :constraints,
    :health,
    :location,
    :extensions
  ]
  @runtime_classes [:direct, :session, :stream]
  @target_health [:healthy, :degraded, :unavailable]

  @schema Zoi.struct(
            __MODULE__,
            %{
              target_id: Contracts.non_empty_string_schema("target_descriptor.target_id"),
              capability_id: Contracts.non_empty_string_schema("target_descriptor.capability_id"),
              runtime_class:
                Contracts.enumish_schema(
                  @runtime_classes,
                  "target_descriptor.runtime_class"
                ),
              version: Contracts.non_empty_string_schema("target_descriptor.version"),
              features: Contracts.any_map_schema(),
              constraints: Contracts.any_map_schema(),
              health: Contracts.enumish_schema(@target_health, "target_descriptor.health"),
              location: Contracts.any_map_schema(),
              extensions: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = descriptor), do: normalize(descriptor)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> prepare_attrs()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = descriptor) do
    case normalize(descriptor) do
      {:ok, descriptor} -> descriptor
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, descriptor} -> descriptor
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec compatibility(t(), map()) ::
          {:ok, %{runspec_version: String.t() | nil, event_schema_version: String.t() | nil}}
          | {:error, atom()}
  def compatibility(%__MODULE__{} = descriptor, requirements) when is_map(requirements) do
    requirements = Map.new(requirements)

    with :ok <- match_capability(descriptor, requirements),
         :ok <- match_runtime_class(descriptor, requirements),
         :ok <- match_health(descriptor),
         :ok <- match_version(descriptor, requirements),
         :ok <- match_required_features(descriptor, requirements),
         {:ok, runspec_version} <-
           negotiate_protocol(
             descriptor.features,
             requirements,
             :accepted_runspec_versions,
             :runspec_versions
           ),
         {:ok, event_schema_version} <-
           negotiate_protocol(
             descriptor.features,
             requirements,
             :accepted_event_schema_versions,
             :event_schema_versions
           ) do
      {:ok,
       %{
         runspec_version: runspec_version,
         event_schema_version: event_schema_version
       }}
    end
  end

  defp prepare_attrs(attrs) do
    Map.put(attrs, :extensions, normalize_extensions(attrs))
  end

  defp normalize(%__MODULE__{} = descriptor) do
    {:ok,
     %__MODULE__{
       descriptor
       | runtime_class: Contracts.validate_runtime_class!(descriptor.runtime_class),
         version: Contracts.validate_semver!(descriptor.version, "version"),
         features: normalize_features!(descriptor.features),
         constraints: normalize_constraints!(descriptor.constraints),
         health: Contracts.validate_target_health!(descriptor.health),
         location: normalize_location!(descriptor.location),
         extensions: validate_extensions!(descriptor.extensions)
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_features!(features) when is_map(features) do
    extras =
      collect_unknown_fields(features, [:feature_ids, :runspec_versions, :event_schema_versions])

    extras
    |> Map.merge(%{
      feature_ids:
        Contracts.normalize_string_list!(
          Contracts.get(features, :feature_ids, []),
          "features.feature_ids"
        ),
      runspec_versions:
        Contracts.normalize_version_list!(
          Contracts.get(features, :runspec_versions, []),
          "features.runspec_versions"
        ),
      event_schema_versions:
        Contracts.normalize_version_list!(
          Contracts.get(features, :event_schema_versions, []),
          "features.event_schema_versions"
        )
    })
  end

  defp normalize_features!(features) do
    raise ArgumentError, "features must be a map, got: #{inspect(features)}"
  end

  defp normalize_constraints!(constraints) when is_map(constraints) do
    constraints
    |> collect_unknown_fields([:regions, :sandbox_levels])
    |> put_optional_field(constraints, :regions, fn values ->
      Contracts.normalize_string_list!(values, "constraints.regions")
    end)
    |> put_optional_field(constraints, :sandbox_levels, fn values ->
      normalize_sandbox_levels!(values)
    end)
  end

  defp normalize_constraints!(value) do
    raise ArgumentError, "constraints must be a map, got: #{inspect(value)}"
  end

  defp normalize_location!(location) when is_map(location) do
    location
    |> collect_unknown_fields([:mode, :region, :workspace_root])
    |> Map.put(:mode, Contracts.validate_target_mode!(Contracts.fetch!(location, :mode)))
    |> put_optional_field(location, :region, fn value ->
      Contracts.validate_non_empty_string!(value, "location.region")
    end)
    |> put_optional_field(location, :workspace_root, fn value ->
      Contracts.validate_non_empty_string!(value, "location.workspace_root")
    end)
  end

  defp normalize_location!(value) do
    raise ArgumentError, "location must be a map, got: #{inspect(value)}"
  end

  defp normalize_sandbox_levels!(sandbox_levels) when is_list(sandbox_levels) do
    Enum.map(sandbox_levels, &Contracts.validate_sandbox_level!/1)
  end

  defp normalize_sandbox_levels!(sandbox_levels) do
    raise ArgumentError,
          "constraints.sandbox_levels must be a list, got: #{inspect(sandbox_levels)}"
  end

  defp normalize_extensions(attrs) do
    extensions =
      case Contracts.get(attrs, :extensions, %{}) do
        value when is_map(value) -> value
        value -> raise ArgumentError, "extensions must be a map, got: #{inspect(value)}"
      end

    attrs
    |> collect_unknown_fields(@known_keys)
    |> Map.merge(extensions)
  end

  defp validate_extensions!(extensions) when is_map(extensions), do: extensions

  defp validate_extensions!(extensions) do
    raise ArgumentError, "extensions must be a map, got: #{inspect(extensions)}"
  end

  defp match_capability(descriptor, requirements) do
    requested_capability = Contracts.get(requirements, :capability_id)

    if is_nil(requested_capability) or requested_capability == descriptor.capability_id do
      :ok
    else
      {:error, :capability_mismatch}
    end
  end

  defp match_runtime_class(descriptor, requirements) do
    requested_runtime_class = Contracts.get(requirements, :runtime_class)

    cond do
      is_nil(requested_runtime_class) ->
        :ok

      Contracts.validate_runtime_class!(requested_runtime_class) == descriptor.runtime_class ->
        :ok

      true ->
        {:error, :runtime_class_mismatch}
    end
  end

  defp match_health(%__MODULE__{health: :healthy}), do: :ok
  defp match_health(_descriptor), do: {:error, :target_unhealthy}

  defp match_version(descriptor, requirements) do
    case Contracts.validate_version_requirement!(
           Contracts.get(requirements, :version_requirement)
         ) do
      nil ->
        :ok

      requirement ->
        if Version.match?(descriptor.version, requirement) do
          :ok
        else
          {:error, :version_mismatch}
        end
    end
  end

  defp match_required_features(descriptor, requirements) do
    target_features =
      descriptor.features
      |> Contracts.get(:feature_ids, [])
      |> MapSet.new()

    required_features =
      requirements
      |> Contracts.get(:required_features, [])
      |> Contracts.normalize_string_list!("required_features")

    if Enum.all?(required_features, &MapSet.member?(target_features, &1)) do
      :ok
    else
      {:error, :missing_required_features}
    end
  end

  defp negotiate_protocol(features, requirements, request_key, target_key) do
    accepted_versions = Contracts.get(requirements, request_key)

    if is_nil(accepted_versions) do
      {:ok, nil}
    else
      target_versions = Contracts.get(features, target_key, [])

      mutual_versions =
        target_versions
        |> MapSet.new()
        |> MapSet.intersection(
          accepted_versions
          |> Contracts.normalize_version_list!(Atom.to_string(request_key))
          |> MapSet.new()
        )
        |> MapSet.to_list()

      case Enum.sort(mutual_versions, &(Version.compare(&1, &2) == :gt)) do
        [highest | _rest] -> {:ok, highest}
        [] -> {:error, :version_mismatch}
      end
    end
  end

  defp collect_unknown_fields(map, known_keys) do
    known_string_keys = Enum.map(known_keys, &Atom.to_string/1)

    Enum.reduce(map, %{}, fn {key, value}, acc ->
      known_variants =
        case key do
          atom when is_atom(atom) -> [atom, Atom.to_string(atom)]
          binary when is_binary(binary) -> [binary]
        end

      if Enum.any?(known_variants, &(&1 in known_keys or &1 in known_string_keys)) do
        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp put_optional_field(acc, source, key, normalize) when is_function(normalize, 1) do
    case fetch_optional(source, key) do
      {:ok, value} -> Map.put(acc, key, normalize.(value))
      :error -> acc
    end
  end

  defp fetch_optional(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Map.fetch(map, Atom.to_string(key))
    end
  end
end
