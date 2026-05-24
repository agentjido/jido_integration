# Jido Inference Runtime

This package executes `Jido.Integration.ModelInvocation.Request` values through
explicit invoker backends and emits `Jido.Integration.ModelInvocation.Receipt`
values.

The default backend is deterministic and fixture-safe. Live or control-plane
execution requires an explicit invoker option. Runtime code does not read
provider selection, credentials, or backend choice from ambient environment.

Backends:

- `Jido.Integration.InferenceRuntime.FakeInvoker`
- `Jido.Integration.InferenceRuntime.ControlPlaneInvoker`

The control-plane invoker delegates to the existing
`Jido.Integration.V2.ControlPlane.invoke_inference/2` path, preserving durable
run, attempt, event, credential lease, and review truth.
