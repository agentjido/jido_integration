defmodule Jido.Integration.V2.ReferenceContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.SubjectRef

  test "subject refs expose a stable canonical ref and dump shape" do
    subject =
      SubjectRef.new!(%{
        kind: :attempt,
        id: "run-123:2",
        metadata: %{run_id: "run-123", attempt: 2}
      })

    assert subject.ref == "jido://v2/subject/attempt/run-123%3A2"

    assert SubjectRef.dump(subject) == %{
             ref: "jido://v2/subject/attempt/run-123%3A2",
             kind: :attempt,
             id: "run-123:2",
             metadata: %{run_id: "run-123", attempt: 2}
           }
  end

  test "evidence refs carry packet lineage and round-trip through their dump" do
    subject = SubjectRef.new!(%{kind: :run, id: "run-123"})

    evidence =
      EvidenceRef.new!(%{
        kind: :event,
        id: "event-123",
        packet_ref: "jido://v2/review_packet/run/run-123?attempt_id=run-123%3A2",
        subject: subject,
        metadata: %{attempt_id: "run-123:2", type: "run.completed"}
      })

    assert evidence.ref == "jido://v2/evidence/event/event-123"

    dumped = EvidenceRef.dump(evidence)

    assert dumped == %{
             ref: "jido://v2/evidence/event/event-123",
             kind: :event,
             id: "event-123",
             packet_ref: "jido://v2/review_packet/run/run-123?attempt_id=run-123%3A2",
             subject: SubjectRef.dump(subject),
             metadata: %{attempt_id: "run-123:2", type: "run.completed"}
           }

    assert EvidenceRef.new!(dumped) == evidence
  end

  test "governance refs anchor policy lineage through subject and evidence refs" do
    subject = SubjectRef.new!(%{kind: :run, id: "run-123"})

    evidence =
      EvidenceRef.new!(%{
        kind: :event,
        id: "event-456",
        packet_ref: "jido://v2/review_packet/run/run-123",
        subject: subject,
        metadata: %{type: "audit.policy_denied"}
      })

    governance =
      GovernanceRef.new!(%{
        kind: :policy_decision,
        id: "event-456",
        subject: subject,
        evidence: [evidence],
        metadata: %{status: :denied, event_type: "audit.policy_denied"}
      })

    assert governance.ref == "jido://v2/governance/policy_decision/event-456"

    assert GovernanceRef.dump(governance) == %{
             ref: "jido://v2/governance/policy_decision/event-456",
             kind: :policy_decision,
             id: "event-456",
             subject: SubjectRef.dump(subject),
             evidence: [EvidenceRef.dump(evidence)],
             metadata: %{status: :denied, event_type: "audit.policy_denied"}
           }
  end
end
