# Jido Integration Generalized Stack Boundary

## Responsibility

Jido Integration owns connector publication, provider adapter packages, auth
lifecycle, credential leases, connector registry, runtime routing, lower
invocation, durable lower facts, conformance, and generated consumer surfaces.

It does not own product UI, product workflow lifecycle, Citadel authority
decisions, Execution Plane lane internals, or GroundPlane primitive semantics.

## Public Interfaces

Primary package groups:

- `core/contracts`, `core/platform`, `core/control_plane`, `core/auth`,
  `core/secrets_provider`, `core/connector_registry`,
  `core/connector_admission_engine`, and `core/provider_classification`;
- `core/runtime_router`, `core/runtime_control`, `core/direct_runtime`,
  `core/session_runtime`, `core/dispatch_runtime`,
  `core/platform_cluster_runtime`, and `core/webhook_router`;
- `core/store_local`, `core/store_postgres`, `core/conformance`,
  `core/conformance_contracts`, and `core/consumer_surfaces`;
- `connectors/*` for provider-specific adapters;
- `apps/*` and `scaffolds/*` for proof apps and connector generation.

## Dependency Rules

Allowed dependencies:

- Execution Plane contracts for lower route, attach, intent, outcome, and event
  shapes;
- Citadel/Jido shared contracts for authority and governance refs;
- GroundPlane primitives for lower refs, leases, fences, and persistence
  policy;
- connector SDKs inside connector packages only.

Forbidden dependencies:

- generic core maps that hard-code provider dispatch as policy;
- raw credential values in public DTOs, receipts, logs, traces, or durable
  lower facts;
- product-specific workflow decisions in connector packages;
- unsupervised runtime workers, webhook listeners, or async dispatch tasks.

## Provider Vocabulary Zoning

Provider names are legitimate in connector packages, manifests, provider
classification, provider feature data, conformance fixtures, and adapter
receipts. Generic core modules must use connector refs, capability refs,
credential lease refs, runtime route refs, tenant refs, and authority refs.

## Extravaganza Cutover Proof

The Extravaganza product proof exercises Jido Integration through AppKit,
Mezzanine, and Citadel rather than by calling connectors directly. The current
live proof covered:

- Linear issue/source discovery, current-state readback, source publication,
  and GraphQL tool execution;
- Codex coding-runtime turn execution with `OPENAI_API_KEY` as the required
  live credential for the active connector profile;
- GitHub proposed-change evidence and cleanup, including a disposable cleanup
  fixture.

These are connector and runtime facts inside Jido Integration. Higher layers
should see connector-binding refs, credential-lease refs, runtime route refs,
lower-request refs, review/lower-fact refs, and receipts. Raw credential values
must not appear in DTOs, receipts, traces, durable lower facts, or public docs
evidence.

Live provider commands that exercise GitHub or Linear must be run with:

```bash
~/scripts/with_bash_secrets <command>
```

This keeps release proof commands reproducible without recording secret values.

## Migration And Cleanup Ownership

Jido Integration cleanup work removes hidden provider defaults, raw secret
ingress, duplicate provider classifiers outside the canonical classification
package, direct runtime bypasses, and ungoverned connector calls after scanner
and conformance proofs cover the replacement path.
