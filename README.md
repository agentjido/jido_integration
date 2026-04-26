# Jido Integration

Jido Integration is an Elixir integration platform for publishing connector
capabilities, managing auth lifecycle, invoking work across direct and
runtime-control-backed runtimes, and reviewing durable execution state.

This repository includes the public platform facade, bridge packages,
connector packages, durability tiers, and app-level proofs for hosted webhook
and async flows. If you are evaluating or using the platform, start here. If
you are changing the internals of the monorepo itself, use `docs/`,
package-local READMEs, and app-local runbooks in `apps/*/README.md`.

Connector packages that depend on external SDK or runtime repos should prefer
sibling-relative paths during active local development and fall back to pinned
git refs otherwise. They should not rely on connector-local vendored `deps/`
trees for runtime dependency sourcing.

## Start Here

- read [Architecture](guides/architecture.md) for the platform shape and
  package responsibilities
- read [Execution Plane Alignment](guides/execution_plane_alignment.md) for
  the frozen lower-boundary contract packet and carriage rules
- read [Runtime Model](guides/runtime_model.md) to choose between direct,
  session, stream, and inference execution
- read [Inference Baseline](guides/inference_baseline.md) for the first live
  inference runtime family, durable event set, and proof flow
- read [Durability](guides/durability.md) before selecting in-memory,
  local-file, or Postgres-backed state
- read [Publishing](guides/publishing.md) for the welded package release flow
- use `apps/*/README.md` for proof-app runbooks and host-level proof flows

## Documentation

### General

- [Guide Index](guides/index.md)
- [Architecture](guides/architecture.md)
- [Execution Plane Alignment](guides/execution_plane_alignment.md)
- [Runtime Model](guides/runtime_model.md)
- [Inference Baseline](guides/inference_baseline.md)
- [Durability](guides/durability.md)
- [Connector Lifecycle](guides/connector_lifecycle.md)
- [Conformance](guides/conformance.md)
- [Async And Webhooks](guides/async_and_webhooks.md)
- [Publishing](guides/publishing.md)
- [Observability](guides/observability.md)

Repo-internal developer notes stay in `docs/`. Host-level proof runbooks stay
in `apps/*/README.md`.

## What The Platform Exposes

- `Jido.Integration.V2` is the stable public entrypoint for connector
  discovery, auth lifecycle calls, invocation, review lookups, and target
  lookup.
- the repo now aligns its lower-boundary vocabulary with the frozen
  Execution Plane packet: `AuthorityDecision.v1`,
  `BoundarySessionDescriptor.v1`, `ExecutionIntentEnvelope.v1`,
  `ExecutionRoute.v1`, `AttachGrant.v1`, `CredentialHandleRef.v1`,
  `ExecutionEvent.v1`, and `ExecutionOutcome.v1`
- boundary-backed session carriage now keeps the Wave 5 durable subcontracts
  explicit under named metadata groups for descriptor, route, attach grant,
  replay, approval, callback, and identity truth
- Wave 7 keeps durable service descriptors, lease lineage, and attachability
  above lower process state instead of leaking raw Execution Plane structs into
  the public lower-gateway surface
- connector packages publish authored capability contracts and may also expose
  curated generated `Jido.Action`, `Jido.Sensor`, and `Jido.Plugin` surfaces.
- `core/dispatch_runtime` and `core/webhook_router` provide the hosted async
  and webhook APIs above the main facade.

Key public capabilities today include:

- connector discovery through `connectors/0`, `capabilities/0`,
  `fetch_connector/1`, `fetch_capability/1`, and
  `projected_catalog_entries/0`
- auth lifecycle through `start_install/3`, `complete_install/2`,
  `fetch_install/1`, `connection_status/1`, `request_lease/2`,
  `rotate_connection/2`, and `revoke_connection/2`
- invocation through `InvocationRequest.new!/1`, `invoke/1`, and `invoke/3`
- inference execution through `invoke_inference/2`
- review and targeting through `fetch_run/1`, `fetch_attempt/1`, `events/1`,
  `run_artifacts/1`, `fetch_artifact/1`, `announce_target/1`, `fetch_target/1`,
  `compatible_targets/1`, and `review_packet/2`
- substrate readback through `Jido.Integration.V2.LowerFacts`, including
  tenant-scoped submission receipt, run, attempt, event, artifact, trace, and
  terminal execution outcome reads for Mezzanine

Phase 1 also lands the first live inference runtime family on that same
surface:

- shared inference contracts now live in `core/contracts`
- `core/control_plane` now builds the local `ReqLLMCallSpec`, executes both
  cloud, CLI-endpoint, and self-hosted requests through `req_llm`, and records
  the durable event minimum
- `agent_session_manager` now publishes CLI-backed endpoint descriptors through
  `ASM.InferenceEndpoint`, with Gemini as the first preferred common-surface
  proof provider
- `review_packet/2` reconstructs inference runs without requiring a registered
  connector manifest
- `apps/inference_ops` is the dedicated proof app for the cloud,
  CLI-endpoint, and self-hosted paths
- spawned self-hosted service startup now resolves through
  an optional self-hosted endpoint provider on top of `execution_plane`, while
  attached-local `ollama` keeps service-runtime semantics in the same family kit
  instead of in the control plane

Phase 7 also lands the explicit cross-repo reference seam in
`core/contracts`:

- `SubjectRef` names the primary source subject for a higher-order record
- `EvidenceRef` names exact source records plus the review-packet lineage they
  were read through
- `GovernanceRef` names approval, denial, override, rollback, or
  policy-decision lineage without creating duplicate control-plane ownership or
  a separate persisted review record family
- `ReviewProjection` is the contracts-only `packet.metadata` shape for
  northbound consumers that need review packet lineage without depending on
  `core/platform`

Phase 8 also freezes the higher-order seam: higher-order sidecars such as
`jido_memory`, `jido_skill`, and `jido_eval` stay on the `core/contracts` seam
and may persist only derived state.

Phase 9 provider-factory work builds on that already-correct ownership split
instead of reopening control-plane, catalog, or review authority in those
repos.

The lower execution packet is carried, not re-exported, from this repo.
`core/contracts` remains the stable lower-gateway public seam, while the
family-facing minimal-lane payload interiors for `HttpExecutionIntent.v1`,
`ProcessExecutionIntent.v1`, and `JsonRpcExecutionIntent.v1` are explicitly
provisional until Wave 3 closes prove-out.

Hosted webhook routing and async replay are intentionally separate public
package APIs:

- `Jido.Integration.V2.DispatchRuntime`
- `Jido.Integration.V2.WebhookRouter`

## Current Proof Surface

Runtime families proved in-tree:

- `:direct`
  - GitHub issue and comment operations
  - Linear user, issue, workflow-state, comment create/update, and
    connector-local raw GraphQL operations
  - Notion user, search, page, block, data-source, and comment operations
- `:session`
  - `codex.session.start`
  - `codex.session.turn`
  - `codex.session.cancel`
  - `codex.session.status`
- `:stream`
  - `codex.session.stream`
  - `market.ticks.pull`
- `:inference`
  - cloud provider execution through `req_llm`
  - CLI endpoint execution through `ASM.InferenceEndpoint` plus `req_llm`
  - self-hosted `llama_cpp_sdk` endpoint execution through `req_llm`
  - attached local `ollama` endpoint execution through `req_llm`

Inference phase-1 proofs:

- `core/contracts/test/jido/integration/v2/inference_contracts_test.exs`
- `core/control_plane/test/jido/integration/v2/control_plane_inference_test.exs`
- `core/control_plane/test/jido/integration/v2/control_plane_inference_execution_test.exs`
- `core/platform/test/jido/integration/v2_inference_review_packet_test.exs`
- `core/platform/test/jido/integration/v2_inference_invoke_test.exs`
- package-local examples under `core/contracts/examples/`,
  `core/control_plane/examples/`, and `core/platform/examples/`
- `apps/inference_ops`

Reference apps:

- `apps/devops_incident_response`
  - proves hosted webhook registration, async dispatch, dead-letter, replay,
  and restart recovery
  - keeps webhook behavior app-local instead of widening `connectors/github`
- `apps/inference_ops`
  - proves cloud, CLI endpoint, spawned self-hosted, and attached-local
    inference execution through the public facade
  - keeps durable review truth in `core/control_plane`
  - keeps client execution in `req_llm` and supplies the current optional
    self-hosted provider backed by `self_hosted_inference_core`, the built-in
    `ollama` adapter, and `llama_cpp_sdk`

The current surface also proves:

- authored `AuthSpec` is now profile-driven, with explicit
  `supported_profiles`, `default_profile`, connector-level `install` and
  `reauth` posture, and honest per-profile scope, lease, and management-mode
  publication
- durable auth truth now spans `Install`, `Connection`, `CredentialRef`,
  versioned `Credential`, and short-lived `CredentialLease`/lease metadata,
  with `profile_id`, credential lineage, and secret-source posture staying
  inside `core/auth`
- connectors execute through short-lived auth leases, not durable credential
  truth
- public invocation binds auth through `connection_id`; `credential_ref`
  remains internal execution plumbing
- GitHub, Linear, and Notion all publish generated common consumer surfaces from
  authored contracts, and conformance keeps those curated common ids unique
  within each connector
- conformance runs from the root while connector evidence stays package-local
- conformance fixtures now prove lease projection and redaction posture, not
  just execution success
- local durability, async queue state, and webhook route state are all
  explicit opt-in packages
- durable brain-to-lower-gateway acceptance now stays on an explicit seam:
  - `core/contracts` owns canonical JSON, submission identity, audit payload,
    and governance-projection contracts
  - governance projections require
    `sandbox.acceptable_attestation` and carry that list into gateway and
    runtime shadows instead of inventing an implicit local fallback
  - `core/brain_ingress` owns verification, scope resolution, and durable
    acceptance or typed rejection before runtime policy continues
  - `core/runtime_router` maps accepted governance into
    `ExecutionPlane.Admission.Request` values and owns fallback ladders by
    calling the runtime-client execute callback once per acceptable-attestation
    rung
  - `core/store_local` and `core/store_postgres` provide the concrete
    submission-ledger backends
- substrate-facing lower-facts reads are no longer an unscoped convenience
  path: `Jido.Integration.V2.TenantScope` is mandatory for submission, run,
  attempt, event, artifact, and trace reads, and
  `Jido.Integration.V2.SubstrateReadSlice` fails closed on tenant or
  installation mismatch
- the Postgres auth tier carries a forward-only expansion migration,
  `20260403000000_expand_phase_0_auth_truth_columns.exs`, so existing dev/test
  databases can adopt the richer auth lineage shape without rewriting prior
  migration history

## Publishing The Unified Package

The source monorepo remains the system of record. The publishable Hex package
is generated from this repo through `weld`.

The release path is explicit:

1. `mix release.prepare`
2. `mix release.track`
3. `mix release.publish.dry_run`
4. `mix release.publish`
5. `mix release.archive`

`mix release.prepare` generates the welded package, runs the artifact quality
lane, builds the tarball, and writes a durable release bundle under `dist/`.
That prepared bundle is intended to stay runnable on its own, including
bundle-local `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test`, `mix credo --strict`,
`mix dialyzer`, `mix docs --warnings-as-errors`, `mix ecto.create`, and
`mix ecto.migrate` when the published slice includes the Postgres durability
tier.

`mix release.track` updates the default orphan-backed
`projection/jido_integration` branch from that prepared bundle so unreleased and
pre-release welded snapshots can be pinned and exercised before Hex release.

The committed workspace dependency stays on the released Hex Weld line. When
coordinating pre-release Weld validation across repos, use a normal prerelease
version bump instead of embedding repo-local path or git override logic.

`mix release.publish` publishes from that prepared bundle snapshot rather than
from the monorepo root. `mix release.archive` then preserves the prepared
bundle in the archive tree so the exact released artifact remains inspectable.

The first published welded artifact intentionally ships the direct-runtime,
webhook, async, durability, auth, and public-facade surface. The runtime-control-backed
session and stream packages, plus lower-boundary bridge packages, stay
source-repo packages for now because they are intentionally excluded by the
repo-local Weld contract rather than by an unresolved external package split.

That source-only boundary is now explicit in the repo-local Weld contract. The
published monolith can still run integrated tests that need source-only support
packages, but those support packages must be declared explicitly in the
monolith manifest rather than being pulled in by silent projector behavior.

## Repository Layout

The repo root is a workspace and documentation layer. Runtime code lives in
child packages and top-level apps.

```text
jido_integration/
  mix.exs                    # workspace root only
  README.md                  # user-facing repo entry point
  guides/                    # user-facing and developer guide entry points
  docs/                      # repo-level developer notes and workflows
  lib/                       # root Mix tasks and workspace helpers only
  test/                      # root tooling tests only
  core/
    platform/                # public facade package (`:jido_integration_v2`)
    contracts/               # shared public structs and behaviours
    brain_ingress/           # durable brain-to-lower-gateway intake and scope resolution
    auth/                    # install, connection, credential, and lease truth
    control_plane/           # durable run, trigger, and artifact truth
    runtime_router/         # runtime-control-backed session/stream adapter package
    consumer_surfaces/       # generated common Jido surface runtime support
    direct_runtime/          # direct capability execution
    asm_runtime_bridge/      # integration-owned `asm` Runtime Control driver projection
    session_runtime/         # integration-owned `jido_session` Runtime Control driver
    ingress/                 # trigger normalization and durable admission
    policy/                  # pre-attempt policy and shed decisions
    dispatch_runtime/        # async queue, retry, replay, recovery
    webhook_router/          # hosted route lifecycle and ingress bridge
    conformance/             # reusable connector conformance engine
    store_local/             # restart-safe local durability tier
    store_postgres/          # database-backed durable tier
  connectors/
    github/                  # direct GitHub connector + live acceptance runbook
    linear/                  # direct Linear connector + package-local docs
    notion/                  # direct Notion connector + package-local live proofs
    codex_cli/               # runtime-control-routed session connector via `asm`
    market_data/             # runtime-control-routed stream connector via `asm`
  apps/
    devops_incident_response # hosted webhook + async recovery proof
    inference_ops/           # cloud + self-hosted inference proof
    trading_ops/             # archived proof, excluded from default workspace/CI
```

## Direct Versus Runtime Boundary

GitHub, Linear, and Notion stay on the direct provider-SDK path and do not inherit
session or stream runtime-kernel coupling merely because the repo also ships
non-direct capability families.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

Only actual `:session` and `:stream` capabilities use
`jido_runtime_control` via `Jido.RuntimeControl`.

`Jido.Integration.V2 -> RuntimeRouter -> Jido.RuntimeControl -> {asm | jido_session}`

`asm` routes through `core/asm_runtime_bridge` into `agent_session_manager`
and `cli_subprocess_core`, while `jido_session` routes through
`core/session_runtime` via `Jido.Session.RuntimeControlDriver`.

Phase 6A removed the old `core/session_kernel` and `core/stream_runtime`
bridge packages. They are not part of the repo or the target runtime
architecture.

The current core runtime graph stops at those two runtime-control lanes. Lower-boundary
work is not part of the active `asm` or `jido_session` dependency path.

The default root workspace gate is explicit about that scope.
`build_support/workspace_contract.exs` defines the active workspace package
globs that run under `mix mr.*` and `mix ci`.

## Developer Docs

User-facing guides live under `guides/`. Developer-focused repo notes remain in
`docs/`, and package-specific workflows remain in package-local READMEs.

Primary package and app runbooks:

- `core/platform/README.md`
- `core/brain_ingress/README.md`
- `core/consumer_surfaces/README.md`
- `core/conformance/README.md`
- `core/session_runtime/README.md`
- `core/store_local/README.md`
- `core/dispatch_runtime/README.md`
- `core/webhook_router/README.md`
- `connectors/github/README.md`
- `connectors/github/docs/live_acceptance.md`
- `connectors/linear/README.md`
- `connectors/notion/README.md`
- `connectors/notion/docs/live_acceptance.md`
- `apps/devops_incident_response/README.md`
- `apps/inference_ops/README.md`

## Validation Prerequisites

The monorepo test and CI surface now includes packages that wire
`core/store_postgres` in `:test`.

`mix mr.test` and `mix ci` therefore expect a reachable Postgres test store.
Before calling the repo blocked on Postgres reachability, run:

```bash
mix mr.pg.preflight
```

That check validates the canonical `core/store_postgres` test tier only. The
repo still supports the other two durability tiers in parallel:

- in-memory defaults in `core/auth` and `core/control_plane`
- `core/store_local` for restart-safe local durability
- `core/store_postgres` for the shared database-backed tier

## Temporal developer environment

Temporal CLI is expected to be available as `temporal` on this developer workstation for local durable-workflow development. Current provisioning is machine-level dotfiles setup, not a repo-local dependency.

TODO: make Temporal ergonomics explicit for developers by adding repo-local setup scripts, version expectations, and fallback instructions so the tool is not silently assumed from the workstation.

## Native Temporal development substrate

Temporal runtime development is managed from the Mezzanine checkout through its
repo-owned `just` workflow, not by manually starting ad hoc Temporal processes.

Use:

```bash
cd "$MEZZANINE_ROOT"
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Expected local contract: `127.0.0.1:7233`, UI `http://127.0.0.1:8233`, namespace `default`, native service `mezzanine-temporal-dev.service`, persistent state `~/.local/share/temporal/dev-server.db`.
