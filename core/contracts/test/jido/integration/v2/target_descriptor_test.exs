defmodule Jido.Integration.V2.TargetDescriptorTest do
  use ExUnit.Case

  alias Jido.Integration.V2.TargetDescriptor

  test "preserves unknown fields and negotiates compatible protocol versions" do
    descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-pool-1",
        capability_id: "python3",
        runtime_class: :direct,
        version: "2.1.0",
        features: %{
          feature_ids: ["docker", "python3", "sandbox"],
          runspec_versions: ["1.0.0", "1.1.0"],
          event_schema_versions: ["1.0.0", "1.2.0"]
        },
        constraints: %{regions: ["us-west-2"], sandbox_levels: [:strict]},
        health: :healthy,
        location: %{mode: :beam, region: "us-west-2", workspace_root: "/srv/jido"},
        queue_weight: 0.5
      })

    assert descriptor.extensions.queue_weight == 0.5

    assert {:ok, negotiated_versions} =
             TargetDescriptor.compatibility(descriptor, %{
               capability_id: "python3",
               runtime_class: :direct,
               version_requirement: "~> 2.0",
               required_features: ["docker", "python3"],
               accepted_runspec_versions: ["1.0.0", "1.1.0"],
               accepted_event_schema_versions: ["1.0.0", "1.2.0"]
             })

    assert negotiated_versions == %{
             runspec_version: "1.1.0",
             event_schema_version: "1.2.0"
           }
  end

  test "returns explicit incompatibility reasons" do
    descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-unhealthy",
        capability_id: "python3",
        runtime_class: :direct,
        version: "1.0.0",
        features: %{
          feature_ids: ["python3"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{},
        health: :degraded,
        location: %{mode: :beam, region: "us-west-2"}
      })

    assert {:error, :target_unhealthy} =
             TargetDescriptor.compatibility(descriptor, %{
               capability_id: "python3",
               runtime_class: :direct,
               version_requirement: "~> 1.0"
             })

    healthy_descriptor = %{descriptor | health: :healthy}

    assert {:error, :version_mismatch} =
             TargetDescriptor.compatibility(healthy_descriptor, %{
               capability_id: "python3",
               runtime_class: :direct,
               version_requirement: "~> 2.0"
             })
  end

  test "normalizes persisted string-backed target enums" do
    descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-persisted",
        capability_id: "python3",
        runtime_class: :direct,
        version: "2.1.0",
        features: %{
          feature_ids: ["docker", "python3"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{sandbox_levels: ["standard"]},
        health: :healthy,
        location: %{mode: "beam", region: "us-west-2"}
      })

    assert descriptor.constraints.sandbox_levels == [:standard]
    assert descriptor.location.mode == :beam
  end
end
