defmodule Jido.Integration.V2.ConnectorAdmissionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ConnectorAdmission

  test "accepts scoped admitted connector evidence" do
    assert {:ok, admission} =
             admission_attrs(status: :admitted)
             |> ConnectorAdmission.new()

    assert admission.contract_name == "Platform.ConnectorAdmission.v1"
    assert admission.status == :admitted
    assert admission.duplicate_of_ref == nil
  end

  test "accepts duplicate rejection evidence with duplicate ref" do
    assert {:ok, admission} =
             admission_attrs(
               status: "rejected_duplicate",
               duplicate_of_ref: "connector:github:v1"
             )
             |> ConnectorAdmission.new()

    assert admission.status == :rejected_duplicate
    assert admission.duplicate_of_ref == "connector:github:v1"
  end

  test "rejects duplicate status without duplicate ref" do
    assert {:error, :invalid_connector_admission} =
             admission_attrs(status: :rejected_duplicate)
             |> ConnectorAdmission.new()
  end

  test "rejects connector admission without idempotency scope" do
    assert {:error, {:missing_required_fields, fields}} =
             admission_attrs(status: :admitted)
             |> Map.delete(:admission_idempotency_key)
             |> ConnectorAdmission.new()

    assert :admission_idempotency_key in fields
  end

  defp admission_attrs(opts) do
    attrs = %{
      tenant_ref: "tenant:alpha",
      installation_ref: "installation:alpha-prod",
      workspace_ref: "workspace:alpha",
      project_ref: "project:phase4",
      environment_ref: "env:prod",
      system_actor_ref: "system:connector-admission",
      resource_ref: "connector:github",
      authority_packet_ref: "authority:connector-admission",
      permission_decision_ref: "decision:allow-connector-admission",
      idempotency_key: "idem:connector-admission:1",
      trace_id: "trace:connector-admission:1",
      correlation_id: "corr:connector-admission:1",
      release_manifest_ref: "phase4-v6-milestone14-extension-authoring-supply-chain",
      connector_ref: "connector:github:v2",
      pack_ref: "pack:expense-approval@1.0.0",
      signature_ref: "sig:phase4-expense-approval",
      schema_ref: "schema:extension-pack:v1",
      admission_idempotency_key: "admission:tenant-alpha:github"
    }

    Enum.reduce(opts, attrs, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end
end
