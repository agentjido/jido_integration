defmodule Jido.Integration.V2.BoundarySession do
  @moduledoc """
  Durable lower-truth record for one boundary session lineage.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @statuses [:allocated, :attaching, :attached, :stale, :closed]

  @schema Zoi.struct(
            __MODULE__,
            %{
              boundary_session_id:
                Contracts.non_empty_string_schema("boundary_session.boundary_session_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              session_id:
                Contracts.non_empty_string_schema("boundary_session.session_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              tenant_id:
                Contracts.non_empty_string_schema("boundary_session.tenant_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              target_id:
                Contracts.non_empty_string_schema("boundary_session.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              route_id:
                Contracts.non_empty_string_schema("boundary_session.route_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              attach_grant_id:
                Contracts.non_empty_string_schema("boundary_session.attach_grant_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              status:
                Contracts.enumish_schema(@statuses, "boundary_session.status")
                |> Zoi.default(:allocated),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{}),
              inserted_at:
                Contracts.datetime_schema("boundary_session.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("boundary_session.updated_at")
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
  def new(%__MODULE__{} = boundary_session), do: normalize(boundary_session)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = boundary_session),
    do: normalize(boundary_session) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = boundary_session) do
    inserted_at = boundary_session.inserted_at || Contracts.now()

    {:ok,
     %__MODULE__{
       boundary_session
       | boundary_session_id:
           boundary_session.boundary_session_id || Contracts.next_id("boundary_session"),
         inserted_at: inserted_at,
         updated_at: boundary_session.updated_at || inserted_at
     }}
  end
end
