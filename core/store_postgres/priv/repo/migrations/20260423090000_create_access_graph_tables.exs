defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.CreateAccessGraphTables do
  use Ecto.Migration

  def up do
    create table(:access_graph_epochs, primary_key: false) do
      add(:tenant_ref, :text, null: false)
      add(:epoch, :bigint, null: false)
      add(:committed_at, :utc_datetime_usec, null: false)
      add(:cause, :text, null: false)
      add(:trace_id, :text)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:access_graph_epochs, [:tenant_ref, :epoch],
        name: :access_graph_epochs_tenant_epoch_index
      )
    )

    create(
      constraint(:access_graph_epochs, :access_graph_epochs_epoch_positive_check,
        check: "epoch > 0"
      )
    )

    create table(:access_graph_edges, primary_key: false) do
      add(:edge_id, :text, primary_key: true)
      add(:edge_type, :text, null: false)
      add(:head_ref, :text, null: false)
      add(:tail_ref, :text, null: false)
      add(:tenant_ref, :text, null: false)
      add(:epoch_start, :bigint, null: false)
      add(:epoch_end, :bigint)
      add(:granting_authority_ref, :map, null: false)
      add(:revoking_authority_ref, :map)
      add(:evidence_refs, {:array, :map}, null: false, default: [])
      add(:policy_refs, {:array, :text}, null: false, default: [])
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:access_graph_edges, [:tenant_ref, :edge_type, :head_ref, :epoch_start]))
    create(index(:access_graph_edges, [:tenant_ref, :edge_type, :tail_ref, :epoch_start]))

    create(
      constraint(:access_graph_edges, :access_graph_edges_edge_type_check,
        check: "edge_type IN ('ua', 'ar', 'us', 'sr', 'up', 'aur')"
      )
    )

    create(
      constraint(:access_graph_edges, :access_graph_edges_epoch_start_positive_check,
        check: "epoch_start > 0"
      )
    )

    create(
      constraint(:access_graph_edges, :access_graph_edges_epoch_end_after_start_check,
        check: "epoch_end IS NULL OR epoch_end > epoch_start"
      )
    )

    create(
      constraint(:access_graph_edges, :access_graph_edges_revocation_authority_check,
        check: "epoch_end IS NULL OR revoking_authority_ref IS NOT NULL"
      )
    )

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

    execute("""
    CREATE TRIGGER access_graph_edges_reject_identity_update
    BEFORE UPDATE ON access_graph_edges
    FOR EACH ROW
    EXECUTE FUNCTION reject_access_graph_edge_identity_update();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS access_graph_edges_reject_identity_update ON access_graph_edges")
    execute("DROP FUNCTION IF EXISTS reject_access_graph_edge_identity_update()")
    drop(table(:access_graph_edges))
    drop(table(:access_graph_epochs))
  end
end
