defmodule Jido.Integration.V2.PolicyTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Policy

  test "denies when required scopes are missing" do
    decision =
      Policy.evaluate(
        capability(%{}),
        credential(["echo:read"]),
        %{},
        request(%{allowed_operations: ["test.echo"]})
      )

    assert decision.status == :denied
    assert "missing required scopes: echo:write" in decision.reasons
  end

  test "denies when actor and tenant admission do not satisfy the credential boundary" do
    decision =
      Policy.evaluate(
        capability(%{}),
        credential(["echo:write"]),
        %{},
        request(%{
          actor_id: nil,
          tenant_id: "tenant-2",
          credential_ref: credential_ref("tenant-1")
        })
      )

    assert decision.status == :denied
    assert "actor_id is required" in decision.reasons
    assert "tenant tenant-2 cannot use credential for tenant tenant-1" in decision.reasons
  end

  test "denies when the environment or runtime class falls outside the capability policy" do
    decision =
      Policy.evaluate(
        capability(%{
          runtime_class: :session,
          metadata: %{
            policy: %{
              allowed_environments: [:prod],
              allowed_runtime_classes: [:direct]
            }
          }
        }),
        credential(["echo:write"]),
        %{},
        request(%{environment: :dev, runtime_class: :session})
      )

    assert decision.status == :denied
    assert "environment dev is not permitted for test.echo" in decision.reasons
    assert "runtime class session is not permitted for test.echo" in decision.reasons
  end

  test "denies when the requested sandbox posture is weaker than the capability contract" do
    decision =
      Policy.evaluate(
        capability(%{}),
        credential(["echo:write"]),
        %{},
        request(%{
          sandbox: %{
            level: :standard,
            egress: :open,
            approvals: :auto,
            file_scope: "/srv/tenant-1",
            allowed_tools: ["connector.echo"]
          }
        })
      )

    assert decision.status == :denied
    assert "sandbox level standard is weaker than required strict" in decision.reasons
    assert "egress open exceeds required restricted" in decision.reasons
  end

  test "returns a normalized execution policy when admission passes" do
    decision =
      Policy.evaluate(
        capability(%{}),
        credential(["echo:write"]),
        %{},
        request(%{
          sandbox: %{
            level: :strict,
            egress: :restricted,
            approvals: :auto,
            file_scope: "/srv/tenant-1",
            allowed_tools: ["connector.echo", "connector.debug"]
          }
        })
      )

    assert decision.status == :allowed
    assert decision.execution_policy.runtime_class == :direct
    assert decision.execution_policy.sandbox.level == :strict
    assert decision.execution_policy.sandbox.egress == :restricted
    assert decision.execution_policy.sandbox.approvals == :auto
    assert decision.execution_policy.sandbox.file_scope == "/srv/tenant-1"
    assert decision.execution_policy.sandbox.allowed_tools == ["connector.echo"]
  end

  test "returns a shed decision when the gateway metadata carries a pressure signal" do
    decision =
      Policy.evaluate(
        capability(%{}),
        credential(["echo:write"]),
        %{},
        request(%{
          metadata: %{
            pressure: %{
              decision: :shed,
              reason: "dispatch queue saturated",
              scope: "tenant-1:github"
            }
          }
        })
      )

    assert decision.status == :shed
    assert decision.reasons == ["dispatch queue saturated"]
    assert decision.audit_context.pressure.decision == :shed
    assert decision.audit_context.pressure.reason == "dispatch queue saturated"
    assert decision.audit_context.pressure.scope == "tenant-1:github"
  end

  test "deny reasons win over shed pressure signals" do
    decision =
      Policy.evaluate(
        capability(%{}),
        credential(["echo:read"]),
        %{},
        request(%{
          metadata: %{
            pressure: %{
              decision: :shed,
              reason: "dispatch queue saturated"
            }
          }
        })
      )

    assert decision.status == :denied
    assert "missing required scopes: echo:write" in decision.reasons
    refute "dispatch queue saturated" in decision.reasons
    assert decision.audit_context.pressure.reason == "dispatch queue saturated"
  end

  defp capability(overrides) do
    attrs =
      %{
        id: "test.echo",
        connector: "test",
        runtime_class: :direct,
        kind: :operation,
        transport_profile: :action,
        handler: __MODULE__,
        metadata: %{
          required_scopes: ["echo:write"],
          policy: %{
            allowed_actor_ids: ["actor-1"],
            allowed_tenant_ids: ["tenant-1"],
            allowed_environments: [:prod],
            allowed_runtime_classes: [:direct],
            sandbox: %{
              level: :strict,
              egress: :restricted,
              approvals: :auto,
              file_scope: "/srv/tenant-1",
              allowed_tools: ["connector.echo"]
            }
          }
        }
      }
      |> deep_merge(Map.new(overrides))

    Capability.new!(attrs)
  end

  defp credential(scopes) do
    Credential.new!(%{
      id: "cred-1",
      subject: "octocat",
      auth_type: :oauth2,
      scopes: scopes,
      secret: %{access_token: "gho_test"}
    })
  end

  defp credential_ref(tenant_id) do
    CredentialRef.new!(%{
      id: "cred-1",
      subject: "octocat",
      scopes: ["echo:write"],
      metadata: %{tenant_id: tenant_id, connector_id: "test"}
    })
  end

  defp request(overrides) do
    %{
      actor_id: "actor-1",
      tenant_id: "tenant-1",
      environment: :prod,
      runtime_class: :direct,
      allowed_operations: ["test.echo"],
      credential_ref: credential_ref("tenant-1"),
      sandbox: %{
        level: :strict,
        egress: :restricted,
        approvals: :auto,
        file_scope: "/srv/tenant-1",
        allowed_tools: ["connector.echo"]
      }
    }
    |> deep_merge(Map.new(overrides))
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end
end
