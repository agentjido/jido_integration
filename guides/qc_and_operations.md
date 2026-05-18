# Jido Integration QC And Operations

## Local Commands

```bash
mix deps.get
mix ci
```

Use package-local tests for connector/runtime/auth changes, then root `mix ci`
before commit. When a change crosses repo boundaries, also run the relevant
StackLab connector, tenant, and proof-matrix checks.

## Scanner And Proof Obligations

Jido Integration changes must keep these obligations green:

- connector conformance and registry tests;
- auth install, credential lease, rotation, revocation, and secret provider
  tests;
- runtime route, dispatch, webhook, stream, session, and direct-runtime tests;
- StackLab `mix gn_ten.connector.scan --all-repos`;
- StackLab `mix gn_ten.tenant.scan --all-repos`;
- no Regex usage in touched code/tests;
- no dynamic atom construction from runtime input;
- every runtime worker, listener, task runner, and session manager is
  supervised.

## Secrets And Live Providers

Live GitHub and Linear commands must run through the secret wrapper:

```bash
~/scripts/with_bash_secrets <command>
```

Provider adapters materialize credentials from a lease for one operation and
must not write raw values to public DTOs, traces, receipts, logs, durable lower
facts, or generated docs.

## Tenant, Observability, And Replay

Lower facts, connector receipts, dispatch events, review packets, and runtime
events must carry tenant, connector, credential lease, authority, target,
operation, and trace refs. AITrace and StackLab receipts should be sufficient to
join lower execution back to governed intent without raw provider payloads.

## Documentation Checks

After doc edits, run:

```bash
test -f README.md
find guides -maxdepth 1 -type f -name '*.md' -print | sort
git diff --check -- README.md guides
```
