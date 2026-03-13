# GitHub Live Acceptance

This package keeps two separate quality surfaces:

- deterministic CI via `mix test` and the root monorepo gates
- manual, opt-in live proofs via package-local example scripts

The live path exists to prove the current v2 auth and platform boundary against
real GitHub state without contaminating default CI.

## Before You Run It

Prerequisites:

- a GitHub token with the scopes required by the proof mode you intend to run
- one readable repository for the read proof
- one disposable sandbox repository for the write proof
- `gh` authenticated locally if you want token fallback through `gh auth token`

Safety:

- live proofs perform real reads and, in write mode, real writes
- use a sandbox repository for write mode
- the scripts attempt cleanup, but they are still real API calls

## Proof Modes

### Full Acceptance

Command:

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_LIVE_WRITE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO=owner/sandbox-repo \
scripts/live_acceptance.sh all
```

What it proves:

- the auth lifecycle proof
- the read proof surface (`github.issue.list` and `github.issue.fetch`)
- the write proof surface (`github.issue.create`, update, label, comment, and close)

Combined-mode behavior:

- if `JIDO_INTEGRATION_V2_GITHUB_READ_ISSUE_NUMBER` is set, `all` uses that issue
- otherwise `all` first looks for an existing issue in `JIDO_INTEGRATION_V2_GITHUB_REPO`
- if none exists, `all` bootstraps `JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO` by creating
  one issue and reuses it for the read and write steps

Use `all` when you want one end-to-end smoke run without having to pre-seed a
readable repo issue.

### Auth Lifecycle

Command:

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
scripts/live_acceptance.sh auth
```

What it proves:

- `start_install/3` creates durable install truth
- `complete_install/2` binds the GitHub token to durable connection truth
- `request_lease/2` mints a short-lived lease with only `access_token`
- the connector package can drive that lifecycle locally through `Jido.Integration.V2`

### Read-Only Acceptance

Command:

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
scripts/live_acceptance.sh read
```

What it proves:

- auth lifecycle bootstraps a usable `CredentialRef`
- `github.issue.list` runs live through `Jido.Integration.V2.invoke/3`
- `github.issue.fetch` runs live through the same platform path
- runtime output, events, and artifact refs do not leak the raw token

Notes:

- use a repo with at least one issue, or set `JIDO_INTEGRATION_V2_GITHUB_READ_ISSUE_NUMBER`
- for a one-command smoke run that can bootstrap its own issue, use `scripts/live_acceptance.sh all`
- the connector still requires the `repo` scope for the live read proof because
  that is the current published capability contract

### Write Acceptance

Command:

```bash
cd connectors/github
JIDO_INTEGRATION_V2_GITHUB_LIVE=1 \
JIDO_INTEGRATION_V2_GITHUB_LIVE_WRITE=1 \
JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo \
JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO=owner/sandbox-repo \
scripts/live_acceptance.sh write
```

What it proves:

- `github.issue.create`
- `github.issue.fetch`
- `github.issue.update`
- `github.issue.label`
- `github.comment.create`
- `github.comment.update`
- `github.issue.close`

Use a sandbox repository. The script attempts to close the created issue even
if a later proof step fails, but it still performs real writes.

## Environment Contract

Required for all live proofs:

- `JIDO_INTEGRATION_V2_GITHUB_LIVE=1`

Required for read and write proofs:

- `JIDO_INTEGRATION_V2_GITHUB_REPO=owner/repo`

Required for write proofs:

- `JIDO_INTEGRATION_V2_GITHUB_LIVE_WRITE=1`

Required for `all`:

- the same environment contract as write proofs

Optional overrides:

- `JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO=owner/repo`
  Defaults to `JIDO_INTEGRATION_V2_GITHUB_REPO`.
- `JIDO_INTEGRATION_V2_GITHUB_TOKEN`
  Preferred explicit token source.
- `GITHUB_TOKEN`
  Fallback token source.
- `JIDO_INTEGRATION_V2_GITHUB_READ_ISSUE_NUMBER`
  Forces the issue number used by the read-only fetch proof.
- `JIDO_INTEGRATION_V2_GITHUB_SUBJECT`
  Defaults to `github-live-proof`.
- `JIDO_INTEGRATION_V2_GITHUB_ACTOR_ID`
  Defaults to `github-live-proof`.
- `JIDO_INTEGRATION_V2_GITHUB_TENANT_ID`
  Defaults to `tenant-github-live`.
- `JIDO_INTEGRATION_V2_GITHUB_WRITE_LABEL`
  Defaults to `jido-live-acceptance`.
- `JIDO_INTEGRATION_V2_GITHUB_API_BASE_URL`
  Optional GitHub Enterprise API base URL.
- `JIDO_INTEGRATION_V2_GITHUB_TIMEOUT_MS`
  Optional HTTP timeout override.

If neither `JIDO_INTEGRATION_V2_GITHUB_TOKEN` nor `GITHUB_TOKEN` is set, the
scripts fall back to `gh auth token`.

## Validation Boundary

These live proofs are package-local and opt-in by design.

They are not part of:

- `mix test`
- `mix monorepo.test`
- `mix ci`
- default root connector conformance

## Implementation Files

- `examples/support/live_support.exs`
- `examples/github_live_all_acceptance.exs`
- `examples/github_auth_lifecycle.exs`
- `examples/github_live_read_acceptance.exs`
- `examples/github_live_write_acceptance.exs`
- `scripts/live_acceptance.sh`

These files are package-local by design. The repo root remains tooling-only.
