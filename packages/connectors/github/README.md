# Jido Integration GitHub

First-party GitHub connector package for `jido_integration`.

This package gives you two distinct modes:

- deterministic local tests by default
- explicit live acceptance against real GitHub state

## Quickstart

### Deterministic Default

```bash
cd packages/connectors/github
mix deps.get
mix compile --warnings-as-errors
mix test
```

This runs:

- adapter tests
- conformance tests
- non-live coverage only

Live tests are excluded unless you opt in.

### Live Read-Only Acceptance

Prerequisites:

- GitHub CLI installed
- `gh auth login` completed, or `GITHUB_TOKEN` exported
- token should include `repo` and `read:org` for the current live example set

Recommended verification:

```bash
gh auth status
gh auth token >/dev/null
```

If needed:

```bash
gh auth refresh -s repo,read:org
```

Run:

```bash
cd packages/connectors/github
JIDO_INTEGRATION_GITHUB_LIVE=1 ./scripts/live_acceptance.sh read
```

This exercises:

- the auth lifecycle example
- live issue reads
- live control-plane execution against GitHub
- webhook ingress through the durable dispatch path using a local payload

### Live Write Acceptance

Additional prerequisites:

- a sandbox repository you can safely mutate
- `GITHUB_TEST_OWNER`
- `GITHUB_TEST_REPO`

Run:

```bash
cd packages/connectors/github
export GITHUB_TEST_OWNER=your-username
export GITHUB_TEST_REPO=your-sandbox-repo
JIDO_INTEGRATION_GITHUB_LIVE=1 \
JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1 \
./scripts/live_acceptance.sh write
```

This exercises real GitHub mutations:

- create issue
- fetch issue
- update issue
- label issue
- create comment
- update comment
- close issue

Use a sandbox repository. The write path is intentionally real.

## What The Package Provides

Operations:

- `github.list_issues`
- `github.fetch_issue`
- `github.create_issue`
- `github.update_issue`
- `github.label_issue`
- `github.close_issue`
- `github.create_comment`
- `github.update_comment`

Trigger support:

- `github.webhook.push`

## Test Modes

### Offline Package Test

```bash
mix test
```

Expected result:

- deterministic pass
- no network access

Package release gate:

```bash
mix compile --warnings-as-errors
mix test
```

### Live Read-Only Test

```bash
JIDO_INTEGRATION_GITHUB_LIVE=1 mix test test/examples/github_auth_lifecycle_test.exs
JIDO_INTEGRATION_GITHUB_LIVE=1 mix test test/examples/github_integration_test.exs
```

Expected result:

- real GitHub auth lifecycle passes
- real issue reads pass

### Live Write Test

```bash
export GITHUB_TEST_OWNER=your-username
export GITHUB_TEST_REPO=your-sandbox-repo
JIDO_INTEGRATION_GITHUB_LIVE=1 \
JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1 \
mix test test/examples/github_integration_test.exs
```

Expected result:

- issue lifecycle tests pass against your sandbox repo

## Credentials And Auth

Live examples resolve credentials in this order:

1. `GITHUB_TOKEN`
2. `gh auth token`

The examples still drive state through `Auth.Server`. That means the live
examples exercise connector operations through the same control-plane path used
by the substrate, rather than bypassing it.

That includes the OAuth-style install and callback handshake: `start_install`
creates a durable install-session record, `session_state` is the opaque host
payload that carries the callback handle, and the callback is accepted exactly
once even if `Auth.Server` restarts between those two steps.

In a production host app, `Auth.Bridge` would own the HTTP routing, actor and
tenant resolution, and runtime selection around that same engine. The host does
not reimplement install, callback, or refresh semantics.

## Webhook Behavior

The current package proves webhook handling through the substrate using:

1. `Webhook.Router`
2. `Webhook.Ingress`
3. `Dispatch.Consumer`
4. an explicit callback module

What is honest to say today:

- the package proves the durable ingress and dispatch path
- the package does not yet ship a first-class public tunnel setup walkthrough
  for receiving real GitHub webhooks from the internet

## Troubleshooting

If read-only live tests are skipped:

- check `gh auth status`
- check `gh auth token`
- or export `GITHUB_TOKEN`

If read-only tests authenticate but fail on permissions:

- refresh GitHub CLI scopes with `gh auth refresh -s repo,read:org`
- or provide a `GITHUB_TOKEN` with those scopes

If write tests fail early:

- check `GITHUB_TEST_OWNER`
- check `GITHUB_TEST_REPO`
- confirm your token can write to that repository

If you only want deterministic verification:

```bash
mix test
```

## Files To Read

- live example:
  `examples/github_integration.ex`
- auth-focused live example:
  `examples/github_auth_lifecycle.ex`
- deterministic adapter tests:
  `test/jido/integration/connectors/github_test.exs`
- live acceptance wrapper:
  `scripts/live_acceptance.sh`
