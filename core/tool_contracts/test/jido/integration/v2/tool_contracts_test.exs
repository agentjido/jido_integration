defmodule Jido.Integration.V2.ToolContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ToolContracts

  test "builds bounded ref-only contract summaries" do
    assert {:ok, contract} =
             ToolContracts.new(%{
               contract_ref: "tool-contract://amp/command",
               category: :provider_native_tool,
               auth_source: :provider_native_assertion_ref,
               execution_authority: :provider_native_runtime,
               redaction_class: :provider_tool_metadata,
               allowed_payload_keys: ["prompt", "thread_ref"],
               metadata: %{provider: :amp}
             })

    assert ToolContracts.summary(contract) == %{
             contract_ref: "tool-contract://amp/command",
             category: :provider_native_tool,
             auth_source: :provider_native_assertion_ref,
             execution_authority: :provider_native_runtime,
             redaction_class: :provider_tool_metadata,
             allowed_payload_keys: ["prompt", "thread_ref"],
             metadata: %{provider: :amp}
           }
  end

  test "rejects smuggled authority and credential fields" do
    assert {:error, {:forbidden_tool_contract_fields, fields}} =
             ToolContracts.new(%{
               contract_ref: "tool-contract://amp/command",
               category: :provider_native_tool,
               auth_source: :provider_native_assertion_ref,
               execution_authority: :provider_native_runtime,
               redaction_class: :provider_tool_metadata,
               allowed_payload_keys: ["prompt"],
               env: %{"AMP_API_KEY" => "secret"},
               metadata: %{provider_payload: %{}}
             })

    assert Enum.sort(fields) == [:env, :provider_payload]
  end

  test "binds provider operation rows to explicit authority refs before effects" do
    rows = ToolContracts.provider_operation_rows()

    assert Enum.map(rows, & &1.provider) == [
             :github,
             :linear,
             :notion,
             :reqllm_next,
             :inference,
             :codex,
             :claude,
             :gemini,
             :amp
           ]

    Enum.each(rows, fn row ->
      assert {:ok, binding} =
               row
               |> operation_attrs()
               |> ToolContracts.bind_operation()

      assert binding.raw_material_present? == false
      assert binding.provider_family == row.family
      assert binding.requested_operation == row.operation
      assert binding.tool_sandbox == "strict"
      assert binding.connector_binding_ref =~ "connector-binding://"
      refute inspect(binding) =~ "secret"
    end)
  end

  test "rejects tool operation smuggling and undeclared payload keys" do
    assert {:error, {:forbidden_tool_payload_fields, fields}} =
             %{
               provider: :github,
               family: "http",
               category: :connector_tool,
               operation: "github.issue.list"
             }
             |> operation_attrs()
             |> Map.put(:payload, %{"query" => "issues", "env" => %{"GITHUB_TOKEN" => "secret"}})
             |> ToolContracts.bind_operation()

    assert fields == [:env]

    assert {:error, {:undeclared_tool_payload_keys, ["private_path"]}} =
             %{
               provider: :github,
               family: "http",
               category: :connector_tool,
               operation: "github.issue.list"
             }
             |> operation_attrs()
             |> Map.put(:payload, %{
               "query" => "issues",
               "private_path" => "/home/operator/.config"
             })
             |> ToolContracts.bind_operation()
  end

  test "rejects missing and mismatched tool operation authority refs" do
    assert {:error, {:missing_tool_operation_refs, missing}} =
             %{
               provider: :github,
               family: "http",
               category: :connector_tool,
               operation: "github.issue.list"
             }
             |> operation_attrs()
             |> Map.put(:credential_lease_ref, "")
             |> ToolContracts.bind_operation()

    assert missing == [:credential_lease_ref]

    assert {:error, {:tool_operation_ref_mismatch, fields}} =
             %{
               provider: :github,
               family: "http",
               category: :connector_tool,
               operation: "github.issue.list"
             }
             |> operation_attrs()
             |> Map.put(:target_ref, "credential-lease://tenant-1/github/default")
             |> ToolContracts.bind_operation()

    assert fields == [:target_ref]
  end

  test "rejects multi-operation provider, tenant, token-family, and sandbox mismatches" do
    attrs =
      operation_attrs(%{
        provider: :github,
        family: "http",
        category: :connector_tool,
        operation: "github.issue.list"
      })

    assert {:error, {:multi_tool_operation_rejected, [:operations]}} =
             attrs
             |> Map.put(:operations, ["github.issue.list", "github.issue.create"])
             |> ToolContracts.bind_operation()

    assert {:error, {:provider_ref_mismatch, fields}} =
             attrs
             |> Map.put(:provider_account_ref, "provider-account://tenant-1/linear/http/default")
             |> ToolContracts.bind_operation()

    assert :provider_account_ref in fields

    assert {:error, {:tenant_ref_mismatch, tenant_fields}} =
             attrs
             |> Map.put(
               :connector_binding_ref,
               "connector-binding://tenant-2/github/http/default"
             )
             |> ToolContracts.bind_operation()

    assert :connector_binding_ref in tenant_fields

    assert {:error, {:token_family_ref_mismatch, family_fields}} =
             attrs
             |> Map.put(
               :operation_policy_ref,
               "operation-policy://tenant-1/github/graphql/github.issue.list"
             )
             |> ToolContracts.bind_operation()

    assert :operation_policy_ref in family_fields

    assert {:error, {:target_ref_mismatch, target_fields}} =
             attrs
             |> Map.put(:target_ref, "target://tenant-1/github/graphql/default")
             |> ToolContracts.bind_operation()

    assert :target_ref in target_fields

    assert {:error, {:tool_sandbox_mismatch, %{expected: "strict", got: "read_only"}}} =
             attrs
             |> Map.put(:tool_sandbox, "read_only")
             |> ToolContracts.bind_operation()
  end

  test "unsupported tool modes fail closed with operator visible facts" do
    assert {:error,
            {:unsupported_tool_mode,
             %{
               requested_operation: "github.issue.list",
               provider_family: "http",
               category: :operator_action
             }}} =
             %{
               provider: :github,
               family: "http",
               category: :connector_tool,
               operation: "github.issue.list"
             }
             |> operation_attrs()
             |> Map.put(:category, :operator_action)
             |> ToolContracts.bind_operation()
  end

  test "tool result receipts remain redacted and reject raw result material" do
    assert {:ok, binding} =
             %{
               provider: :github,
               family: "http",
               category: :connector_tool,
               operation: "github.issue.list"
             }
             |> operation_attrs()
             |> ToolContracts.bind_operation()

    assert {:ok, receipt} =
             ToolContracts.operation_result_receipt(binding,
               payload_ref: "payload://redacted/github/issues"
             )

    assert receipt.raw_material_present? == false
    assert receipt.provider_payload_redacted? == true
    assert receipt.result_ref == "tool-result://tenant-1/github/http/github.issue.list"
    refute inspect(receipt) =~ "secret"

    assert {:error, {:forbidden_tool_result_fields, [:provider_payload, :raw_token]}} =
             ToolContracts.operation_result_receipt(binding,
               provider_payload: %{body: "secret"},
               raw_token: "secret"
             )
  end

  defp operation_attrs(row) do
    provider = Atom.to_string(row.provider)
    family = row.family

    %{
      tool_ref: "tool://#{provider}/#{row.operation}",
      contract_ref: "tool-contract://#{provider}/#{row.operation}",
      category: row.category,
      provider_family: row.family,
      requested_operation: row.operation,
      tool_sandbox: "strict",
      tenant_ref: "tenant://tenant-1",
      installation_ref: "installation://tenant-1/#{provider}/#{family}/default",
      trace_ref: "trace://tenant-1/#{provider}/#{family}/operation",
      provider_account_ref: "provider-account://tenant-1/#{provider}/#{family}/default",
      connector_instance_ref: "connector-instance://tenant-1/#{provider}/#{family}/default",
      connector_binding_ref: "connector-binding://tenant-1/#{provider}/#{family}/default",
      operation_policy_ref: "operation-policy://tenant-1/#{provider}/#{family}/#{row.operation}",
      credential_handle_ref: "credential-handle://tenant-1/#{provider}/#{family}/default",
      credential_lease_ref: "credential-lease://tenant-1/#{provider}/#{family}/default",
      target_ref: "target://tenant-1/#{provider}/#{family}/default",
      connector_admission_ref:
        "connector-admission://tenant-1/#{provider}/#{family}/#{row.operation}",
      redaction_class: :provider_tool_metadata,
      allowed_payload_keys: ["query", "prompt", "thread_ref"],
      payload: %{"query" => row.operation}
    }
  end
end
