defmodule Jido.Integration.V2.ClusterInvalidationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ClusterInvalidation

  @node_ref "node://ji_1@127.0.0.1/node-a"
  @commit_hlc %{
    "w" => 1_776_947_200_000_000_000,
    "l" => 0,
    "n" => @node_ref
  }

  test "encodes typed refs as bounded lowercase topic segments" do
    topic =
      ClusterInvalidation.policy_topic!(
        tenant_ref: "tenant://alpha",
        installation_ref: "installation://app-a",
        kind: :read,
        policy_id: "policy://read/default",
        version: 7
      )

    assert topic ==
             "memory.policy.#{ClusterInvalidation.hash_segment("tenant://alpha")}.#{ClusterInvalidation.hash_segment("installation://app-a")}.read.#{ClusterInvalidation.hash_segment("policy://read/default")}.7"

    for segment <- String.split(topic, ".") do
      assert segment =~ ~r/\A[a-z0-9_-]+\z/
      refute String.contains?(segment, "://")
    end
  end

  test "builds graph, fragment, and durable invalidation topics" do
    assert ClusterInvalidation.graph_topic!("tenant://alpha", 12) ==
             "memory.graph.#{ClusterInvalidation.hash_segment("tenant://alpha")}.epoch.12"

    assert ClusterInvalidation.fragment_topic!("tenant://alpha", "fragment://private/a") ==
             "memory.fragment.#{ClusterInvalidation.hash_segment("tenant://alpha")}.#{ClusterInvalidation.hash_segment("fragment://private/a")}"

    assert ClusterInvalidation.invalidation_topic!(
             "tenant://alpha",
             "invalidation://private/a"
           ) ==
             "memory.invalidation.#{ClusterInvalidation.hash_segment("tenant://alpha")}.#{ClusterInvalidation.hash_segment("invalidation://private/a")}"
  end

  test "normalizes invalidation messages with ordering evidence and rejects raw refs in topics" do
    topic = ClusterInvalidation.fragment_topic!("tenant://alpha", "fragment://memory/private-a")

    assert {:ok, message} =
             ClusterInvalidation.new(%{
               invalidation_id: "invalidation://memory/private-a",
               tenant_ref: "tenant://alpha",
               topic: topic,
               source_node_ref: @node_ref,
               commit_lsn: "16/B374D848",
               commit_hlc: @commit_hlc,
               published_at: ~U[2026-04-23 12:00:00Z],
               metadata: %{reason: :user_deletion}
             })

    assert message.topic == topic
    assert message.commit_lsn == "16/B374D848"
    assert message.commit_hlc == @commit_hlc

    assert ClusterInvalidation.dump(message).metadata == %{"reason" => "user_deletion"}

    assert {:error, %ArgumentError{} = error} =
             ClusterInvalidation.new(%{
               invalidation_id: "bad",
               tenant_ref: "tenant://alpha",
               topic: "memory.fragment.tenant://alpha.fragment-a",
               source_node_ref: @node_ref,
               commit_lsn: "16/B374D848",
               commit_hlc: @commit_hlc,
               published_at: ~U[2026-04-23 12:00:00Z]
             })

    assert error.message =~ "cluster_invalidation.topic"
  end
end
