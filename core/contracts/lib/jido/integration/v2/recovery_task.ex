defmodule Jido.Integration.V2.RecoveryTask do
  @moduledoc """
  Durable lower-truth recovery or reconciliation task.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @statuses [:pending, :running, :resolved, :quarantined]

  @schema Zoi.struct(
            __MODULE__,
            %{
              task_id:
                Contracts.non_empty_string_schema("recovery_task.task_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              subject_ref: Contracts.non_empty_string_schema("recovery_task.subject_ref"),
              run_id:
                Contracts.non_empty_string_schema("recovery_task.run_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              attempt_id:
                Contracts.non_empty_string_schema("recovery_task.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              route_id:
                Contracts.non_empty_string_schema("recovery_task.route_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              receipt_id:
                Contracts.non_empty_string_schema("recovery_task.receipt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              reason: Contracts.non_empty_string_schema("recovery_task.reason"),
              status:
                Contracts.enumish_schema(@statuses, "recovery_task.status")
                |> Zoi.default(:pending),
              due_at:
                Contracts.datetime_schema("recovery_task.due_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{}),
              inserted_at:
                Contracts.datetime_schema("recovery_task.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              updated_at:
                Contracts.datetime_schema("recovery_task.updated_at")
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
  def new(%__MODULE__{} = recovery_task), do: normalize(recovery_task)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = recovery_task),
    do: normalize(recovery_task) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  defp normalize(%__MODULE__{} = recovery_task) do
    inserted_at = recovery_task.inserted_at || Contracts.now()

    task_id =
      recovery_task.task_id ||
        Contracts.recovery_task_id(recovery_task.subject_ref, recovery_task.reason)

    {:ok,
     %__MODULE__{
       recovery_task
       | task_id: task_id,
         due_at: recovery_task.due_at || inserted_at,
         inserted_at: inserted_at,
         updated_at: recovery_task.updated_at || inserted_at
     }}
  end
end
