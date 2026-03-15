defmodule Jido.Integration.V2.Connectors.GitHub do
  @moduledoc """
  Thin direct GitHub connector package backed by `github_ex`.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Connectors.GitHub.CapabilityCatalog
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "github",
      capabilities: CapabilityCatalog.published_capabilities(),
      metadata: %{
        provider_sdk: :github_ex,
        published_slice: :a0_issue_workflows
      }
    })
  end
end
