defmodule Jido.Integration.V2.Connectors.Notion.Build.DependencyResolver do
  @moduledoc false

  def notion_sdk(opts \\ []) do
    {:notion_sdk, "~> 0.2.0", opts}
  end
end
