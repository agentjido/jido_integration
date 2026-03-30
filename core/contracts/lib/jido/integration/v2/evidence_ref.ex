defmodule Jido.Integration.V2.EvidenceRef do
  @moduledoc """
  Stable reference to a source record backing a packet, decision, or interpretation.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.SubjectRef

  @kinds [:run, :attempt, :event, :artifact, :trigger, :target, :connection, :install]

  @schema Zoi.struct(
            __MODULE__,
            %{
              ref:
                Contracts.non_empty_string_schema("evidence_ref.ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              kind: Contracts.enumish_schema(@kinds, "evidence_ref.kind"),
              id: Contracts.non_empty_string_schema("evidence_ref.id"),
              packet_ref: Contracts.non_empty_string_schema("evidence_ref.packet_ref"),
              subject: Contracts.struct_schema(SubjectRef, "evidence_ref.subject"),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type kind ::
          :run | :attempt | :event | :artifact | :trigger | :target | :connection | :install

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = evidence_ref), do: normalize(evidence_ref)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> prepare_attrs()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = evidence_ref),
    do: normalize(evidence_ref) |> then(fn {:ok, value} -> value end)

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    case new(attrs) do
      {:ok, evidence_ref} -> evidence_ref
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec ref(kind(), String.t()) :: String.t()
  def ref(kind, id), do: Contracts.reference_uri("evidence", kind, id)

  @spec dump(t()) :: %{
          ref: String.t(),
          kind: kind(),
          id: String.t(),
          packet_ref: String.t(),
          subject: map(),
          metadata: map()
        }
  def dump(%__MODULE__{} = evidence_ref) do
    %{
      ref: evidence_ref.ref,
      kind: evidence_ref.kind,
      id: evidence_ref.id,
      packet_ref: evidence_ref.packet_ref,
      subject: SubjectRef.dump(evidence_ref.subject),
      metadata: evidence_ref.metadata
    }
  end

  defp prepare_attrs(attrs) do
    Map.update(attrs, :subject, nil, fn
      %SubjectRef{} = subject -> subject
      subject when is_map(subject) -> SubjectRef.new!(subject)
      subject -> subject
    end)
  end

  defp normalize(%__MODULE__{} = evidence_ref) do
    expected_ref = ref(evidence_ref.kind, evidence_ref.id)

    if is_nil(evidence_ref.ref) or evidence_ref.ref == expected_ref do
      {:ok,
       %__MODULE__{
         evidence_ref
         | ref: expected_ref,
           packet_ref:
             Contracts.validate_non_empty_string!(
               evidence_ref.packet_ref,
               "evidence_ref.packet_ref"
             ),
           metadata: normalize_metadata(evidence_ref.metadata)
       }}
    else
      {:error,
       ArgumentError.exception(
         "evidence_ref.ref must match kind and id: #{inspect({evidence_ref.kind, evidence_ref.id, evidence_ref.ref})}"
       )}
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata

  defp normalize_metadata(metadata) do
    raise ArgumentError, "evidence_ref.metadata must be a map, got: #{inspect(metadata)}"
  end
end
