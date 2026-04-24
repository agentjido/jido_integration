defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateMemoryTierTables do
  use Ecto.Migration

  def up do
    create_memory_private()
    create_memory_shared()
    create_memory_governed()
    create_memory_invalidations()
    create_optional_scope_gin_index()
    create_provenance_triggers()
  end

  def down do
    drop_provenance_triggers()
    execute("DROP INDEX IF EXISTS memory_shared_scope_ref_gin_index")
    drop(table(:memory_invalidations))
    drop(table(:memory_governed))
    drop(table(:memory_shared))
    drop(table(:memory_private))
  end

  defp create_memory_private do
    create table(:memory_private, primary_key: false) do
      add(:fragment_id, :text, primary_key: true)
      add(:tenant_ref, :text, null: false)
      add(:user_ref, :text, null: false)
      add(:creating_user_ref, :text, null: false)
      add_common_fragment_columns()

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:memory_private, [:tenant_ref, :user_ref]))

    create(
      constraint(:memory_private, :memory_private_creating_user_matches_user_check,
        check: "creating_user_ref = user_ref"
      )
    )

    create(
      constraint(:memory_private, :memory_private_governance_refs_empty_check,
        check: "cardinality(governance_refs) = 0"
      )
    )

    create_embedding_dimension_check(:memory_private)
  end

  defp create_memory_shared do
    create table(:memory_shared, primary_key: false) do
      add(:fragment_id, :text, primary_key: true)
      add(:tenant_ref, :text, null: false)
      add(:scope_ref, :text, null: false)
      add_common_fragment_columns()
      add(:share_up_policy_ref, :text, null: false)
      add(:transform_pipeline, {:array, :map}, null: false, default: [])
      add(:non_identity_transform_count, :integer, null: false, default: 0)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:memory_shared, [:tenant_ref, :scope_ref]))

    create(
      constraint(:memory_shared, :memory_shared_parent_fragment_required_check,
        check: "parent_fragment_id IS NOT NULL"
      )
    )

    create(
      constraint(:memory_shared, :memory_shared_non_identity_transform_count_check,
        check: "non_identity_transform_count > 0"
      )
    )

    create_embedding_dimension_check(:memory_shared)
  end

  defp create_memory_governed do
    create table(:memory_governed, primary_key: false) do
      add(:fragment_id, :text, primary_key: true)
      add(:tenant_ref, :text, null: false)
      add(:installation_ref, :text, null: false)
      add_common_fragment_columns()
      add(:promotion_decision_ref, :text, null: false)
      add(:promotion_policy_ref, :text)
      add(:rebuild_spec, :map, null: false)
      add(:derived_state_attachment_ref, :text)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:memory_governed, [:tenant_ref, :installation_ref]))

    create(
      constraint(:memory_governed, :memory_governed_evidence_refs_non_empty_check,
        check: "cardinality(evidence_refs) > 0"
      )
    )

    create(
      constraint(:memory_governed, :memory_governed_governance_refs_non_empty_check,
        check: "cardinality(governance_refs) > 0"
      )
    )

    create_embedding_dimension_check(:memory_governed)
  end

  defp create_memory_invalidations do
    create table(:memory_invalidations, primary_key: false) do
      add(:invalidation_id, :text, primary_key: true)
      add(:tenant_ref, :text, null: false)
      add(:fragment_id, :text, null: false)
      add(:tier, :text, null: false)
      add(:effective_at, :utc_datetime_usec, null: false)
      add(:invalidate_policy_ref, :text, null: false)
      add(:authority_ref, :map, null: false)
      add(:evidence_refs, {:array, :map}, null: false, default: [])
      add(:reason, :text, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:memory_invalidations, [:tenant_ref, :fragment_id, :effective_at]))
  end

  defp add_common_fragment_columns do
    add(:t_epoch, :bigint, null: false)
    add(:source_agents, {:array, :text}, null: false, default: [])
    add(:source_resources, {:array, :text}, null: false, default: [])
    add(:source_scopes, {:array, :text}, null: false, default: [])
    add(:access_agents, {:array, :text}, null: false, default: [])
    add(:access_resources, {:array, :text}, null: false, default: [])
    add(:access_scopes, {:array, :text}, null: false, default: [])
    add(:access_projection_hash, :text, null: false)
    add(:applied_policies, {:array, :text}, null: false, default: [])
    add(:evidence_refs, {:array, :map}, null: false, default: [])
    add(:governance_refs, {:array, :map}, null: false, default: [])
    add(:parent_fragment_id, :text)
    add(:content_hash, :text, null: false)
    add(:content_ref, :map, null: false)
    add(:schema_ref, :text, null: false)
    add(:embedding, {:array, :float})
    add(:embedding_model_ref, :text)
    add(:embedding_dimension, :integer)
    add(:redaction_summary, :map, null: false, default: %{})
    add(:confidence, :float)
    add(:retention_class, :text)
    add(:expires_at, :utc_datetime_usec)
    add(:metadata, :map, null: false, default: %{})
  end

  defp create_embedding_dimension_check(table) do
    create(
      constraint(table, :"#{table}_embedding_dimension_matches_vector_check",
        check: "embedding IS NULL OR embedding_dimension = cardinality(embedding)"
      )
    )

    create(
      constraint(table, :"#{table}_embedding_model_dimension_pair_check",
        check:
          "(embedding IS NULL AND embedding_model_ref IS NULL AND embedding_dimension IS NULL) OR (embedding IS NOT NULL AND embedding_model_ref IS NOT NULL AND embedding_dimension IS NOT NULL)"
      )
    )
  end

  defp create_optional_scope_gin_index do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_trgm') THEN
        CREATE EXTENSION IF NOT EXISTS pg_trgm;
        CREATE INDEX IF NOT EXISTS memory_shared_scope_ref_gin_index
          ON memory_shared USING GIN (scope_ref gin_trgm_ops);
      END IF;
    END;
    $$;
    """)
  end

  defp create_provenance_triggers do
    create_private_provenance_trigger()
    create_shared_provenance_trigger()
    create_governed_provenance_trigger()
  end

  defp drop_provenance_triggers do
    execute("DROP TRIGGER IF EXISTS memory_private_reject_provenance_update ON memory_private")
    execute("DROP TRIGGER IF EXISTS memory_shared_reject_provenance_update ON memory_shared")
    execute("DROP TRIGGER IF EXISTS memory_governed_reject_provenance_update ON memory_governed")
    execute("DROP FUNCTION IF EXISTS reject_memory_private_provenance_update()")
    execute("DROP FUNCTION IF EXISTS reject_memory_shared_provenance_update()")
    execute("DROP FUNCTION IF EXISTS reject_memory_governed_provenance_update()")
  end

  defp create_private_provenance_trigger do
    execute("""
    CREATE OR REPLACE FUNCTION reject_memory_private_provenance_update()
    RETURNS trigger AS $$
    BEGIN
      IF #{common_provenance_changed?()}
         OR OLD.user_ref IS DISTINCT FROM NEW.user_ref
         OR OLD.creating_user_ref IS DISTINCT FROM NEW.creating_user_ref THEN
        RAISE EXCEPTION 'memory_private immutable provenance fields cannot be updated';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER memory_private_reject_provenance_update
    BEFORE UPDATE ON memory_private
    FOR EACH ROW
    EXECUTE FUNCTION reject_memory_private_provenance_update();
    """)
  end

  defp create_shared_provenance_trigger do
    execute("""
    CREATE OR REPLACE FUNCTION reject_memory_shared_provenance_update()
    RETURNS trigger AS $$
    BEGIN
      IF #{common_provenance_changed?()}
         OR OLD.scope_ref IS DISTINCT FROM NEW.scope_ref
         OR OLD.share_up_policy_ref IS DISTINCT FROM NEW.share_up_policy_ref
         OR OLD.transform_pipeline IS DISTINCT FROM NEW.transform_pipeline
         OR OLD.non_identity_transform_count IS DISTINCT FROM NEW.non_identity_transform_count THEN
        RAISE EXCEPTION 'memory_shared immutable provenance fields cannot be updated';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER memory_shared_reject_provenance_update
    BEFORE UPDATE ON memory_shared
    FOR EACH ROW
    EXECUTE FUNCTION reject_memory_shared_provenance_update();
    """)
  end

  defp create_governed_provenance_trigger do
    execute("""
    CREATE OR REPLACE FUNCTION reject_memory_governed_provenance_update()
    RETURNS trigger AS $$
    BEGIN
      IF #{common_provenance_changed?()}
         OR OLD.installation_ref IS DISTINCT FROM NEW.installation_ref
         OR OLD.promotion_decision_ref IS DISTINCT FROM NEW.promotion_decision_ref
         OR OLD.promotion_policy_ref IS DISTINCT FROM NEW.promotion_policy_ref
         OR OLD.rebuild_spec IS DISTINCT FROM NEW.rebuild_spec
         OR OLD.derived_state_attachment_ref IS DISTINCT FROM NEW.derived_state_attachment_ref THEN
        RAISE EXCEPTION 'memory_governed immutable provenance fields cannot be updated';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER memory_governed_reject_provenance_update
    BEFORE UPDATE ON memory_governed
    FOR EACH ROW
    EXECUTE FUNCTION reject_memory_governed_provenance_update();
    """)
  end

  defp common_provenance_changed? do
    """
    OLD.t_epoch IS DISTINCT FROM NEW.t_epoch
    OR OLD.source_agents IS DISTINCT FROM NEW.source_agents
    OR OLD.source_resources IS DISTINCT FROM NEW.source_resources
    OR OLD.source_scopes IS DISTINCT FROM NEW.source_scopes
    OR OLD.access_agents IS DISTINCT FROM NEW.access_agents
    OR OLD.access_resources IS DISTINCT FROM NEW.access_resources
    OR OLD.access_scopes IS DISTINCT FROM NEW.access_scopes
    OR OLD.access_projection_hash IS DISTINCT FROM NEW.access_projection_hash
    OR OLD.applied_policies IS DISTINCT FROM NEW.applied_policies
    OR OLD.evidence_refs IS DISTINCT FROM NEW.evidence_refs
    OR OLD.governance_refs IS DISTINCT FROM NEW.governance_refs
    OR OLD.parent_fragment_id IS DISTINCT FROM NEW.parent_fragment_id
    OR OLD.content_hash IS DISTINCT FROM NEW.content_hash
    OR OLD.content_ref IS DISTINCT FROM NEW.content_ref
    OR OLD.schema_ref IS DISTINCT FROM NEW.schema_ref
    OR OLD.embedding IS DISTINCT FROM NEW.embedding
    OR OLD.embedding_model_ref IS DISTINCT FROM NEW.embedding_model_ref
    OR OLD.embedding_dimension IS DISTINCT FROM NEW.embedding_dimension
    """
  end
end
