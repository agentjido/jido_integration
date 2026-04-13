# jido_integration v0.1.0 - API Reference

## Modules

- [Jido.Integration.V2](Jido.Integration.V2.md): Public facade package for the greenfield `jido_integration_v2` platform.
- [Jido.Integration.V2.ArtifactRef](Jido.Integration.V2.ArtifactRef.md): Stable public reference to a run artifact.
- [Jido.Integration.V2.AttachGrant](Jido.Integration.V2.AttachGrant.md): Durable lower-truth grant allowing a route or consumer to attach to a boundary session.

- [Jido.Integration.V2.Attempt](Jido.Integration.V2.Attempt.md): One concrete execution attempt of a run.

- [Jido.Integration.V2.Auth](Jido.Integration.V2.Auth.md): Durable connection/install truth plus short-lived credential leases.

- [Jido.Integration.V2.Auth.Connection](Jido.Integration.V2.Auth.Connection.md): Durable connection truth owned by `auth`.

- [Jido.Integration.V2.Auth.ConnectionStore](Jido.Integration.V2.Auth.ConnectionStore.md): Durable connection-truth behaviour owned by `auth`.

- [Jido.Integration.V2.Auth.CredentialStore](Jido.Integration.V2.Auth.CredentialStore.md): Durable credential-truth behaviour owned by `auth`.

- [Jido.Integration.V2.Auth.Install](Jido.Integration.V2.Auth.Install.md): Durable install-session truth owned by `auth`.

- [Jido.Integration.V2.Auth.InstallStore](Jido.Integration.V2.Auth.InstallStore.md): Durable install-session behaviour owned by `auth`.

- [Jido.Integration.V2.Auth.LeaseRecord](Jido.Integration.V2.Auth.LeaseRecord.md): Durable lease metadata. Secret payload is reconstructed from credential truth.

- [Jido.Integration.V2.Auth.LeaseStore](Jido.Integration.V2.Auth.LeaseStore.md): Durable credential-lease behaviour owned by `auth`.

- [Jido.Integration.V2.AuthSpec](Jido.Integration.V2.AuthSpec.md): Authored auth contract for a connector manifest.

- [Jido.Integration.V2.AuthorityAuditEnvelope](Jido.Integration.V2.AuthorityAuditEnvelope.md): Spine-owned machine-readable authority audit payload derived from the Brain packet.

- [Jido.Integration.V2.BackendManifest](Jido.Integration.V2.BackendManifest.md): Declares what a runtime backend can expose to the inference control plane.

- [Jido.Integration.V2.BoundaryCapability](Jido.Integration.V2.BoundaryCapability.md): Typed boundary capability advertisement for target descriptors.
- [Jido.Integration.V2.BoundarySession](Jido.Integration.V2.BoundarySession.md): Durable lower-truth record for one boundary session lineage.

- [Jido.Integration.V2.BrainIngress](Jido.Integration.V2.BrainIngress.md): Durable Brain-to-Spine invocation intake.

- [Jido.Integration.V2.BrainIngress.ScopeResolver](Jido.Integration.V2.BrainIngress.ScopeResolver.md): Resolves logical workspace references into concrete runtime paths.

- [Jido.Integration.V2.BrainIngress.StaticScopeResolver](Jido.Integration.V2.BrainIngress.StaticScopeResolver.md): Minimal same-node resolver for logical workspace references.

- [Jido.Integration.V2.BrainIngress.SubmissionLedger](Jido.Integration.V2.BrainIngress.SubmissionLedger.md): Durable acceptance ledger for Brain submissions.

- [Jido.Integration.V2.BrainInvocation](Jido.Integration.V2.BrainInvocation.md): Durable Brain-to-Spine invocation handoff packet.

- [Jido.Integration.V2.CanonicalJson](Jido.Integration.V2.CanonicalJson.md): Spine-owned canonical JSON normalization and RFC 8785 / JCS encoding helpers.

- [Jido.Integration.V2.Capability](Jido.Integration.V2.Capability.md): Derived executable projection used by the control plane.

- [Jido.Integration.V2.CatalogSpec](Jido.Integration.V2.CatalogSpec.md): Authored catalog metadata for a connector manifest.

- [Jido.Integration.V2.CompatibilityResult](Jido.Integration.V2.CompatibilityResult.md): Typed compatibility outcome for an admitted inference route.

- [Jido.Integration.V2.Connector](Jido.Integration.V2.Connector.md): Behaviour for connector packages that publish manifests.

- [Jido.Integration.V2.Connectors.GitHub](Jido.Integration.V2.Connectors.GitHub.md): Thin direct GitHub connector package backed by `github_ex`.

- [Jido.Integration.V2.Connectors.Linear](Jido.Integration.V2.Connectors.Linear.md): Thin direct Linear connector package backed by `linear_sdk`.

- [Jido.Integration.V2.Connectors.Notion](Jido.Integration.V2.Connectors.Notion.md): Thin direct Notion connector package backed by `notion_sdk`.

- [Jido.Integration.V2.ConsumerManifest](Jido.Integration.V2.ConsumerManifest.md): Declares what an inference consumer can accept from a runtime route.

- [Jido.Integration.V2.ConsumerProjection](Jido.Integration.V2.ConsumerProjection.md): Shared projection rules for generated consumer surfaces built from authored
manifests.
- [Jido.Integration.V2.ConsumerProjection.ActionProjection](Jido.Integration.V2.ConsumerProjection.ActionProjection.md): Projected metadata for a generated `Jido.Action` surface.

- [Jido.Integration.V2.ConsumerProjection.PluginProjection](Jido.Integration.V2.ConsumerProjection.PluginProjection.md): Projected metadata for a generated `Jido.Plugin` bundle.

- [Jido.Integration.V2.ConsumerProjection.SensorProjection](Jido.Integration.V2.ConsumerProjection.SensorProjection.md): Projected metadata for a generated `Jido.Sensor` surface.

- [Jido.Integration.V2.Contracts](Jido.Integration.V2.Contracts.md): Shared public types and validation helpers for the greenfield integration platform.

- [Jido.Integration.V2.ControlPlane](Jido.Integration.V2.ControlPlane.md): Connector registry plus canonical run/attempt/event ledger.
- [Jido.Integration.V2.ControlPlane.ArtifactStore](Jido.Integration.V2.ControlPlane.ArtifactStore.md): Durable artifact-reference truth owned by `control_plane`.

- [Jido.Integration.V2.ControlPlane.AttemptStore](Jido.Integration.V2.ControlPlane.AttemptStore.md): Durable attempt-truth behaviour owned by `control_plane`.

- [Jido.Integration.V2.ControlPlane.EventStore](Jido.Integration.V2.ControlPlane.EventStore.md): Durable append-only event-ledger behaviour owned by `control_plane`.

- [Jido.Integration.V2.ControlPlane.IngressStore](Jido.Integration.V2.ControlPlane.IngressStore.md): Durable ingress-truth behaviour owned by `control_plane`.

- [Jido.Integration.V2.ControlPlane.RunStore](Jido.Integration.V2.ControlPlane.RunStore.md): Durable run-truth behaviour owned by `control_plane`.

- [Jido.Integration.V2.ControlPlane.TargetStore](Jido.Integration.V2.ControlPlane.TargetStore.md): Durable target-descriptor truth owned by `control_plane`.

- [Jido.Integration.V2.Credential](Jido.Integration.V2.Credential.md): Resolved credential owned by the control plane.

- [Jido.Integration.V2.CredentialLease](Jido.Integration.V2.CredentialLease.md): Short-lived execution material derived from a durable `CredentialRef`.

- [Jido.Integration.V2.CredentialRef](Jido.Integration.V2.CredentialRef.md): Opaque control-plane-owned credential handle.

- [Jido.Integration.V2.DerivedStateAttachment](Jido.Integration.V2.DerivedStateAttachment.md): Canonical attachment contract for higher-order derived state.
- [Jido.Integration.V2.DirectRuntime](Jido.Integration.V2.DirectRuntime.md): Executes direct capabilities through `Jido.Action` modules.

- [Jido.Integration.V2.DispatchRuntime](Jido.Integration.V2.DispatchRuntime.md): Async trigger dispatch runtime with durable transport-state recovery.

- [Jido.Integration.V2.DispatchRuntime.Dispatch](Jido.Integration.V2.DispatchRuntime.Dispatch.md): Durable transport-state record for async trigger execution.

- [Jido.Integration.V2.DispatchRuntime.Handler](Jido.Integration.V2.DispatchRuntime.Handler.md): Host-controlled trigger handler registration for async dispatch execution.

- [Jido.Integration.V2.DispatchRuntime.Telemetry](Jido.Integration.V2.DispatchRuntime.Telemetry.md): Package-owned `:telemetry` surface for async dispatch lifecycle observation.
- [Jido.Integration.V2.EndpointDescriptor](Jido.Integration.V2.EndpointDescriptor.md): Execution-ready resolved inference endpoint for one attempt or lease.

- [Jido.Integration.V2.Event](Jido.Integration.V2.Event.md): Canonical append-only event for run and attempt observation.

- [Jido.Integration.V2.EvidenceRef](Jido.Integration.V2.EvidenceRef.md): Stable reference to a source record backing a packet, decision, or interpretation.

- [Jido.Integration.V2.ExecutionGovernanceProjection](Jido.Integration.V2.ExecutionGovernanceProjection.md): Spine-owned machine-readable governance projection carried in Brain submissions.

- [Jido.Integration.V2.ExecutionGovernanceProjection.Compiler](Jido.Integration.V2.ExecutionGovernanceProjection.Compiler.md): Compiles Spine-owned governance projections into operational shadow sections.

- [Jido.Integration.V2.ExecutionGovernanceProjection.Verifier](Jido.Integration.V2.ExecutionGovernanceProjection.Verifier.md): Verifies that supplied operational shadow sections still match the Spine compiler.

- [Jido.Integration.V2.ExecutionRoute](Jido.Integration.V2.ExecutionRoute.md): Durable lower-truth record for a committed execution route.

- [Jido.Integration.V2.ExecutionRouter](Jido.Integration.V2.ExecutionRouter.md): Stable runtime-family routing seam for the control plane.

- [Jido.Integration.V2.Gateway](Jido.Integration.V2.Gateway.md): Canonical gateway input for pre-dispatch admission and in-run execution policy.

- [Jido.Integration.V2.Gateway.Policy](Jido.Integration.V2.Gateway.Policy.md): Normalized capability policy contract for gateway admission and execution.

- [Jido.Integration.V2.GeneratedAction](Jido.Integration.V2.GeneratedAction.md): Macro for generating a `Jido.Action` from an authored operation spec.

- [Jido.Integration.V2.GeneratedPlugin](Jido.Integration.V2.GeneratedPlugin.md): Macro for generating a connector-level `Jido.Plugin` bundle from authored
manifest truth.
- [Jido.Integration.V2.GeneratedSensor](Jido.Integration.V2.GeneratedSensor.md): Macro for generating a `Jido.Sensor` from an authored trigger spec.
- [Jido.Integration.V2.GovernanceRef](Jido.Integration.V2.GovernanceRef.md): Stable reference to governance lineage such as approval, denial, override, rollback, or policy decisions.

- [Jido.Integration.V2.InferenceExecutionContext](Jido.Integration.V2.InferenceExecutionContext.md): Control-plane context attached to an admitted inference attempt.

- [Jido.Integration.V2.InferenceRequest](Jido.Integration.V2.InferenceRequest.md): Normalized admitted inference intent before target resolution.

- [Jido.Integration.V2.InferenceResult](Jido.Integration.V2.InferenceResult.md): Canonical terminal inference outcome projected by the control plane.

- [Jido.Integration.V2.Ingress](Jido.Integration.V2.Ingress.md): Normalizes webhook and polling triggers into durable control-plane truth.

- [Jido.Integration.V2.Ingress.Definition](Jido.Integration.V2.Ingress.Definition.md): Ingress-side trigger definition used to normalize webhook and polling inputs.

- [Jido.Integration.V2.InvocationRequest](Jido.Integration.V2.InvocationRequest.md): Typed public request for capability invocation through the v2 facade.
- [Jido.Integration.V2.LeaseRef](Jido.Integration.V2.LeaseRef.md): Durable reference to a reusable runtime lease or endpoint instance.

- [Jido.Integration.V2.Manifest](Jido.Integration.V2.Manifest.md): Connector-level authored contract plus derived executable projection.

- [Jido.Integration.V2.OperationSpec](Jido.Integration.V2.OperationSpec.md): Authored operation contract for a connector manifest.

- [Jido.Integration.V2.Operator](Jido.Integration.V2.Operator.md): Shared read-only operator surface over durable auth and control-plane truth.
- [Jido.Integration.V2.Policy](Jido.Integration.V2.Policy.md): Admission and execution governor for capability invocation.

- [Jido.Integration.V2.Policy.RespectPressure](Jido.Integration.V2.Policy.RespectPressure.md): Translates host-supplied pressure snapshots into a shed-only admission verdict.
- [Jido.Integration.V2.Policy.Rule](Jido.Integration.V2.Policy.Rule.md): Behaviour for admission rules.

- [Jido.Integration.V2.PolicyDecision](Jido.Integration.V2.PolicyDecision.md): Captures the control-plane admission decision for a run.

- [Jido.Integration.V2.Receipt](Jido.Integration.V2.Receipt.md): Durable lower-truth acknowledgement or completion receipt.

- [Jido.Integration.V2.RecoveryTask](Jido.Integration.V2.RecoveryTask.md): Durable lower-truth recovery or reconciliation task.

- [Jido.Integration.V2.Redaction](Jido.Integration.V2.Redaction.md): Recursive redaction for audit-visible durable truth.

- [Jido.Integration.V2.ReviewBundle](Jido.Integration.V2.ReviewBundle.md): Operator-facing lower-truth review bundle usable by northbound surfaces.

- [Jido.Integration.V2.ReviewProjection](Jido.Integration.V2.ReviewProjection.md): Contracts-only northbound review projection carried in review packet metadata.

- [Jido.Integration.V2.Run](Jido.Integration.V2.Run.md): Durable record of requested work.

- [Jido.Integration.V2.RuntimeResult](Jido.Integration.V2.RuntimeResult.md): Shared runtime emission envelope for direct, session, and stream execution.

- [Jido.Integration.V2.StoreLocal](Jido.Integration.V2.StoreLocal.md): Local durable adapter package for auth and control-plane store behaviours.

- [Jido.Integration.V2.StorePostgres](Jido.Integration.V2.StorePostgres.md): Postgres durability package owning the Repo, migrations, and SQL sandbox posture.

- [Jido.Integration.V2.StorePostgres.Repo](Jido.Integration.V2.StorePostgres.Repo.md)
- [Jido.Integration.V2.SubjectRef](Jido.Integration.V2.SubjectRef.md): Stable reference to the primary node-local subject a higher-order record is about.

- [Jido.Integration.V2.SubmissionAcceptance](Jido.Integration.V2.SubmissionAcceptance.md): Durable Spine acceptance receipt for a Brain submission.

- [Jido.Integration.V2.SubmissionIdentity](Jido.Integration.V2.SubmissionIdentity.md): Spine-owned stable identity for a durable Brain submission.

- [Jido.Integration.V2.SubmissionRejection](Jido.Integration.V2.SubmissionRejection.md): Typed Spine rejection for a Brain submission.

- [Jido.Integration.V2.TargetDescriptor](Jido.Integration.V2.TargetDescriptor.md): Stable public descriptor for an execution target.
- [Jido.Integration.V2.TriggerCheckpoint](Jido.Integration.V2.TriggerCheckpoint.md): Durable checkpoint for polling-style trigger progression.

- [Jido.Integration.V2.TriggerRecord](Jido.Integration.V2.TriggerRecord.md): Durable trigger admission or rejection record owned by the control plane.

- [Jido.Integration.V2.TriggerSpec](Jido.Integration.V2.TriggerSpec.md): Authored trigger contract for a connector manifest.

- [Jido.Integration.V2.WebhookRouter](Jido.Integration.V2.WebhookRouter.md): Hosted webhook route registry plus ingress and dispatch bridging.

- [Jido.Integration.V2.WebhookRouter.Route](Jido.Integration.V2.WebhookRouter.Route.md): Durable hosted-webhook route metadata.

- [Jido.Integration.V2.WebhookRouter.Telemetry](Jido.Integration.V2.WebhookRouter.Telemetry.md): Package-owned `:telemetry` surface for hosted webhook route resolution.

