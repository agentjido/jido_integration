defmodule Jido.Integration.V2.InvocationRequest do
  @moduledoc """
  Typed public request for capability invocation through the v2 facade.

  The request keeps the stable control-plane invoke fields explicit while still
  allowing non-reserved extension opts to flow through to runtime context.

  When a capability requires auth, the public binding is `connection_id`.
  Credential refs remain internal auth and execution plumbing.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Gateway
  alias Jido.Integration.V2.Schema

  @reserved_extension_keys [
    :connection_id,
    :actor_id,
    :tenant_id,
    :environment,
    :trace_id,
    :allowed_operations,
    :sandbox,
    :target_id,
    :aggregator_id,
    :aggregator_epoch
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              capability_id: Contracts.non_empty_string_schema("invocation.capability_id"),
              connection_id:
                Contracts.non_empty_string_schema("invocation.connection_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              actor_id:
                Contracts.non_empty_string_schema("invocation.actor_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              tenant_id:
                Contracts.non_empty_string_schema("invocation.tenant_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              environment:
                Zoi.union([Zoi.atom(), Zoi.string()]) |> Zoi.nullish() |> Zoi.optional(),
              trace_id:
                Contracts.non_empty_string_schema("invocation.trace_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              target_id:
                Contracts.non_empty_string_schema("invocation.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              aggregator_id:
                Contracts.non_empty_string_schema("invocation.aggregator_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              aggregator_epoch:
                Contracts.positive_integer_schema("aggregator_epoch")
                |> Zoi.nullish()
                |> Zoi.optional(),
              input: Contracts.map_schema("input") |> Zoi.default(%{}),
              allowed_operations:
                Contracts.string_list_schema("invocation.allowed_operations")
                |> Zoi.nullish()
                |> Zoi.optional(),
              sandbox: Contracts.map_schema("sandbox") |> Zoi.default(%{}),
              extensions:
                Contracts.keyword_list_schema("invocation.extensions") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = request), do: normalize(request)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    reject_credential_ref!(attrs)

    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, request} -> normalize(request)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = request) do
    case normalize(request) do
      {:ok, request} -> request
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec to_opts(t()) :: keyword()
  def to_opts(%__MODULE__{} = request) do
    reject_extension_credential_ref!(request.extensions)

    [
      {:connection_id, request.connection_id},
      {:actor_id, request.actor_id},
      {:tenant_id, request.tenant_id},
      {:environment, request.environment},
      {:trace_id, request.trace_id},
      {:allowed_operations, request.allowed_operations},
      {:sandbox, request.sandbox},
      {:target_id, request.target_id},
      {:aggregator_id, request.aggregator_id},
      {:aggregator_epoch, request.aggregator_epoch}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Kernel.++(request.extensions)
  end

  defp normalize(%__MODULE__{} = request) do
    with :ok <- reject_reserved_extension_keys(request.extensions) do
      capability_id =
        Contracts.validate_non_empty_string!(request.capability_id, "capability_id")

      reject_extension_credential_ref!(request.extensions)

      {:ok,
       %__MODULE__{
         request
         | capability_id: capability_id,
           environment: normalize_environment(request.environment),
           allowed_operations: request.allowed_operations || [capability_id],
           sandbox: normalize_sandbox(request.sandbox)
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp normalize_environment(nil), do: nil
  defp normalize_environment(value) when is_atom(value), do: value

  defp normalize_environment(value) when is_binary(value) do
    Contracts.validate_non_empty_string!(value, "environment")
  end

  defp normalize_sandbox(sandbox) when is_map(sandbox) do
    Gateway.new!(%{runtime_class: :direct, sandbox: sandbox}).sandbox
  end

  defp reject_extension_credential_ref!(extensions) do
    if Keyword.has_key?(extensions, :credential_ref) do
      raise ArgumentError, "credential_ref is not part of the public invocation contract"
    end

    :ok
  end

  defp reject_credential_ref!(attrs) do
    if Map.has_key?(attrs, :credential_ref) or Map.has_key?(attrs, "credential_ref") do
      raise ArgumentError, "credential_ref is not part of the public invocation contract"
    end
  end

  defp reject_reserved_extension_keys(extensions) do
    reserved_keys =
      extensions
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.filter(&(&1 in @reserved_extension_keys))

    if reserved_keys == [] do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "extensions must not redefine reserved invoke fields: #{inspect(reserved_keys)}"
       )}
    end
  end
end
