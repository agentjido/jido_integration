defmodule Jido.Integration.V2.StorePostgres.ClusterInvalidationPublisherTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.ClusterInvalidation
  alias Jido.Integration.V2.StorePostgres.ClusterInvalidationPublisher

  @node_ref "node://ji_1@127.0.0.1/node-a"
  @commit_hlc %{
    "w" => 1_776_947_200_000_000_000,
    "l" => 0,
    "n" => @node_ref
  }

  test "configured Phoenix PubSub publisher broadcasts invalidation messages" do
    pubsub = Module.concat(__MODULE__, PubSub)
    start_supervised!({Phoenix.PubSub, name: pubsub})

    previous_publisher =
      Application.get_env(:jido_integration_v2_store_postgres, :cluster_invalidation_publisher)

    Application.put_env(
      :jido_integration_v2_store_postgres,
      :cluster_invalidation_publisher,
      {:phoenix_pubsub, pubsub}
    )

    on_exit(fn ->
      if is_nil(previous_publisher) do
        Application.delete_env(
          :jido_integration_v2_store_postgres,
          :cluster_invalidation_publisher
        )
      else
        Application.put_env(
          :jido_integration_v2_store_postgres,
          :cluster_invalidation_publisher,
          previous_publisher
        )
      end
    end)

    message =
      ClusterInvalidation.new!(%{
        invalidation_id: "invalidation://memory/private-a",
        tenant_ref: "tenant://alpha",
        topic: ClusterInvalidation.fragment_topic!("tenant://alpha", "fragment://private-a"),
        source_node_ref: @node_ref,
        commit_lsn: "16/B374D848",
        commit_hlc: @commit_hlc,
        published_at: ~U[2026-04-23 12:00:00Z]
      })

    :ok = Phoenix.PubSub.subscribe(pubsub, message.topic)
    assert :ok = ClusterInvalidationPublisher.publish(message)

    assert_receive {:cluster_invalidation, ^message}
  end
end
