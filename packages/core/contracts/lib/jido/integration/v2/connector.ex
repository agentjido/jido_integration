defmodule Jido.Integration.V2.Connector do
  @moduledoc """
  Behaviour for connector packages that publish manifests.
  """

  alias Jido.Integration.V2.Manifest

  @callback manifest() :: Manifest.t()
end
