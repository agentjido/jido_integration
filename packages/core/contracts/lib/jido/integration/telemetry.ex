defmodule Jido.Integration.Telemetry do
  @moduledoc """
  Telemetry naming standard for the Jido integration platform.

  All telemetry events follow the `jido.integration.*` namespace.
  Events are fire-and-forget observational — they do not affect
  control flow.

  ## Standard Events

  ### Operations
  - `jido.integration.operation.started`
  - `jido.integration.operation.succeeded`
  - `jido.integration.operation.failed`

  ### Auth
  - `jido.integration.auth.install.started`
  - `jido.integration.auth.install.succeeded`
  - `jido.integration.auth.install.failed`
  - `jido.integration.auth.token.refreshed`
  - `jido.integration.auth.token.refresh_failed`
  - `jido.integration.auth.scope.mismatch`
  - `jido.integration.auth.scope.gated`
  - `jido.integration.auth.revoked`

  ### Triggers / Webhooks
  - `jido.integration.trigger.received`
  - `jido.integration.webhook.received`
  - `jido.integration.webhook.routed`
  - `jido.integration.webhook.route_failed`
  - `jido.integration.webhook.signature_failed`
  - `jido.integration.webhook.dispatched`

  ### Registry
  - `jido.integration.registry.registered`
  - `jido.integration.registry.unregistered`

  ### Gateway
  - `jido.integration.gateway.admitted`
  - `jido.integration.gateway.backoff`
  - `jido.integration.gateway.shed`

  ### Dispatch Transport
  - `jido.integration.dispatch.enqueued`
  - `jido.integration.dispatch.delivered`
  - `jido.integration.dispatch.retry`
  - `jido.integration.dispatch.dead_lettered`
  - `jido.integration.dispatch.replayed`

  ### Run Execution
  - `jido.integration.run.accepted`
  - `jido.integration.run.started`
  - `jido.integration.run.succeeded`
  - `jido.integration.run.failed`
  - `jido.integration.run.dead_lettered`

  Legacy `jido.integration.dispatch_stub.*` events remain emittable only as a
  temporary compatibility alias during the migration window. They are not part
  of the public standard event list.
  """

  alias Jido.Integration.Auth.Credential
  alias Jido.Integration.Error

  @valid_event_prefixes [
    "jido.integration.operation.",
    "jido.integration.auth.",
    "jido.integration.trigger.",
    "jido.integration.webhook.",
    "jido.integration.registry.",
    "jido.integration.gateway.",
    "jido.integration.artifact.",
    "jido.integration.conformance.",
    "jido.integration.dispatch.",
    "jido.integration.run.",
    "jido.integration.dispatch_stub."
  ]

  @standard_events [
    "jido.integration.operation.started",
    "jido.integration.operation.succeeded",
    "jido.integration.operation.failed",
    "jido.integration.auth.install.started",
    "jido.integration.auth.install.succeeded",
    "jido.integration.auth.install.failed",
    "jido.integration.auth.token.refreshed",
    "jido.integration.auth.token.refresh_failed",
    "jido.integration.auth.scope.mismatch",
    "jido.integration.auth.scope.gated",
    "jido.integration.auth.revoked",
    "jido.integration.auth.rotated",
    "jido.integration.auth.rotation_overdue",
    "jido.integration.trigger.received",
    "jido.integration.trigger.validated",
    "jido.integration.trigger.rejected",
    "jido.integration.trigger.dispatched",
    "jido.integration.trigger.duplicate",
    "jido.integration.trigger.retry_scheduled",
    "jido.integration.trigger.dead_lettered",
    "jido.integration.trigger.checkpoint_committed",
    "jido.integration.webhook.received",
    "jido.integration.webhook.routed",
    "jido.integration.webhook.route_failed",
    "jido.integration.webhook.signature_failed",
    "jido.integration.webhook.dispatched",
    "jido.integration.registry.registered",
    "jido.integration.registry.unregistered",
    "jido.integration.gateway.admitted",
    "jido.integration.gateway.backoff",
    "jido.integration.gateway.shed",
    "jido.integration.dispatch.enqueued",
    "jido.integration.dispatch.delivered",
    "jido.integration.dispatch.retry",
    "jido.integration.dispatch.dead_lettered",
    "jido.integration.dispatch.replayed",
    "jido.integration.run.accepted",
    "jido.integration.run.started",
    "jido.integration.run.succeeded",
    "jido.integration.run.failed",
    "jido.integration.run.dead_lettered",
    "jido.integration.artifact.chunk_emitted",
    "jido.integration.artifact.complete",
    "jido.integration.artifact.checksum_failed",
    "jido.integration.artifact.retransmit_requested",
    "jido.integration.artifact.gc_executed",
    "jido.integration.conformance.suite_started",
    "jido.integration.conformance.suite_completed"
  ]

  @legacy_alias_events [
    "jido.integration.dispatch_stub.accepted",
    "jido.integration.dispatch_stub.started",
    "jido.integration.dispatch_stub.succeeded",
    "jido.integration.dispatch_stub.failed",
    "jido.integration.dispatch_stub.dead_lettered"
  ]

  @emittable_events @standard_events ++ @legacy_alias_events

  @event_atoms Map.new(@emittable_events, fn event_name ->
                 {event_name, event_name |> String.split(".") |> Enum.map(&String.to_atom/1)}
               end)

  @doc "Returns the list of standard telemetry event names."
  @spec standard_events() :: [String.t()]
  def standard_events, do: @standard_events

  @doc "Checks if a telemetry event name follows the naming standard."
  @spec valid_event?(String.t()) :: boolean()
  def valid_event?(event_name) when is_binary(event_name) do
    Enum.any?(@valid_event_prefixes, &String.starts_with?(event_name, &1))
  end

  @doc "Checks if an event name is in the standard event list."
  @spec standard_event?(String.t()) :: boolean()
  def standard_event?(event_name), do: event_name in @standard_events

  @doc """
  Emit a telemetry event in the jido.integration namespace.

  Converts the dot-separated event name to the Erlang telemetry
  atom list format. Migration-only compatibility aliases may also be emitted,
  but they are intentionally excluded from `standard_events/0`.
  """
  @spec emit(String.t(), map(), map()) :: :ok | {:error, Error.t()}
  def emit(event_name, measurements \\ %{}, metadata \\ %{}) do
    case Map.fetch(@event_atoms, event_name) do
      {:ok, event} ->
        :telemetry.execute(event, sanitize_map(measurements), sanitize_metadata(metadata))
        :ok

      :error ->
        {:error,
         Error.new(:invalid_request, "Unknown telemetry event: #{event_name}",
           code: "telemetry.invalid_event"
         )}
    end
  end

  @doc "Redact telemetry metadata recursively before emission."
  @spec sanitize_metadata(map()) :: map()
  def sanitize_metadata(metadata) when is_map(metadata), do: sanitize_map(metadata)

  defp sanitize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, sanitize_value(key, value)} end)
  end

  defp sanitize_value(_key, %Credential{} = credential), do: Credential.redact(credential)

  defp sanitize_value(key, value) when is_map(value) do
    if sensitive_key?(key), do: redacted(), else: sanitize_map(value)
  end

  defp sanitize_value(key, value) when is_list(value) do
    if sensitive_key?(key) do
      redacted()
    else
      Enum.map(value, &sanitize_value(key, &1))
    end
  end

  defp sanitize_value(key, value) do
    if sensitive_key?(key), do: redacted(), else: value
  end

  defp sensitive_key?(key) do
    normalized =
      key
      |> to_string()
      |> String.downcase()

    Enum.any?(
      [
        "access_token",
        "refresh_token",
        "token",
        "authorization",
        "secret",
        "secret_ref",
        "client_secret",
        "key",
        "credential",
        "raw_body",
        "code_verifier"
      ],
      &String.contains?(normalized, &1)
    )
  end

  defp redacted, do: "***REDACTED***"
end
