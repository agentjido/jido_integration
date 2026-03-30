defmodule Jido.BoundaryBridge.Extensions.Tracing do
  @moduledoc """
  Typed tracing-carrier extension for boundary descriptors.
  """

  alias Jido.BoundaryBridge.Contracts
  alias Jido.BoundaryBridge.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              traceparent:
                Contracts.non_empty_string_schema("extensions.tracing.traceparent")
                |> Zoi.nullish()
                |> Zoi.optional(),
              tracestate:
                Contracts.non_empty_string_schema("extensions.tracing.tracestate")
                |> Zoi.nullish()
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = tracing), do: {:ok, tracing}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = tracing), do: tracing
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
end
