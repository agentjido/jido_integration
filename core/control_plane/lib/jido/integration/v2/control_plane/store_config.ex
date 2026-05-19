defmodule Jido.Integration.V2.ControlPlane.StoreConfig do
  @moduledoc """
  Control-plane store reset service behind the public facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate reset!(), to: ServiceCore
end
