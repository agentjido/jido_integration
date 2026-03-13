# Jido Integration V2 GitHub Connector

Deterministic direct GitHub connector package.

Proves:

- direct capability publishing against the shared `RuntimeResult` substrate
- `Jido.Action`-backed execution for deterministic issue and comment operations
- package-local provider and client abstractions with a deterministic default
- connector-specific review events plus one durable artifact ref per run
- lease-bound auth handling with redacted `auth_binding` digests
- explicit policy posture for environment and sandbox tool allowlists

## Capability Surface

The connector publishes these direct capabilities:

- `github.issue.list`
- `github.issue.fetch`
- `github.issue.create`
- `github.issue.update`
- `github.issue.label`
- `github.issue.close`
- `github.comment.create`
- `github.comment.update`

All current direct capabilities require the GitHub `repo` scope. The v2
deterministic slice does not model public-repo versus private-repo visibility,
so the connector keeps the admission rule explicit and conservative.

## Provider Model

The package defaults to the deterministic provider:

- `Jido.Integration.V2.Connectors.GitHub.Provider.Deterministic`

That provider is what the package tests and platform tests exercise. It keeps
the connector offline and repeatable while still emitting connector-specific
events and durable artifact refs.

For live use, point the provider at the live implementation and HTTP client:

```elixir
config :jido_integration_v2_github, Jido.Integration.V2.Connectors.GitHub.Provider,
  implementation: Jido.Integration.V2.Connectors.GitHub.Provider.Live

config :jido_integration_v2_github, Jido.Integration.V2.Connectors.GitHub.Provider.Live,
  client: Jido.Integration.V2.Connectors.GitHub.Client.HTTP
```

The live provider reads `access_token` from the short-lived credential lease,
never from durable review truth.

## Review Surface

Successful runs emit:

- one connector-specific `connector.github.*` event
- one `:tool_output` artifact ref under the `connector_review` store
- output payloads carrying only redacted `auth_binding` digests, not raw tokens

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jido_integration_v2_github` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_v2_github, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_integration_v2_github>.
