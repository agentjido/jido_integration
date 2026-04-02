# Platform Examples

These examples exercise the public inference review seam above the durable
control plane.

## Files

- `inference_review_packet.exs`
  - records one inference attempt through the control plane
  - reads it back through `Jido.Integration.V2.review_packet/2`
  - shows the synthetic inference connector and capability summary

## Notes

- the example depends only on the phase-0 durable baseline
- the stored inference envelopes stay string-keyed and JSON-safe while the
  projected packet keeps typed runtime summary fields
- no live runtime integrations are required
