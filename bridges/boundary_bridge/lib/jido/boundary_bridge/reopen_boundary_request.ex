defmodule Jido.BoundaryBridge.ReopenBoundaryRequest do
  @moduledoc """
  Typed reopen request for the lower-boundary bridge.
  """

  alias Jido.BoundaryBridge.{AttachConfig, Contracts, PolicyIntent, Refs, Schema}

  @schema Zoi.struct(
            __MODULE__,
            %{
              boundary_session_id:
                Contracts.non_empty_string_schema("reopen_boundary_request.boundary_session_id"),
              backend_kind: Contracts.atomish_schema("reopen_boundary_request.backend_kind"),
              boundary_class:
                Contracts.atomish_schema("reopen_boundary_request.boundary_class")
                |> Zoi.nullish()
                |> Zoi.optional(),
              attach: Contracts.any_map_schema() |> Zoi.default(%{}),
              policy_intent: Contracts.any_map_schema() |> Zoi.default(%{}),
              refs: Contracts.any_map_schema(),
              checkpoint_id:
                Contracts.non_empty_string_schema("reopen_boundary_request.checkpoint_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              readiness_timeout_ms: Zoi.integer() |> Zoi.default(5_000),
              extensions: Contracts.any_map_schema() |> Zoi.default(%{}),
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
  def new(%__MODULE__{} = request), do: normalize(request)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    __MODULE__
    |> Schema.new(@schema, Map.new(attrs))
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
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

  defp normalize(%__MODULE__{} = request) do
    {:ok,
     %__MODULE__{
       request
       | attach: AttachConfig.new!(request.attach),
         policy_intent: PolicyIntent.new!(request.policy_intent),
         refs: Refs.new!(request.refs),
         readiness_timeout_ms:
           validate_positive_integer!(
             request.readiness_timeout_ms,
             "reopen_boundary_request.readiness_timeout_ms"
           )
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_positive_integer!(value, _field_name) when is_integer(value) and value > 0,
    do: value

  defp validate_positive_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a positive integer, got: #{inspect(value)}"
  end
end
