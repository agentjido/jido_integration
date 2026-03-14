# Notion Live Acceptance

This package keeps two separate quality surfaces:

- deterministic CI through `mix test` and the root monorepo gates
- manual, opt-in live proofs through package-local example scripts

The live path exists to prove the current Jido auth and platform boundary
against real Notion state without contaminating default CI.

## Before You Run It

Prerequisites:

- a public Notion integration with OAuth enabled
- a registered redirect URI for the auth lifecycle proof
- one readable page id for the read proof
- one disposable data source for the write proof
- Notion integration capabilities that cover the proof mode you intend to run
- the target page or data source shared with the integration

Safety:

- `auth` performs a real OAuth authorization-code exchange
- `read` performs live reads
- `write` performs real writes, comments, and block appends before archiving the
  created page

Do not point `write` at production content you are not willing to mutate.

## Proof Modes

### Auth Lifecycle

Command:

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_CLIENT_ID="..." \
JIDO_INTEGRATION_V2_NOTION_CLIENT_SECRET="..." \
JIDO_INTEGRATION_V2_NOTION_REDIRECT_URI="https://example.test/notion/callback" \
scripts/live_acceptance.sh auth
```

What it proves:

- `Jido.Integration.V2.start_install/3` creates install and connection truth
- `NotionSDK.OAuth.authorization_request/1` produces the consent URL
- `NotionSDK.OAuth.exchange_code/2` returns the provider token payload
- `Jido.Integration.V2.complete_install/2` stores the durable credential truth
- `Jido.Integration.V2.request_lease/2` mints a runtime lease containing only
  runtime-safe fields such as `access_token`, `workspace_id`,
  `workspace_name`, and `bot_id` when present

By default the script prints the authorization URL and waits for you to paste
the callback URL or the temporary authorization code.

Optional shortcuts:

- `JIDO_INTEGRATION_V2_NOTION_AUTH_CODE`
- `JIDO_INTEGRATION_V2_NOTION_CALLBACK_URL`

Use one of those when you want to skip the interactive prompt.

### Read Acceptance

Command:

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN="..." \
JIDO_INTEGRATION_V2_NOTION_READ_PAGE_ID="..." \
scripts/live_acceptance.sh read
```

What it proves:

- a pre-obtained access token can still be installed through the Jido auth
  surface
- `notion.users.get_self` runs live through `Jido.Integration.V2.invoke/3`
- `notion.pages.retrieve` runs through the same path
- result output, events, and artifact refs stay token-safe

If you already know the provider metadata, you can also pass these optional
install-time fields so the proof mirrors the real install record more closely:

- `JIDO_INTEGRATION_V2_NOTION_REFRESH_TOKEN`
- `JIDO_INTEGRATION_V2_NOTION_WORKSPACE_ID`
- `JIDO_INTEGRATION_V2_NOTION_WORKSPACE_NAME`
- `JIDO_INTEGRATION_V2_NOTION_BOT_ID`

### Write Acceptance

Command:

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_LIVE_WRITE=1 \
JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN="..." \
JIDO_INTEGRATION_V2_NOTION_WRITE_PARENT_DATA_SOURCE_ID="..." \
scripts/live_acceptance.sh write
```

What it proves:

- `notion.pages.create`
- `notion.pages.update`
- `notion.blocks.append_children`
- `notion.comments.create`
- cleanup by archiving the created page with `notion.pages.update`

The write proof assumes the parent data source has a title property named
`Name`. Override that when your schema uses a different title field:

- `JIDO_INTEGRATION_V2_NOTION_WRITE_TITLE_PROPERTY`

Optional write-specific overrides:

- `JIDO_INTEGRATION_V2_NOTION_WRITE_PAGE_TITLE`
- `JIDO_INTEGRATION_V2_NOTION_API_BASE_URL`
- `JIDO_INTEGRATION_V2_NOTION_TIMEOUT_MS`

## Environment Contract

Required for all live proofs:

- `JIDO_INTEGRATION_V2_NOTION_LIVE=1`

Required for `auth`:

- `JIDO_INTEGRATION_V2_NOTION_CLIENT_ID`
- `JIDO_INTEGRATION_V2_NOTION_CLIENT_SECRET`
- `JIDO_INTEGRATION_V2_NOTION_REDIRECT_URI`

Required for `read`:

- `JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN`
- `JIDO_INTEGRATION_V2_NOTION_READ_PAGE_ID`

Required for `write`:

- `JIDO_INTEGRATION_V2_NOTION_LIVE_WRITE=1`
- `JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN`
- `JIDO_INTEGRATION_V2_NOTION_WRITE_PARENT_DATA_SOURCE_ID`

Optional for all modes:

- `JIDO_INTEGRATION_V2_NOTION_SUBJECT`
- `JIDO_INTEGRATION_V2_NOTION_ACTOR_ID`
- `JIDO_INTEGRATION_V2_NOTION_TENANT_ID`
- `JIDO_INTEGRATION_V2_NOTION_API_BASE_URL`
- `JIDO_INTEGRATION_V2_NOTION_TIMEOUT_MS`

Optional install metadata:

- `JIDO_INTEGRATION_V2_NOTION_REFRESH_TOKEN`
- `JIDO_INTEGRATION_V2_NOTION_WORKSPACE_ID`
- `JIDO_INTEGRATION_V2_NOTION_WORKSPACE_NAME`
- `JIDO_INTEGRATION_V2_NOTION_BOT_ID`

## Validation Boundary

These live proofs are package-local and opt-in by design.

They are not part of:

- `mix test`
- `mix monorepo.test`
- `mix ci`
- default root connector conformance

## Implementation Files

- `examples/support/live_support.exs`
- `examples/notion_auth_lifecycle.exs`
- `examples/notion_live_read_acceptance.exs`
- `examples/notion_live_write_acceptance.exs`
- `scripts/live_acceptance.sh`

These files stay inside the connector package on purpose. The repo root remains
tooling-only.
