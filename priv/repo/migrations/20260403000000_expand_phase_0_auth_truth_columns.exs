defmodule Jido.Integration.V2.StorePostgres.Repo.Migrations.ExpandPhase0AuthTruthColumns do
  use Ecto.Migration

  def up do
    expand_connections()
    expand_install_sessions()
    expand_credentials()
    expand_credential_leases()
    backfill_auth_lineage()
    create_missing_indexes()
  end

  def down, do: :ok

  defp expand_connections do
    execute("""
    ALTER TABLE connections
      ADD COLUMN IF NOT EXISTS profile_id text,
      ADD COLUMN IF NOT EXISTS current_credential_ref_id text,
      ADD COLUMN IF NOT EXISTS current_credential_id text,
      ADD COLUMN IF NOT EXISTS management_mode text,
      ADD COLUMN IF NOT EXISTS secret_source text,
      ADD COLUMN IF NOT EXISTS external_secret_ref jsonb,
      ADD COLUMN IF NOT EXISTS last_refresh_at timestamp(6) without time zone,
      ADD COLUMN IF NOT EXISTS last_refresh_status text,
      ADD COLUMN IF NOT EXISTS degraded_reason text,
      ADD COLUMN IF NOT EXISTS reauth_required_reason text,
      ADD COLUMN IF NOT EXISTS disabled_reason text
    """)
  end

  defp expand_install_sessions do
    execute("""
    ALTER TABLE install_sessions
      ADD COLUMN IF NOT EXISTS profile_id text,
      ADD COLUMN IF NOT EXISTS flow_kind text,
      ADD COLUMN IF NOT EXISTS state_token text,
      ADD COLUMN IF NOT EXISTS pkce_verifier_digest text,
      ADD COLUMN IF NOT EXISTS callback_uri text,
      ADD COLUMN IF NOT EXISTS callback_received_at timestamp(6) without time zone,
      ADD COLUMN IF NOT EXISTS cancelled_at timestamp(6) without time zone,
      ADD COLUMN IF NOT EXISTS failure_reason text,
      ADD COLUMN IF NOT EXISTS reauth_of_connection_id text
    """)
  end

  defp expand_credentials do
    execute("""
    ALTER TABLE credentials
      ADD COLUMN IF NOT EXISTS credential_ref_id text,
      ADD COLUMN IF NOT EXISTS profile_id text,
      ADD COLUMN IF NOT EXISTS version integer DEFAULT 1,
      ADD COLUMN IF NOT EXISTS refresh_token_expires_at timestamp(6) without time zone,
      ADD COLUMN IF NOT EXISTS source text,
      ADD COLUMN IF NOT EXISTS source_ref jsonb,
      ADD COLUMN IF NOT EXISTS supersedes_credential_id text
    """)
  end

  defp expand_credential_leases do
    execute("""
    ALTER TABLE credential_leases
      ADD COLUMN IF NOT EXISTS credential_id text,
      ADD COLUMN IF NOT EXISTS profile_id text
    """)
  end

  defp backfill_auth_lineage do
    execute("""
    UPDATE credentials
    SET credential_ref_id = id
    WHERE credential_ref_id IS NULL
    """)

    execute("""
    UPDATE credentials
    SET version = 1
    WHERE version IS NULL
    """)

    execute("""
    UPDATE connections
    SET current_credential_ref_id = credential_ref_id
    WHERE current_credential_ref_id IS NULL
      AND credential_ref_id IS NOT NULL
    """)

    execute("""
    UPDATE connections
    SET current_credential_id = credential_ref_id
    WHERE current_credential_id IS NULL
      AND credential_ref_id IS NOT NULL
    """)

    execute("""
    UPDATE install_sessions
    SET profile_id = 'default'
    WHERE profile_id IS NULL
    """)

    execute("""
    UPDATE credential_leases
    SET credential_id = credential_ref_id
    WHERE credential_id IS NULL
      AND credential_ref_id IS NOT NULL
    """)

    execute("""
    UPDATE credentials AS credentials
    SET profile_id = connections.profile_id
    FROM connections
    WHERE credentials.connection_id = connections.connection_id
      AND credentials.profile_id IS NULL
    """)

    execute("""
    UPDATE credential_leases AS leases
    SET profile_id = connections.profile_id
    FROM connections
    WHERE leases.connection_id = connections.connection_id
      AND leases.profile_id IS NULL
    """)

    execute("""
    ALTER TABLE credentials
      ALTER COLUMN credential_ref_id SET NOT NULL,
      ALTER COLUMN version SET DEFAULT 1,
      ALTER COLUMN version SET NOT NULL
    """)

    execute("""
    ALTER TABLE install_sessions
      ALTER COLUMN profile_id SET DEFAULT 'default',
      ALTER COLUMN profile_id SET NOT NULL
    """)

    execute("""
    ALTER TABLE credential_leases
      ALTER COLUMN credential_id SET NOT NULL
    """)

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'credential_leases_credential_id_fkey'
      ) THEN
        ALTER TABLE credential_leases
        ADD CONSTRAINT credential_leases_credential_id_fkey
        FOREIGN KEY (credential_id)
        REFERENCES credentials(id)
        ON DELETE CASCADE;
      END IF;
    END
    $$;
    """)
  end

  defp create_missing_indexes do
    execute("""
    CREATE INDEX IF NOT EXISTS credentials_connection_id_index
    ON credentials (connection_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS credentials_credential_ref_id_index
    ON credentials (credential_ref_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS connections_tenant_id_connector_id_index
    ON connections (tenant_id, connector_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS connections_credential_ref_id_index
    ON connections (credential_ref_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS install_sessions_connection_id_index
    ON install_sessions (connection_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS install_sessions_tenant_id_connector_id_index
    ON install_sessions (tenant_id, connector_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS credential_leases_credential_ref_id_index
    ON credential_leases (credential_ref_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS credential_leases_credential_id_index
    ON credential_leases (credential_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS credential_leases_connection_id_index
    ON credential_leases (connection_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS credential_leases_expires_at_index
    ON credential_leases (expires_at)
    """)
  end
end
