defmodule Jido.Integration.V2.BackendManifest do
  @moduledoc """
  Declares what a runtime backend can expose to the inference control plane.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()
  @supported_surfaces [:local_subprocess, :ssh_exec, :guest_bridge]

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("backend_manifest.contract_version")
                |> Zoi.default(@contract_version),
              backend: Contracts.atomish_schema("backend_manifest.backend"),
              runtime_kind:
                Contracts.enumish_schema([:task, :service], "backend_manifest.runtime_kind"),
              management_modes:
                Zoi.list(
                  Contracts.enumish_schema(
                    [:provider_managed, :jido_managed, :externally_managed],
                    "backend_manifest.management_modes"
                  )
                ),
              startup_kind:
                Contracts.enumish_schema(
                  [:spawned, :attach_existing_service],
                  "backend_manifest.startup_kind"
                )
                |> Zoi.nullish()
                |> Zoi.optional(),
              protocols:
                Zoi.list(
                  Contracts.enumish_schema(
                    [:openai_chat_completions],
                    "backend_manifest.protocols"
                  )
                ),
              capabilities: Contracts.any_map_schema() |> Zoi.default(%{}),
              supported_surfaces:
                Zoi.list(Contracts.atomish_schema("backend_manifest.supported_surfaces")),
              resource_profile: Contracts.any_map_schema() |> Zoi.default(%{}),
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
  def new(%__MODULE__{} = manifest), do: normalize(manifest)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = manifest) do
    case normalize(manifest) do
      {:ok, manifest} -> manifest
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, manifest} -> manifest
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = manifest) do
    %{
      "contract_version" => manifest.contract_version,
      "backend" => manifest.backend,
      "runtime_kind" => manifest.runtime_kind,
      "management_modes" => manifest.management_modes,
      "startup_kind" => manifest.startup_kind,
      "protocols" => manifest.protocols,
      "capabilities" => manifest.capabilities,
      "supported_surfaces" => manifest.supported_surfaces,
      "resource_profile" => manifest.resource_profile,
      "metadata" => manifest.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  defp normalize(%__MODULE__{} = manifest) do
    {:ok,
     %__MODULE__{
       manifest
       | contract_version:
           Contracts.validate_inference_contract_version!(manifest.contract_version),
         backend: Contracts.normalize_atomish!(manifest.backend, "backend"),
         runtime_kind: validate_backend_runtime_kind!(manifest.runtime_kind),
         management_modes: normalize_management_modes!(manifest.management_modes),
         startup_kind: normalize_startup_kind(manifest.startup_kind),
         protocols: normalize_protocols!(manifest.protocols),
         capabilities: normalize_capabilities!(manifest.capabilities),
         supported_surfaces: normalize_supported_surfaces!(manifest.supported_surfaces),
         resource_profile: normalize_map!(manifest.resource_profile, "resource_profile"),
         metadata: normalize_map!(manifest.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_backend_runtime_kind!(runtime_kind) do
    runtime_kind = Contracts.validate_runtime_kind!(runtime_kind)

    if runtime_kind in [:task, :service] do
      runtime_kind
    else
      raise ArgumentError, "backend runtime_kind must be :task or :service"
    end
  end

  defp normalize_management_modes!(modes) when is_list(modes) do
    Enum.map(modes, &Contracts.validate_management_mode!/1)
  end

  defp normalize_management_modes!(modes) do
    raise ArgumentError, "management_modes must be a list, got: #{inspect(modes)}"
  end

  defp normalize_startup_kind(nil), do: nil

  defp normalize_startup_kind(value) when value in [:spawned, :attach_existing_service],
    do: value

  defp normalize_startup_kind(value) when is_binary(value) do
    case value do
      "spawned" -> :spawned
      "attach_existing_service" -> :attach_existing_service
      _ -> raise ArgumentError, "invalid startup_kind: #{inspect(value)}"
    end
  end

  defp normalize_startup_kind(value) do
    raise ArgumentError, "invalid startup_kind: #{inspect(value)}"
  end

  defp normalize_protocols!(protocols) when is_list(protocols) do
    Enum.map(protocols, &Contracts.validate_inference_protocol!/1)
  end

  defp normalize_protocols!(protocols) do
    raise ArgumentError, "protocols must be a list, got: #{inspect(protocols)}"
  end

  defp normalize_capabilities!(%{} = capabilities) do
    capabilities
    |> Map.new()
    |> Map.put(
      :streaming?,
      normalize_capability_boolean(
        Contracts.get(capabilities, :streaming?),
        "capabilities.streaming?"
      )
    )
    |> Map.put(
      :tool_calling?,
      normalize_capability_boolean_or_unknown(
        Contracts.get(capabilities, :tool_calling?),
        "capabilities.tool_calling?"
      )
    )
    |> Map.put(
      :embeddings?,
      normalize_capability_boolean_or_unknown(
        Contracts.get(capabilities, :embeddings?),
        "capabilities.embeddings?"
      )
    )
  end

  defp normalize_capabilities!(value) do
    raise ArgumentError, "capabilities must be a map, got: #{inspect(value)}"
  end

  defp normalize_supported_surfaces!(surfaces) when is_list(surfaces) do
    Enum.map(surfaces, fn surface ->
      surface = Contracts.normalize_atomish!(surface, "supported_surfaces")

      if surface in @supported_surfaces do
        surface
      else
        raise ArgumentError, "unsupported surface: #{inspect(surface)}"
      end
    end)
  end

  defp normalize_supported_surfaces!(surfaces) do
    raise ArgumentError, "supported_surfaces must be a list, got: #{inspect(surfaces)}"
  end

  defp normalize_capability_boolean(value, _field_name) when is_boolean(value), do: value

  defp normalize_capability_boolean(value, field_name) do
    raise ArgumentError, "#{field_name} must be a boolean, got: #{inspect(value)}"
  end

  defp normalize_capability_boolean_or_unknown(value, _field_name)
       when is_boolean(value) or value == :unknown,
       do: value

  defp normalize_capability_boolean_or_unknown("unknown", _field_name), do: :unknown

  defp normalize_capability_boolean_or_unknown(value, field_name) do
    raise ArgumentError, "#{field_name} must be a boolean or :unknown, got: #{inspect(value)}"
  end

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
