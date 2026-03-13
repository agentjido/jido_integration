# Operations And Release

This repo keeps deterministic verification separate from opt-in live acceptance.

That split should show up in both local release discipline and CI.

## Recommended Local Release Gate

From the repo root:

```bash
mix format
mix compile --warnings-as-errors
mix test
mix conformance
mix credo --strict
mix dialyzer
```

If the change touched guides, also run:

```bash
mix docs
```

`mix format` is the local repair step. In CI, use `mix format --check-formatted`
instead.

## What Each Gate Checks

### `mix format`

Checks source formatting consistency.

Why it matters:

- keeps diffs reviewable
- prevents avoidable CI failures later

Typical failure mode:

- a touched file was not re-formatted after edits

Fix:

- run `mix format`

### `mix compile --warnings-as-errors`

Checks that the project still compiles cleanly and treats warnings as release
failures.

Why it matters:

- warnings often signal stale APIs, unused code, or broken contracts
- releaseable code should not ship with ignored compiler warnings

Typical failure modes:

- stale function calls after refactors
- missing aliases or imports
- dead code warnings

Fix:

- update call sites or remove the unused code instead of suppressing warnings

### `mix test`

Runs the deterministic test suite.

Why it matters:

- proves the contract and runtime behavior together
- catches regressions in auth, ingress, dispatch, and reference-app proofs

Typical failure modes:

- adapter result shape no longer matches manifest schema
- webhook or dispatch recovery behavior regressed
- conformance-tagged tests fail as part of the full deterministic suite

Fix:

- repair the contract mismatch or runtime behavior before moving on

### `mix conformance`

Runs the dedicated conformance-tagged test lane:

```bash
mix test --only conformance
```

Why it matters:

- gives a focused signal on connector contract quality
- helps isolate conformance failures from broader runtime failures

Typical failure modes:

- a manifest advertises legacy telemetry
- an operation is missing `rate_limit`
- a connector added webhook verification in the adapter package

Fix:

- repair the contract or connector implementation, then rerun the lane

### `mix credo --strict`

Runs static analysis and style checks.

Why it matters:

- catches maintainability problems that the compiler does not treat as errors

Typical failure modes:

- large or complex functions
- duplicated logic
- readability issues

Fix:

- simplify or restructure the offending code instead of ignoring the warning

### `mix dialyzer`

Runs type analysis.

Why it matters:

- catches mismatched return values and broken assumptions that still compile

Typical failure modes:

- a function now returns a shape that no longer matches its callers
- a success tuple or error tuple shape drifted

Fix:

- correct the type mismatch or update the specs if the contract changed

### `mix docs`

Builds HexDocs from the configured extras and modules.

Why it matters:

- catches broken guide formatting or references before docs changes merge

Typical failure modes:

- invalid Markdown structure
- references to guides or files that no longer exist
- docs examples or headings that break ex_doc rendering

Fix:

- repair the guide content and rebuild until `mix docs` is clean

## Recommended CI Order

The repo benefits from failing fast on cheap checks and leaving expensive checks
for later stages.

Recommended CI order:

1. `mix deps.get`
2. `mix format --check-formatted`
3. `mix compile --warnings-as-errors`
4. `mix test`
5. `mix conformance`
6. `mix credo --strict`
7. `mix dialyzer`
8. `mix docs` when docs or public APIs changed

That order keeps feedback efficient:

- formatting and compile failures return quickly
- tests and conformance validate behavior
- static analysis and docs run after the code already builds and passes

## Connector Package Gate

The GitHub package has its own deterministic release gate.

From `packages/connectors/github`:

```bash
mix compile --warnings-as-errors
mix test
```

Why that is enough for the package lane:

- `mix test` includes deterministic package tests
- conformance coverage lives inside the package test suite
- live tests remain excluded unless env flags are set

For focused contract debugging in the package, you can also run:

```bash
mix jido.conformance Jido.Integration.Connectors.GitHub --profile bronze
mix jido.conformance Jido.Integration.Connectors.GitHub --profile silver
```

That report is diagnostic. It does not replace the full package test run.

## Live Acceptance Is Not A Release Gate

GitHub live acceptance stays opt-in:

```bash
cd packages/connectors/github
JIDO_INTEGRATION_GITHUB_LIVE=1 ./scripts/live_acceptance.sh read
```

Write-path acceptance requires an extra opt-in:

```bash
cd packages/connectors/github
export GITHUB_TEST_OWNER=your-username
export GITHUB_TEST_REPO=your-sandbox-repo
JIDO_INTEGRATION_GITHUB_LIVE=1 \
JIDO_INTEGRATION_GITHUB_LIVE_WRITE=1 \
./scripts/live_acceptance.sh write
```

Those commands are useful before release, but they are not part of the default
deterministic gate and should not silently creep into it.

## Common Failure Patterns

### Compile Passes, Tests Fail

Usually means a behavioral regression rather than a syntax problem.

Common causes:

- manifest and adapter drift
- dispatch or auth state transition regressions
- broken fixture expectations

### `mix conformance` Fails But `mix test` Looks Fine

Usually means the connector still behaves, but its declared contract no longer
matches the shared rules.

Common causes:

- invalid telemetry event names
- missing rate-limit declarations
- invalid auth descriptor values
- connector-level webhook verification logic

### Dialyzer Fails Late

Usually means tuple shapes or data types drifted across package boundaries.

The fix is rarely to relax specs. More often the fix is to restore the actual
contract the caller and callee are supposed to share.

### Docs Fail Late

Usually means:

- a guide references a path that moved
- a Markdown table or fenced block is malformed
- the docs config and extras drifted from the file tree

That is why `mix docs` is worth running for documentation-heavy changes even if
code was untouched.

## Adding A New Connector Package To The Release Chain

Scaffolding a new connector package is not the same as putting it into the
release chain.

For a new package such as `packages/connectors/acme_crm`, the minimum follow-up
steps are:

1. keep the package deterministic by default
2. make sure `mix test` in that package passes without network access
3. add package-level conformance coverage
4. document any live acceptance as opt-in only
5. add the package lane to CI alongside the root lane

A practical package lane usually looks like:

```bash
cd packages/connectors/acme_crm
mix deps.get
mix compile --warnings-as-errors
mix test
mix jido.conformance Jido.Integration.Connectors.AcmeCrm --profile bronze
```

If the connector has fixtures and triggers, add silver as well.

Do not add a connector to the default release chain until:

- the deterministic package lane is green
- the manifest is no longer placeholder data
- the package README describes any live steps honestly

## Release Discipline

The repo works best when maintainers keep these rules:

- keep the root facade thin
- keep control-plane truth in shared runtime packages
- keep connectors deterministic by default
- keep live acceptance opt-in and documented
- treat docs as part of the release surface, not an afterthought

That discipline matters more than any individual command because the repo is
explicitly designed to separate shipped, deterministic behavior from future or
opt-in flows.
