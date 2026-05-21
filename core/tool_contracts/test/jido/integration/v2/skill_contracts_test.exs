defmodule Jido.Integration.V2.SkillContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.SkillContracts
  alias Jido.Integration.V2.SkillContracts.SkillPackage

  test "validates governed skill package manifests by canonical hash" do
    attrs = package_attrs("summarize")

    assert {:ok, %SkillPackage{} = package} = SkillContracts.package(attrs)
    assert package.skill_ref == "skill://tenant-1/summarize"
    assert package.manifest_hash == SkillContracts.canonical_manifest_hash(attrs)
    assert package.credential_posture == :lease_required
    assert package.allowed_runtime_families == [:direct, :process]

    assert [%{kind: :jido_action, schema_ref: "schema://skill/summarize/input"}] =
             package.entrypoints
  end

  test "rejects missing or mismatched manifest hashes" do
    attrs = Map.delete(package_attrs("summarize"), :manifest_hash)

    assert {:error, %ArgumentError{} = error} = SkillContracts.package(attrs)
    assert Exception.message(error) == "manifest_hash is required"

    attrs = Map.put(package_attrs("summarize"), :manifest_hash, "sha256:wrong")

    assert {:error, {:manifest_hash_mismatch, mismatch}} = SkillContracts.package(attrs)
    assert mismatch.expected == SkillContracts.canonical_manifest_hash(attrs)
    assert mismatch.got == "sha256:wrong"
  end

  test "rejects arbitrary script paths and raw credential material" do
    attrs =
      package_attrs("unsafe")
      |> put_in([:entrypoints], [
        %{
          name: "invoke",
          kind: :jido_action,
          schema_ref: "schema://skill/unsafe/input",
          script_path: "/tmp/run.sh"
        }
      ])
      |> rehash()

    assert {:error, {:forbidden_skill_package_fields, [:entrypoints, 0, :script_path]}} =
             SkillContracts.package(attrs)

    attrs =
      package_attrs("unsafe")
      |> Map.put(:credentials, %{"api_key" => "secret"})
      |> rehash()

    assert {:error, {:forbidden_skill_package_fields, [:credentials]}} =
             SkillContracts.package(attrs)
  end

  test "builds invocation envelopes only from authority and lease refs" do
    package = SkillContracts.package!(package_attrs("summarize"))

    assert {:ok, intent} =
             SkillContracts.invocation_intent(%{
               invocation_ref: "skill-invocation://tenant-1/summarize/1",
               skill_ref: package.skill_ref,
               tenant_ref: "tenant://tenant-1",
               authority_ref: "authority://tenant-1/agent",
               idempotency_key: "idem-summarize-1",
               entrypoint_name: "invoke",
               credential_lease_ref: "credential-lease://tenant-1/skill/summarize",
               target_ref: "target://tenant-1/document/1",
               trace_ref: "trace://tenant-1/skill/summarize",
               input_ref: "payload://tenant-1/document/1"
             })

    assert {:ok, envelope} =
             SkillContracts.invocation_envelope(package, intent,
               policy_projection_ref: "agent-policy-projection://tenant-1/skill/summarize",
               receipt_ledger_ref: "agent-turn-ledger://tenant-1/run/1"
             )

    assert envelope.skill_ref == package.skill_ref
    assert envelope.authority_ref == "authority://tenant-1/agent"
    assert envelope.credential_lease_ref == "credential-lease://tenant-1/skill/summarize"
    assert envelope.raw_material_present? == false
  end

  test "invocation envelope rejects unknown entrypoints and raw payloads" do
    package = SkillContracts.package!(package_attrs("summarize"))

    assert {:ok, intent} =
             SkillContracts.invocation_intent(%{
               invocation_ref: "skill-invocation://tenant-1/summarize/1",
               skill_ref: package.skill_ref,
               tenant_ref: "tenant://tenant-1",
               authority_ref: "authority://tenant-1/agent",
               idempotency_key: "idem-summarize-1",
               entrypoint_name: "not-present",
               credential_lease_ref: "credential-lease://tenant-1/skill/summarize",
               target_ref: "target://tenant-1/document/1",
               trace_ref: "trace://tenant-1/skill/summarize",
               input_ref: "payload://tenant-1/document/1"
             })

    assert {:error, {:unknown_skill_entrypoint, "not-present"}} =
             SkillContracts.invocation_envelope(package, intent,
               policy_projection_ref: "agent-policy-projection://tenant-1/skill/summarize",
               receipt_ledger_ref: "agent-turn-ledger://tenant-1/run/1"
             )

    assert {:error, {:forbidden_skill_invocation_fields, [:raw_token]}} =
             SkillContracts.invocation_intent(%{
               invocation_ref: "skill-invocation://tenant-1/summarize/1",
               skill_ref: package.skill_ref,
               tenant_ref: "tenant://tenant-1",
               authority_ref: "authority://tenant-1/agent",
               idempotency_key: "idem-summarize-1",
               entrypoint_name: "invoke",
               credential_lease_ref: "credential-lease://tenant-1/skill/summarize",
               target_ref: "target://tenant-1/document/1",
               trace_ref: "trace://tenant-1/skill/summarize",
               input_ref: "payload://tenant-1/document/1",
               raw_token: "secret"
             })
  end

  defp package_attrs(name) do
    %{
      skill_ref: "skill://tenant-1/#{name}",
      package_name: name,
      version: "1.0.0",
      description: "Summarize a document.",
      entrypoints: [
        %{
          name: "invoke",
          kind: :jido_action,
          schema_ref: "schema://skill/#{name}/input",
          capability_ref: "capability://skill/#{name}/invoke"
        }
      ],
      allowed_artifact_posture: :claim_checked,
      credential_posture: :lease_required,
      allowed_runtime_families: [:direct, :process],
      policy_refs: ["policy://skill/#{name}"],
      docs_ref: "doc://skill/#{name}",
      tenant_ref: "tenant://tenant-1",
      installation_ref: "installation://tenant-1/skills",
      capability_refs: ["capability://skill/#{name}/invoke"],
      trace_ref: "trace://skill/#{name}",
      release_manifest_ref: "release://skill/#{name}",
      redaction_posture: :refs_only
    }
    |> rehash()
  end

  defp rehash(attrs),
    do: Map.put(attrs, :manifest_hash, SkillContracts.canonical_manifest_hash(attrs))
end
