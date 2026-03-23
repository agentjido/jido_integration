# Jido Integration V2 GitHub Connector

Thin direct GitHub connector package backed by `github_ex`, with deterministic
offline tests and package-local, opt-in live proofs.

Proves:

- direct capability publishing against the shared `RuntimeResult` substrate
- generated `Jido.Action` modules and a connector-level `Jido.Plugin` bundle projected from the authored manifest
- `github_ex`-backed execution through one lease-bound SDK client factory
- package-local deterministic tests through the SDK transport seam
- connector-specific review events plus one durable artifact ref per run
- lease-bound auth handling with redacted `auth_binding` digests
- opt-in live auth, read, and write proofs through `Jido.Integration.V2`

## Runtime And Auth Posture

- runtime family: `:direct`
- public auth binding is `connection_id`
- the connector mints short-lived credential leases and builds `GitHubEx.Client`
  instances from those leases only
- the current authored capability slice requires the GitHub `repo` scope
- hosted webhook routing stays out of this package and lives above the direct
  connector contract

## Capability Surface

The connector publishes these direct runtime capabilities:

- `github.issue.list`
- `github.issue.fetch`
- `github.issue.create`
- `github.issue.update`
- `github.issue.label`
- `github.issue.close`
- `github.comment.create`
- `github.comment.update`

All direct capabilities currently require the GitHub `repo` scope.

These runtime capability ids stay provider-facing on purpose. They are the
stable internal routing ids used by the control plane, conformance layer, and
connector review surface.

The generated consumer surface is a separate, curated common layer. The same
authored operation specs project into these normalized action names:

- `work_item_list`
- `work_item_fetch`
- `work_item_create`
- `work_item_update`
- `work_item_label_add`
- `work_item_close`
- `comment_create`
- `comment_update`

That common layer now projects into:

- the derived executable entry catalog used by the runtime and conformance seam
- generated actions under `lib/jido/integration/v2/connectors/git_hub/generated/actions.ex`
- a generated plugin bundle at `lib/jido/integration/v2/connectors/git_hub/generated/plugin.ex`

The generated actions use the real `Jido.Action` contract with the authored
operation input and output schemas. They resolve `connection_id` from params or
runtime context and then invoke the public integration facade through its typed
request contract. The generated surface does not expose a caller-supplied
invoker override seam.

The authored A0 slice lives in rich `OperationSpec` records inside
`lib/jido/integration/v2/connectors/git_hub/operation_catalog.ex`. Those specs
now declare both:

- the provider-facing runtime capability id
- the normalized `consumer_surface` metadata that decides whether and how the
  operation projects into generated consumer surfaces

This package does not auto-project arbitrary `github_ex` methods. The current
common surface is intentionally limited to issue and comment workflows that are
meaningfully reusable across providers.

The generated plugin uses the real `Jido.Plugin` `actions:` and
`subscriptions/2` surface. In this phase its subscriptions remain empty.

Webhook routing is intentionally not part of this package. Hosted webhook proof
code lives in `apps/devops_incident_response` so the direct connector contract
stays honest.

## Package Verification

Default package tests stay offline and deterministic through the `github_ex`
transport seam. There is no second handwritten GitHub HTTP client inside
`jido_integration`.

```bash
cd connectors/github
mix deps.get
mix compile --warnings-as-errors
mix test
mix docs
```

The root monorepo gates use that same deterministic surface. Live proofs are
not part of default `mix test`, `mix monorepo.test`, or `mix ci`.

From the workspace root, the connector should also pass the root acceptance
surface:

```bash
cd /home/home/p/g/n/jido_integration
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
mix ci
```

## Live Proof Status

Package-local live proofs exist, but they stay opt-in. They always run through
the current v2 auth and platform surface:

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

## SDK Boundary

Runtime requests build `GitHubEx.Client` instances only from Jido-issued
credential leases.

The connector owns:

- authored operation-spec publication and derived executable entry projection
- lease-bound client construction
- SDK method mapping from the public `repo` input shape
- normalized runtime output, events, artifacts, and conformance fixtures

`github_ex` owns:

- provider HTTP execution
- auth header behavior
- retry and rate-limit behavior
- generated REST operation wrappers such as `GitHubEx.Issues.*`

Live proofs override the connector client config to use the real SDK
transport. Offline tests override the transport with fixture responses.
Neither path moves provider HTTP logic back into `jido_integration`.

## Package Boundary

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

- authored operation specs and derived executable catalog:
  `lib/jido/integration/v2/connectors/git_hub/operation_catalog.ex`
- lease-bound client factory: `lib/jido/integration/v2/connectors/git_hub/client_factory.ex`
- generic SDK operation handler: `lib/jido/integration/v2/connectors/git_hub/operation.ex`
- deterministic fixture seam: `lib/jido/integration/v2/connectors/git_hub/fixtures.ex`
- full live proof: `examples/github_live_all_acceptance.exs`
- live auth proof: `examples/github_auth_lifecycle.exs`
- live read proof: `examples/github_live_read_acceptance.exs`
- live write proof: `examples/github_live_write_acceptance.exs`
- live proof wrapper: `scripts/live_acceptance.sh`
- deterministic tests: `test/jido/integration/v2/connectors/git_hub_test.exs`
- operation tests: `test/jido/integration/v2/connectors/git_hub/operation_test.exs`
- client factory tests:
  `test/jido/integration/v2/connectors/git_hub/client_factory_test.exs`
- conformance tests: `test/jido/integration/v2/connectors/git_hub/conformance_test.exs`
- deterministic live gating tests:
  `test/jido/integration/v2/connectors/git_hub/live_env_test.exs`
