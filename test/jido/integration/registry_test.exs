defmodule Jido.Integration.RegistryTest do
  use ExUnit.Case

  alias Jido.Integration.Registry
  alias Jido.Integration.Test.{ConflictingAdapter, TestAdapter}

  setup do
    # Start a fresh registry for each test
    name = :"registry_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Registry.start_link(name: name)
    %{registry: name, pid: pid}
  end

  describe "register/2" do
    test "registers an adapter", %{registry: name} do
      assert :ok = Registry.register(TestAdapter, server: name)
    end

    test "allows re-registration (update)", %{registry: name} do
      assert :ok = Registry.register(TestAdapter, server: name)
      assert :ok = Registry.register(TestAdapter, server: name)
    end

    test "rejects conflicting modules that reuse the same connector id", %{registry: name} do
      assert :ok = Registry.register(TestAdapter, server: name)
      assert {:error, error} = Registry.register(ConflictingAdapter, server: name)
      assert error.class == :invalid_request
    end
  end

  describe "lookup/2" do
    test "finds registered adapter", %{registry: name} do
      :ok = Registry.register(TestAdapter, server: name)
      assert {:ok, TestAdapter} = Registry.lookup("test_adapter", server: name)
    end

    test "returns error for unknown connector", %{registry: name} do
      assert {:error, error} = Registry.lookup("nonexistent", server: name)
      assert error.class == :invalid_request
      assert error.message =~ "not found"
    end
  end

  describe "unregister/2" do
    test "removes a registered adapter", %{registry: name} do
      :ok = Registry.register(TestAdapter, server: name)
      assert :ok = Registry.unregister("test_adapter", server: name)
      assert {:error, _} = Registry.lookup("test_adapter", server: name)
    end

    test "returns error for unknown connector", %{registry: name} do
      assert {:error, error} = Registry.unregister("nonexistent", server: name)
      assert error.class == :invalid_request
    end
  end

  describe "list/1" do
    test "returns empty list initially", %{registry: name} do
      assert Registry.list(server: name) == []
    end

    test "returns all registered adapters", %{registry: name} do
      :ok = Registry.register(TestAdapter, server: name)
      entries = Registry.list(server: name)
      assert length(entries) == 1
      [entry] = entries
      assert entry.id == "test_adapter"
      assert entry.module == TestAdapter
    end
  end

  describe "registered?/2" do
    test "returns true for registered adapter", %{registry: name} do
      :ok = Registry.register(TestAdapter, server: name)
      assert Registry.registered?("test_adapter", server: name)
    end

    test "returns false for unknown adapter", %{registry: name} do
      refute Registry.registered?("nonexistent", server: name)
    end
  end
end
