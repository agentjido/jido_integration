defmodule Jido.Integration.V2.StorePostgres.Schemas.MemorySharedRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:fragment_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "memory_shared" do
    field(:tenant_ref, :string)
    field(:source_node_ref, :string)
    field(:scope_ref, :string)
    field(:t_epoch, :integer)
    field(:source_agents, {:array, :string}, default: [])
    field(:source_resources, {:array, :string}, default: [])
    field(:source_scopes, {:array, :string}, default: [])
    field(:access_agents, {:array, :string}, default: [])
    field(:access_resources, {:array, :string}, default: [])
    field(:access_scopes, {:array, :string}, default: [])
    field(:access_projection_hash, :string)
    field(:applied_policies, {:array, :string}, default: [])
    field(:evidence_refs, {:array, :map}, default: [])
    field(:governance_refs, {:array, :map}, default: [])
    field(:parent_fragment_id, :string)
    field(:content_hash, :string)
    field(:content_ref, :map)
    field(:schema_ref, :string)
    field(:embedding, {:array, :float})
    field(:embedding_model_ref, :string)
    field(:embedding_dimension, :integer)
    field(:redaction_summary, :map, default: %{})
    field(:confidence, :float)
    field(:retention_class, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})
    field(:share_up_policy_ref, :string)
    field(:transform_pipeline, {:array, :map}, default: [])
    field(:non_identity_transform_count, :integer, default: 0)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, fields())
    |> validate_required(required_fields())
    |> unique_constraint(:fragment_id, name: :memory_shared_pkey)
    |> check_constraint(:parent_fragment_id,
      name: :memory_shared_parent_fragment_required_check
    )
    |> check_constraint(:non_identity_transform_count,
      name: :memory_shared_non_identity_transform_count_check
    )
    |> check_constraint(:embedding_dimension,
      name: :memory_shared_embedding_dimension_matches_vector_check
    )
    |> check_constraint(:embedding_model_ref,
      name: :memory_shared_embedding_model_dimension_pair_check
    )
    |> check_constraint(:source_node_ref, name: :memory_shared_source_node_ref_non_empty_check)
  end

  def fields do
    [
      :fragment_id,
      :tenant_ref,
      :source_node_ref,
      :scope_ref,
      :t_epoch,
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
      :redaction_summary,
      :confidence,
      :retention_class,
      :expires_at,
      :metadata,
      :share_up_policy_ref,
      :transform_pipeline,
      :non_identity_transform_count,
      :inserted_at,
      :updated_at
    ]
  end

  defp required_fields do
    [
      :fragment_id,
      :tenant_ref,
      :source_node_ref,
      :scope_ref,
      :t_epoch,
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
      :share_up_policy_ref,
      :transform_pipeline,
      :non_identity_transform_count
    ]
  end
end
