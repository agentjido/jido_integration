defmodule Jido.Integration.V2.DerivedStateAttachment do
  @moduledoc """
  Canonical attachment contract for higher-order derived state.

  Higher-order repos persist their own enrichments, memories, lineage, and
  scores, but those records must stay anchored to node-local source truth
  through explicit subject, evidence, and governance refs.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.SubjectRef

  @schema Zoi.struct(
            __MODULE__,
            %{
              subject: Contracts.struct_schema(SubjectRef, "derived_state_attachment.subject"),
              evidence_refs:
                Zoi.list(
                  Contracts.struct_schema(EvidenceRef, "derived_state_attachment.evidence_refs")
                )
                |> Zoi.default([]),
              governance_refs:
                Zoi.list(
                  Contracts.struct_schema(
                    GovernanceRef,
                    "derived_state_attachment.governance_refs"
                  )
                )
                |> Zoi.default([]),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @type dump_t :: %{
          subject: map(),
          evidence_refs: [map()],
          governance_refs: [map()],
          metadata: map()
        }

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = attachment), do: normalize(attachment)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> prepare_attrs()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = attachment),
    do: normalize(attachment) |> then(fn {:ok, value} -> value end)

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    case new(attrs) do
      {:ok, attachment} -> attachment
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec dump(t()) :: dump_t()
  def dump(%__MODULE__{} = attachment) do
    %{
      subject: SubjectRef.dump(attachment.subject),
      evidence_refs: Enum.map(attachment.evidence_refs, &EvidenceRef.dump/1),
      governance_refs: Enum.map(attachment.governance_refs, &GovernanceRef.dump/1),
      metadata: attachment.metadata
    }
  end

  defp prepare_attrs(attrs) do
    attrs
    |> Map.update(:subject, nil, fn
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

  defp normalize(%__MODULE__{} = attachment) when is_map(attachment.metadata),
    do: {:ok, attachment}

  defp normalize(%__MODULE__{metadata: metadata}) do
    {:error,
     ArgumentError.exception(
       "derived_state_attachment.metadata must be a map, got: #{inspect(metadata)}"
     )}
  end
end
