# GitHub Live Acceptance

This package keeps two separate quality surfaces:

- deterministic CI via `mix test` and the root monorepo gates
- manual, opt-in live proofs via package-local example scripts

The live path exists to prove the current v2 auth and platform boundary against
real GitHub state without contaminating default CI.

For this package, "live" means the connector switches its lease-bound
`GitHubEx.Client` configuration from the deterministic fixture transport to the
real SDK transport. The HTTP lane still lives in `github_ex`, not in
`jido_integration`.

## No Env Contract

The live proof does not read process environment variables and does not accept
static issue, PR, comment, review, workflow, or commit identifiers from the
operator. Inputs are typed command-line arguments. Provider object identity is
discovered through connector list/read operations, created in the disposable
write repo, or carried forward from provider responses.

## Before You Run It

Prerequisites:

- `gh` installed and authenticated with `gh auth login`
- one readable repository for the read proof
- one disposable sandbox repository for the write proof

Safety:

- live proofs perform real reads and, in write mode, real writes
- use a sandbox repository for write mode
- the scripts attempt cleanup, but they are still real API calls

## Proof Modes

### Full Acceptance

Command:

```bash
cd connectors/github
scripts/live_acceptance.sh all --repo owner/repo --write-repo owner/sandbox-repo
```

What it proves:

- the auth lifecycle proof
- the read proof surface, including issue list/fetch, commit evidence, statuses, checks, and PR discovery
- the write proof surface, including issue create, fetch, update, label, comment create/update, close, repository metadata fetch, disposable branch create/delete, scratch file upsert, disposable PR create/fetch/review/list evidence/close

Combined-mode behavior:

- `all` first lists issues in the read repo
- if an issue exists, its provider-returned number is carried into the fetch proof
- if no issue exists, `all` creates a temporary issue in the writable repo and carries that returned issue number into the read and write steps
- PR read proof lists pull requests in the read repo and exercises fetch/reviews/comments only when a PR is discovered
- PR write proof fetches the writable repository, discovers the default branch head commit, creates a unique disposable branch, commits a scratch file, opens a disposable PR, publishes a comment review, reads the PR/review evidence, closes the PR, and deletes the branch

Use `all` when you want one end-to-end smoke run without having to pre-seed a
readable repo issue.

### Auth Lifecycle

Command:

```bash
cd connectors/github
scripts/live_acceptance.sh auth
```

What it proves:

- `start_install/3` creates durable install truth
- `complete_install/2` binds the GitHub token returned by `gh auth token` to durable connection truth
- `request_lease/2` mints a short-lived lease with only `access_token`
- the connector package can drive that lifecycle locally through `Jido.Integration.V2`

This package-local auth proof currently exercises the default
`personal_access_token` profile. The published manifest also supports an
`oauth_user` profile for browser OAuth plus hosted or manual callback
completion, but that hosted callback lane is not owned by this package-local
script surface.

### Read-Only Acceptance

Command:

```bash
cd connectors/github
scripts/live_acceptance.sh read --repo owner/repo
```

What it proves:

- auth lifecycle bootstraps a usable `CredentialRef`
- `github.issue.list` runs live through `Jido.Integration.V2.invoke/3`
- `github.issue.fetch` runs live using an issue number returned by the list step
- `github.commits.list`, `github.commit.statuses.*`, and `github.check_runs.list_for_ref` run against the discovered head commit
- `github.pr.list` discovers pull requests; when one exists, `github.pr.fetch`, `github.pr.reviews.list`, and `github.pr.review_comments.list` use the discovered PR number
- runtime output, events, and artifact refs do not leak the raw token

Notes:

- use a repo with at least one issue
- for a one-command smoke run that can bootstrap its own issue, use `scripts/live_acceptance.sh all`
- the connector still requires the `repo` scope for the live read proof because that is the current published capability contract

### Write Acceptance

Command:

```bash
cd connectors/github
scripts/live_acceptance.sh write --write-repo owner/sandbox-repo
```

What it proves:

- `github.issue.create`
- `github.issue.fetch`
- `github.issue.update`
- `github.issue.label`
- `github.comment.create`
- `github.comment.update`
- `github.issue.close`
- `github.repo.fetch`
- `github.commits.list`
- `github.git.ref.create`
- `github.contents.upsert`
- `github.pr.create`
- `github.pr.fetch`
- `github.pr.review.create`
- `github.pr.reviews.list`
- `github.pr.review_comments.list`
- `github.pr.update`
- `github.git.ref.delete`

Use a sandbox repository. The script attempts to close the created issue and
pull request and delete the disposable branch if a later proof step fails, but
it still performs real writes.

Identity lifecycle:

- repository identity is the typed `--write-repo owner/repo` argument
- default branch identity comes from `github.repo.fetch`
- base commit identity comes from `github.commits.list` scoped to that default branch
- branch identity is generated uniquely for the run and then carried into `github.git.ref.create`, `github.contents.upsert`, and `github.pr.create`
- scratch commit SHA, PR number, review id, comment id, and cleanup refs come from provider responses and are recorded in the run summary
- the caller cannot provide issue numbers, PR numbers, branch names, commit SHAs, review ids, or comment ids

## Typed Arguments

Accepted arguments:

- `--repo owner/repo`
  Read target for read/all modes.
- `--write-repo owner/repo`
  Disposable write target for write/all modes. Defaults to `--repo` for write/all when omitted.
- `--subject value`
  Install subject label. Defaults to `github-live-proof`.
- `--actor-id value`
  Operator actor id. Defaults to `github-live-proof`.
- `--tenant-id value`
  Tenant id. Defaults to `tenant-github-live`.
- `--write-label value`
  Label applied during write proof. Defaults to `jido-live-acceptance`.
- `--api-base-url url`
  Optional GitHub Enterprise API base URL.
- `--timeout-ms positive_integer`
  Optional HTTP timeout override.

## Validation Boundary

These live proofs are package-local and opt-in by design.

They are not part of:

- `mix test`
- `mix monorepo.test`
- `mix ci`
- default root connector conformance

## Implementation Files

- `lib/jido/integration/v2/connectors/git_hub/live_spec.ex`
- `lib/jido/integration/v2/connectors/git_hub/live_plan.ex`
- `examples/support/live_support.exs`
- `examples/github_live_all_acceptance.exs`
- `examples/github_auth_lifecycle.exs`
- `examples/github_live_read_acceptance.exs`
- `examples/github_live_write_acceptance.exs`
- `scripts/live_acceptance.sh`

These files are package-local by design. The repo root remains tooling-only.
