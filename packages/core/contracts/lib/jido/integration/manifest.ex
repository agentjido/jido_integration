defmodule Jido.Integration.Manifest do
  @moduledoc """
  Connector manifest — the control-plane source of truth for a connector.

  A manifest declares everything the control plane needs to know about a
  connector: its identity, capabilities, auth requirements, operations,
  triggers, and quality tier.

  ## Required Fields

  - `id` — globally unique, stable string identifier
  - `display_name` — human-readable name
  - `vendor` — vendor/publisher name
  - `domain` — connector domain classification
  - `version` — semantic version string
  - `quality_tier` — bronze | silver | gold
  - `auth` — list of auth descriptors
  - `operations` — list of operation descriptors

  ## Optional Fields

  - `triggers` — list of trigger descriptors
  - `capabilities` — capability map (string keys, status values)
  - `telemetry_namespace` — hierarchical telemetry namespace
  - `config_schema` — JSON schema for connector config
  - `extensions` — arbitrary extension data
  """

  alias Jido.Integration.{Auth, Capability, Error, Operation, Trigger}

  @valid_domains ~w(
    messaging
    llm_provider
    cli_provider
    protocol
    saas
    data
    crm
    storage
    ai
    devtools
    infra
    custom
  )
  @valid_quality_tiers ~w(bronze silver gold)

  @type t :: %__MODULE__{
          id: String.t(),
          display_name: String.t(),
          vendor: String.t(),
          domain: String.t(),
          version: String.t(),
          quality_tier: String.t(),
          auth: [Auth.Descriptor.t()],
          operations: [Operation.Descriptor.t()],
          triggers: [Trigger.Descriptor.t()],
          capabilities: %{String.t() => String.t()},
          telemetry_namespace: String.t() | nil,
          config_schema: map() | nil,
          extensions: map()
        }

  @enforce_keys [
    :id,
    :display_name,
    :vendor,
    :domain,
    :version,
    :quality_tier,
    :auth,
    :operations
  ]
  defstruct [
    :id,
    :display_name,
    :vendor,
    :domain,
    :version,
    :quality_tier,
    :telemetry_namespace,
    :config_schema,
    auth: [],
    operations: [],
    triggers: [],
    capabilities: %{},
    extensions: %{}
  ]

  @doc """
  Create a new manifest from a map or keyword list.

  Validates all required fields and nested descriptors.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_map(attrs) do
    with {:ok, attrs} <- validate_required(attrs),
         {:ok, attrs} <- validate_sections(attrs),
         {:ok, attrs} <- validate_domain(attrs),
         {:ok, attrs} <- validate_quality_tier(attrs),
         {:ok, attrs} <- validate_version(attrs),
         {:ok, auth} <- parse_auth(attrs),
         {:ok, operations} <- parse_operations(attrs),
         {:ok, triggers} <- parse_triggers(attrs),
         {:ok, capabilities} <- parse_capabilities(attrs) do
      manifest = %__MODULE__{
        id: Map.fetch!(attrs, "id"),
        display_name: Map.fetch!(attrs, "display_name"),
        vendor: Map.fetch!(attrs, "vendor"),
        domain: Map.fetch!(attrs, "domain"),
        version: Map.fetch!(attrs, "version"),
        quality_tier: Map.fetch!(attrs, "quality_tier"),
        auth: auth,
        operations: operations,
        triggers: triggers,
        capabilities: capabilities,
        telemetry_namespace: Map.get(attrs, "telemetry_namespace"),
        config_schema: Map.get(attrs, "config_schema"),
        extensions: Map.get(attrs, "extensions", %{})
      }

      {:ok, manifest}
    end
  end

  def new(attrs) when is_list(attrs) do
    attrs |> Map.new(fn {k, v} -> {to_string(k), v} end) |> new()
  end

  @doc """
  Create a manifest, raising on validation failure.
  """
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, manifest} -> manifest
      {:error, error} -> raise ArgumentError, Error.message(error)
    end
  end

  @doc """
  Parse a manifest from a JSON string.
  """
  @spec from_json(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def from_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, attrs} -> new(attrs)
      {:error, _} -> {:error, Error.new(:invalid_request, "Invalid JSON")}
    end
  end

  @doc """
  Serialize a manifest to a JSON-encodable map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = m) do
    %{
      "id" => m.id,
      "display_name" => m.display_name,
      "vendor" => m.vendor,
      "domain" => m.domain,
      "version" => m.version,
      "quality_tier" => m.quality_tier,
      "auth" => Enum.map(m.auth, &Auth.Descriptor.to_map/1),
      "operations" => Enum.map(m.operations, &Operation.Descriptor.to_map/1),
      "triggers" => Enum.map(m.triggers, &Trigger.Descriptor.to_map/1),
      "capabilities" => m.capabilities,
      "telemetry_namespace" => m.telemetry_namespace,
      "config_schema" => m.config_schema,
      "extensions" => m.extensions
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Returns the list of valid domain values.
  """
  @spec valid_domains() :: [String.t()]
  def valid_domains, do: @valid_domains

  @doc """
  Returns the list of valid quality tier values.
  """
  @spec valid_quality_tiers() :: [String.t()]
  def valid_quality_tiers, do: @valid_quality_tiers

  # Validation helpers

  @required_fields ~w(id display_name vendor domain version quality_tier auth operations)

  defp validate_required(attrs) do
    missing = Enum.filter(@required_fields, &(not Map.has_key?(attrs, &1)))

    if missing == [] do
      {:ok, attrs}
    else
      {:error,
       Error.new(:invalid_request, "Missing required fields: #{Enum.join(missing, ", ")}")}
    end
  end

  defp validate_sections(attrs) do
    with :ok <- validate_auth_section(attrs),
         :ok <- validate_operations_section(attrs),
         :ok <- validate_optional_list(attrs, "triggers"),
         :ok <- validate_optional_map(attrs, "config_schema"),
         :ok <- validate_optional_map(attrs, "extensions") do
      {:ok, attrs}
    end
  end

  defp validate_auth_section(attrs) do
    case Map.get(attrs, "auth") do
      auth when is_list(auth) and auth != [] ->
        :ok

      [] ->
        {:error,
         Error.new(:invalid_request, "Manifest auth must declare at least one auth descriptor")}

      other ->
        {:error,
         Error.new(:invalid_request, "Manifest auth must be a list, got: #{inspect(other)}")}
    end
  end

  defp validate_operations_section(attrs) do
    case Map.get(attrs, "operations") do
      operations when is_list(operations) ->
        :ok

      other ->
        {:error,
         Error.new(:invalid_request, "Manifest operations must be a list, got: #{inspect(other)}")}
    end
  end

  defp validate_optional_list(attrs, key) do
    case Map.get(attrs, key) do
      nil ->
        :ok

      value when is_list(value) ->
        :ok

      other ->
        {:error, Error.new(:invalid_request, "#{key} must be a list, got: #{inspect(other)}")}
    end
  end

  defp validate_optional_map(attrs, key) do
    case Map.get(attrs, key) do
      nil ->
        :ok

      value when is_map(value) ->
        :ok

      other ->
        {:error, Error.new(:invalid_request, "#{key} must be a map, got: #{inspect(other)}")}
    end
  end

  defp validate_domain(attrs) do
    domain = Map.get(attrs, "domain")

    if domain in @valid_domains do
      {:ok, attrs}
    else
      {:error,
       Error.new(
         :invalid_request,
         "Invalid domain: #{inspect(domain)}. Must be one of: #{Enum.join(@valid_domains, ", ")}"
       )}
    end
  end

  defp validate_quality_tier(attrs) do
    tier = Map.get(attrs, "quality_tier")

    if tier in @valid_quality_tiers do
      {:ok, attrs}
    else
      {:error,
       Error.new(
         :invalid_request,
         "Invalid quality_tier: #{inspect(tier)}. Must be one of: #{Enum.join(@valid_quality_tiers, ", ")}"
       )}
    end
  end

  defp validate_version(attrs) do
    version = Map.get(attrs, "version")

    if is_binary(version) && Version.parse(version) != :error do
      {:ok, attrs}
    else
      {:error,
       Error.new(:invalid_request, "Invalid version: #{inspect(version)}. Must be semver.")}
    end
  end

  defp parse_auth(attrs) do
    auth_list = Map.get(attrs, "auth", [])

    results =
      Enum.map(auth_list, fn a ->
        Auth.Descriptor.new(a)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, d} -> d end)}
      {:error, _} = err -> err
    end
  end

  defp parse_operations(attrs) do
    ops_list = Map.get(attrs, "operations", [])

    results = Enum.map(ops_list, &Operation.Descriptor.new/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, d} -> d end)}
      {:error, _} = err -> err
    end
  end

  defp parse_triggers(attrs) do
    triggers_list = Map.get(attrs, "triggers", [])

    results = Enum.map(triggers_list, &Trigger.Descriptor.new/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, d} -> d end)}
      {:error, _} = err -> err
    end
  end

  defp parse_capabilities(attrs) do
    caps = Map.get(attrs, "capabilities", %{})

    normalized_caps =
      Map.new(caps, fn {k, v} ->
        {to_string(k), to_string(v)}
      end)

    case Capability.validate(normalized_caps) do
      :ok ->
        {:ok, normalized_caps}

      {:error, errors} ->
        details =
          Enum.map(errors, fn {key, message} ->
            "#{key}: #{message}"
          end)

        {:error, Error.new(:invalid_request, "Invalid capabilities: #{Enum.join(details, "; ")}")}
    end
  end
end
