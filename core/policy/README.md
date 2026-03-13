# Jido Integration V2 Policy

Owns the admission and execution governor for connector capabilities.

Current responsibilities:

- normalize the shared `Gateway` request shape before attempt creation
- compose actor, tenant, environment, runtime-class, operation, scope, and sandbox rules
- return `PolicyDecision` values with durable audit context plus normalized execution policy
- keep sandbox and egress posture as explicit policy data instead of ad hoc runtime flags

Current built-in rule set:

- `RequireOperation`
- `RequireActor`
- `RequireTenant`
- `RequireEnvironment`
- `RequireRuntimeClass`
- `RequireScopes`
- `EnforceSandbox`

Security floor:

- denials happen before attempt creation
- denials stay durable through `PolicyDecision.audit_context`
- `sandbox: :none` requires manual approvals
- runtime code receives execution policy separately from pre-dispatch admission facts
