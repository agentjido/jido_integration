# Jido Integration V2 Ingress

Owns trigger normalization at the control-plane boundary:

- webhook signature verification and normalization
- polling trigger normalization
- durable dedupe and checkpoint progression through `core/control_plane`
- trigger-to-run admission without creating runtime-local truth
- `jido_signal` envelope creation at the ingress boundary only

Does not own:

- hosted webhook route registration or removal
- static vs dynamic callback-topology resolution
- secret-ref lookup through `core/auth`
- dispatch-runtime enqueueing after admission

Those concerns live in `core/webhook_router`, which assembles
`Ingress.Definition` values and then delegates request normalization here.
