# Connector Review Baseline

Date: 2026-03-09
Status: Baseline trio rebuilt against the hardened substrate

## Baseline trio

- direct: `github.issue.create`
- session: `codex.exec.session`
- stream: `market.ticks.pull`

## What this baseline now proves

- connector execution goes through auth leases instead of durable credential truth
- policy admission stays explicit at the capability boundary
- direct, session, and stream runtimes can all emit connector-specific review events
- review artifacts are durable control-plane truth through `ArtifactRef`

## Substrate pressure exposed

1. `RuntimeResult` had to become a shared contract.
   Before this slice, runtimes only emitted generic attempt events. The trio required a first-class way for every runtime family to surface connector-specific events and artifact refs.

2. Runtime affinity is still connector-defined.
   The session and stream baselines moved reuse keys to `credential_ref.id` to avoid cross-connection bleed, but the substrate still lacks a first-class affinity contract for session/stream reuse policy.

3. Artifact truth is durable but still projected through a side channel.
   `run_artifacts/1` is now the honest review surface. `Run.artifact_refs` is not yet updated automatically when artifacts are recorded, so run projection is still thinner than artifact truth.

4. Host-side invoke ergonomics are still sharp.
   Admission is intentionally strict, but connector invocation still needs the caller to provide explicit `allowed_operations`, environment, and sandbox posture. That is honest today, but it is a likely place for a higher-level gateway builder later.
