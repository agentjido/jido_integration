defmodule Jido.Integration.V2.Connectors.GitHub.LivePlan do
  @moduledoc false

  @spec all_read_target(map(), [map()]) ::
          {:existing, %{repo: String.t(), issue_number: pos_integer(), source: atom()}}
          | {:bootstrap, %{repo: String.t(), reason: atom()}}
  def all_read_target(spec, [%{issue_number: issue_number} | _rest])
      when is_map(spec) and is_integer(issue_number) and issue_number > 0 do
    {:existing,
     %{
       repo: spec.repo,
       issue_number: issue_number,
       source: :existing_issue
     }}
  end

  def all_read_target(spec, issues) when is_map(spec) and is_list(issues) do
    {:bootstrap,
     %{
       repo: spec.write_repo || spec.repo,
       reason: :missing_read_issue
     }}
  end
end
