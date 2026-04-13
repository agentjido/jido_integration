defmodule Jido.Integration.V2.DerivedStateAttachmentTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.DerivedStateAttachment
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.SubjectRef

  test "anchors derived state through explicit subject, evidence, and governance refs" do
    subject = SubjectRef.new!(%{kind: :run, id: "run-123", metadata: %{connector: "github"}})

    evidence =
      EvidenceRef.new!(%{
        kind: :event,
        id: "event-123",
        packet_ref: "jido://v2/review_packet/run/run-123?attempt_id=run-123%3A1",
        subject: subject,
        metadata: %{type: "run.completed"}
      })

    governance =
      GovernanceRef.new!(%{
        kind: :policy_decision,
        id: "decision-123",
        subject: subject,
        evidence: [evidence],
        metadata: %{status: :allowed}
      })

    attachment =
      DerivedStateAttachment.new!(%{
        subject: subject,
        evidence_refs: [evidence],
        governance_refs: [governance],
        metadata: %{repo: "jido_memory"}
      })

    assert DerivedStateAttachment.dump(attachment) == %{
             subject: SubjectRef.dump(subject),
             evidence_refs: [EvidenceRef.dump(evidence)],
             governance_refs: [GovernanceRef.dump(governance)],
             metadata: %{repo: "jido_memory"}
           }
  end
end
