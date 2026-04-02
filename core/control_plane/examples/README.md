# Control Plane Examples

These examples exercise the live inference control-plane path while keeping the
proof offline and deterministic.

## Files

- `inference_event_baseline.exs`
  - invokes one cloud inference request through `ControlPlane.invoke_inference/2`
  - shows the durable event order emitted by the live runtime path
  - demonstrates that the stored attempt output stays reviewable without
    reaching back into runtime state
- `inference_cli_endpoint_baseline.exs`
  - invokes one CLI inference request through `ControlPlane.invoke_inference/2`
  - publishes the endpoint through `ASM.InferenceEndpoint`
  - records the durable `:cli` route, backend manifest, and reviewable event
    sequence without depending on a real provider login

## Notes

- the example starts the auth and control-plane OTP trees directly
- durable inference envelopes are stored with string keys so they stay
  JSON-safe for cross-repo review
- the cloud lane stays offline by using `Req.Test`
- the CLI lane stays offline by configuring a fake ASM backend under the real
  endpoint publication seam
