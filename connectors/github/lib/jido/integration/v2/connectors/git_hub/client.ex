defmodule Jido.Integration.V2.Connectors.GitHub.Client do
  @moduledoc false

  @callback list_issues(String.t(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback fetch_issue(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback create_issue(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback update_issue(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback label_issue(String.t(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback close_issue(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback create_comment(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback update_comment(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
end
