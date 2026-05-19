defmodule Jido.Integration.V2.Auth.StoreConfig do
  @moduledoc """
  Auth store and runtime-handler configuration facade.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate reset!(), to: ServiceCore
end
