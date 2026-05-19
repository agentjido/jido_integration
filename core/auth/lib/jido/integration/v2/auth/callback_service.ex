defmodule Jido.Integration.V2.Auth.CallbackService do
  @moduledoc """
  Hosted install callback service behind `Jido.Integration.V2.Auth`.
  """

  alias Jido.Integration.V2.Auth.ServiceCore

  defdelegate resolve_install_callback(attrs), to: ServiceCore
end
