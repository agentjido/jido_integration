# Control Plane Examples

These examples exercise the live inference control-plane path while keeping the
proof offline and deterministic.

## Files

- `inference_event_baseline.exs`
  - invokes one cloud inference request through `ControlPlane.invoke_inference/2`
  - shows the durable event order emitted by the live runtime path
  - demonstrates that the stored attempt output stays reviewable without
    reaching back into runtime state

## Notes

- the example starts the auth and control-plane OTP trees directly
- durable inference envelopes are stored with string keys so they stay
  JSON-safe for cross-repo review
- the cloud lane stays offline by using `Req.Test`
- CLI publication and live `jido_os` integration remain out of scope in this
  phase
