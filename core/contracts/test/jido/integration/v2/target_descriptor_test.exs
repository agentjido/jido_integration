defmodule Jido.Integration.V2.TargetDescriptorTest do
  use ExUnit.Case

  alias Jido.Integration.V2.BoundaryCapability
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.TargetDescriptor

  test "derives compatibility requirements from authored capability posture" do
    capability =
      Capability.new!(%{
        id: "codex.exec.session",
        connector: "codex_cli",
        runtime_class: :session,
        kind: :operation,
        transport_profile: :stdio,
        handler: __MODULE__,
        metadata: %{
          runtime: %{
            driver: "asm",
            provider: :codex,
            options: %{"lane" => "sdk"}
          }
        }
      })

    assert TargetDescriptor.authored_requirements(capability, %{
             capability_id: "override.capability",
             runtime_class: :stream,
             version_requirement: "~> 1.0",
             required_features: ["tenant_isolated"],
             accepted_runspec_versions: ["1.0.0"],
             accepted_event_schema_versions: ["1.0.0"]
           }) == %{
             capability_id: "codex.exec.session",
             runtime_class: :session,
             version_requirement: "~> 1.0",
             required_features: ["asm", "tenant_isolated"],
             accepted_runspec_versions: ["1.0.0"],
             accepted_event_schema_versions: ["1.0.0"]
           }
  end

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

  test "rejects compatibility requirements that try to override authored runtime posture" do
    descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-runtime",
        capability_id: "codex.exec.session",
        runtime_class: :session,
        version: "1.0.0",
        features: %{
          feature_ids: ["asm", "codex.exec.session"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{},
        health: :healthy,
        location: %{mode: :beam, region: "us-west-2"}
      })

    assert_raise ArgumentError,
                 ~r/target compatibility requirements must not declare runtime override keys/,
                 fn ->
                   TargetDescriptor.compatibility(descriptor, %{
                     capability_id: "codex.exec.session",
                     runtime_class: :session,
                     runtime: %{driver: "override_driver"}
                   })
                 end
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

  test "reads the authored boundary capability advertisement from extensions" do
    descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-boundary-authored",
        capability_id: "codex.exec.session",
        runtime_class: :session,
        version: "1.0.0",
        features: %{
          feature_ids: ["asm", "codex.exec.session"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{},
        health: :healthy,
        location: %{mode: :beam, region: "test"},
        extensions: %{
          "boundary" => %{
            "supported" => true,
            "boundary_classes" => ["sidecar", "leased_cell"],
            "attach_modes" => ["guest_bridge", "none"],
            "checkpointing" => true
          }
        }
      })

    assert TargetDescriptor.authored_boundary_capability(descriptor) ==
             BoundaryCapability.new!(%{
               supported: true,
               boundary_classes: ["sidecar", "leased_cell"],
               attach_modes: ["guest_bridge", "none"],
               checkpointing: true
             })
  end

  test "builds a runtime-merged live boundary capability view when worker facts sharpen the result" do
    descriptor =
      TargetDescriptor.new!(%{
        target_id: "target-boundary-live",
        capability_id: "codex.exec.session",
        runtime_class: :session,
        version: "1.0.0",
        features: %{
          feature_ids: ["asm", "codex.exec.session"],
          runspec_versions: ["1.0.0"],
          event_schema_versions: ["1.0.0"]
        },
        constraints: %{},
        health: :healthy,
        location: %{mode: :beam, region: "test"},
        extensions: %{
          "boundary" => %{
            "supported" => true,
            "boundary_classes" => ["sidecar", "leased_cell"],
            "attach_modes" => ["guest_bridge", "none"],
            "checkpointing" => true
          }
        }
      })

    assert TargetDescriptor.live_boundary_capability(descriptor, %{
             boundary_classes: ["leased_cell", "microvm"],
             attach_modes: ["guest_bridge"],
             checkpointing: false
           }) ==
             BoundaryCapability.new!(%{
               supported: true,
               boundary_classes: ["leased_cell"],
               attach_modes: ["guest_bridge"],
               checkpointing: false
             })
  end
end
