defmodule Jido.Integration.V2.BoundaryCapabilityTest do
  use ExUnit.Case

  alias Jido.Integration.V2.BoundaryCapability

  test "normalizes authored boundary capability advertisements" do
    assert BoundaryCapability.new!(%{
             supported: true,
             boundary_classes: ["sidecar", "leased_cell"],
             attach_modes: ["guest_bridge", "none"],
             checkpointing: true
           }) == %BoundaryCapability{
             supported: true,
             boundary_classes: ["sidecar", "leased_cell"],
             attach_modes: ["guest_bridge", "none"],
             checkpointing: true
           }
  end

  test "runtime merge sharpens but does not widen the authored baseline" do
    authored =
      BoundaryCapability.new!(%{
        supported: true,
        boundary_classes: ["sidecar", "leased_cell"],
        attach_modes: ["guest_bridge", "none"],
        checkpointing: true
      })

    assert BoundaryCapability.merge(authored, %{
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
