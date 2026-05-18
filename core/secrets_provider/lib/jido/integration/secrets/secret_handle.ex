defmodule Jido.Integration.Secrets.SecretHandle do
  @moduledoc """
  Short-lived handle returned by a secrets provider.

  `material` is intentionally private to the brokered call path. Inspect output
  is redacted so accidental log output cannot disclose credential values.
  """

  @enforce_keys [:lease_ref, :provider_ref, :audit_ref, :material]
  defstruct [
    :lease_ref,
    :provider_ref,
    :audit_ref,
    :material,
    scope: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          lease_ref: String.t(),
          provider_ref: String.t(),
          audit_ref: String.t(),
          material: map(),
          scope: map(),
          metadata: map()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, lease_ref} <- required_string(attrs, :lease_ref),
         {:ok, provider_ref} <- required_string(attrs, :provider_ref),
         {:ok, audit_ref} <- required_string(attrs, :audit_ref),
         {:ok, material} <- material_attr(attrs) do
      {:ok,
       %__MODULE__{
         lease_ref: lease_ref,
         provider_ref: provider_ref,
         audit_ref: audit_ref,
         material: material,
         scope: Map.get(attrs, :scope, %{}),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, handle} -> handle
      {:error, reason} -> raise ArgumentError, "invalid secret handle: #{inspect(reason)}"
    end
  end

  @spec public_ref(t()) :: map()
  def public_ref(%__MODULE__{} = handle) do
    public_ref = %{
      lease_ref: handle.lease_ref,
      provider_ref: handle.provider_ref,
      audit_ref: handle.audit_ref
    }

    case public_metadata(handle.metadata) do
      metadata when map_size(metadata) == 0 -> public_ref
      metadata -> Map.put(public_ref, :metadata, metadata)
    end
  end

  @spec material(t()) :: map()
  def material(%__MODULE__{} = handle), do: handle.material

  defp required_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_secret_handle_field, key}}
    end
  end

  defp material_attr(attrs) do
    case Map.get(attrs, :material) do
      %{} = material when map_size(material) > 0 -> {:ok, material}
      _missing -> {:error, :missing_secret_material}
    end
  end

  defp public_metadata(metadata) when is_map(metadata) do
    Map.drop(metadata, [:material, "material", :secret, "secret", :credential, "credential"])
  end

  defp public_metadata(_metadata), do: %{}

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(%{} = attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {string_key(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp string_key("lease_ref"), do: :lease_ref
  defp string_key("provider_ref"), do: :provider_ref
  defp string_key("audit_ref"), do: :audit_ref
  defp string_key("material"), do: :material
  defp string_key("scope"), do: :scope
  defp string_key("metadata"), do: :metadata
  defp string_key(key), do: key
end

defimpl Inspect, for: Jido.Integration.Secrets.SecretHandle do
  import Inspect.Algebra

  def inspect(handle, opts) do
    concat([
      "#Jido.Integration.Secrets.SecretHandle<",
      to_doc(
        %{
          lease_ref: handle.lease_ref,
          provider_ref: handle.provider_ref,
          audit_ref: handle.audit_ref,
          material: :redacted
        },
        opts
      ),
      ">"
    ])
  end
end
