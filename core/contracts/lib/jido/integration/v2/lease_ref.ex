defmodule Jido.Integration.V2.LeaseRef do
  @moduledoc """
  Durable reference to a reusable runtime lease or endpoint instance.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version Contracts.inference_contract_version()

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("lease_ref.contract_version")
                |> Zoi.default(@contract_version),
              lease_ref: Contracts.non_empty_string_schema("lease_ref.lease_ref"),
              owner_ref:
                Contracts.non_empty_string_schema("lease_ref.owner_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              ttl_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.nullish() |> Zoi.optional(),
              renewable?: Zoi.boolean() |> Zoi.default(false),
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
  def new(%__MODULE__{} = lease_ref), do: normalize(lease_ref)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = lease_ref) do
    case normalize(lease_ref) do
      {:ok, lease_ref} -> lease_ref
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, lease_ref} -> lease_ref
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = lease_ref) do
    %{
      "contract_version" => lease_ref.contract_version,
      "lease_ref" => lease_ref.lease_ref,
      "owner_ref" => lease_ref.owner_ref,
      "ttl_ms" => lease_ref.ttl_ms,
      "renewable?" => lease_ref.renewable?,
      "metadata" => lease_ref.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  defp normalize(%__MODULE__{} = lease_ref) do
    {:ok,
     %__MODULE__{
       lease_ref
       | contract_version:
           Contracts.validate_inference_contract_version!(lease_ref.contract_version),
         metadata: normalize_map!(lease_ref.metadata, "metadata")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_map!(%{} = value, _field_name), do: Map.new(value)

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
