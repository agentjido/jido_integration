# Jido Integration V2 GitHub Connector

Deterministic direct GitHub connector package with package-local, opt-in live
proofs.

Proves:

- direct capability publishing against the shared `RuntimeResult` substrate
- `Jido.Action`-backed execution for deterministic issue and comment operations
- package-local provider and client abstractions with a deterministic default
- connector-specific review events plus one durable artifact ref per run
- lease-bound auth handling with redacted `auth_binding` digests
- opt-in live auth, read, and write proofs through `Jido.Integration.V2`

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

All direct capabilities currently require the GitHub `repo` scope.

## Deterministic CI

Default package tests stay offline and deterministic.

```bash
cd connectors/github
mix test
```

The root monorepo gates use that same deterministic surface. Live proofs are not
part of default `mix test`, `mix monorepo.test`, or `mix ci`.

## Live Proofs

Live proofs stay package-local and opt-in. They always run through the current
v2 auth and platform surface:

- `Jido.Integration.V2.start_install/3`
- `Jido.Integration.V2.complete_install/2`
- `Jido.Integration.V2.request_lease/2`
- `Jido.Integration.V2.invoke/3`

Use the package-local wrapper:

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
scripts/live_acceptance.sh auth
```

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
scripts/live_acceptance.sh read
```

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_LIVE_WRITE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO=owner/sandbox-repo \
scripts/live_acceptance.sh write
```

Read the detailed runbook in [`docs/live_acceptance.md`](docs/live_acceptance.md).

## Provider Model

The package defaults to the deterministic provider:

- `Jido.Integration.V2.Connectors.GitHub.Provider.Deterministic`

The live proof scripts switch the provider to:

- `Jido.Integration.V2.Connectors.GitHub.Provider.Live`
- `Jido.Integration.V2.Connectors.GitHub.Client.HTTP`

The live provider reads `access_token` from the short-lived credential lease,
never from durable review truth.

## Review Surface

Successful runs emit:

- one connector-specific `connector.github.*` event
- one `:tool_output` artifact ref under the `connector_review` store
- output payloads carrying only redacted `auth_binding` digests, not raw tokens

## Files

- live auth proof: `examples/github_auth_lifecycle.exs`
- live read proof: `examples/github_live_read_acceptance.exs`
- live write proof: `examples/github_live_write_acceptance.exs`
- live proof wrapper: `scripts/live_acceptance.sh`
- deterministic tests: `test/jido/integration/v2/connectors/git_hub_test.exs`
- deterministic live gating tests:
  `test/jido/integration/v2/connectors/git_hub/live_env_test.exs`
