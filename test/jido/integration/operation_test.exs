defmodule Jido.Integration.OperationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Operation.{Descriptor, Envelope, Result}

  describe "Descriptor.new/1" do
    test "creates descriptor from valid map" do
      attrs = %{
        "id" => "test.op",
        "summary" => "A test operation",
        "input_schema" => %{"type" => "object"},
        "output_schema" => %{"type" => "object"},
        "errors" => [],
        "idempotency" => "optional",
        "timeout_ms" => 5_000
      }

      assert {:ok, desc} = Descriptor.new(attrs)
      assert desc.id == "test.op"
      assert desc.summary == "A test operation"
      assert desc.timeout_ms == 5_000
    end

    test "rejects missing id" do
      assert {:error, error} = Descriptor.new(%{"summary" => "No id"})
      assert error.class == :invalid_request
    end

    test "rejects missing summary" do
      assert {:error, error} = Descriptor.new(%{"id" => "test.op"})
      assert error.class == :invalid_request
    end

    test "rejects invalid idempotency" do
      attrs = %{"id" => "test.op", "summary" => "Test", "idempotency" => "always"}
      assert {:error, error} = Descriptor.new(attrs)
      assert error.message =~ "Invalid idempotency"
    end

    test "sets defaults" do
      {:ok, desc} = Descriptor.new(%{"id" => "test.op", "summary" => "Test"})
      assert desc.idempotency == "optional"
      assert desc.timeout_ms == 30_000
      assert desc.rate_limit == "gateway_default"
      assert desc.required_scopes == []
    end
  end

  describe "Descriptor.to_map/1" do
    test "serializes descriptor" do
      {:ok, desc} = Descriptor.new(%{"id" => "test.op", "summary" => "Test"})
      map = Descriptor.to_map(desc)
      assert map["id"] == "test.op"
      assert map["summary"] == "Test"
      assert map["timeout_ms"] == 30_000
    end
  end

  describe "Envelope.new/3" do
    test "creates envelope with required fields" do
      envelope = Envelope.new("test.op", %{"key" => "value"})
      assert envelope.operation_id == "test.op"
      assert envelope.args == %{"key" => "value"}
    end

    test "generates trace context" do
      envelope = Envelope.new("test.op")
      assert is_binary(envelope.context["trace_id"])
      assert is_binary(envelope.context["span_id"])
    end

    test "accepts custom context" do
      envelope =
        Envelope.new("test.op", %{},
          context: %{"trace_id" => "custom-trace", "span_id" => "custom-span"}
        )

      assert envelope.context["trace_id"] == "custom-trace"
      assert envelope.context["span_id"] == "custom-span"
    end

    test "accepts idempotency_key" do
      envelope = Envelope.new("test.op", %{}, idempotency_key: "idem-123")
      assert envelope.idempotency_key == "idem-123"
    end

    test "accepts timeout_ms override" do
      envelope = Envelope.new("test.op", %{}, timeout_ms: 5_000)
      assert envelope.timeout_ms == 5_000
    end

    test "accepts auth_ref" do
      envelope = Envelope.new("test.op", %{}, auth_ref: "tok_abc123")
      assert envelope.auth_ref == "tok_abc123"
    end
  end

  describe "Result.new/1" do
    test "wraps result data" do
      result = Result.new(%{"issues" => [1, 2, 3]})
      assert result.status == :ok
      assert result.result == %{"issues" => [1, 2, 3]}
      assert is_binary(result.meta["timestamp"])
    end
  end
end
