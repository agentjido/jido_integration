defmodule Jido.Integration.V2.Connectors.Notion do
  @moduledoc """
  Thin direct Notion connector package backed by `notion_sdk`.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Connectors.Notion.CapabilityCatalog
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "notion",
      capabilities: CapabilityCatalog.published_capabilities(),
      metadata: %{
        provider_sdk: :notion_sdk,
        published_slice: :a0_content_publishing
      }
    })
  end
end
