# Jido Integration

`jido_integration` is the thin public facade for the substrate packages in this
monorepo. The root package is where you run the deterministic end-to-end proofs,
read the top-level guides, and verify the active reference-app slice.

## Auth Ownership Baseline

`Auth.Server` is the canonical auth lifecycle engine in this repo. It owns:

- install start and callback state transitions
- durable install-session correlation with consume-once callback acceptance
- credential and connection truth through runtime store adapters
- token refresh coordination
- scope gating and blocked-state enforcement

`Auth.Bridge` is the host integration boundary around that engine. Host apps
still own:

- HTTP routes and controllers for install start and provider callbacks
- actor and tenant resolution from host request context
- selecting the correct `Auth.Server` instance plus store/vault adapters
- exposing host-facing admin or API surfaces

Hosts do not reimplement the auth lifecycle state machine. The GitHub examples
call `Auth.Server` directly because they prove the canonical engine in
isolation; production hosts route the same flows through `Auth.Bridge`.

Current durability note: credentials, connections, install sessions, dedupe
keys, dispatch records, and run records all sit behind explicit store
behaviors. OAuth start and callback correlation now run through the durable
install-session store, so callback success does not depend on the original
`Auth.Server` process still being alive and duplicate callbacks are rejected
after the first consume. The repo ships ETS and disk adapters plus shared
contract tests for those local adapters; production durable adapters remain a
separate follow-on path.

## Dispatch Ownership Baseline

`Dispatch.Consumer` is currently a host-owned runtime role.

The root OTP application starts:

- `Jido.Integration.Registry`
- `Jido.Integration.Auth.Server`
- `Jido.Integration.Webhook.Router`
- `Jido.Integration.Webhook.Dedupe`

It intentionally does not start `Jido.Integration.Dispatch.Consumer`.

Hosts that use webhook ingress own:

- supervising the consumer process
- choosing dispatch and run store adapters
- setting retry and backoff policy
- registering trigger callback modules
- passing `dispatch_consumer:` into `Webhook.Ingress.process/2`

The active reference app and webhook examples already use that boundary today.

Dispatch and run durability now have a tighter contract in-tree:

- `dispatch_id` and `run_id` are the stable primary identities
- `idempotency_key` durably resolves an existing run binding
- dispatch and run records can be queried by status and scope fields for
  recovery and operator inspection
- pre-ack store failures return an error instead of returning success or
  crashing the consumer
- dead-lettered runs remain replayable

## Honest Current State

Shipped and supported now:

- deterministic root test suite
- deterministic core examples in `examples/`
- deterministic reference-app proof in `reference_apps/devops_incident_response`
- deterministic GitHub package tests
- env-gated GitHub live acceptance using a real token
- env-gated GitHub sandbox write acceptance covering the full shipped
  issue/comment lifecycle

Not shipped yet as a first-class end-user flow:

- browser or public-callback GitHub OAuth or GitHub App install from the internet
- tunnel-backed public GitHub webhook delivery into this repo
- live onboarding for providers other than GitHub
- an end-to-end `reference_apps/sales_pipeline` proof

If a doc implies one of those missing flows already exists, that doc is
overstating reality.

## Start Here

Pick the path that matches what you want to verify.

### 1. Deterministic Repo Verification

```bash
mix deps.get
mix compile --warnings-as-errors
mix test
```

Optional targeted runs:

```bash
mix test test/examples/
mix test test/reference_apps/devops_incident_response_test.exs
```

What this proves:

- auth state-machine behavior
- webhook routing, signature verification, and dedupe
- durable dispatch, dead-lettering, replay, and restart recovery
- the active reference-app slice above the substrate

### 2. GitHub Package Deterministic Verification

```bash
cd packages/connectors/github
mix deps.get
mix test
```

What this proves:

- deterministic adapter tests
- deterministic conformance coverage
- no live network by default

### 3. GitHub Live Read Acceptance

Prerequisites:

- GitHub CLI authenticated with `gh auth login`, or `GITHUB_TOKEN` exported
- the current live example set expects `repo` and `read:org`

```bash
cd packages/connectors/github
JIDO_INTEGRATION_GITHUB_LIVE=1 ./scripts/live_acceptance.sh read
```

What this actually does today:

- resolves a real token from `GITHUB_TOKEN` or `gh auth token`
- feeds that token through the `Auth.Server` install and callback state machine
  locally
- performs live GitHub read operations
- exercises refresh, refresh failure, rotation, revocation, degradation, and
  connection lifecycle transitions
- exercises webhook ingress with locally constructed GitHub-shaped payloads
  through the durable dispatch path

What it does not do:

- browser or public callback handling
- public webhook delivery from GitHub over the internet

### 4. GitHub Live Write Acceptance

Additional prerequisites:

- a sandbox repository you can safely mutate
- `GITHUB_TEST_OWNER`
- `GITHUB_TEST_REPO`

```bash
cd packages/connectors/github
export GITHUB_TEST_OWNER=your-username
export GITHUB_TEST_REPO=your-sandbox-repo
JIDO_INTEGRATION_GITHUB_LIVE=1 \
JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1 \
./scripts/live_acceptance.sh write
```

What this documented acceptance path actually exercises:

- create issue
- fetch issue
- update issue
- label issue
- create comment
- update comment
- close issue

## Current Repo Shape

The root package stays intentionally thin.

```text
lib/
  jido/integration.ex
  jido/integration/application.ex

packages/
  core/
    contracts/
    runtime/
    conformance/
    factory/
    http_common/
  connectors/
    github/

examples/
reference_apps/
guides/
test/
```

Responsibility split:

- root package
  thin facade, docs, deterministic end-to-end tests, reference-app proofs
- contracts package
  behaviors, contracts, and normalized types
- runtime package
  auth server, webhook runtime, and durable dispatch runtime
- support packages
  conformance, factory, and shared HTTP support
- connector package
  GitHub is the first provider connector currently shipped in-tree

## What Is Proven Today

Core substrate:

- durable credential, connection, install-session, route, dedupe, dispatch, and
  run stores
- shared contract suites for critical control-plane store adapters
- enqueue, consume, dead-letter, replay, and restart recovery

Reference apps:

- `reference_apps/devops_incident_response`
  active deterministic proof for auth, trigger ingress, durable dispatch,
  replay, and restart recovery
- `reference_apps/sales_pipeline`
  scaffold only, not a finished proving slice

Connector coverage:

- `packages/connectors/github`
  deterministic package tests plus env-gated live acceptance using a real token

## Docs To Read Next

Core examples:

- [examples/README.md](/home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration/examples/README.md)

Guides:

- [guides/00_overview.md](/home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration/guides/00_overview.md)
- [guides/06_reference_apps.md](/home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration/guides/06_reference_apps.md)
- [guides/07_live_examples.md](/home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration/guides/07_live_examples.md)

GitHub package onboarding:

- [packages/connectors/github/README.md](/home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration/packages/connectors/github/README.md)

## Quality Gates

Release gate from repo root:

```bash
mix format
mix compile --warnings-as-errors
mix test
mix conformance
mix credo --strict
mix dialyzer
```

GitHub connector gate:

```bash
cd packages/connectors/github
mix compile --warnings-as-errors
mix test
```

Optional doc build:

```bash
mix docs
cd packages/connectors/github && mix docs
```
