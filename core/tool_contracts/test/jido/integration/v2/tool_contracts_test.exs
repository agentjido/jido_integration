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
end
