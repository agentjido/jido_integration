defmodule Jido.Integration.ManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Manifest

  @valid_manifest %{
    "id" => "protocol.http",
    "display_name" => "HTTP",
    "vendor" => "Jido",
    "domain" => "protocol",
    "version" => "0.1.0",
    "quality_tier" => "bronze",
    "telemetry_namespace" => "jido.integration.protocol.http",
    "auth" => [
      %{
        "id" => "none",
        "type" => "none",
        "display_name" => "No Auth",
        "secret_refs" => [],
        "scopes" => [],
        "token_semantics" => "none",
        "rotation_policy" => %{"required" => false, "interval_days" => nil},
        "tenant_binding" => "tenant_only",
        "health_check" => %{"enabled" => false, "interval_s" => 3600}
      }
    ],
    "operations" => [
      %{
        "id" => "http.request",
        "summary" => "Perform an HTTP request",
        "input_schema" => %{"type" => "object"},
        "output_schema" => %{"type" => "object"},
        "errors" => [
          %{
            "code" => "http.invalid_request",
            "class" => "invalid_request",
            "retryability" => "terminal"
          }
        ],
        "idempotency" => "optional",
        "timeout_ms" => 30_000,
        "rate_limit" => "gateway_default",
        "required_scopes" => []
      }
    ]
  }

  describe "new/1" do
    test "creates manifest from valid map" do
      assert {:ok, manifest} = Manifest.new(@valid_manifest)
      assert manifest.id == "protocol.http"
      assert manifest.display_name == "HTTP"
      assert manifest.vendor == "Jido"
      assert manifest.domain == "protocol"
      assert manifest.version == "0.1.0"
      assert manifest.quality_tier == "bronze"
    end

    test "parses auth descriptors" do
      {:ok, manifest} = Manifest.new(@valid_manifest)
      assert length(manifest.auth) == 1
      [auth] = manifest.auth
      assert auth.id == "none"
      assert auth.type == "none"
    end

    test "parses operation descriptors" do
      {:ok, manifest} = Manifest.new(@valid_manifest)
      assert length(manifest.operations) == 1
      [op] = manifest.operations
      assert op.id == "http.request"
      assert op.summary == "Perform an HTTP request"
      assert op.timeout_ms == 30_000
    end

    test "rejects missing required fields" do
      assert {:error, error} = Manifest.new(%{})
      assert error.class == :invalid_request
      assert error.message =~ "Missing required fields"
    end

    test "rejects manifests missing auth declarations" do
      attrs = Map.delete(@valid_manifest, "auth")
      assert {:error, error} = Manifest.new(attrs)
      assert error.class == :invalid_request
      assert error.message =~ "auth"
    end

    test "rejects manifests missing operations declarations" do
      attrs = Map.delete(@valid_manifest, "operations")
      assert {:error, error} = Manifest.new(attrs)
      assert error.class == :invalid_request
      assert error.message =~ "operations"
    end

    test "rejects invalid domain" do
      attrs = Map.put(@valid_manifest, "domain", "invalid_domain")
      assert {:error, error} = Manifest.new(attrs)
      assert error.message =~ "Invalid domain"
    end

    test "rejects invalid quality_tier" do
      attrs = Map.put(@valid_manifest, "quality_tier", "platinum")
      assert {:error, error} = Manifest.new(attrs)
      assert error.message =~ "Invalid quality_tier"
    end

    test "rejects invalid version" do
      attrs = Map.put(@valid_manifest, "version", "not-semver")
      assert {:error, error} = Manifest.new(attrs)
      assert error.message =~ "Invalid version"
    end

    test "accepts all valid domains" do
      for domain <- Manifest.valid_domains() do
        attrs = Map.put(@valid_manifest, "domain", domain)
        assert {:ok, _} = Manifest.new(attrs), "domain #{domain} should be valid"
      end
    end

    test "accepts all valid quality tiers" do
      for tier <- Manifest.valid_quality_tiers() do
        attrs = Map.put(@valid_manifest, "quality_tier", tier)
        assert {:ok, _} = Manifest.new(attrs), "tier #{tier} should be valid"
      end
    end

    test "parses triggers when present" do
      attrs =
        Map.put(@valid_manifest, "triggers", [
          %{
            "id" => "webhook.received",
            "class" => "webhook",
            "summary" => "Inbound webhook",
            "payload_schema" => %{"type" => "object"},
            "verification" => %{"type" => "hmac", "header" => "x-signature"},
            "callback_topology" => "dynamic_per_install"
          }
        ])

      assert {:ok, manifest} = Manifest.new(attrs)
      assert length(manifest.triggers) == 1
      [trigger] = manifest.triggers
      assert trigger.id == "webhook.received"
      assert trigger.class == "webhook"
    end

    test "parses capabilities" do
      attrs =
        Map.put(@valid_manifest, "capabilities", %{
          "auth.oauth2" => "native",
          "triggers.webhook" => "fallback"
        })

      assert {:ok, manifest} = Manifest.new(attrs)
      assert manifest.capabilities["auth.oauth2"] == "native"
      assert manifest.capabilities["triggers.webhook"] == "fallback"
    end

    test "rejects invalid capabilities" do
      attrs =
        Map.put(@valid_manifest, "capabilities", %{
          "not.real" => "native"
        })

      assert {:error, error} = Manifest.new(attrs)
      assert error.class == :invalid_request
      assert error.message =~ "Invalid capabilities"
    end

    test "stores extensions" do
      attrs =
        Map.put(@valid_manifest, "extensions", %{
          "telemetry_events" => ["jido.integration.operation.started"]
        })

      {:ok, manifest} = Manifest.new(attrs)
      assert manifest.extensions["telemetry_events"] == ["jido.integration.operation.started"]
    end
  end

  describe "new!/1" do
    test "returns manifest on success" do
      manifest = Manifest.new!(@valid_manifest)
      assert manifest.id == "protocol.http"
    end

    test "raises on failure" do
      assert_raise ArgumentError, fn ->
        Manifest.new!(%{})
      end
    end
  end

  describe "from_json/1" do
    test "parses valid JSON" do
      json = Jason.encode!(@valid_manifest)
      assert {:ok, manifest} = Manifest.from_json(json)
      assert manifest.id == "protocol.http"
    end

    test "rejects invalid JSON" do
      assert {:error, error} = Manifest.from_json("not json")
      assert error.class == :invalid_request
    end
  end

  describe "to_map/1" do
    test "round-trips through to_map" do
      {:ok, manifest} = Manifest.new(@valid_manifest)
      map = Manifest.to_map(manifest)

      assert map["id"] == "protocol.http"
      assert map["display_name"] == "HTTP"
      assert length(map["auth"]) == 1
      assert length(map["operations"]) == 1
    end

    test "preserves config_schema" do
      attrs =
        Map.put(@valid_manifest, "config_schema", %{
          "type" => "object",
          "properties" => %{"endpoint" => %{"type" => "string"}}
        })

      {:ok, manifest} = Manifest.new(attrs)
      map = Manifest.to_map(manifest)

      assert map["config_schema"] == attrs["config_schema"]
    end
  end

  describe "valid_domains/0" do
    test "returns expected domains" do
      domains = Manifest.valid_domains()
      assert "messaging" in domains
      assert "saas" in domains
      assert "protocol" in domains
      assert "custom" in domains
    end
  end
end
