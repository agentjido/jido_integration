defmodule Jido.Integration.Application do
  @moduledoc """
  Default OTP application for the thin root facade package.

  The root application starts the shared runtime services that have a clear
  singleton shape inside this repo:

  - `Jido.Integration.Registry`
  - `Jido.Integration.Auth.Server`
  - `Jido.Integration.Webhook.Router`
  - `Jido.Integration.Webhook.Dedupe`

  It intentionally does not start `Jido.Integration.Dispatch.Consumer`.

  Dispatch is currently a host-owned runtime role because host applications need
  to choose consumer topology, store adapters, retry policy, and callback
  registration explicitly.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Integration.Registry,
      Jido.Integration.Auth.Server,
      Jido.Integration.Webhook.Router,
      Jido.Integration.Webhook.Dedupe
    ]

    opts = [strategy: :one_for_one, name: Jido.Integration.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
