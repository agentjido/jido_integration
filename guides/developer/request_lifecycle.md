# Request Lifecycle

This is the internal path a request takes through the repo.

## Direct Capability Flow

1. a consumer builds `InvocationRequest`
2. `core/platform` normalizes the request
3. `core/auth` resolves the connection and issues a short-lived lease if
   needed
4. `core/policy` evaluates the gateway request and either allows, denies, or
   sheds it
5. `core/control_plane` creates or loads the run and attempt truth
6. `core/direct_runtime` executes the capability through the provider SDK path
7. `core/control_plane` records events, artifacts, and final run state

## Runtime-Control-Backed Flow

1. the capability is authored with a non-direct runtime driver such as `asm`
   or `jido_session`
2. `core/control_plane` resolves the authored target requirements
3. `core/asm_runtime_bridge` projects the authored `asm` driver into Runtime Control
   when that driver is selected
4. `core/session_runtime` owns the in-repo `jido_session` driver when that
   driver is selected
5. `Jido.RuntimeControl` executes the runtime driver and returns session-aware output
6. `core/control_plane` persists attempts, events, and artifacts

## Brain-to-lower-gateway Submission Flow

1. an upstream Brain emits a durable submission packet such as
   `BrainInvocation`
2. `core/brain_ingress` validates the packet and re-verifies lower-gateway-owned
   governance shadows before runtime policy is touched
3. `core/brain_ingress` resolves logical workspace or file-scope refs into
   concrete runtime paths
4. the selected submission ledger records durable acceptance or typed
   rejection
5. the resulting `Gateway` and runtime inputs continue through the normal
   policy and runtime paths downstream of durable acceptance

## Async And Hosted Webhook Flow

1. a hosted route is registered in `core/webhook_router`
2. an incoming webhook is normalized into an `Ingress.Definition`
3. `core/ingress` validates the signal and records durable trigger admission
4. `core/control_plane` creates the run truth
5. `core/dispatch_runtime` owns delivery, retry, dead-letter, and replay

## Data Ownership

- auth state belongs to `core/auth`
- durable brain-to-lower-gateway acceptance belongs to `core/brain_ingress`
- run and attempt truth belongs to `core/control_plane`
- route state belongs to `core/webhook_router`
- transport retry state belongs to `core/dispatch_runtime`
- projection contracts belong to `core/contracts`

## Practical Rule

When you are debugging a flow, ask which package owns the first durable write
and which package owns the last runtime action. That usually identifies the
place to instrument or modify.

If the answer is "the workspace root", the ownership is probably wrong.
