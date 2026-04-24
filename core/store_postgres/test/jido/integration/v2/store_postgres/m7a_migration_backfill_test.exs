defmodule Jido.Integration.V2.StorePostgres.M7AMigrationBackfillTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.NodeIdentity
  alias Jido.Integration.V2.StorePostgres.M7A

  @deployment_uuid "5c91c53b-4c41-4e49-9d78-5d8bc9f1e7a1"
  @migration_start_ns 1_776_999_600_000_000_000
  @migration_path Path.expand(
                    "../../../../../priv/repo/migrations/20260423190000_add_m7a_node_ordering_to_memory_foundation.exs",
                    __DIR__
                  )

  test "registers a synthetic migration node identity" do
    assert %NodeIdentity{} =
             identity =
             M7A.migration_node_identity(
               deployment_uuid: @deployment_uuid,
               started_at: ~U[2026-04-24 12:00:00Z]
             )

    assert identity.node_ref == "node://migration@m7a/#{@deployment_uuid}"
    assert identity.node_role == :migration
    assert identity.deployment_ref == "deployment://phase7/m7a/#{@deployment_uuid}"
    assert identity.release_manifest_ref == "release-manifest://phase7/m15"
    assert identity.metadata["migration"] == "M7A.backfill_access_graph_node_and_order"
  end

  test "builds deterministic migration HLCs by row batch order" do
    assert M7A.backfill_hlc(@deployment_uuid, @migration_start_ns, 7) == %{
             "w" => @migration_start_ns,
             "l" => 7,
             "n" => "node://migration@m7a/#{@deployment_uuid}"
           }
  end

  test "describes the M7A backfill table families and proof-token compatibility policy" do
    plan =
      M7A.backfill_access_graph_node_and_order(
        deployment_uuid: @deployment_uuid,
        migration_start_ns: @migration_start_ns
      )

    assert plan.migration_node_ref == "node://migration@m7a/#{@deployment_uuid}"
    assert plan.idempotency_predicate == "source_node_ref IS NULL"
    assert plan.ordered_tables == [:access_graph_epochs, :memory_invalidations]

    assert plan.source_node_only_tables == [
             :access_graph_edges,
             :memory_private,
             :memory_shared,
             :memory_governed
           ]

    assert plan.proof_token_policy == %{
             legacy_hash_version: "m6.v1",
             ordered_hash_version: "m7a.v1",
             synthesize_legacy_order?: false
           }
  end

  test "migration SQL captures real LSNs and deterministic HLCs instead of legacy placeholders" do
    contents = File.read!(@migration_path)

    refute contents =~ "node://migration@m7a/legacy"
    refute contents =~ "commit_lsn = '0/0'"
    assert contents =~ "pg_current_wal_lsn()::text"
    assert contents =~ "row_number() OVER"
    assert contents =~ "jsonb_build_object('w'"
    assert contents =~ "row_batch_index"

    for table <- ~w(access_graph_epochs access_graph_edges memory_invalidations) do
      assert contents =~ "UPDATE #{table}"
      assert contents =~ "WHERE source_node_ref IS NULL"
    end

    for table <- ~w(memory_private memory_shared memory_governed) do
      assert contents =~ "add_memory_source_node(:#{table})"
    end
  end
end
