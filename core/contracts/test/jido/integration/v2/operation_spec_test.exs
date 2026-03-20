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

  test "rejects late-bound schema metadata without a real context source" do
    assert_raise ArgumentError,
                 "operation.metadata.schema_context_source must identify a real lookup source when late-bound schema metadata is declared",
                 fn ->
                   operation_spec!(%{
                     schema_strategy: :late_bound_input,
                     schema_context_source: :none,
                     schema_slots: [
                       %{
                         surface: :input,
                         path: ["properties"],
                         kind: :data_source_properties,
                         source: :parent_data_source
                       }
                     ]
                   })
                 end
  end

  test "rejects late-bound schema slots without a real lookup source" do
    assert_raise ArgumentError,
                 "operation.metadata.schema_slots[0].source must identify a real lookup source",
                 fn ->
                   operation_spec!(%{
                     schema_strategy: :late_bound_input,
                     schema_context_source: :parent_data_source,
                     schema_slots: [
                       %{
                         surface: :input,
                         path: ["properties"],
                         kind: :data_source_properties,
                         source: :none
                       }
                     ]
                   })
                 end
  end

  test "exposes canonical authored runtime routing and family helpers for common session surfaces" do
    operation =
      operation_spec_with(%{
        runtime_class: :session,
        transport_mode: :stdio,
        input_schema:
          Zoi.object(%{
            prompt: Zoi.string()
          }),
        output_schema:
          Zoi.object(%{
            text: Zoi.string()
          }),
        runtime: %{
          "driver" => "asm",
          "provider" => "codex",
          "options" => %{"lane" => "sdk"}
        },
        consumer_surface: %{
          mode: :common,
          normalized_id: "codex.exec.session",
          action_name: "codex_exec_session"
        },
        schema_policy: %{input: :defined, output: :defined},
        metadata: %{
          "runtime_family" => %{
            "session_affinity" => "connection",
            "resumable" => true,
            "approval_required" => true,
            "stream_capable" => true,
            "lifecycle_owner" => "asm",
            "runtime_ref" => "session"
          }
        }
      })

    assert OperationSpec.runtime_driver(operation) == "asm"
    assert OperationSpec.runtime_provider(operation) == :codex
    assert OperationSpec.runtime_options(operation) == %{"lane" => "sdk"}

    assert OperationSpec.runtime_family(operation) == %{
             session_affinity: :connection,
             resumable: true,
             approval_required: true,
             stream_capable: true,
             lifecycle_owner: :asm,
             runtime_ref: :session
           }
  end

  test "requires runtime_family metadata for common non-direct projected surfaces" do
    assert_raise ArgumentError,
                 ~r/operation.metadata.runtime_family is required for common projected session and stream surfaces/,
                 fn ->
                   operation_spec_with(%{
                     runtime_class: :session,
                     transport_mode: :stdio,
                     input_schema:
                       Zoi.object(%{
                         prompt: Zoi.string()
                       }),
                     output_schema:
                       Zoi.object(%{
                         text: Zoi.string()
                       }),
                     runtime: %{driver: "asm"},
                     consumer_surface: %{
                       mode: :common,
                       normalized_id: "codex.exec.session",
                       action_name: "codex_exec_session"
                     },
                     schema_policy: %{input: :defined, output: :defined},
                     metadata: %{}
                   })
                 end
  end

  test "keeps connector-local non-direct operations as an explicit authored exception" do
    operation =
      operation_spec_with(%{
        runtime_class: :stream,
        transport_mode: :stdio,
        runtime: %{driver: "asm"},
        consumer_surface: %{
          mode: :connector_local,
          reason: "Provider-specific stream state stays off the common surface"
        },
        metadata: %{}
      })

    assert OperationSpec.connector_local_consumer_surface?(operation)
    assert OperationSpec.runtime_driver(operation) == "asm"
    assert OperationSpec.runtime_family(operation) == nil
  end

  test "rejects non-direct runtime maps that drift beyond driver provider and options" do
    assert_raise ArgumentError,
                 ~r/operation.runtime only supports driver, provider, and options for session and stream authored routing/,
                 fn ->
                   operation_spec_with(%{
                     runtime_class: :session,
                     transport_mode: :stdio,
                     runtime: %{
                       driver: "asm",
                       lane: :sdk
                     },
                     metadata: %{}
                   })
                 end
  end

  defp operation_spec!(schema_metadata \\ %{}) do
    operation_spec_with(%{metadata: schema_metadata})
  end

  defp operation_spec_with(overrides) do
    overrides = Map.new(overrides)
    replace_keys = [:consumer_surface, :schema_policy, :runtime, :metadata]

    base =
      %{
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
        runtime: %{},
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
        metadata: %{}
      }
      |> maybe_replace_nested(overrides, replace_keys)

    overrides
    |> Map.drop(replace_keys)
    |> then(&deep_merge(base, &1))
    |> OperationSpec.new!()
  end

  defp deep_merge(%{} = left, %{} = right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp maybe_replace_nested(base, overrides, keys) do
    Enum.reduce(keys, base, fn key, acc ->
      if Map.has_key?(overrides, key) do
        Map.put(acc, key, Map.fetch!(overrides, key))
      else
        acc
      end
    end)
  end
end
