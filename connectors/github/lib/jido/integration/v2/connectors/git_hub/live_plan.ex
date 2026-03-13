defmodule Jido.Integration.V2.Connectors.GitHub.LivePlan do
  @moduledoc false

  @spec all_read_target(map(), [map()]) ::
          {:existing, %{repo: String.t(), issue_number: pos_integer(), source: atom()}}
          | {:bootstrap, %{repo: String.t(), reason: atom()}}
  def all_read_target(spec, issues) when is_map(spec) and is_list(issues) do
    cond do
      positive_integer?(spec.read_issue_number) ->
        {:existing,
         %{
           repo: spec.repo,
           issue_number: spec.read_issue_number,
           source: :explicit_issue_number
         }}

      match?(
        [%{issue_number: issue_number} | _rest]
        when is_integer(issue_number) and issue_number > 0,
        issues
      ) ->
        [%{issue_number: issue_number} | _rest] = issues

        {:existing,
         %{
           repo: spec.repo,
           issue_number: issue_number,
           source: :existing_issue
         }}

      true ->
        {:bootstrap,
         %{
           repo: spec.write_repo || spec.repo,
           reason: :missing_read_issue
         }}
    end
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0
end
