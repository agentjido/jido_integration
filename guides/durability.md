# Durability

Durability is explicit. The platform does not hide a storage choice behind the
facade. Hosts choose the tier that matches their environment.

## Default State

`core/auth` and `core/control_plane` ship with in-memory defaults. That is the
right choice when process lifetime is enough.

## Local Durability

`core/store_local` is the restart-safe single-node durability tier.

Use it when:

- you want restart recovery without provisioning Postgres
- you are proving end-to-end behavior locally
- you want a simple local file-backed durability story
- you want the first durable submission-ledger backend for local
  Brain-to-Spine intake proofs

## Postgres Durability

`core/store_postgres` is the canonical shared durable tier.

Use it when:

- you need multi-process or shared-environment durability
- you want Ecto-backed migrations and SQL tooling
- you need the operational model that the reference apps and root validation
  expect
- you need the canonical durable submission-ledger backend for shared
  Brain-to-Spine intake

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

That same rule now applies to durable Brain-to-Spine intake. Submission
acceptance is owned by `core/brain_ingress`, while `core/store_local` and
`core/store_postgres` provide the concrete ledger backends.
