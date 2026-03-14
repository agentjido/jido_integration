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

Webhook routing is intentionally not part of this package. Hosted webhook proof
code lives in `apps/devops_incident_response` so the direct connector contract
stays honest.

## Deterministic CI

Default package tests stay offline and deterministic.

```bash
cd connectors/github
mix test
```

The root monorepo gates use that same deterministic surface. Live proofs are not
part of default `mix test`, `mix monorepo.test`, or `mix ci`.

The connector should also pass the root conformance surface:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
```

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
JIDO_INTEGRATION_V2_GITHUB_LIVE_WRITE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO=owner/sandbox-repo \
scripts/live_acceptance.sh all
```

`all` runs one combined live proof. If the read repo does not already have an
issue and `JIDO_INTEGRATION_V2_GITHUB_READ_ISSUE_NUMBER` is not set, the
combined flow bootstraps the writable repo with a temporary issue and reuses it
for the read and write steps.

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
scripts/live_acceptance.sh auth
```

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
scripts/live_acceptance.sh read
```

`read` stays strict on purpose. It still needs an existing issue in the target
repo or `JIDO_INTEGRATION_V2_GITHUB_READ_ISSUE_NUMBER` set explicitly.

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

- `lib/jido/integration/v2/connectors/git_hub/provider/deterministic.ex`

The live proof scripts switch the provider to:

- `lib/jido/integration/v2/connectors/git_hub/provider/live.ex`
- `lib/jido/integration/v2/connectors/git_hub/client/http.ex`

The live provider reads `access_token` from the short-lived credential lease,
never from durable review truth.

## Architecture Boundary

This package owns direct GitHub capability execution only.

It does not own:

- hosted webhook route registration
- dispatch-runtime handlers
- reference-app proof composition

Those higher-level concerns stay in app packages so this connector remains a
reusable direct integration deliverable.

## Review Surface

Successful runs emit:

- one connector-specific `connector.github.*` event
- one `:tool_output` artifact ref under the `connector_review` store
- output payloads carrying only redacted `auth_binding` digests, not raw tokens

## Files

- full live proof: `examples/github_live_all_acceptance.exs`
- live auth proof: `examples/github_auth_lifecycle.exs`
- live read proof: `examples/github_live_read_acceptance.exs`
- live write proof: `examples/github_live_write_acceptance.exs`
- live proof wrapper: `scripts/live_acceptance.sh`
- deterministic tests: `test/jido/integration/v2/connectors/git_hub_test.exs`
- deterministic live gating tests:
  `test/jido/integration/v2/connectors/git_hub/live_env_test.exs`
