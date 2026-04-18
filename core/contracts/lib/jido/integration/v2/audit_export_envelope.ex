defmodule Jido.Integration.V2.AuditExportEnvelope do
  @moduledoc """
  Stable replayable observer export envelope over durable lower facts.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @export_kinds [
    "run.accepted",
    "attempt.recorded",
    "event.appended",
    "artifact.recorded"
  ]
  @staleness [:live, :diagnostic_only]

  @schema Zoi.struct(
            __MODULE__,
            %{
              export_id: Contracts.non_empty_string_schema("audit_export.export_id"),
              export_kind:
                Contracts.non_empty_string_schema("audit_export.export_kind")
                |> Zoi.refine({__MODULE__, :validate_export_kind_refine, []}),
              trace_id: Contracts.non_empty_string_schema("audit_export.trace_id"),
              tenant_id: Contracts.non_empty_string_schema("audit_export.tenant_id"),
              installation_id:
                Contracts.non_empty_string_schema("audit_export.installation_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              run_id: Contracts.non_empty_string_schema("audit_export.run_id"),
              attempt_id:
                Contracts.non_empty_string_schema("audit_export.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              event_id:
                Contracts.non_empty_string_schema("audit_export.event_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              staleness: Contracts.enumish_schema(@staleness, "audit_export.staleness"),
              payload: Contracts.any_map_schema()
            },
            coerce: true
          )

  @type export_kind :: String.t()
  @type staleness :: :live | :diagnostic_only
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec export_kinds() :: [export_kind(), ...]
  def export_kinds, do: @export_kinds

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = envelope), do: {:ok, envelope}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = envelope), do: envelope
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)

  @doc false
  @spec validate_export_kind_refine(String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_export_kind_refine(value, _opts) when is_binary(value) do
    if value in @export_kinds do
      :ok
    else
      {:error, "invalid audit_export.export_kind: #{inspect(value)}"}
    end
  end

  def validate_export_kind_refine(value, _opts) do
    {:error, "invalid audit_export.export_kind: #{inspect(value)}"}
  end
end
