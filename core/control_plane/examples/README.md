# Control Plane Examples

These examples exercise the phase-0 inference durability path without
introducing live runtime dependencies.

## Files

- `inference_event_baseline.exs`
  - records one self-hosted streaming attempt
  - shows the durable event order
  - demonstrates the minimum persisted stream lifecycle summary

## Notes

- the example starts the auth and control-plane OTP trees directly
- no live `req_llm`, CLI runtime, self-hosted runtime, or `jido_os`
  integration is required
