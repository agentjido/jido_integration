defmodule Jido.Integration.V2.ReviewBundle do
  @moduledoc """
  Operator-facing lower-truth review bundle usable by northbound surfaces.
  """

  alias Jido.Integration.V2.{
    Attempt,
    Contracts,
    Receipt,
    RecoveryTask,
    ReviewProjection,
    Run,
    Schema
  }

  @schema Zoi.struct(
            __MODULE__,
            %{
              bundle_id:
                Contracts.non_empty_string_schema("review_bundle.bundle_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              review_projection:
                Contracts.struct_schema(ReviewProjection, "review_bundle.review_projection"),
              run: Contracts.struct_schema(Run, "review_bundle.run"),
              attempt:
                Contracts.struct_schema(Attempt, "review_bundle.attempt")
                |> Zoi.nullish()
                |> Zoi.optional(),
              receipts:
                Zoi.list(Contracts.struct_schema(Receipt, "review_bundle.receipts"))
                |> Zoi.default([]),
              recovery_tasks:
                Zoi.list(Contracts.struct_schema(RecoveryTask, "review_bundle.recovery_tasks"))
                |> Zoi.default([]),
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
  def new(%__MODULE__{} = review_bundle), do: normalize(review_bundle)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = review_bundle),
    do: normalize(review_bundle) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = review_bundle) do
    bundle_id =
      review_bundle.bundle_id ||
        Contracts.next_id("review_bundle")

    {:ok, %__MODULE__{review_bundle | bundle_id: bundle_id}}
  end
end
