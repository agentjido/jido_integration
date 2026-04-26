# Jido Integration V2 GitHub Connector

Thin direct GitHub connector package backed by `github_ex`, with deterministic
offline tests and package-local, opt-in live proofs.

This connector stays on the direct provider-SDK path and does not inherit
session or stream runtime-kernel coupling merely because the repo also ships
non-direct capability families.

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
- supported auth profiles:
  - `personal_access_token` as the default manual or external-secret profile
  - `oauth_user` as the browser OAuth profile
- the manifest is the authored source of truth for `supported_profiles`,
  install modes, and reauth posture; nothing is inferred from `github_ex`
  helper defaults
- connector-wide management modes: `[:external_secret, :hosted, :manual]`
- durable secret fields union:
  `["access_token", "refresh_token"]`
- lease fields union:
  `["access_token"]`
- install posture is explicit by profile:
  - `personal_access_token` supports manual token entry or external-secret
    completion with no callback
  - `oauth_user` supports browser OAuth plus hosted or manual callback
    completion with state correlation
- reauth is published only for `oauth_user`
- the connector mints short-lived credential leases and builds `GitHubEx.Client`
  instances from those leases only
- the live execution path is
  `Jido.Integration.V2 -> DirectRuntime -> connector -> github_ex -> pristine`
- the current authored capability slice requires the GitHub `repo` scope
- hosted webhook routing stays out of this package and lives above the direct
  connector contract

## Capability Surface

The connector publishes these direct runtime capabilities:

- `github.check_runs.list_for_ref`
- `github.issue.list`
- `github.issue.fetch`
- `github.issue.create`
- `github.issue.update`
- `github.issue.label`
- `github.issue.close`
- `github.comment.create`
- `github.comment.update`
- `github.commit.statuses.get_combined`
- `github.commit.statuses.list`
- `github.commits.list`
- `github.pr.create`
- `github.pr.fetch`
- `github.pr.list`
- `github.pr.update`
- `github.pr.reviews.list`
- `github.pr.review_comments.list`
- `github.pr.review.create`
- `github.pr.review_comment.create`

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
- `check_run_list`
- `commit_status_combined_fetch`
- `commit_status_list`
- `commit_list`
- `pull_request_create`
- `pull_request_fetch`
- `pull_request_list`
- `pull_request_update`
- `pull_request_review_list`
- `pull_request_review_comment_list`
- `pull_request_review_create`
- `pull_request_review_comment_create`

That common layer now projects into:

- the derived executable entry catalog used by the runtime and conformance seam
- generated actions under `lib/jido/integration/v2/connectors/git_hub/generated/actions.ex`
- a generated plugin bundle at `lib/jido/integration/v2/connectors/git_hub/generated/plugin.ex`

Those generated outputs are derivative only. They stay pinned to the authored
common operation specs and do not become a second authoring plane for GitHub
inventory or auth behavior.

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
common surface is intentionally limited to issue, comment, PR, review, status,
check-run, and commit evidence workflows that are meaningfully reusable across
providers.

PR outputs include GitHub evidence URLs such as `html_url`, `diff_url`,
`patch_url`, `commits_url`, and `review_comments_url`. Commit and status
capabilities expose normalized evidence summaries. The connector does not
publish the generated `github_ex` compare endpoint in this slice because the
SDK path guard rejects the triple-dot compare separator before transport; PR and
commit evidence refs cover the product parity need without publishing a
provider call that cannot be live-tested safely.

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

For local multi-repo development, the connector resolves `github_ex` from a
sibling checkout when it exists and falls back to Hex otherwise. The package
does not carry Git fallback wiring for that SDK or a connector-local vendored
`deps/` tree.

The root monorepo gates use that same deterministic surface. Live proofs are
not part of default `mix test`, `mix monorepo.test`, or `mix ci`.

From the workspace root, the connector should also pass the root acceptance
surface:

```bash
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

The current package-local live scripts exercise the default
`personal_access_token` profile. The published manifest also supports the
`oauth_user` profile for hosted or manually completed OAuth installs without
adding OAuth control endpoints to the invoke surface.

Use the package-local wrapper with typed arguments:

```bash
cd connectors/github
scripts/live_acceptance.sh all --repo owner/repo --write-repo owner/sandbox-repo
```

`all` runs one combined live proof. If the read repo does not already have an
issue, the combined flow bootstraps the writable repo with a temporary issue
and reuses the provider-returned issue number for the read and write steps.

```bash
cd connectors/github
scripts/live_acceptance.sh auth
```

```bash
cd connectors/github
scripts/live_acceptance.sh read --repo owner/repo
```

`read` stays strict on purpose. It still needs an existing issue in the target
repo. PR read evidence is discovered by listing pull requests; if no PR exists,
the proof reports the PR read branch as not exercised instead of accepting a
caller-supplied PR number.

```bash
cd connectors/github
scripts/live_acceptance.sh write --write-repo owner/sandbox-repo
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
