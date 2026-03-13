# Live Examples

This guide explains exactly how live examples are expected to work in this
repo.

## Rules

- default `mix test` stays offline
- live-provider behavior is always opt-in
- write paths require a second explicit opt-in
- docs must describe real setup steps, not implied or simulated ones

## Current Live Coverage

Shipped now:

- GitHub live auth lifecycle
- GitHub live read-only issue flows
- GitHub live write issue/comment flows

Not shipped yet as a first-class live runbook:

- tunnel-backed public webhook reception from GitHub
- live connector onboarding for providers other than GitHub

That distinction matters. End-user docs should not pretend a live path exists if
the repo does not provide a repeatable flow for it.

## GitHub Read-Only Onboarding

Prerequisites:

- GitHub CLI installed
- `gh auth login` completed, or `GITHUB_TOKEN` exported
- current live example set expects `repo` and `read:org`

Recommended verification:

```bash
gh auth status
gh auth token >/dev/null
```

If needed:

```bash
gh auth refresh -s repo,read:org
```

Run the read-only live acceptance:

```bash
cd packages/connectors/github
JIDO_INTEGRATION_GITHUB_LIVE=1 ./scripts/live_acceptance.sh read
```

What this runs:

- `test/examples/github_auth_lifecycle_test.exs`
- `test/examples/github_integration_test.exs`

What should succeed:

- real credential lifecycle through `Auth.Server`
- durable install start and callback correlation through the runtime-owned auth
  engine
- real issue reads against GitHub
- local webhook normalization through the durable dispatch path

The examples talk directly to `Auth.Server` because they prove the canonical
engine. In a production host app, `Auth.Bridge` would own the browser or
callback HTTP boundary and delegate into the same runtime calls. The
`session_state` returned by `start_install/4` is an opaque host payload backed
by a durable install-session record, not an in-memory callback shortcut.

## GitHub Write Onboarding

Additional prerequisites:

- a sandbox repository you own
- `GITHUB_TEST_OWNER`
- `GITHUB_TEST_REPO`

Example:

```bash
cd packages/connectors/github
export GITHUB_TEST_OWNER=your-username
export GITHUB_TEST_REPO=your-sandbox-repo
JIDO_INTEGRATION_GITHUB_LIVE=1 \
JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1 \
./scripts/live_acceptance.sh write
```

What this proves:

- create issue
- fetch issue
- update issue
- label issue
- create comment
- update comment
- close issue

Use a sandbox repository. The write flow mutates real GitHub state by design.

## Troubleshooting

If live read-only tests are skipped or fail early:

- confirm `gh auth status`
- confirm `gh auth token` returns a token
- or export `GITHUB_TOKEN`

If live write tests fail early:

- confirm `GITHUB_TEST_OWNER`
- confirm `GITHUB_TEST_REPO`
- confirm the token can write to that repository

If you want only deterministic behavior:

```bash
cd packages/connectors/github
mix test
```

## Other Examples

For deterministic substrate examples, stay at the repo root:

```bash
mix test test/examples/
mix test test/reference_apps/devops_incident_response_test.exs
```

Those are the recommended first runs for anyone onboarding to the repo itself.
