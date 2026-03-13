defmodule Jido.Integration.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Error

  describe "new/3" do
    test "creates error with default retryability" do
      error = Error.new(:rate_limited, "Too many requests")
      assert error.class == :rate_limited
      assert error.retryability == :retryable
      assert error.message == "Too many requests"
    end

    test "creates terminal error for invalid_request" do
      error = Error.new(:invalid_request, "Bad input")
      assert error.retryability == :terminal
    end

    test "creates terminal error for auth_failed" do
      error = Error.new(:auth_failed, "Unauthorized")
      assert error.retryability == :terminal
    end

    test "creates fatal error for internal" do
      error = Error.new(:internal, "Unexpected failure")
      assert error.retryability == :fatal
    end

    test "allows retryability override" do
      error = Error.new(:invalid_request, "Retry anyway", retryability: :retryable)
      assert error.retryability == :retryable
    end

    test "sets error code" do
      error = Error.new(:rate_limited, "Slow down", code: "github.rate_limited")
      assert error.code == "github.rate_limited"
    end

    test "sets upstream_context" do
      ctx = %{"provider_error" => "429"}
      error = Error.new(:rate_limited, "Rate limited", upstream_context: ctx)
      assert error.upstream_context == ctx
    end
  end

  describe "taxonomy" do
    test "all seven classes are valid" do
      classes = Error.valid_classes()
      assert length(classes) == 7

      assert :invalid_request in classes
      assert :auth_failed in classes
      assert :rate_limited in classes
      assert :unavailable in classes
      assert :timeout in classes
      assert :unsupported in classes
      assert :internal in classes
    end

    test "default_retryability matches spec" do
      assert Error.default_retryability(:invalid_request) == :terminal
      assert Error.default_retryability(:auth_failed) == :terminal
      assert Error.default_retryability(:rate_limited) == :retryable
      assert Error.default_retryability(:unavailable) == :retryable
      assert Error.default_retryability(:timeout) == :retryable
      assert Error.default_retryability(:unsupported) == :terminal
      assert Error.default_retryability(:internal) == :fatal
    end

    test "valid_retryability? checks against taxonomy" do
      assert Error.valid_retryability?("rate_limited", "retryable")
      assert Error.valid_retryability?("invalid_request", "terminal")
      assert Error.valid_retryability?("internal", "fatal")

      refute Error.valid_retryability?("rate_limited", "terminal")
      refute Error.valid_retryability?("invalid_request", "retryable")
    end
  end

  describe "predicates" do
    test "retryable?" do
      assert Error.retryable?(Error.new(:rate_limited, "test"))
      refute Error.retryable?(Error.new(:invalid_request, "test"))
      refute Error.retryable?(Error.new(:internal, "test"))
    end

    test "terminal?" do
      assert Error.terminal?(Error.new(:invalid_request, "test"))
      assert Error.terminal?(Error.new(:auth_failed, "test"))
      refute Error.terminal?(Error.new(:rate_limited, "test"))
    end

    test "fatal?" do
      assert Error.fatal?(Error.new(:internal, "test"))
      refute Error.fatal?(Error.new(:rate_limited, "test"))
    end
  end

  describe "message/1" do
    test "returns message without code" do
      error = Error.new(:internal, "Something broke")
      assert Error.message(error) == "Something broke"
    end

    test "includes code prefix when present" do
      error = Error.new(:rate_limited, "Slow down", code: "github.rate_limited")
      assert Error.message(error) == "[github.rate_limited] Slow down"
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON" do
      error = Error.new(:rate_limited, "Too fast", code: "test.rate_limited")
      {:ok, json} = Jason.encode(error)
      decoded = Jason.decode!(json)

      assert decoded["class"] == "rate_limited"
      assert decoded["retryability"] == "retryable"
      assert decoded["message"] == "Too fast"
      assert decoded["code"] == "test.rate_limited"
    end
  end
end
