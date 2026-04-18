# Jido Integration V2 Brain Ingress

`core/brain_ingress` owns the durable brain-to-lower-gateway intake seam.

It is responsible for:

- validating the Brain submission packet
- verifying lower-gateway-owned governance shadows
- resolving logical workspace scope into concrete runtime paths
- recording durable submission acceptance or typed rejection
- exposing durable submission acceptance lookup for lower receipt readback

It does not own execution itself. Execution remains downstream of durable
acceptance.
