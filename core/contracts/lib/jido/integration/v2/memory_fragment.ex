defmodule Jido.Integration.V2.MemoryFragment do
  @moduledoc """
  Immutable governed-memory fragment envelope.

  Contract: `Platform.MemoryFragment.V1`.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef

  @contract_name "Platform.MemoryFragment.V1"
  @contract_version "1.0.0"
  @tiers [:private, :shared, :governed]

  @fields [
    :contract_name,
    :contract_version,
    :fragment_id,
    :tenant_ref,
    :source_node_ref,
    :tier,
    :t_epoch,
    :creating_user_ref,
    :user_ref,
    :scope_ref,
    :installation_ref,
    :source_agents,
    :source_resources,
    :source_scopes,
    :access_agents,
    :access_resources,
    :access_scopes,
    :access_projection_hash,
    :applied_policies,
    :evidence_refs,
    :governance_refs,
    :parent_fragment_id,
    :content_hash,
    :content_ref,
    :schema_ref,
    :embedding,
    :embedding_model_ref,
    :embedding_dimension,
    :share_up_policy_ref,
    :transform_pipeline,
    :non_identity_transform_count,
    :promotion_decision_ref,
    :promotion_policy_ref,
    :rebuild_spec,
    :derived_state_attachment_ref,
    :redaction_summary,
    :confidence,
    :retention_class,
    :expires_at,
    :metadata
  ]

  @enforce_keys [
    :contract_name,
    :contract_version,
    :fragment_id,
    :tenant_ref,
    :tier,
    :t_epoch,
    :source_agents,
    :source_resources,
    :source_scopes,
    :access_agents,
    :access_resources,
    :access_scopes,
    :access_projection_hash,
    :applied_policies,
    :content_hash,
    :content_ref,
    :schema_ref
  ]

  defstruct @fields

  @type tier :: :private | :shared | :governed
  @type t :: %__MODULE__{
          contract_name: String.t(),
          contract_version: String.t(),
          fragment_id: String.t(),
          tenant_ref: String.t(),
          source_node_ref: String.t(),
          tier: tier(),
          t_epoch: pos_integer(),
          creating_user_ref: String.t() | nil,
          user_ref: String.t() | nil,
          scope_ref: String.t() | nil,
          installation_ref: String.t() | nil,
          source_agents: [String.t()],
          source_resources: [String.t()],
          source_scopes: [String.t()],
          access_agents: [String.t()],
          access_resources: [String.t()],
          access_scopes: [String.t()],
          access_projection_hash: String.t(),
          applied_policies: [String.t()],
          evidence_refs: [EvidenceRef.t()],
          governance_refs: [GovernanceRef.t()],
          parent_fragment_id: String.t() | nil,
          content_hash: String.t(),
          content_ref: map(),
          schema_ref: String.t(),
          embedding: [float()] | nil,
          embedding_model_ref: String.t() | nil,
          embedding_dimension: pos_integer() | nil,
          share_up_policy_ref: String.t() | nil,
          transform_pipeline: [map()],
          non_identity_transform_count: non_neg_integer(),
          promotion_decision_ref: String.t() | nil,
          promotion_policy_ref: String.t() | nil,
          rebuild_spec: map() | nil,
          derived_state_attachment_ref: String.t() | nil,
          redaction_summary: map(),
          confidence: number() | nil,
          retention_class: String.t() | nil,
          expires_at: DateTime.t() | nil,
          metadata: map()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec tiers() :: [tier()]
  def tiers, do: @tiers

  @spec provenance_fields() :: [atom()]
  def provenance_fields do
    [
      :t_epoch,
      :source_node_ref,
      :creating_user_ref,
      :source_agents,
      :source_resources,
      :source_scopes,
      :access_agents,
      :access_resources,
      :access_scopes,
      :access_projection_hash,
      :applied_policies,
      :evidence_refs,
      :governance_refs,
      :parent_fragment_id,
      :content_hash,
      :schema_ref,
      :embedding_model_ref,
      :embedding_dimension,
      :share_up_policy_ref,
      :promotion_decision_ref,
      :promotion_policy_ref,
      :rebuild_spec,
      :derived_state_attachment_ref
    ]
  end

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = fragment), do: normalize(fragment)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = fragment) do
    case normalize(fragment) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = fragment) do
    %{
      contract_name: fragment.contract_name,
      contract_version: fragment.contract_version,
      fragment_id: fragment.fragment_id,
      tenant_ref: fragment.tenant_ref,
      source_node_ref: fragment.source_node_ref,
      tier: fragment.tier,
      t_epoch: fragment.t_epoch,
      creating_user_ref: fragment.creating_user_ref,
      user_ref: fragment.user_ref,
      scope_ref: fragment.scope_ref,
      installation_ref: fragment.installation_ref,
      source_agents: fragment.source_agents,
      source_resources: fragment.source_resources,
      source_scopes: fragment.source_scopes,
      access_agents: fragment.access_agents,
      access_resources: fragment.access_resources,
      access_scopes: fragment.access_scopes,
      access_projection_hash: fragment.access_projection_hash,
      applied_policies: fragment.applied_policies,
      evidence_refs: Enum.map(fragment.evidence_refs, &EvidenceRef.dump/1),
      governance_refs: Enum.map(fragment.governance_refs, &GovernanceRef.dump/1),
      parent_fragment_id: fragment.parent_fragment_id,
      content_hash: fragment.content_hash,
      content_ref: fragment.content_ref,
      schema_ref: fragment.schema_ref,
      embedding: fragment.embedding,
      embedding_model_ref: fragment.embedding_model_ref,
      embedding_dimension: fragment.embedding_dimension,
      share_up_policy_ref: fragment.share_up_policy_ref,
      transform_pipeline: fragment.transform_pipeline,
      non_identity_transform_count: fragment.non_identity_transform_count,
      promotion_decision_ref: fragment.promotion_decision_ref,
      promotion_policy_ref: fragment.promotion_policy_ref,
      rebuild_spec: fragment.rebuild_spec,
      derived_state_attachment_ref: fragment.derived_state_attachment_ref,
      redaction_summary: fragment.redaction_summary,
      confidence: fragment.confidence,
      retention_class: fragment.retention_class,
      expires_at: fragment.expires_at,
      metadata: fragment.metadata
    }
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, :contract_name),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, :contract_version),
      fragment_id:
        attrs
        |> Contracts.get(:fragment_id, Contracts.next_id("memory_fragment"))
        |> required_string(:fragment_id),
      tenant_ref:
        attrs |> Contracts.fetch_required!(:tenant_ref, field(:tenant_ref)) |> ref!(:tenant_ref),
      source_node_ref:
        attrs
        |> Contracts.fetch_required!(:source_node_ref, field(:source_node_ref))
        |> ref!(:source_node_ref),
      tier:
        attrs
        |> Contracts.fetch_required!(:tier, field(:tier))
        |> Contracts.validate_enum_atomish!(@tiers, field(:tier)),
      t_epoch:
        attrs
        |> Contracts.fetch_required!(:t_epoch, field(:t_epoch))
        |> Contracts.validate_positive_integer!(field(:t_epoch)),
      creating_user_ref: optional_ref(attrs, :creating_user_ref),
      user_ref: optional_ref(attrs, :user_ref),
      scope_ref: optional_ref(attrs, :scope_ref),
      installation_ref: optional_ref(attrs, :installation_ref),
      source_agents: required_string_list(attrs, :source_agents),
      source_resources: required_string_list(attrs, :source_resources),
      source_scopes: required_string_list(attrs, :source_scopes),
      access_agents: required_string_list(attrs, :access_agents),
      access_resources: required_string_list(attrs, :access_resources),
      access_scopes: required_string_list(attrs, :access_scopes),
      access_projection_hash:
        attrs
        |> Contracts.fetch_required!(:access_projection_hash, field(:access_projection_hash))
        |> required_string(:access_projection_hash),
      applied_policies: required_string_list(attrs, :applied_policies),
      evidence_refs:
        attrs
        |> Contracts.get(:evidence_refs, [])
        |> evidence_refs!(),
      governance_refs:
        attrs
        |> Contracts.get(:governance_refs, [])
        |> governance_refs!(),
      parent_fragment_id: optional_ref(attrs, :parent_fragment_id),
      content_hash:
        attrs
        |> Contracts.fetch_required!(:content_hash, field(:content_hash))
        |> required_string(:content_hash),
      content_ref:
        attrs
        |> Contracts.fetch_required!(:content_ref, field(:content_ref))
        |> Contracts.validate_map!(field(:content_ref)),
      schema_ref:
        attrs
        |> Contracts.fetch_required!(:schema_ref, field(:schema_ref))
        |> required_string(:schema_ref),
      embedding: optional_embedding(attrs),
      embedding_model_ref: optional_ref(attrs, :embedding_model_ref),
      embedding_dimension: optional_positive_integer(attrs, :embedding_dimension),
      share_up_policy_ref: optional_ref(attrs, :share_up_policy_ref),
      transform_pipeline:
        attrs
        |> Contracts.get(:transform_pipeline, [])
        |> map_list!(:transform_pipeline),
      non_identity_transform_count:
        attrs
        |> Contracts.get(:non_identity_transform_count, 0)
        |> non_negative_integer!(:non_identity_transform_count),
      promotion_decision_ref: optional_ref(attrs, :promotion_decision_ref),
      promotion_policy_ref: optional_ref(attrs, :promotion_policy_ref),
      rebuild_spec:
        attrs
        |> Contracts.get(:rebuild_spec)
        |> optional_map!(:rebuild_spec),
      derived_state_attachment_ref: optional_ref(attrs, :derived_state_attachment_ref),
      redaction_summary:
        attrs
        |> Contracts.get(:redaction_summary, %{})
        |> Contracts.validate_map!(field(:redaction_summary)),
      confidence: optional_number(attrs, :confidence),
      retention_class: optional_ref(attrs, :retention_class),
      expires_at: optional_datetime(attrs, :expires_at),
      metadata:
        attrs
        |> Contracts.get(:metadata, %{})
        |> Contracts.validate_map!(field(:metadata))
    }
    |> validate_embedding_contract!()
    |> validate_tier_contract!()
  end

  defp normalize(%__MODULE__{} = fragment) do
    {:ok, fragment |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_embedding_contract!(%__MODULE__{embedding: nil} = fragment), do: fragment

  defp validate_embedding_contract!(%__MODULE__{
         embedding: embedding,
         embedding_model_ref: nil
       })
       when is_list(embedding) do
    raise ArgumentError, "#{field(:embedding_model_ref)} is required when embedding is set"
  end

  defp validate_embedding_contract!(%__MODULE__{
         embedding: embedding,
         embedding_dimension: nil
       })
       when is_list(embedding) do
    raise ArgumentError, "#{field(:embedding_dimension)} is required when embedding is set"
  end

  defp validate_embedding_contract!(%__MODULE__{} = fragment) do
    if length(fragment.embedding) == fragment.embedding_dimension do
      fragment
    else
      raise ArgumentError, "#{field(:embedding_dimension)} must match embedding length"
    end
  end

  defp validate_tier_contract!(%__MODULE__{tier: :private} = fragment) do
    require_present!(fragment.user_ref, :user_ref, "for private tier")
    require_present!(fragment.creating_user_ref, :creating_user_ref, "for private tier")

    if fragment.creating_user_ref == fragment.user_ref do
      :ok
    else
      raise ArgumentError, "#{field(:creating_user_ref)} must equal user_ref for private tier"
    end

    if fragment.governance_refs == [] do
      fragment
    else
      raise ArgumentError, "#{field(:governance_refs)} must be empty for private tier"
    end
  end

  defp validate_tier_contract!(%__MODULE__{tier: :shared} = fragment) do
    require_present!(fragment.scope_ref, :scope_ref, "for shared tier")
    require_present!(fragment.parent_fragment_id, :parent_fragment_id, "for shared tier")
    require_present!(fragment.share_up_policy_ref, :share_up_policy_ref, "for shared tier")

    if fragment.transform_pipeline == [] do
      raise ArgumentError, "#{field(:transform_pipeline)} must be non-empty for shared tier"
    end

    if fragment.non_identity_transform_count > 0 do
      fragment
    else
      raise ArgumentError,
            "#{field(:non_identity_transform_count)} must be greater than 0 for shared tier"
    end
  end

  defp validate_tier_contract!(%__MODULE__{tier: :governed} = fragment) do
    require_present!(fragment.installation_ref, :installation_ref, "for governed tier")

    require_present!(
      fragment.promotion_decision_ref,
      :promotion_decision_ref,
      "for governed tier"
    )

    require_present!(fragment.rebuild_spec, :rebuild_spec, "for governed tier")

    if fragment.evidence_refs == [] do
      raise ArgumentError, "#{field(:evidence_refs)} must be non-empty for governed tier"
    end

    if fragment.governance_refs == [] do
      raise ArgumentError, "#{field(:governance_refs)} must be non-empty for governed tier"
    end

    fragment
  end

  defp evidence_refs!(values) when is_list(values) do
    Enum.map(values, fn
      %EvidenceRef{} = value ->
        value

      value when is_map(value) or is_list(value) ->
        value
        |> normalize_ref_attrs()
        |> EvidenceRef.new!()

      value ->
        raise ArgumentError,
              "#{field(:evidence_refs)} must contain EvidenceRef values, got: #{inspect(value)}"
    end)
  end

  defp evidence_refs!(values) do
    raise ArgumentError, "#{field(:evidence_refs)} must be a list, got: #{inspect(values)}"
  end

  defp governance_refs!(values) when is_list(values) do
    Enum.map(values, fn
      %GovernanceRef{} = value ->
        value

      value when is_map(value) or is_list(value) ->
        value
        |> normalize_ref_attrs()
        |> GovernanceRef.new!()

      value ->
        raise ArgumentError,
              "#{field(:governance_refs)} must contain GovernanceRef values, got: #{inspect(value)}"
    end)
  end

  defp governance_refs!(values) do
    raise ArgumentError, "#{field(:governance_refs)} must be a list, got: #{inspect(values)}"
  end

  defp normalize_ref_attrs(values) when is_list(values),
    do: values |> Map.new() |> normalize_ref_attrs()

  defp normalize_ref_attrs(values) when is_map(values) do
    values
    |> Map.new(fn {key, value} -> {known_ref_key(key), normalize_ref_value(value)} end)
  end

  defp normalize_ref_value(values) when is_list(values),
    do: Enum.map(values, &normalize_ref_value/1)

  defp normalize_ref_value(values) when is_map(values), do: normalize_ref_attrs(values)
  defp normalize_ref_value(value), do: value

  defp known_ref_key(key) when is_atom(key), do: key

  defp known_ref_key(key) when is_binary(key) do
    case key do
      "ref" -> :ref
      "kind" -> :kind
      "id" -> :id
      "subject" -> :subject
      "evidence" -> :evidence
      "packet_ref" -> :packet_ref
      "metadata" -> :metadata
      other -> other
    end
  end

  defp required_string_list(attrs, key) do
    attrs
    |> Contracts.fetch_required!(key, field(key))
    |> Contracts.normalize_string_list!(field(key))
  end

  defp optional_ref(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> required_string(value, key)
    end
  end

  defp optional_positive_integer(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> Contracts.validate_positive_integer!(value, field(key))
    end
  end

  defp non_negative_integer!(value, _key) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer!(value, key) do
    raise ArgumentError, "#{field(key)} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp optional_number(attrs, key) do
    case Contracts.get(attrs, key) do
      nil ->
        nil

      value when is_number(value) ->
        value

      value ->
        raise ArgumentError, "#{field(key)} must be a number, got: #{inspect(value)}"
    end
  end

  defp optional_datetime(attrs, key) do
    case Contracts.get(attrs, key) do
      nil ->
        nil

      %DateTime{} = value ->
        value

      value ->
        raise ArgumentError, "#{field(key)} must be a DateTime, got: #{inspect(value)}"
    end
  end

  defp optional_map!(nil, _key), do: nil

  defp optional_map!(value, key) do
    Contracts.validate_map!(value, field(key))
  end

  defp map_list!(values, key) when is_list(values) do
    Enum.map(values, fn
      value when is_map(value) -> value
      value -> raise ArgumentError, "#{field(key)} must contain maps, got: #{inspect(value)}"
    end)
  end

  defp map_list!(values, key) do
    raise ArgumentError, "#{field(key)} must be a list, got: #{inspect(values)}"
  end

  defp optional_embedding(attrs) do
    case Contracts.get(attrs, :embedding) do
      nil -> nil
      values -> embedding!(values)
    end
  end

  defp embedding!(values) when is_list(values) do
    Enum.map(values, fn
      value when is_number(value) ->
        value * 1.0

      value ->
        raise ArgumentError, "#{field(:embedding)} must contain numbers, got: #{inspect(value)}"
    end)
  end

  defp embedding!(values) do
    raise ArgumentError, "#{field(:embedding)} must be a list, got: #{inspect(values)}"
  end

  defp require_present!(nil, key, suffix) do
    raise ArgumentError, "#{field(key)} is required #{suffix}"
  end

  defp require_present!(value, key, suffix) when is_map(value) and map_size(value) == 0 do
    raise ArgumentError, "#{field(key)} is required #{suffix}"
  end

  defp require_present!(_value, _key, _suffix), do: :ok

  defp ref!(value, key), do: required_string(value, key)

  defp required_string(value, key), do: Contracts.validate_non_empty_string!(value, field(key))

  defp validate_literal!(value, expected, key) do
    if value == expected do
      value
    else
      raise ArgumentError, "#{field(key)} must be #{inspect(expected)}, got: #{inspect(value)}"
    end
  end

  defp field(key), do: "memory_fragment.#{key}"
end
