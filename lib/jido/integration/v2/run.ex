defmodule Jido.Integration.V2.Run do
  @moduledoc """
  Durable record of requested work.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Schema

  @statuses [:accepted, :running, :completed, :failed, :denied, :shed]

  @schema Zoi.struct(
            __MODULE__,
            %{
              run_id:
                Contracts.non_empty_string_schema("run.run_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              capability_id: Contracts.non_empty_string_schema("run.capability_id"),
              runtime_class:
                Contracts.enumish_schema([:direct, :session, :stream], "run.runtime"),
              status: Contracts.enumish_schema(@statuses, "run.status") |> Zoi.default(:accepted),
              input: Contracts.any_map_schema(),
              credential_ref: Contracts.struct_schema(CredentialRef, "run.credential_ref"),
              target_id:
                Contracts.non_empty_string_schema("run.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              result: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
              inserted_at:
                Contracts.datetime_schema("run.inserted_at") |> Zoi.nullish() |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("run.updated_at") |> Zoi.nullish() |> Zoi.optional(),
              artifact_refs:
                Zoi.list(Contracts.struct_schema(ArtifactRef, "run.artifact_refs"))
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = run), do: {:ok, normalize(run)}

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, run} -> {:ok, normalize(run)}
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = run), do: normalize(run)

  def new!(attrs) do
    case new(attrs) do
      {:ok, run} -> run
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = run) do
    timestamp = run.inserted_at || Contracts.now()

    %__MODULE__{
      run
      | run_id: run.run_id || Contracts.next_id("run"),
        inserted_at: timestamp,
        updated_at: run.updated_at || timestamp
    }
  end
end
