defmodule Jido.Integration.CapabilityTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Capability

  describe "canonical/0" do
    test "returns non-empty vocabulary" do
      caps = Capability.canonical()
      assert map_size(caps) > 0
    end

    test "includes key domains" do
      caps = Capability.canonical()
      assert Map.has_key?(caps, "auth.oauth2")
      assert Map.has_key?(caps, "triggers.webhook")
      assert Map.has_key?(caps, "messaging.channel.read")
      assert Map.has_key?(caps, "devtools.issues.read")
      assert Map.has_key?(caps, "ai.completions")
    end
  end

  describe "valid_statuses/0" do
    test "returns the four status values" do
      statuses = Capability.valid_statuses()
      assert "native" in statuses
      assert "fallback" in statuses
      assert "unsupported" in statuses
      assert "experimental" in statuses
      assert length(statuses) == 4
    end
  end

  describe "valid_status?/1" do
    test "accepts valid statuses" do
      assert Capability.valid_status?("native")
      assert Capability.valid_status?("fallback")
      assert Capability.valid_status?("unsupported")
      assert Capability.valid_status?("experimental")
    end

    test "rejects invalid statuses" do
      refute Capability.valid_status?("active")
      refute Capability.valid_status?("deprecated")
      refute Capability.valid_status?("")
    end
  end

  describe "canonical?/1" do
    test "recognizes canonical keys" do
      assert Capability.canonical?("auth.oauth2")
      assert Capability.canonical?("triggers.webhook")
      assert Capability.canonical?("devtools.issues.read")
    end

    test "rejects unknown keys" do
      refute Capability.canonical?("unknown.thing")
      refute Capability.canonical?("foo.bar")
    end
  end

  describe "valid_key?/1" do
    test "accepts canonical keys" do
      assert Capability.valid_key?("auth.oauth2")
    end

    test "accepts custom.* keys" do
      assert Capability.valid_key?("custom.my_feature")
      assert Capability.valid_key?("custom.anything.here")
    end

    test "rejects non-canonical, non-custom keys" do
      refute Capability.valid_key?("foo.bar")
    end
  end

  describe "validate/1" do
    test "returns :ok for valid capabilities" do
      caps = %{
        "auth.oauth2" => "native",
        "triggers.webhook" => "fallback"
      }

      assert :ok = Capability.validate(caps)
    end

    test "returns errors for invalid keys" do
      caps = %{"unknown.thing" => "native"}
      assert {:error, errors} = Capability.validate(caps)
      assert length(errors) == 1
    end

    test "returns errors for invalid statuses" do
      caps = %{"auth.oauth2" => "broken"}
      assert {:error, errors} = Capability.validate(caps)
      assert length(errors) == 1
    end

    test "allows custom.* keys" do
      caps = %{"custom.my_feature" => "experimental"}
      assert :ok = Capability.validate(caps)
    end
  end

  describe "domain/1" do
    test "extracts domain prefix" do
      assert Capability.domain("auth.oauth2") == "auth"
      assert Capability.domain("triggers.webhook") == "triggers"
      assert Capability.domain("devtools.issues.read") == "devtools"
    end
  end

  describe "for_domain/2" do
    test "filters capabilities by domain" do
      caps = %{
        "auth.oauth2" => "native",
        "auth.api_key" => "fallback",
        "triggers.webhook" => "native"
      }

      auth_caps = Capability.for_domain(caps, "auth")
      assert map_size(auth_caps) == 2
      assert Map.has_key?(auth_caps, "auth.oauth2")
      assert Map.has_key?(auth_caps, "auth.api_key")
    end
  end

  describe "with_status/2" do
    test "filters capabilities by status" do
      caps = %{
        "auth.oauth2" => "native",
        "auth.api_key" => "fallback",
        "triggers.webhook" => "native"
      }

      native = Capability.with_status(caps, "native")
      assert map_size(native) == 2
    end
  end
end
