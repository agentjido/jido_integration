defmodule Jido.Integration.V2.GovernanceRef do
  @moduledoc """
  Stable reference to governance lineage such as approval, denial, override, rollback, or policy decisions.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.SubjectRef

  @kinds [:approval, :denial, :override, :rollback, :policy_decision]

  @schema Zoi.struct(
            __MODULE__,
            %{
              ref:
                Contracts.non_empty_string_schema("governance_ref.ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              kind: Contracts.enumish_schema(@kinds, "governance_ref.kind"),
              id: Contracts.non_empty_string_schema("governance_ref.id"),
              subject: Contracts.struct_schema(SubjectRef, "governance_ref.subject"),
              evidence:
                Zoi.list(Contracts.struct_schema(EvidenceRef, "governance_ref.evidence"))
                |> Zoi.default([]),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type kind :: :approval | :denial | :override | :rollback | :policy_decision

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = governance_ref), do: normalize(governance_ref)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> prepare_attrs()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = governance_ref),
    do: normalize(governance_ref) |> then(fn {:ok, value} -> value end)

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    case new(attrs) do
      {:ok, governance_ref} -> governance_ref
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec ref(kind(), String.t()) :: String.t()
  def ref(kind, id), do: Contracts.reference_uri("governance", kind, id)

  @spec dump(t()) :: %{
          ref: String.t(),
          kind: kind(),
          id: String.t(),
          subject: map(),
          evidence: [map()],
          metadata: map()
        }
  def dump(%__MODULE__{} = governance_ref) do
    %{
      ref: governance_ref.ref,
      kind: governance_ref.kind,
      id: governance_ref.id,
      subject: SubjectRef.dump(governance_ref.subject),
      evidence: Enum.map(governance_ref.evidence, &EvidenceRef.dump/1),
      metadata: governance_ref.metadata
    }
  end

  defp prepare_attrs(attrs) do
    attrs
    |> Map.update(:subject, nil, fn
      %SubjectRef{} = subject -> subject
      subject when is_map(subject) -> SubjectRef.new!(subject)
      subject -> subject
    end)
    |> Map.update(:evidence, [], fn evidence ->
      Enum.map(evidence, fn
        %EvidenceRef{} = evidence_ref -> evidence_ref
        evidence_ref when is_map(evidence_ref) -> EvidenceRef.new!(evidence_ref)
        evidence_ref -> evidence_ref
      end)
    end)
  end

  defp normalize(%__MODULE__{} = governance_ref) do
    expected_ref = ref(governance_ref.kind, governance_ref.id)

    if is_nil(governance_ref.ref) or governance_ref.ref == expected_ref do
      {:ok,
       %__MODULE__{
         governance_ref
         | ref: expected_ref,
           metadata: normalize_metadata(governance_ref.metadata)
       }}
    else
      {:error,
       ArgumentError.exception(
         "governance_ref.ref must match kind and id: #{inspect({governance_ref.kind, governance_ref.id, governance_ref.ref})}"
       )}
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata

  defp normalize_metadata(metadata) do
    raise ArgumentError, "governance_ref.metadata must be a map, got: #{inspect(metadata)}"
  end
end
