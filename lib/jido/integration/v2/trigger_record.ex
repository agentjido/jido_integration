defmodule Jido.Integration.V2.TriggerRecord do
  @moduledoc """
  Durable trigger admission or rejection record owned by the control plane.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @sources [:webhook, :poll]
  @statuses [:accepted, :rejected]

  @schema Zoi.struct(
            __MODULE__,
            %{
              admission_id:
                Contracts.non_empty_string_schema("trigger_record.admission_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              source: Contracts.enumish_schema(@sources, "trigger_record.source"),
              connector_id: Contracts.non_empty_string_schema("trigger_record.connector_id"),
              trigger_id: Contracts.non_empty_string_schema("trigger_record.trigger_id"),
              capability_id: Contracts.non_empty_string_schema("trigger_record.capability_id"),
              tenant_id: Contracts.non_empty_string_schema("trigger_record.tenant_id"),
              external_id:
                Contracts.non_empty_string_schema("trigger_record.external_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              dedupe_key: Contracts.non_empty_string_schema("trigger_record.dedupe_key"),
              partition_key:
                Contracts.non_empty_string_schema("trigger_record.partition_key")
                |> Zoi.nullish()
                |> Zoi.optional(),
              payload: Contracts.any_map_schema() |> Zoi.default(%{}),
              signal: Contracts.any_map_schema() |> Zoi.default(%{}),
              status:
                Contracts.enumish_schema(@statuses, "trigger_record.status")
                |> Zoi.default(:accepted),
              run_id:
                Contracts.non_empty_string_schema("trigger_record.run_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              rejection_reason: Zoi.any() |> Zoi.nullish() |> Zoi.optional(),
              inserted_at:
                Contracts.datetime_schema("trigger_record.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("trigger_record.updated_at")
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
  def new(%__MODULE__{} = trigger_record), do: normalize(trigger_record)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = trigger_record),
    do: normalize(trigger_record) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = trigger_record) do
    inserted_at = trigger_record.inserted_at || Contracts.now()

    {:ok,
     %__MODULE__{
       trigger_record
       | admission_id: trigger_record.admission_id || Contracts.next_id("trigger"),
         inserted_at: inserted_at,
         updated_at: trigger_record.updated_at || inserted_at
     }}
  end
end
