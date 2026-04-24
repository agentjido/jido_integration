defmodule Jido.Integration.V2.StorePostgres.M7A do
  @moduledoc """
  M7A migration contract helpers for node/order backfill planning.

  The Ecto migration remains self-contained, but this module exposes the
  owner-visible contract that the migration follows so tests and release
  evidence can verify the same table families and legacy proof-token policy.
  """

  alias Jido.Integration.V2.NodeIdentity

  @migration_name "M7A.backfill_access_graph_node_and_order"
  @default_deployment_uuid "5c91c53b-4c41-4e49-9d78-5d8bc9f1e7a1"
  @ordered_tables [:access_graph_epochs, :memory_invalidations]
  @source_node_only_tables [
    :access_graph_edges,
    :memory_private,
    :memory_shared,
    :memory_governed
  ]
  @release_manifest_ref "release-manifest://phase7/m15"

  @type backfill_plan :: %{
          migration: String.t(),
          migration_node_ref: String.t(),
          migration_node_identity: map(),
          migration_start_ns: non_neg_integer(),
          idempotency_predicate: String.t(),
          ordered_tables: [atom()],
          source_node_only_tables: [atom()],
          proof_token_policy: map()
        }

  @spec migration_name() :: String.t()
  def migration_name, do: @migration_name

  @spec migration_node_ref(String.t()) :: String.t()
  def migration_node_ref(deployment_uuid \\ @default_deployment_uuid) do
    "node://migration@m7a/#{deployment_uuid}"
  end

  @spec migration_node_identity(keyword()) :: NodeIdentity.t()
  def migration_node_identity(opts \\ []) do
    deployment_uuid = Keyword.get(opts, :deployment_uuid, @default_deployment_uuid)

    NodeIdentity.new!(%{
      node_ref: migration_node_ref(deployment_uuid),
      node_instance_id: "node-instance://migration@m7a/#{deployment_uuid}",
      boot_generation: 1,
      node_role: :migration,
      deployment_ref: "deployment://phase7/m7a/#{deployment_uuid}",
      release_manifest_ref: @release_manifest_ref,
      started_at: Keyword.get(opts, :started_at, DateTime.utc_now()),
      cluster_ref: "cluster://phase7/migration",
      metadata: %{
        "deployment_uuid" => deployment_uuid,
        "migration" => @migration_name,
        "phase" => "phase7"
      }
    })
  end

  @spec backfill_hlc(String.t(), non_neg_integer(), non_neg_integer()) :: map()
  def backfill_hlc(deployment_uuid, migration_start_ns, row_batch_index)
      when is_binary(deployment_uuid) and is_integer(migration_start_ns) and
             migration_start_ns >= 0 and is_integer(row_batch_index) and row_batch_index >= 0 do
    %{
      "w" => migration_start_ns,
      "l" => row_batch_index,
      "n" => migration_node_ref(deployment_uuid)
    }
  end

  @spec backfill_access_graph_node_and_order(keyword()) :: backfill_plan()
  def backfill_access_graph_node_and_order(opts \\ []) do
    deployment_uuid = Keyword.get(opts, :deployment_uuid, @default_deployment_uuid)
    migration_start_ns = Keyword.get(opts, :migration_start_ns, System.os_time(:nanosecond))

    %{
      migration: @migration_name,
      migration_node_ref: migration_node_ref(deployment_uuid),
      migration_node_identity:
        opts
        |> Keyword.put(:deployment_uuid, deployment_uuid)
        |> migration_node_identity()
        |> NodeIdentity.dump(),
      migration_start_ns: migration_start_ns,
      idempotency_predicate: "source_node_ref IS NULL",
      ordered_tables: @ordered_tables,
      source_node_only_tables: @source_node_only_tables,
      proof_token_policy: %{
        legacy_hash_version: "m6.v1",
        ordered_hash_version: "m7a.v1",
        synthesize_legacy_order?: false
      }
    }
  end
end
