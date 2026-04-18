defmodule Jido.Integration.V2.Attempt do
  @moduledoc """
  One concrete execution attempt of a run.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @statuses [:accepted, :running, :completed, :failed]

  @schema Zoi.struct(
            __MODULE__,
            %{
              attempt_id:
                Contracts.non_empty_string_schema("attempt.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              run_id: Contracts.non_empty_string_schema("attempt.run_id"),
              attempt: Zoi.integer() |> Zoi.min(1),
              aggregator_id:
                Contracts.non_empty_string_schema("attempt.aggregator_id")
                |> Zoi.default("control_plane"),
              aggregator_epoch: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
              runtime_class:
                Contracts.enumish_schema([:direct, :session, :stream], "attempt.runtime_class"),
              status:
                Contracts.enumish_schema(@statuses, "attempt.status") |> Zoi.default(:accepted),
              credential_lease_id:
                Contracts.non_empty_string_schema("attempt.credential_lease_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              target_id:
                Contracts.non_empty_string_schema("attempt.target_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              runtime_ref_id:
                Contracts.non_empty_string_schema("attempt.runtime_ref_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              output: Contracts.any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
              output_payload_ref:
                Contracts.payload_ref_schema("attempt.output_payload_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              inserted_at:
                Contracts.datetime_schema("attempt.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("attempt.updated_at")
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
  def new(%__MODULE__{} = attempt), do: normalize(attempt)

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, attempt} -> normalize(attempt)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = attempt) do
    case normalize(attempt) do
      {:ok, attempt} -> attempt
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, attempt} -> attempt
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = attempt) do
    attempt_id = attempt.attempt_id || Contracts.attempt_id(attempt.run_id, attempt.attempt)
    expected_attempt_id = Contracts.attempt_id(attempt.run_id, attempt.attempt)

    if attempt_id == expected_attempt_id do
      timestamp = attempt.inserted_at || Contracts.now()

      {:ok,
       %__MODULE__{
         attempt
         | attempt_id: attempt_id,
           inserted_at: timestamp,
           updated_at: attempt.updated_at || timestamp,
           aggregator_epoch: Contracts.validate_aggregator_epoch!(attempt.aggregator_epoch)
       }}
    else
      {:error,
       ArgumentError.exception(
         "attempt_id must match run_id and attempt: #{inspect({attempt.run_id, attempt.attempt, attempt_id})}"
       )}
    end
  end
end
