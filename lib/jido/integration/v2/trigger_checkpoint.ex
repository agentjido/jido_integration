defmodule Jido.Integration.V2.TriggerCheckpoint do
  @moduledoc """
  Durable checkpoint for polling-style trigger progression.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              tenant_id: Contracts.non_empty_string_schema("trigger_checkpoint.tenant_id"),
              connector_id: Contracts.non_empty_string_schema("trigger_checkpoint.connector_id"),
              trigger_id: Contracts.non_empty_string_schema("trigger_checkpoint.trigger_id"),
              partition_key:
                Contracts.non_empty_string_schema("trigger_checkpoint.partition_key"),
              cursor: Contracts.non_empty_string_schema("trigger_checkpoint.cursor"),
              last_event_id:
                Contracts.non_empty_string_schema("trigger_checkpoint.last_event_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              last_event_time:
                Contracts.datetime_schema("trigger_checkpoint.last_event_time")
                |> Zoi.nullish()
                |> Zoi.optional(),
              revision: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
              updated_at:
                Contracts.datetime_schema("trigger_checkpoint.updated_at")
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
  def new(%__MODULE__{} = checkpoint), do: normalize(checkpoint)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = checkpoint),
    do: normalize(checkpoint) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = checkpoint) do
    {:ok, %__MODULE__{checkpoint | updated_at: checkpoint.updated_at || Contracts.now()}}
  end
end
