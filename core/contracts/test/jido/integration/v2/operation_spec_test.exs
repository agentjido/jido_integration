defmodule Jido.Integration.V2.OperationSpecTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.OperationSpec

  defmodule Handler do
    def run(_params, _context), do: {:ok, %{}}
  end

  test "exposes authored schema metadata helpers when present" do
    schema_slots = [
      %{
        surface: :input,
        path: ["properties"],
        kind: :data_source_properties,
        source: :parent_data_source
      }
    ]

    operation =
      operation_spec!(%{
        schema_strategy: :late_bound_input,
        schema_context_source: :parent_data_source,
        schema_slots: schema_slots
      })

    assert OperationSpec.schema_strategy(operation) == :late_bound_input
    assert OperationSpec.schema_context_source(operation) == :parent_data_source
    assert OperationSpec.schema_slots(operation) == schema_slots
    assert OperationSpec.late_bound_schema?(operation)
  end

  test "returns empty authored schema metadata when none is declared" do
    operation = operation_spec!()

    assert OperationSpec.schema_strategy(operation) == nil
    assert OperationSpec.schema_context_source(operation) == nil
    assert OperationSpec.schema_slots(operation) == []
    refute OperationSpec.late_bound_schema?(operation)
  end

  test "rejects unsupported schema strategies" do
    assert_raise ArgumentError,
                 "operation.metadata.schema_strategy must be one of [:static, :late_bound_input, :late_bound_output, :late_bound_input_output]",
                 fn ->
                   operation_spec!(%{schema_strategy: :unknown})
                 end
  end

  test "rejects malformed schema slot metadata" do
    assert_raise ArgumentError,
                 "operation.metadata.schema_slots[0].surface must be :input or :output",
                 fn ->
                   operation_spec!(%{
                     schema_strategy: :late_bound_input,
                     schema_context_source: :parent_data_source,
                     schema_slots: [
                       %{
                         surface: :config,
                         path: ["properties"],
                         kind: :data_source_properties,
                         source: :parent_data_source
                       }
                     ]
                   })
                 end
  end

  defp operation_spec!(schema_metadata \\ %{}) do
    OperationSpec.new!(%{
      operation_id: "acme.pages.create",
      name: "pages_create",
      display_name: "Pages create",
      description: "Creates one page",
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: Handler,
      input_schema: Zoi.map(description: "input"),
      output_schema: Zoi.map(description: "output"),
      permissions: %{required_scopes: ["pages:write"]},
      policy: %{
        environment: %{allowed: [:prod]},
        sandbox: %{
          level: :standard,
          egress: :restricted,
          approvals: :auto,
          allowed_tools: ["acme.pages.create"]
        }
      },
      upstream: %{method: "POST", path: "/pages"},
      consumer_surface: %{
        mode: :connector_local,
        reason: "Provider-specific operation"
      },
      schema_policy: %{
        input: :passthrough,
        output: :passthrough,
        justification: "The authored schema boundary is intentionally passthrough"
      },
      jido: %{action: %{name: "acme_pages_create"}},
      metadata: schema_metadata
    })
  end
end
