defmodule Jido.Integration.V2.TargetDescriptor do
  @moduledoc """
  Stable public descriptor for an execution target.

  A target is an execution environment advertisement, not a connector
  identity. Compatibility is explicit through runtime class, target
  capability, semantic versioning, and protocol version negotiation.
  """

  alias Jido.Integration.V2.Contracts

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

  @enforce_keys [
    :target_id,
    :capability_id,
    :runtime_class,
    :version,
    :features,
    :constraints,
    :health,
    :location
  ]
  defstruct [
    :target_id,
    :capability_id,
    :runtime_class,
    :version,
    :health,
    features: %{},
    constraints: %{},
    location: %{},
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          target_id: String.t(),
          capability_id: String.t(),
          runtime_class: Contracts.runtime_class(),
          version: String.t(),
          features: map(),
          constraints: map(),
          health: Contracts.target_health(),
          location: map(),
          extensions: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    extensions = normalize_extensions(attrs)

    struct!(__MODULE__, %{
      target_id:
        Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :target_id), "target_id"),
      capability_id:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(attrs, :capability_id),
          "capability_id"
        ),
      runtime_class: Contracts.validate_runtime_class!(Contracts.fetch!(attrs, :runtime_class)),
      version: Contracts.validate_semver!(Contracts.fetch!(attrs, :version), "version"),
      features: normalize_features!(Contracts.fetch!(attrs, :features)),
      constraints: normalize_constraints!(Contracts.fetch!(attrs, :constraints)),
      health: Contracts.validate_target_health!(Contracts.fetch!(attrs, :health)),
      location: normalize_location!(Contracts.fetch!(attrs, :location)),
      extensions: extensions
    })
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
