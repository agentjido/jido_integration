defmodule Jido.Integration.V2.StorePostgres.Schemas.MemoryPrivateRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:fragment_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "memory_private" do
    field(:tenant_ref, :string)
    field(:source_node_ref, :string)
    field(:user_ref, :string)
    field(:creating_user_ref, :string)
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

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, fields())
    |> validate_required(required_fields())
    |> unique_constraint(:fragment_id, name: :memory_private_pkey)
    |> check_constraint(:creating_user_ref,
      name: :memory_private_creating_user_matches_user_check
    )
    |> check_constraint(:governance_refs, name: :memory_private_governance_refs_empty_check)
    |> check_constraint(:embedding_dimension,
      name: :memory_private_embedding_dimension_matches_vector_check
    )
    |> check_constraint(:embedding_model_ref,
      name: :memory_private_embedding_model_dimension_pair_check
    )
    |> check_constraint(:source_node_ref, name: :memory_private_source_node_ref_non_empty_check)
  end

  def fields do
    [
      :fragment_id,
      :tenant_ref,
      :source_node_ref,
      :user_ref,
      :creating_user_ref,
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
      :inserted_at,
      :updated_at
    ]
  end

  defp required_fields do
    [
      :fragment_id,
      :tenant_ref,
      :source_node_ref,
      :user_ref,
      :creating_user_ref,
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
      :content_hash,
      :content_ref,
      :schema_ref
    ]
  end
end
