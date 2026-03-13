defmodule Jido.Integration.TriggerTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Trigger.Descriptor

  @valid_webhook %{
    "id" => "webhook.received",
    "class" => "webhook",
    "summary" => "Inbound webhook event",
    "payload_schema" => %{"type" => "object"},
    "delivery_semantics" => "at_least_once",
    "verification" => %{"type" => "hmac", "header" => "x-signature"},
    "callback_topology" => "dynamic_per_install"
  }

  describe "Descriptor.new/1" do
    test "creates webhook trigger" do
      assert {:ok, desc} = Descriptor.new(@valid_webhook)
      assert desc.id == "webhook.received"
      assert desc.class == "webhook"
      assert desc.delivery_semantics == "at_least_once"
      assert desc.callback_topology == "dynamic_per_install"
    end

    test "sets defaults" do
      {:ok, desc} = Descriptor.new(@valid_webhook)
      assert desc.ordering_scope == "tenant_connector"
      assert desc.checkpoint_mode == "cursor"
      assert desc.max_delivery_lag_s == 300
      assert desc.replay_window_days == 7
      assert desc.backfill_supported == false
    end

    test "rejects missing required fields" do
      assert {:error, error} = Descriptor.new(%{})
      assert error.class == :invalid_request
    end

    test "rejects invalid class" do
      attrs = Map.put(@valid_webhook, "class", "invalid")
      assert {:error, error} = Descriptor.new(attrs)
      assert error.message =~ "Invalid trigger class"
    end

    test "accepts all valid classes" do
      for class <- Descriptor.valid_classes() do
        attrs = Map.put(@valid_webhook, "class", class)
        assert {:ok, _} = Descriptor.new(attrs)
      end
    end

    test "accepts all valid topologies" do
      for topo <- Descriptor.valid_topologies() do
        attrs = Map.put(@valid_webhook, "callback_topology", topo)
        assert {:ok, desc} = Descriptor.new(attrs)
        assert desc.callback_topology == topo
      end
    end
  end

  describe "Descriptor.to_map/1" do
    test "serializes trigger descriptor" do
      {:ok, desc} = Descriptor.new(@valid_webhook)
      map = Descriptor.to_map(desc)

      assert map["id"] == "webhook.received"
      assert map["class"] == "webhook"
      assert map["verification"] == %{"type" => "hmac", "header" => "x-signature"}
    end
  end
end
