# Platform Examples

These examples exercise the public inference facade and review seam above the
durable control plane.

## Files

- `inference_review_packet.exs`
  - invokes one cloud inference request through `Jido.Integration.V2.invoke_inference/2`
  - reads it back through `Jido.Integration.V2.review_packet/2`
  - shows the synthetic inference connector and capability summary

## Notes

- the example keeps the cloud proof offline with `Req.Test`
- the stored inference envelopes stay string-keyed and JSON-safe while the
  projected packet keeps typed runtime summary fields
- no live self-hosted runtime or `jido_os` integration is required
