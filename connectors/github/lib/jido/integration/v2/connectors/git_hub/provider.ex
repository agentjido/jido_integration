defmodule Jido.Integration.V2.Connectors.GitHub.Provider do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport
  alias Jido.Integration.V2.Connectors.GitHub.Provider.Deterministic

  @callback list_issues(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback fetch_issue(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_issue(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_issue(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback label_issue(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback close_issue(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_comment(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_comment(map(), map()) :: {:ok, map()} | {:error, term()}

  @spec execute(ActionSupport.operation(), map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(operation, params, context) do
    provider = implementation()

    case operation do
      :issue_list -> provider.list_issues(params, context)
      :issue_fetch -> provider.fetch_issue(params, context)
      :issue_create -> provider.create_issue(params, context)
      :issue_update -> provider.update_issue(params, context)
      :issue_label -> provider.label_issue(params, context)
      :issue_close -> provider.close_issue(params, context)
      :comment_create -> provider.create_comment(params, context)
      :comment_update -> provider.update_comment(params, context)
    end
  end

  @spec implementation() :: module()
  def implementation do
    :jido_integration_v2_github
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:implementation, Deterministic)
  end
end
