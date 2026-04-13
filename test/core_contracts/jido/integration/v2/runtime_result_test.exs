defmodule Jido.Integration.V2.RuntimeResultTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.RuntimeResult

  test "normalizes event specs and artifact refs" do
    artifact =
      ArtifactBuilder.build!(
        run_id: "run-1",
        attempt_id: "run-1:1",
        artifact_type: :log,
        key: "github/run-1/review.log",
        content: %{summary: "reviewed"}
      )

    runtime_result =
      RuntimeResult.new!(%{
        output: %{status: "ok"},
        runtime_ref_id: "session-1",
        events: [
          %{
            type: "connector.review.completed",
            stream: :control,
            level: :info,
            payload: %{ok: true},
            runtime_ref_id: "session-1"
          }
        ],
        artifacts: [artifact]
      })

    assert runtime_result.output == %{status: "ok"}
    assert runtime_result.runtime_ref_id == "session-1"

    assert [%{type: "connector.review.completed", runtime_ref_id: "session-1"}] =
             runtime_result.events

    assert runtime_result.artifacts == [artifact]
  end

  test "rejects non-map event payloads" do
    assert_raise ArgumentError, ~r/event payload must be a map/, fn ->
      RuntimeResult.new!(%{
        output: %{status: "bad"},
        events: [%{type: "connector.review.completed", payload: "bad"}]
      })
    end
  end
end
