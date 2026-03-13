# Jido Integration V2 Ingress

Owns trigger normalization at the control-plane boundary:

- webhook signature verification and normalization
- polling trigger normalization
- durable dedupe and checkpoint progression through `core/control_plane`
- trigger-to-run admission without creating runtime-local truth
- `jido_signal` envelope creation at the ingress boundary only
