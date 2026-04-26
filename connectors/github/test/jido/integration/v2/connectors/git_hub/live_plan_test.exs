defmodule Jido.Integration.V2.Connectors.GitHub.LivePlanTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub.LivePlan

  test "uses the first existing issue when the read repo is already seeded" do
    spec = %{
      repo: "agentjido/jido_integration_v2",
      write_repo: "agentjido/jido_integration_v2_sandbox"
    }

    issues = [%{issue_number: 7}, %{issue_number: 9}]

    assert {:existing, target} = LivePlan.all_read_target(spec, issues)
    assert target.repo == spec.repo
    assert target.issue_number == 7
    assert target.source == :existing_issue
  end

  test "bootstraps the write repo when the read repo has no issues" do
    spec = %{
      repo: "agentjido/jido_integration_v2",
      write_repo: "agentjido/jido_integration_v2_sandbox"
    }

    assert {:bootstrap, target} = LivePlan.all_read_target(spec, [])
    assert target.repo == spec.write_repo
    assert target.reason == :missing_read_issue
  end
end
