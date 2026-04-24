defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.AddM7ANodeOrderingToMemoryFoundation do
  use Ecto.Migration

  @legacy_node_ref "node://migration@m7a/legacy"
  @legacy_hlc %{"w" => 0, "l" => 0, "n" => @legacy_node_ref}

  def up do
    alter table(:access_graph_epochs) do
      add(:source_node_ref, :text)
      add(:commit_lsn, :text)
      add(:commit_hlc, :map)
    end

    execute("""
    UPDATE access_graph_epochs
    SET source_node_ref = '#{@legacy_node_ref}',
        commit_lsn = '0/0',
        commit_hlc = '#{Jason.encode!(@legacy_hlc)}'::jsonb
    WHERE source_node_ref IS NULL
    """)

    alter table(:access_graph_epochs) do
      modify(:source_node_ref, :text, null: false)
      modify(:commit_lsn, :text, null: false)
      modify(:commit_hlc, :map, null: false)
    end

    create(constraint(:access_graph_epochs, :access_graph_epochs_source_node_ref_non_empty_check,
      check: "length(source_node_ref) > 0"
    ))

    create(constraint(:access_graph_epochs, :access_graph_epochs_commit_lsn_non_empty_check,
      check: "length(commit_lsn) > 0"
    ))

    alter table(:access_graph_edges) do
      add(:source_node_ref, :text)
    end

    execute("""
    UPDATE access_graph_edges
    SET source_node_ref = '#{@legacy_node_ref}'
    WHERE source_node_ref IS NULL
    """)

    alter table(:access_graph_edges) do
      modify(:source_node_ref, :text, null: false)
    end

    create(constraint(:access_graph_edges, :access_graph_edges_source_node_ref_non_empty_check,
      check: "length(source_node_ref) > 0"
    ))

    execute("""
    CREATE OR REPLACE FUNCTION reject_access_graph_edge_identity_update()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.edge_id IS DISTINCT FROM NEW.edge_id
         OR OLD.edge_type IS DISTINCT FROM NEW.edge_type
         OR OLD.head_ref IS DISTINCT FROM NEW.head_ref
         OR OLD.tail_ref IS DISTINCT FROM NEW.tail_ref
         OR OLD.tenant_ref IS DISTINCT FROM NEW.tenant_ref
         OR OLD.source_node_ref IS DISTINCT FROM NEW.source_node_ref
         OR OLD.epoch_start IS DISTINCT FROM NEW.epoch_start
         OR OLD.granting_authority_ref IS DISTINCT FROM NEW.granting_authority_ref THEN
        RAISE EXCEPTION 'access_graph_edges immutable identity fields cannot be updated';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    add_memory_source_node(:memory_private)
    add_memory_source_node(:memory_shared)
    add_memory_source_node(:memory_governed)
    replace_memory_provenance_triggers()

    alter table(:memory_invalidations) do
      add(:source_node_ref, :text)
      add(:commit_lsn, :text)
      add(:commit_hlc, :map)
      add(:effective_at_epoch, :bigint)
    end

    execute("""
    UPDATE memory_invalidations
    SET source_node_ref = '#{@legacy_node_ref}',
        commit_lsn = '0/0',
        commit_hlc = '#{Jason.encode!(@legacy_hlc)}'::jsonb,
        effective_at_epoch = 1
    WHERE source_node_ref IS NULL
    """)

    alter table(:memory_invalidations) do
      modify(:source_node_ref, :text, null: false)
      modify(:commit_lsn, :text, null: false)
      modify(:commit_hlc, :map, null: false)
      modify(:effective_at_epoch, :bigint, null: false)
    end

    create(
      constraint(:memory_invalidations, :memory_invalidations_source_node_ref_non_empty_check,
        check: "length(source_node_ref) > 0"
      )
    )

    create(
      constraint(:memory_invalidations, :memory_invalidations_commit_lsn_non_empty_check,
        check: "length(commit_lsn) > 0"
      )
    )
  end

  def down do
    drop(constraint(:memory_invalidations, :memory_invalidations_commit_lsn_non_empty_check))
    drop(constraint(:memory_invalidations, :memory_invalidations_source_node_ref_non_empty_check))

    alter table(:memory_invalidations) do
      remove(:effective_at_epoch)
      remove(:commit_hlc)
      remove(:commit_lsn)
      remove(:source_node_ref)
    end

    remove_memory_source_node(:memory_governed)
    remove_memory_source_node(:memory_shared)
    remove_memory_source_node(:memory_private)

    execute("""
    CREATE OR REPLACE FUNCTION reject_access_graph_edge_identity_update()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.edge_id IS DISTINCT FROM NEW.edge_id
         OR OLD.edge_type IS DISTINCT FROM NEW.edge_type
         OR OLD.head_ref IS DISTINCT FROM NEW.head_ref
         OR OLD.tail_ref IS DISTINCT FROM NEW.tail_ref
         OR OLD.tenant_ref IS DISTINCT FROM NEW.tenant_ref
         OR OLD.epoch_start IS DISTINCT FROM NEW.epoch_start
         OR OLD.granting_authority_ref IS DISTINCT FROM NEW.granting_authority_ref THEN
        RAISE EXCEPTION 'access_graph_edges immutable identity fields cannot be updated';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    drop(constraint(:access_graph_edges, :access_graph_edges_source_node_ref_non_empty_check))

    alter table(:access_graph_edges) do
      remove(:source_node_ref)
    end

    drop(constraint(:access_graph_epochs, :access_graph_epochs_commit_lsn_non_empty_check))
    drop(constraint(:access_graph_epochs, :access_graph_epochs_source_node_ref_non_empty_check))

    alter table(:access_graph_epochs) do
      remove(:commit_hlc)
      remove(:commit_lsn)
      remove(:source_node_ref)
    end
  end

  defp add_memory_source_node(table) do
    alter table(table) do
      add(:source_node_ref, :text)
    end

    execute("""
    UPDATE #{table}
    SET source_node_ref = '#{@legacy_node_ref}'
    WHERE source_node_ref IS NULL
    """)

    alter table(table) do
      modify(:source_node_ref, :text, null: false)
    end

    create(constraint(table, :"#{table}_source_node_ref_non_empty_check",
      check: "length(source_node_ref) > 0"
    ))
  end

  defp replace_memory_provenance_triggers do
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
  end

  defp common_provenance_changed? do
    """
    OLD.t_epoch IS DISTINCT FROM NEW.t_epoch
    OR OLD.source_node_ref IS DISTINCT FROM NEW.source_node_ref
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

  defp remove_memory_source_node(table) do
    drop(constraint(table, :"#{table}_source_node_ref_non_empty_check"))

    alter table(table) do
      remove(:source_node_ref)
    end
  end
end
