defmodule Jido.Integration.V2.CapabilityRef do
  @moduledoc """
  External SDK-safe capability reference.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.SDKRefSupport

  @required_fields [:connector_ref, :capability_id, :tenant_ref, :scope_ref, :contract_version]

  @enforce_keys @required_fields
  defstruct @required_fields

  @type t :: %__MODULE__{
          connector_ref: String.t(),
          capability_id: String.t(),
          tenant_ref: String.t(),
          scope_ref: String.t(),
          contract_version: String.t()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: SDKRefSupport.new(__MODULE__, attrs, @required_fields)

  @spec new!(map() | keyword()) :: t()
  def new!(attrs), do: SDKRefSupport.new!(__MODULE__, attrs, @required_fields)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = ref), do: SDKRefSupport.dump(ref)

  @spec load(map()) :: {:ok, t()} | {:error, term()}
  def load(attrs), do: new(attrs)

  @spec canonical_hash(t()) :: String.t()
  def canonical_hash(%__MODULE__{} = ref), do: ref |> dump() |> CanonicalJson.checksum!()
end

defmodule Jido.Integration.V2.ScopeRef do
  @moduledoc """
  SDK-safe scope posture reference.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.SDKRefSupport

  @required_fields [:scope_ref, :tenant_ref, :installation_ref, :scope_class, :contract_version]

  @enforce_keys @required_fields
  defstruct @required_fields

  @type t :: %__MODULE__{
          scope_ref: String.t(),
          tenant_ref: String.t(),
          installation_ref: String.t(),
          scope_class: String.t(),
          contract_version: String.t()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: SDKRefSupport.new(__MODULE__, attrs, @required_fields)

  @spec new!(map() | keyword()) :: t()
  def new!(attrs), do: SDKRefSupport.new!(__MODULE__, attrs, @required_fields)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = ref), do: SDKRefSupport.dump(ref)

  @spec load(map()) :: {:ok, t()} | {:error, term()}
  def load(attrs), do: new(attrs)

  @spec canonical_hash(t()) :: String.t()
  def canonical_hash(%__MODULE__{} = ref), do: ref |> dump() |> CanonicalJson.checksum!()
end

defmodule Jido.Integration.V2.ConformanceRef do
  @moduledoc """
  SDK-safe conformance proof reference.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.SDKRefSupport

  @required_fields [
    :conformance_ref,
    :manifest_hash,
    :contract_version,
    :profile,
    :status,
    :generated_at
  ]

  @enforce_keys @required_fields
  defstruct @required_fields

  @type t :: %__MODULE__{
          conformance_ref: String.t(),
          manifest_hash: String.t(),
          contract_version: String.t(),
          profile: String.t(),
          status: String.t(),
          generated_at: String.t()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: SDKRefSupport.new(__MODULE__, attrs, @required_fields)

  @spec new!(map() | keyword()) :: t()
  def new!(attrs), do: SDKRefSupport.new!(__MODULE__, attrs, @required_fields)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = ref), do: SDKRefSupport.dump(ref)

  @spec load(map()) :: {:ok, t()} | {:error, term()}
  def load(attrs), do: new(attrs)

  @spec canonical_hash(t()) :: String.t()
  def canonical_hash(%__MODULE__{} = ref), do: ref |> dump() |> CanonicalJson.checksum!()
end

defmodule Jido.Integration.V2.SDKRefSupport do
  @moduledoc false

  @known_string_keys %{
    "capability_id" => :capability_id,
    "conformance_ref" => :conformance_ref,
    "contract_version" => :contract_version,
    "connector_ref" => :connector_ref,
    "generated_at" => :generated_at,
    "installation_ref" => :installation_ref,
    "manifest_hash" => :manifest_hash,
    "profile" => :profile,
    "scope_class" => :scope_class,
    "scope_ref" => :scope_ref,
    "status" => :status,
    "tenant_ref" => :tenant_ref
  }

  @spec new(module(), map() | keyword(), [atom()]) :: {:ok, struct()} | {:error, term()}
  def new(module, attrs, required_fields) when is_atom(module) and is_list(required_fields) do
    attrs = normalize_attrs(attrs)
    missing = Enum.reject(required_fields, &present_string?(Map.get(attrs, &1)))

    if missing == [] do
      {:ok, struct!(module, Map.take(attrs, required_fields))}
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  @spec new!(module(), map() | keyword(), [atom()]) :: struct()
  def new!(module, attrs, required_fields) do
    case new(module, attrs, required_fields) do
      {:ok, ref} -> ref
      {:error, reason} -> raise ArgumentError, "invalid SDK ref: #{inspect(reason)}"
    end
  end

  @spec dump(struct()) :: map()
  def dump(%module{} = ref) do
    ref
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
    |> Map.put("ref_type", module |> Module.split() |> List.last())
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key), do: Map.get(@known_string_keys, key, key)

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
