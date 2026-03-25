# Jido Integration V2 Policy

Admission and execution governor for connector capabilities.

## Owns

- normalize the shared `Gateway` request shape before attempt creation
- compose actor, tenant, environment, runtime-class, operation, scope, and
  sandbox rules
- return `PolicyDecision` values with durable audit context plus normalized
  execution policy
- translate host-supplied pressure snapshots into `:shed` admission verdicts
  when requested
- keep sandbox and egress posture as explicit policy data instead of ad hoc
  runtime flags

## Built-In Rules

- `RequireOperation`
- `RequireActor`
- `RequireTenant`
- `RequireEnvironment`
- `RequireRuntimeClass`
- `RequireScopes`
- `EnforceSandbox`

## Security Floor

- denials happen before attempt creation
- denials stay durable through `PolicyDecision.audit_context`
- shed decisions also happen before attempt creation and remain durable through
  `PolicyDecision.audit_context`
- `sandbox: :none` requires manual approvals
- runtime code receives execution policy separately from pre-dispatch
  admission facts

## Pressure Semantics

Policy owns the admission verdict, not the retry schedule.

Current pressure input:

- callers can pass a gateway metadata snapshot like
  `%{pressure: %{decision: :shed, reason: "...", scope: "..."}}`
- `:shed` becomes a distinct policy verdict
- deny reasons still win over shed reasons when both are present
- `:backoff` is intentionally ignored here because async runtimes own retry
  timing

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Observability](../../guides/observability.md)
