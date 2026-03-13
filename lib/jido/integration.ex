defmodule Jido.Integration do
  @moduledoc """
  Jido Integration — connector control plane for the Jido ecosystem.

  `jido_integration` provides the shared control plane for optional connector
  packages across runtime classes. It standardizes:

  - **Manifest schema** — connector metadata, capability declarations, version info
  - **Auth runtime** — `Auth.Server` owns install, callback, refresh, and scope lifecycle
  - **Host bridge** — `Auth.Bridge` integrates host routing and tenancy around that engine
  - **Operation envelope** — standardized request/response contracts
  - **Trigger boundary** — webhook ingress, event dispatch
  - **Error taxonomy** — retryability classes, error codes
  - **Policy enforcement** — rate limiting, sandbox isolation, scope checks
  - **Conformance** — validation profiles (mvp_foundation, bronze, silver, gold)
  - **Registry** — connector discovery, lookup, cache

  ## Architecture

  The integration platform does NOT collapse all integrations into one runtime
  abstraction. It keeps domain runtimes intact and standardizes one control
  plane across them.

      Symphony / apps
        -> jido_integration
          -> connector manifest / auth runtime / host bridge / trigger / conformance / policy
          -> optional connector packages

      Core runtime beneath:
        -> jido / jido_signal / jido_action

  ## Runtime Assembly Baseline

  The root `:jido_integration` OTP application starts shared singleton-style
  services such as `Registry`, `Auth.Server`, `Webhook.Router`, and
  `Webhook.Dedupe`.

  It intentionally does not auto-start `Dispatch.Consumer`.

  Webhook ingress is consumer-backed, but dispatch is currently a host-owned
  runtime role. Host applications choose consumer topology, store adapters,
  retry settings, and callback registration, then pass the chosen consumer to
  `Webhook.Ingress.process/2`.

  ## Quick Start

      # Look up a registered connector
      {:ok, adapter} = Jido.Integration.Registry.lookup("acme_crm")

      # Get its manifest
      manifest = adapter.manifest()

      # Execute an operation
      envelope = Jido.Integration.Operation.Envelope.new("acme_crm.sync", %{
        "tenant_id" => "acme"
      })
      {:ok, result} = Jido.Integration.execute(adapter, envelope)
  """

  alias Jido.Integration.{Execution, Operation, Registry}

  @doc """
  Execute an operation against a registered connector adapter.

  Validates the operation envelope against the adapter's manifest,
  checks auth scopes, applies gateway policy, then delegates to
  the adapter's `run/3` callback.
  """
  @spec execute(module(), Operation.Envelope.t(), keyword()) ::
          {:ok, Operation.Result.t()} | {:error, Jido.Integration.Error.t()}
  def execute(adapter, %Operation.Envelope{} = envelope, opts \\ []) do
    Execution.execute(adapter, envelope, opts)
  end

  @doc """
  Look up a connector adapter by its manifest ID.
  """
  @spec lookup(String.t()) :: {:ok, module()} | {:error, Jido.Integration.Error.t()}
  def lookup(connector_id) do
    Registry.lookup(connector_id)
  end

  @doc """
  List all registered connector adapters.
  """
  @spec list_connectors() :: [map()]
  def list_connectors do
    Registry.list()
  end
end
