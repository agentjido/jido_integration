# Jido Integration V2 Store Postgres

Owns the foundation-phase durability surface:

- the canonical `Ecto.Repo`
- migrations for control-plane and auth truth
- SQL sandbox helpers for durability tests
- Postgres adapters for `control_plane` and `auth` behaviours
- durable tables for `ArtifactRef` and `TargetDescriptor`
- encrypted durable credential rows plus safe connection/install/lease rows for auth lifecycle truth

Repo ownership and migration ownership are explicit here by design. During the
foundation phase, owner packages define behaviours while `store_postgres`
implements them and keeps database startup, migrations, and test posture
coherent.

Current control-plane durability includes:

- runs, attempts, and append-only run events
- trigger records, dedupe keys, and polling checkpoints
- artifact refs keyed by `artifact_id` and indexed by `run_id`
- target descriptors keyed by `target_id`
- durable round-tripping of integrity metadata and target compatibility inputs
- auth rows with:
  - encrypted secret-bearing credential fields
  - explicit connection state and install-session state
  - lease records that persist only bounded metadata, not raw lease payloads
