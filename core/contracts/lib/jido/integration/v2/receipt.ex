defmodule Jido.Integration.V2.Receipt do
  @moduledoc """
  Durable lower-truth acknowledgement or completion receipt.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @receipt_kinds [:handoff, :execution, :publication]
  @statuses [:accepted, :completed, :rejected, :ambiguous]

  @schema Zoi.struct(
            __MODULE__,
            %{
              receipt_id:
                Contracts.non_empty_string_schema("receipt.receipt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              run_id: Contracts.non_empty_string_schema("receipt.run_id"),
              attempt_id:
                Contracts.non_empty_string_schema("receipt.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              route_id:
                Contracts.non_empty_string_schema("receipt.route_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              receipt_kind: Contracts.enumish_schema(@receipt_kinds, "receipt.receipt_kind"),
              status: Contracts.enumish_schema(@statuses, "receipt.status"),
              observed_at:
                Contracts.datetime_schema("receipt.observed_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{}),
              inserted_at:
                Contracts.datetime_schema("receipt.inserted_at")
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
  def new(%__MODULE__{} = receipt), do: normalize(receipt)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = receipt), do: normalize(receipt) |> then(fn {:ok, value} -> value end)
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = receipt) do
    inserted_at = receipt.inserted_at || Contracts.now()
    attempt_id = receipt.attempt_id || "#{receipt.run_id}:run"

    receipt_id =
      receipt.receipt_id ||
        Contracts.receipt_id(receipt.run_id, attempt_id, Atom.to_string(receipt.receipt_kind))

    {:ok,
     %__MODULE__{
       receipt
       | receipt_id: receipt_id,
         attempt_id: attempt_id,
         observed_at: receipt.observed_at || inserted_at,
         inserted_at: inserted_at
     }}
  end
end
