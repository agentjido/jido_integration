# Durability

Durability is explicit. The platform does not hide a storage choice behind the
facade. Hosts choose the tier that matches their environment.

## Default State

`core/auth` and `core/control_plane` ship with in-memory defaults. That is the
right choice when process lifetime is enough. The default profile is
`:mickey_mouse`; it resolves through GroundPlane persistence policy and does
not require host config, Postgres, local durability, or connector-admission
adapter registration.

## Local Durability

`core/store_local` is the restart-safe single-node durability tier.

Use it when:

- you want restart recovery without provisioning Postgres
- you are proving end-to-end behavior locally
- you want a simple local file-backed durability story
- you want the first durable submission-ledger backend for local
  brain-to-lower-gateway intake proofs

Select it explicitly with `Jido.Integration.V2.StoreLocal.configure_defaults!`
and `persistence_profile: :local_restart_safe`. The package publishes a
GroundPlane `:local_restart_safe` capability before auth or control-plane store
selection changes.

## Postgres Durability

`core/store_postgres` is the canonical shared durable tier.

Use it when:

- you need multi-process or shared-environment durability
- you want Ecto-backed migrations and SQL tooling
- you need the operational model that the reference apps and root validation
  expect
- you need the canonical durable submission-ledger backend for shared
  brain-to-lower-gateway intake

Select it explicitly through the Postgres package or test support with
`:integration_postgres`. The package exposes a GroundPlane
`:postgres_shared` capability and durable preflight fails before store mutation
when that capability is not supplied.

## Inference Baseline

The live inference runtime reuses the same control-plane stores.

The minimum persisted truth is:

- one run
- one attempt
- the ordered inference event sequence
- optional artifact refs when transcript or summary persistence is enabled
- enough durable data for `review_packet/2` to reconstruct the operator packet

See `inference_baseline.md` for the exact contract and event minimum.

## Selection Rule

Do not promote durability into the facade by default.
Choose the tier explicitly from the host application and keep the contract
surface stable.

That same rule now applies to durable brain-to-lower-gateway intake. Submission
acceptance is owned by `core/brain_ingress`, while `core/store_local` and
`core/store_postgres` provide the concrete ledger backends.
