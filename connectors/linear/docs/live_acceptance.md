# Linear Live Acceptance

The Linear package-local live proof runs through the public install, lease, and
direct-runtime surface. It does not accept provider object ids from operator
input. Issues, workflow states, comments, and cleanup ids are discovered from
Linear responses during the run.

Exactly one explicit credential source is required:

- `--api-key-stdin` reads a Linear API key from standard input.
- `--api-key-file path` reads a Linear API key from an operator-owned file
  outside the repository.

Examples:

```bash
cd connectors/linear
printf '%s' "$(secret-tool lookup service linear-live-proof)" \
  | scripts/live_acceptance.sh all --api-key-stdin
```

```bash
cd connectors/linear
scripts/live_acceptance.sh read --api-key-file /operator/linear/live-proof-token
```

Modes:

- `auth` completes an API-key install, fetches durable install and connection
  status, requests a short-lived lease, and verifies the lease payload is
  minimized.
- `read` resolves the current user, lists issues, retrieves the first
  discovered issue by provider id, and lists workflow states using the
  discovered team id when one is present.
- `write` lists and retrieves a discovered issue, creates a disposable comment,
  updates that comment, performs a no-op issue state update using the issue's
  current state id from Linear, then deletes the disposable comment through the
  connector-local GraphQL capability.
- `all` runs auth, read, and write in one runtime boot.

Optional typed settings:

```bash
scripts/live_acceptance.sh all \
  --api-key-file /operator/linear/live-proof-token \
  --subject linear-proof-operator \
  --actor-id operator-1 \
  --tenant-id tenant-linear-live \
  --read-limit 10 \
  --timeout-ms 20000
```

The proof intentionally rejects static provider selectors such as issue ids,
comment ids, workflow-state ids, or state ids. Those values must be carried
from source events, provider list/retrieve/create responses, workflow state, or
durable receipts.
