# Durability

Durability is a package-owned concern, not a hidden default.

## Default State

`core/auth` and `core/control_plane` ship with in-memory defaults. That is the
right choice when process lifetime is enough.

## Local Durability

`core/store_local` is the restart-safe single-node durability tier.

Use it when:

- you want restart recovery without provisioning Postgres
- you are proving end-to-end behavior locally
- you want a simple local file-backed durability story

## Postgres Durability

`core/store_postgres` is the canonical shared durable tier.

Use it when:

- you need multi-process or shared-environment durability
- you want Ecto-backed migrations and SQL tooling
- you need the operational model that the reference apps and root validation
  expect

## Selection Rule

Do not promote durability into the facade by default.
Choose the tier explicitly from the host application and keep the contract
surface stable.
