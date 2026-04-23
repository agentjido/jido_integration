defmodule Jido.Integration.V2.NodeIdentity do
  @moduledoc """
  Stable node identity contract for `Platform.NodeIdentity.V1`.
  """

  alias Jido.Integration.V2.{CanonicalJson, Contracts}

  @contract_name "Platform.NodeIdentity.V1"
  @contract_version "1.0.0"
  @default_base_dir "/var/lib/memsim/node_id"
  @max_metadata_bytes 8_192

  @fields [
    :contract_name,
    :contract_version,
    :node_ref,
    :node_instance_id,
    :boot_generation,
    :node_role,
    :deployment_ref,
    :release_manifest_ref,
    :started_at,
    :cluster_ref,
    :metadata
  ]

  @enforce_keys @fields -- [:cluster_ref]
  defstruct @fields

  @type t :: %__MODULE__{
          contract_name: String.t(),
          contract_version: String.t(),
          node_ref: String.t(),
          node_instance_id: String.t(),
          boot_generation: pos_integer(),
          node_role: atom() | String.t(),
          deployment_ref: String.t(),
          release_manifest_ref: String.t(),
          started_at: DateTime.t(),
          cluster_ref: String.t() | nil,
          metadata: map()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec load_or_start!(String.t(), keyword()) :: t()
  def load_or_start!(shortname, opts \\ []) when is_list(opts) do
    shortname = Contracts.validate_non_empty_string!(shortname, "node_identity.shortname")

    host =
      Contracts.validate_non_empty_string!(
        Keyword.get(opts, :host, "localhost"),
        "node_identity.host"
      )

    base_dir = Keyword.get(opts, :base_dir, @default_base_dir)
    path = Path.join(base_dir, "#{shortname}.id")
    File.mkdir_p!(base_dir)

    persisted = load_persisted(path)
    persistent_uuid = Map.get(persisted, "persistent_uuid") || random_uuid()
    boot_generation = Map.get(persisted, "boot_generation", 0) + 1

    next_persisted = %{
      "persistent_uuid" => persistent_uuid,
      "boot_generation" => boot_generation
    }

    File.write!(path, CanonicalJson.encode!(next_persisted))

    new!(%{
      node_ref: "node://#{shortname}@#{host}/#{persistent_uuid}",
      node_instance_id: Keyword.get(opts, :node_instance_id, random_uuid()),
      boot_generation: boot_generation,
      node_role: Keyword.fetch!(opts, :node_role),
      deployment_ref: Keyword.fetch!(opts, :deployment_ref),
      release_manifest_ref: Keyword.fetch!(opts, :release_manifest_ref),
      started_at: Keyword.get(opts, :started_at, Contracts.now()),
      cluster_ref: Keyword.get(opts, :cluster_ref),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = identity), do: normalize(identity)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = identity) do
    case normalize(identity) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = identity) do
    %{
      contract_name: identity.contract_name,
      contract_version: identity.contract_version,
      node_ref: identity.node_ref,
      node_instance_id: identity.node_instance_id,
      boot_generation: identity.boot_generation,
      node_role: identity.node_role,
      deployment_ref: identity.deployment_ref,
      release_manifest_ref: identity.release_manifest_ref,
      started_at: DateTime.to_iso8601(identity.started_at),
      cluster_ref: identity.cluster_ref,
      metadata: identity.metadata
    }
  end

  @spec replay_group(t()) :: {String.t(), pos_integer()}
  def replay_group(%__MODULE__{} = identity), do: {identity.node_ref, identity.boot_generation}

  defp build!(attrs) do
    attrs = Map.new(attrs)
    metadata = attrs |> Contracts.get(:metadata, %{}) |> Contracts.validate_map!(field(:metadata))
    validate_metadata_size!(metadata)

    %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, :contract_name),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, :contract_version),
      node_ref:
        attrs
        |> Contracts.get(:node_ref)
        |> required_string(:node_ref),
      node_instance_id:
        attrs
        |> Contracts.get(:node_instance_id)
        |> required_string(:node_instance_id),
      boot_generation:
        attrs
        |> Contracts.get(:boot_generation)
        |> Contracts.validate_positive_integer!(field(:boot_generation)),
      node_role:
        attrs
        |> Contracts.get(:node_role)
        |> required_role!(),
      deployment_ref:
        attrs
        |> Contracts.get(:deployment_ref)
        |> required_string(:deployment_ref),
      release_manifest_ref:
        attrs
        |> Contracts.get(:release_manifest_ref)
        |> required_string(:release_manifest_ref),
      started_at:
        attrs
        |> Contracts.get(:started_at)
        |> datetime!(:started_at),
      cluster_ref: optional_string(attrs, :cluster_ref),
      metadata: metadata
    }
  end

  defp normalize(%__MODULE__{} = identity) do
    {:ok, identity |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp load_persisted(path) do
    with true <- File.exists?(path),
         {:ok, binary} <- File.read(path),
         {:ok, decoded} <- Jason.decode(binary),
         true <- is_map(decoded) do
      decoded
    else
      _ -> %{}
    end
  end

  defp validate_metadata_size!(metadata) do
    if byte_size(CanonicalJson.encode!(metadata)) <= @max_metadata_bytes do
      :ok
    else
      raise ArgumentError, "#{field(:metadata)} exceeds maximum encoded size"
    end
  end

  defp random_uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    Enum.join(
      [
        Base.encode16(<<a::32>>, case: :lower),
        Base.encode16(<<b::16>>, case: :lower),
        Base.encode16(<<c::16>>, case: :lower),
        Base.encode16(<<d::16>>, case: :lower),
        Base.encode16(<<e::48>>, case: :lower)
      ],
      "-"
    )
  end

  defp required_role!(nil), do: raise(ArgumentError, "#{field(:node_role)} is required")
  defp required_role!(""), do: raise(ArgumentError, "#{field(:node_role)} is required")
  defp required_role!(role) when is_atom(role), do: role
  defp required_role!(role) when is_binary(role), do: required_string(role, :node_role)

  defp required_role!(role) do
    raise ArgumentError, "#{field(:node_role)} must be an atom or string, got: #{inspect(role)}"
  end

  defp optional_string(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> required_string(value, key)
    end
  end

  defp datetime!(%DateTime{} = value, _key), do: value

  defp datetime!(value, key) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> raise ArgumentError, "#{field(key)} must be a DateTime"
    end
  end

  defp datetime!(value, key) do
    raise ArgumentError, "#{field(key)} must be a DateTime, got: #{inspect(value)}"
  end

  defp required_string(value, key), do: Contracts.validate_non_empty_string!(value, field(key))

  defp validate_literal!(value, expected, key) do
    if value == expected do
      value
    else
      raise ArgumentError, "#{field(key)} must be #{inspect(expected)}, got: #{inspect(value)}"
    end
  end

  defp field(key), do: "node_identity.#{key}"
end
