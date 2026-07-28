defmodule Jido.Integration.V2.ControlPlane.ReviewedToolEffectTest do
  use ExUnit.Case, async: true

  alias Citadel.ScopedGrant
  alias Jido.Integration.V2.ControlPlane.ReviewedToolEffect

  @workspace_root "/tmp/jido-reviewed-tool-effect"
  @workspace_ref "workspace://nshkr/reviewed"
  @relative_path "reviewed.txt"
  @reviewed_content "reviewed content"
  @content_digest "sha256:" <>
                    (:crypto.hash(:sha256, @reviewed_content)
                     |> Base.encode16(case: :lower))
  @grant_ref "grant://citadel/tool-effect/reviewed"
  @decision_ref "decision://citadel/tool-effect/reviewed"
  @review_ref "review://mezzanine/reviewed"
  @effect_ref "effect://nshkr/codex/reviewed"

  defmodule Authority do
    def fetch_grant(_grant_ref), do: {:ok, Process.get({__MODULE__, :grant})}

    def verify_grant(_grant_ref, _binding, _now),
      do: Process.get({__MODULE__, :verification}, :ok)
  end

  defmodule RaisingAuthority do
    def fetch_grant(_grant_ref), do: raise("authority must not be consulted")
  end

  test "ordinary managed Codex input keeps provider permission manual" do
    assert {:ok, %{permission_mode: nil, reviewed_approval: nil}} =
             ReviewedToolEffect.runtime_admission(
               %{prompt: "ordinary managed turn"},
               runtime_binding(),
               authority: RaisingAuthority
             )
  end

  test "exact active reviewed-effect authority enables only sandboxed auto permission" do
    Process.put({Authority, :grant}, grant())

    assert {:ok,
            %{
              permission_mode: :auto,
              reviewed_approval: %{
                effect_ref: @effect_ref,
                workspace_root: @workspace_root,
                relative_path: @relative_path,
                reviewed_content: @reviewed_content,
                content_digest: @content_digest
              }
            }} =
             ReviewedToolEffect.runtime_admission(
               reviewed_input(),
               runtime_binding(),
               authority: Authority,
               now: ~U[2026-07-28 12:00:00Z]
             )
  end

  test "any reviewed-effect runtime binding drift fails closed" do
    Process.put({Authority, :grant}, grant())

    mismatches = [
      credential_lease_ref: "lease://other",
      credential_generation: 2,
      managed_session_ref: "managed-session://other",
      session_generation: 2,
      workspace_root: "/tmp/other",
      workspace_ref: "workspace://other",
      operation_ref: "operation://other",
      target_ref: "target://other",
      effect_ref: "effect://other",
      attempt_ref: "attempt://other"
    ]

    Enum.each(mismatches, fn {key, value} ->
      assert {:error, :reviewed_tool_effect_authority_denied} =
               ReviewedToolEffect.runtime_admission(
                 reviewed_input(),
                 Map.put(runtime_binding(), key, value),
                 authority: Authority,
                 now: ~U[2026-07-28 12:00:00Z]
               )
    end)
  end

  test "authority verification failure blocks provider automation" do
    Process.put({Authority, :grant}, grant())
    Process.put({Authority, :verification}, {:error, :expired})

    assert {:error, :reviewed_tool_effect_authority_denied} =
             ReviewedToolEffect.runtime_admission(
               reviewed_input(),
               runtime_binding(),
               authority: Authority,
               now: ~U[2026-07-28 12:00:00Z]
             )
  end

  test "reviewed content digest drift blocks provider automation" do
    Process.put({Authority, :grant}, grant())

    input =
      put_in(
        reviewed_input(),
        [:workspace, :reviewed_content],
        "different reviewed content"
      )

    assert {:error, :reviewed_tool_effect_authority_denied} =
             ReviewedToolEffect.runtime_admission(
               input,
               runtime_binding(),
               authority: Authority,
               now: ~U[2026-07-28 12:00:00Z]
             )
  end

  defp reviewed_input do
    %{
      prompt: "perform the reviewed effect",
      workspace: %{
        workspace_ref: @workspace_ref,
        relative_path: @relative_path,
        content_digest: @content_digest,
        reviewed_content: @reviewed_content
      },
      authority_metadata: %{
        grant_ref: @grant_ref,
        decision_ref: @decision_ref,
        review_ref: @review_ref,
        effect_ref: @effect_ref
      }
    }
  end

  defp runtime_binding do
    %{
      authority_ref: @grant_ref,
      authority_decision_ref: @decision_ref,
      operation_policy_ref: "policy-artifact://citadel/synapse/codex-reviewed-write/v1",
      tenant_ref: "tenant://nshkr/test",
      provider_account_ref: "provider-account://nshkr/codex",
      credential_lease_ref: "lease://jido/codex/reviewed",
      credential_generation: 1,
      managed_session_ref: "managed-session://nshkr/codex/reviewed",
      session_generation: 1,
      workspace_ref: @workspace_ref,
      workspace_root: @workspace_root,
      operation_ref: "operation://codex/reviewed",
      target_ref: "target://nshkr/codex/reviewed",
      effect_ref: @effect_ref,
      attempt_ref: "jido-run://nshkr/codex/reviewed:1",
      capability_id: "codex.session.turn"
    }
  end

  defp grant do
    scope = %{
      "authority_decision_ref" => @decision_ref,
      "input_digest" => "sha256:" <> String.duplicate("c", 64),
      "policy_ref" => "policy-artifact://citadel/synapse/codex-reviewed-write/v1",
      "policy_version" => 1,
      "provider_family" => "codex",
      "provider_account_ref" => "provider-account://nshkr/codex",
      "credential_lease_ref" => "lease://jido/codex/reviewed",
      "credential_generation" => 1,
      "managed_session_ref" => "managed-session://nshkr/codex/reviewed",
      "session_generation" => 1,
      "review_ref" => @review_ref,
      "workspace_policy" => "isolated_disposable_workspace",
      "workspace_ref" => @workspace_ref,
      "workspace_root_digest" => digest(@workspace_root),
      "relative_path" => @relative_path,
      "operation_class" => "create_or_replace",
      "reviewed_content_digest" => @content_digest,
      "target_ref" => "target://nshkr/codex/reviewed",
      "attempt_ref" => "jido-run://nshkr/codex/reviewed:1"
    }

    struct!(ScopedGrant,
      contract_version: 1,
      grant_ref: @grant_ref,
      decision_ref: @decision_ref,
      decision_hash: "sha256:" <> String.duplicate("d", 64),
      policy_artifact_ref: scope["policy_ref"],
      policy_version: 1,
      input_snapshot_hash: scope["input_digest"],
      tenant_ref: "tenant://nshkr/test",
      actor_ref: "actor://synapse/operator",
      subject_ref: "subject://mezzanine/reviewed",
      effect_ref: @effect_ref,
      operation_ref: "operation://codex/reviewed",
      capability_id: "codex.session.turn",
      scope: scope,
      obligations: [],
      result: "permitted",
      issued_at: ~U[2026-07-28 11:59:00Z],
      expires_at: ~U[2026-07-28 12:01:00Z],
      status: "active"
    )
  end

  defp digest(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end
end
