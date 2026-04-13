defmodule Jido.Integration.V2.ExecutionRoute do
  @moduledoc """
  Durable lower-truth record for a committed execution route.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @route_kinds [:process, :http, :jsonrpc, :session]
  @statuses [
    :committed_local,
    :accepted_downstream,
    :started_execution,
    :completed_execution,
    :quarantined,
    :dead_letter
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              route_id:
                Contracts.non_empty_string_schema("execution_route.route_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              run_id: Contracts.non_empty_string_schema("execution_route.run_id"),
              attempt_id:
                Contracts.non_empty_string_schema("execution_route.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              boundary_session_id:
                Contracts.non_empty_string_schema("execution_route.boundary_session_id"),
              target_id:
                Contracts.non_empty_string_schema("execution_route.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              route_kind: Contracts.enumish_schema(@route_kinds, "execution_route.route_kind"),
              status:
                Contracts.enumish_schema(@statuses, "execution_route.status")
                |> Zoi.default(:committed_local),
              handoff_ref:
                Contracts.non_empty_string_schema("execution_route.handoff_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{}),
              inserted_at:
                Contracts.datetime_schema("execution_route.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("execution_route.updated_at")
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
  def new(%__MODULE__{} = execution_route), do: normalize(execution_route)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = execution_route),
    do: normalize(execution_route) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = execution_route) do
    inserted_at = execution_route.inserted_at || Contracts.now()

    {:ok,
     %__MODULE__{
       execution_route
       | route_id: execution_route.route_id || Contracts.next_id("route"),
         inserted_at: inserted_at,
         updated_at: execution_route.updated_at || inserted_at
     }}
  end
end
