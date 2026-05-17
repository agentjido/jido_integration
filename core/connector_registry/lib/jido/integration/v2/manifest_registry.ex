defmodule Jido.Integration.V2.ManifestRegistry do
  @moduledoc """
  Credential-free manifest registry contract for connector operation lookup.
  """

  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationLookupRequest

  @callback fetch_connector_manifest(String.t(), keyword()) ::
              {:ok, Jido.Integration.V2.ManifestRegistry.Entry.t()} | {:error, term()}

  @callback fetch_operation(String.t(), String.t(), keyword()) ::
              {:ok, Manifest.t(), Jido.Integration.V2.OperationSpec.t()} | {:error, term()}

  @callback resolve_operation(OperationLookupRequest.t(), keyword()) ::
              {:ok, Jido.Integration.V2.OperationDescriptor.t()} | {:error, term()}

  defmodule Entry do
    @moduledoc """
    Credential-free connector manifest entry.
    """

    alias Jido.Integration.V2.Contracts
    alias Jido.Integration.V2.Manifest

    @enforce_keys [
      :connector_ref,
      :manifest_ref,
      :manifest,
      :manifest_digest
    ]
    defstruct [
      :connector_ref,
      :manifest_ref,
      :manifest,
      :manifest_digest,
      :connector_version,
      :provider_family,
      :adapter_ref,
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            connector_ref: String.t(),
            manifest_ref: String.t(),
            manifest: Manifest.t(),
            manifest_digest: String.t(),
            connector_version: String.t() | nil,
            provider_family: String.t() | nil,
            adapter_ref: String.t() | nil,
            metadata: map()
          }

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
    def new(%__MODULE__{} = entry), do: normalize(entry)

    def new(attrs) when is_map(attrs) or is_list(attrs) do
      attrs = Map.new(attrs)

      case normalize_manifest(Contracts.fetch_required!(attrs, :manifest, "manifest")) do
        {:ok, manifest} ->
          normalize(%__MODULE__{
            connector_ref: Contracts.fetch_required!(attrs, :connector_ref, "connector_ref"),
            manifest_ref: Contracts.fetch_required!(attrs, :manifest_ref, "manifest_ref"),
            manifest: manifest,
            manifest_digest:
              Contracts.get(attrs, :manifest_digest, Manifest.canonical_hash(manifest)),
            connector_version: Contracts.get(attrs, :connector_version),
            provider_family: Contracts.get(attrs, :provider_family),
            adapter_ref: Contracts.get(attrs, :adapter_ref),
            metadata: Contracts.get(attrs, :metadata, %{})
          })

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error in [ArgumentError, KeyError] -> {:error, error}
    end

    def new(attrs), do: {:error, {:invalid_manifest_entry, attrs}}

    @spec new!(map() | keyword() | t()) :: t()
    def new!(attrs) do
      case new(attrs) do
        {:ok, entry} -> entry
        {:error, %ArgumentError{} = error} -> raise error
        {:error, %KeyError{} = error} -> raise error
        {:error, reason} -> raise ArgumentError, "invalid manifest entry: #{inspect(reason)}"
      end
    end

    defp normalize(%__MODULE__{} = entry) do
      expected_digest = Manifest.canonical_hash(entry.manifest)

      if entry.manifest_digest != expected_digest do
        {:error,
         {:manifest_entry_digest_mismatch, entry.connector_ref, entry.manifest_digest,
          expected_digest}}
      else
        {:ok,
         %__MODULE__{
           entry
           | connector_ref: non_empty!(entry.connector_ref, "connector_ref"),
             manifest_ref: non_empty!(entry.manifest_ref, "manifest_ref"),
             manifest_digest: non_empty!(entry.manifest_digest, "manifest_digest"),
             connector_version: optional_non_empty(entry.connector_version, "connector_version"),
             provider_family: optional_non_empty(entry.provider_family, "provider_family"),
             adapter_ref: optional_non_empty(entry.adapter_ref, "adapter_ref"),
             metadata: map!(entry.metadata, "metadata")
         }}
      end
    rescue
      error in ArgumentError -> {:error, error}
    end

    defp normalize_manifest(%Manifest{} = manifest), do: {:ok, manifest}

    defp normalize_manifest(module) when is_atom(module) do
      if Code.ensure_loaded?(module) and function_exported?(module, :manifest, 0) do
        normalize_manifest(module.manifest())
      else
        {:error, {:invalid_manifest_module, module}}
      end
    end

    defp normalize_manifest(attrs) when is_map(attrs) or is_list(attrs), do: Manifest.new(attrs)
    defp normalize_manifest(attrs), do: {:error, {:invalid_manifest, attrs}}

    defp non_empty!(value, field_name),
      do: Contracts.validate_non_empty_string!(value, field_name)

    defp optional_non_empty(nil, _field_name), do: nil
    defp optional_non_empty(value, field_name), do: non_empty!(value, field_name)

    defp map!(value, _field_name) when is_map(value), do: Map.new(value)

    defp map!(value, field_name) do
      raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
    end
  end
end
