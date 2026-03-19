# Jido Integration V2 Notion Connector

Thin direct Notion connector package backed by `notion_sdk`, with deterministic
offline tests and package-local, opt-in live proofs.

This package keeps the boundary explicit:

- `notion_sdk` owns the provider HTTP and OAuth implementation
- Jido owns install state, durable credential truth, short-lived leases,
  policy, conformance, and connector docs
- OAuth control endpoints stay in the install/auth flow and are not published as
  invoke capabilities

## Capability Surface

The initial published A0 slice focuses on content publishing:

- `notion.users.get_self`
- `notion.search.search`
- `notion.pages.create`
- `notion.pages.retrieve`
- `notion.pages.update`
- `notion.blocks.list_children`
- `notion.blocks.append_children`
- `notion.data_sources.query`
- `notion.comments.create`

`notion.oauth.token`, `notion.oauth.revoke`, and `notion.oauth.introspect` stay
out of the invoke surface on purpose. The connector catalog tracks them as
auth-control inventory, but the package does not publish them as runtime
capabilities.

Those published runtime capability ids are intentionally not treated as a
generated common consumer surface. In this connector they are marked
`consumer_surface.mode: :connector_local`, which means:

- they remain stable runtime capabilities through `Jido.Integration.V2.invoke/3`
- they do not auto-project into generated `Jido.Action` or `Jido.Plugin`
  surfaces
- they carry an explicit passthrough `schema_policy` justification because the
  current Notion runtime slice preserves the SDK-shaped payload boundary
- they now also carry authored schema-contract metadata in
  `OperationSpec.metadata` so the connector can distinguish static operations
  from late-bound schema-sensitive ones without widening the published A0
  surface

This is the architecture stress test for large SDKs: the catalog can track wide
Notion inventory without implying wrapper parity.

## Authored Schema Classification

The Phase 3 authored contract now classifies the published A0 slice with these
metadata keys on each authored operation:

- `schema_strategy`
- `schema_context_source`
- `schema_slots`

Each `schema_slots` entry identifies the affected `surface` (`:input` or
`:output`), the payload `path`, the late-bound `kind`, and the lookup `source`.

Current A0 classification:

- `notion.users.get_self`: `:static`
- `notion.search.search`: `:static`
- `notion.pages.create`: `:late_bound_input`
- `notion.pages.retrieve`: `:late_bound_output`
- `notion.pages.update`: `:late_bound_input_output`
- `notion.blocks.list_children`: `:static`
- `notion.blocks.append_children`: `:static`
- `notion.data_sources.query`: `:late_bound_input_output`
- `notion.comments.create`: `:static`

That keeps the authored-spec spine honest about which payload regions are known
to depend on late-bound data-source metadata.

## Runtime Enrichment

Phase 3 keeps the published A0 invoke surface stable while making the
late-bound path explicit at runtime.

For the late-bound operations, the connector now:

- resolves schema context through `notion_sdk` at invocation time
- uses `NotionSDK.DataSources.retrieve/2` as the source of truth for the
  governing data-source schema
- uses `NotionSDK.Pages.retrieve/2` when a page id must be dereferenced to find
  that governing data source first
- falls back through `NotionSDK.Databases.retrieve/2` when a retrieved page
  still reports a legacy `database_id` parent with a single child data source
- validates late-bound input regions before the provider write or query call
- leaves `output.data` provider-shaped while attaching a deterministic
  `schema_context` summary to connector events and artifact metadata

Current runtime behavior by operation:

- `notion.pages.create`
  resolves `parent.data_source_id`, validates `properties`, then invokes
  `NotionSDK.Pages.create/2`
- `notion.pages.retrieve`
  retrieves the page first, resolves its parent data source when present, and
  falls back through the page's legacy database parent when that database has a
  single child data source, then annotates the runtime result with that schema
  context
- `notion.pages.update`
  retrieves the page, resolves its parent data source or single-child legacy
  database parent, validates input `properties`, then invokes
  `NotionSDK.Pages.update/2`
- `notion.data_sources.query`
  resolves the target data source, validates `filter` and `sorts`, then invokes
  `NotionSDK.DataSources.query/2`

The connector does not introduce a durable schema cache. Each invocation keeps
schema truth provider-local and runtime-local.

## Permission Model

The connector uses Jido semantic permission bundles instead of pretending
Notion capability toggles are a direct OAuth-scope match.

Per-capability bundles are expressed with these semantic permission ids:

- `notion.identity.self`
- `notion.user.read`
- `notion.content.read`
- `notion.content.insert`
- `notion.content.update`
- `notion.comment.read`
- `notion.comment.insert`
- `notion.file_upload.write`

The package also groups those ids into reusable profiles for install flows:

- `workspace_read`
- `content_publishing`
- `full_workspace`

## Deterministic CI

Default package tests stay offline and run through the `notion_sdk` transport
seam. There is no second handwritten fake provider layer.

```bash
cd connectors/notion
mix deps.get
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs
```

The connector should also pass the root conformance surface:

```bash
cd /home/home/p/g/n/jido_integration
mix jido.conformance Jido.Integration.V2.Connectors.Notion
```

## Live Proofs

Live proofs stay package-local and opt-in:

- `auth`
  Proves `start_install/3`, `NotionSDK.OAuth.authorization_request/1`,
  `NotionSDK.OAuth.exchange_code/2`, `complete_install/2`, and lease minting.
- `read`
  Proves live `notion.users.get_self` and `notion.pages.retrieve` through
  `Jido.Integration.V2.invoke/3`.
- `write`
  Proves live `notion.pages.create`, `notion.pages.update`,
  `notion.blocks.append_children`, and `notion.comments.create`, then archives
  the created page.

Use the package-local wrapper:

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_CLIENT_ID="..." \
JIDO_INTEGRATION_V2_NOTION_CLIENT_SECRET="..." \
JIDO_INTEGRATION_V2_NOTION_REDIRECT_URI="https://example.test/notion/callback" \
scripts/live_acceptance.sh auth
```

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN="..." \
JIDO_INTEGRATION_V2_NOTION_READ_PAGE_ID="..." \
scripts/live_acceptance.sh read
```

```bash
cd connectors/notion
JIDO_INTEGRATION_V2_NOTION_LIVE=1 \
JIDO_INTEGRATION_V2_NOTION_LIVE_WRITE=1 \
JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN="..." \
JIDO_INTEGRATION_V2_NOTION_WRITE_PARENT_DATA_SOURCE_ID="..." \
scripts/live_acceptance.sh write
```

Read the detailed runbook in [`docs/live_acceptance.md`](docs/live_acceptance.md).

## Provider Boundary

Runtime requests build `NotionSDK.Client` instances only from Jido-issued
credential leases. The connector never uses `NotionSDK.OAuthTokenFile` as
runtime truth.

The generic operation handler:

- reads `sdk_module` and `sdk_function` from capability metadata
- builds the SDK client from the lease payload
- resolves late-bound schema context inside the connector when the authored
  operation metadata requires it
- validates schema-sensitive input regions for `pages.create`, `pages.update`,
  and `data_sources.query` before the provider call
- keeps runtime output map-first
- normalizes provider failures into the Jido error taxonomy
- normalizes connector preflight validation failures into the same taxonomy with
  the distinct `notion.preflight_validation` code
- emits redacted `auth_binding` digests instead of raw tokens in output and
  event payloads
- records deterministic `schema_context` summaries in connector event payloads
  and artifact metadata without turning generated consumers into runtime schema
  resolvers

Provider inventory beyond the published runtime slice stays in the local
catalog metadata and at the `notion_sdk` boundary. It does not automatically
become generated Jido consumer surface area.

## Files

- live support harness: `examples/support/live_support.exs`
- auth proof: `examples/notion_auth_lifecycle.exs`
- read proof: `examples/notion_live_read_acceptance.exs`
- write proof: `examples/notion_live_write_acceptance.exs`
- live wrapper: `scripts/live_acceptance.sh`
- deterministic tests: `test/jido/integration/v2/connectors/notion_test.exs`
- live env gating tests:
  `test/jido/integration/v2/connectors/notion/live_env_test.exs`
