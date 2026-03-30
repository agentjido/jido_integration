defmodule Jido.Integration.V2.ReviewProjectionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.ReviewProjection
  alias Jido.Integration.V2.SubjectRef

  test "review projections round-trip through dump/1 with typed refs" do
    subject = SubjectRef.new!(%{kind: :run, id: "run-123"})

    selected_attempt =
      SubjectRef.new!(%{
        kind: :attempt,
        id: "run-123:2",
        metadata: %{attempt: 2, run_id: "run-123"}
      })

    evidence =
      EvidenceRef.new!(%{
        kind: :event,
        id: "event-456",
        packet_ref: "jido://v2/review_packet/run/run-123?attempt_id=run-123%3A2",
        subject: subject,
        metadata: %{attempt_id: "run-123:2", type: "run.completed"}
      })

    governance =
      GovernanceRef.new!(%{
        kind: :policy_decision,
        id: "event-456",
        subject: subject,
        evidence: [evidence],
        metadata: %{status: :approved, event_type: "audit.policy_allowed"}
      })

    projection =
      ReviewProjection.new!(%{
        schema_version: "jido.integration.v2",
        projection: "operator.review_packet",
        packet_ref: "jido://v2/review_packet/run/run-123?attempt_id=run-123%3A2",
        subject: subject,
        selected_attempt: selected_attempt,
        evidence_refs: [evidence],
        governance_refs: [governance]
      })

    dumped = ReviewProjection.dump(projection)

    assert dumped == %{
             schema_version: "jido.integration.v2",
             projection: "operator.review_packet",
             packet_ref: "jido://v2/review_packet/run/run-123?attempt_id=run-123%3A2",
             subject: SubjectRef.dump(subject),
             selected_attempt: SubjectRef.dump(selected_attempt),
             evidence_refs: [EvidenceRef.dump(evidence)],
             governance_refs: [GovernanceRef.dump(governance)]
           }

    assert ReviewProjection.new!(dumped) == projection
  end
end
