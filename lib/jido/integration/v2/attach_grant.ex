defmodule Jido.Integration.V2.AttachGrant do
  @moduledoc """
  Durable lower-truth grant allowing a route or consumer to attach to a boundary session.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @statuses [:issued, :accepted, :revoked, :expired]

  @schema Zoi.struct(
            __MODULE__,
            %{
              attach_grant_id:
                Contracts.non_empty_string_schema("attach_grant.attach_grant_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              boundary_session_id:
                Contracts.non_empty_string_schema("attach_grant.boundary_session_id"),
              route_id:
                Contracts.non_empty_string_schema("attach_grant.route_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              subject_id:
                Contracts.non_empty_string_schema("attach_grant.subject_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              status:
                Contracts.enumish_schema(@statuses, "attach_grant.status")
                |> Zoi.default(:issued),
              lease_expires_at:
                Contracts.datetime_schema("attach_grant.lease_expires_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{}),
              inserted_at:
                Contracts.datetime_schema("attach_grant.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("attach_grant.updated_at")
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
  def new(%__MODULE__{} = attach_grant), do: normalize(attach_grant)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = attach_grant),
    do: normalize(attach_grant) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = attach_grant) do
    inserted_at = attach_grant.inserted_at || Contracts.now()

    {:ok,
     %__MODULE__{
       attach_grant
       | attach_grant_id: attach_grant.attach_grant_id || Contracts.next_id("attach_grant"),
         inserted_at: inserted_at,
         updated_at: attach_grant.updated_at || inserted_at
     }}
  end
end
