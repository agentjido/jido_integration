defmodule Jido.Integration.Adapter do
  @moduledoc """
  Behaviour defining the connector adapter contract.

  Every connector must implement this behaviour. The adapter is the
  boundary between the integration control plane and the actual
  service/protocol being integrated.

  ## Required Callbacks

  - `id/0` — returns the globally unique connector ID (string)
  - `manifest/0` — returns the connector's `Manifest` struct
  - `validate_config/1` — validates connector-specific configuration
  - `health/1` — checks the health of a connection

  ## Optional Callbacks

  - `init/1` — initialize adapter state
  - `run/3` — execute an operation
  - `handle_trigger/2` — process an inbound trigger event

  ## Example

      defmodule MyApp.Connectors.GitHub do
        @behaviour Jido.Integration.Adapter

        @impl true
        def id, do: "github"

        @impl true
        def manifest do
          Jido.Integration.Manifest.new!(%{...})
        end

        @impl true
        def validate_config(config) do
          # validate config map
          {:ok, config}
        end

        @impl true
        def health(_opts) do
          {:ok, %{status: :healthy}}
        end

        @impl true
        def run("list_issues", args, opts) do
          # call GitHub API
          {:ok, %{issues: [...]}}
        end
      end
  """

  alias Jido.Integration.{Error, Manifest}

  @doc "Returns the globally unique connector identifier (string, not atom)."
  @callback id() :: String.t()

  @doc "Returns the connector manifest."
  @callback manifest() :: Manifest.t()

  @doc "Validates connector-specific configuration."
  @callback validate_config(config :: map()) :: {:ok, map()} | {:error, Error.t()}

  @doc "Checks the health of a connection."
  @callback health(opts :: keyword()) :: {:ok, map()} | {:error, Error.t()}

  @doc "Initialize adapter state. Called on first use or registration."
  @callback init(opts :: keyword()) :: {:ok, term()} | {:error, Error.t()}

  @doc "Execute a named operation with arguments."
  @callback run(operation_id :: String.t(), args :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @doc "Handle an inbound trigger event (webhook, poll result, etc)."
  @callback handle_trigger(trigger_id :: String.t(), payload :: map()) ::
              {:ok, map()} | {:error, Error.t()}

  @optional_callbacks [init: 1, run: 3, handle_trigger: 2]
end
