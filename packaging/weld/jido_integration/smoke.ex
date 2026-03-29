defmodule Jido.Integration.Package.Smoke do
  def discovery_snapshot do
    %{
      connectors: Jido.Integration.V2.connectors(),
      capabilities: Jido.Integration.V2.capabilities(),
      projected_catalog_entries: Jido.Integration.V2.projected_catalog_entries()
    }
  end
end
