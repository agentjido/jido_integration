defmodule Jido.Integration.V2.ReviewProjection do
  @moduledoc """
  Contracts-only northbound review projection carried in review packet metadata.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.SubjectRef

  @schema Zoi.struct(
            __MODULE__,
            %{
              schema_version:
                Contracts.non_empty_string_schema("review_projection.schema_version"),
              projection: Contracts.non_empty_string_schema("review_projection.projection"),
              packet_ref: Contracts.non_empty_string_schema("review_projection.packet_ref"),
              subject: Contracts.struct_schema(SubjectRef, "review_projection.subject"),
              selected_attempt:
                Contracts.struct_schema(SubjectRef, "review_projection.selected_attempt")
                |> Zoi.nullish()
                |> Zoi.optional(),
              evidence_refs:
                Zoi.list(Contracts.struct_schema(EvidenceRef, "review_projection.evidence_refs"))
                |> Zoi.default([]),
              governance_refs:
                Zoi.list(
                  Contracts.struct_schema(GovernanceRef, "review_projection.governance_refs")
                )
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @type dump_t :: %{
          schema_version: String.t(),
          projection: String.t(),
          packet_ref: String.t(),
          subject: map(),
          selected_attempt: map() | nil,
          evidence_refs: [map()],
          governance_refs: [map()]
        }

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = projection), do: normalize(projection)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> prepare_attrs()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = projection),
    do: normalize(projection) |> then(fn {:ok, value} -> value end)

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    case new(attrs) do
      {:ok, projection} -> projection
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec dump(t()) :: dump_t()
  def dump(%__MODULE__{} = projection) do
    %{
      schema_version: projection.schema_version,
      projection: projection.projection,
      packet_ref: projection.packet_ref,
      subject: SubjectRef.dump(projection.subject),
      selected_attempt: maybe_dump_selected_attempt(projection.selected_attempt),
      evidence_refs: Enum.map(projection.evidence_refs, &EvidenceRef.dump/1),
      governance_refs: Enum.map(projection.governance_refs, &GovernanceRef.dump/1)
    }
  end

  defp prepare_attrs(attrs) do
    attrs
    |> Map.update(:subject, nil, fn
      %SubjectRef{} = subject -> subject
      subject when is_map(subject) -> SubjectRef.new!(subject)
      subject -> subject
    end)
    |> Map.update(:selected_attempt, nil, fn
      nil -> nil
      %SubjectRef{} = subject -> subject
      subject when is_map(subject) -> SubjectRef.new!(subject)
      subject -> subject
    end)
    |> Map.update(:evidence_refs, [], fn evidence_refs ->
      Enum.map(evidence_refs, fn
        %EvidenceRef{} = evidence_ref -> evidence_ref
        evidence_ref when is_map(evidence_ref) -> EvidenceRef.new!(evidence_ref)
        evidence_ref -> evidence_ref
      end)
    end)
    |> Map.update(:governance_refs, [], fn governance_refs ->
      Enum.map(governance_refs, fn
        %GovernanceRef{} = governance_ref -> governance_ref
        governance_ref when is_map(governance_ref) -> GovernanceRef.new!(governance_ref)
        governance_ref -> governance_ref
      end)
    end)
  end

  defp normalize(%__MODULE__{} = projection) do
    with :ok <- validate_selected_attempt(projection.selected_attempt) do
      {:ok, projection}
    end
  end

  defp validate_selected_attempt(nil), do: :ok
  defp validate_selected_attempt(%SubjectRef{kind: :attempt}), do: :ok

  defp validate_selected_attempt(%SubjectRef{} = subject_ref) do
    {:error,
     ArgumentError.exception(
       "review_projection.selected_attempt must be an attempt subject, got: #{inspect(subject_ref.kind)}"
     )}
  end

  defp maybe_dump_selected_attempt(nil), do: nil
  defp maybe_dump_selected_attempt(%SubjectRef{} = subject_ref), do: SubjectRef.dump(subject_ref)
end
