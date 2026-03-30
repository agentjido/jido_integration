# Core Packages

The core packages are intentionally small and explicit. Each package has one
primary owner, one main boundary, and one or two clear upstream consumers.

This is the internal map for contributors. If you are deciding where code
belongs, start here before touching the root workspace or widening an existing
package.

Non-core bridge packages live under `bridges/`. The current dedicated bridge
package is `bridges/boundary_bridge`.

## Package Map

| Package | Owns | Key Use |
| --- | --- | --- |
| `core/contracts` | public IR, behaviours, generated projections | read first when changing the public shape |
| `core/platform` | the stable `Jido.Integration.V2` facade | use when exposing the public API |
| `core/auth` | installs, credentials, connection truth, leases | use for any auth lifecycle change |
| `core/control_plane` | runs, attempts, events, triggers, artifacts, targets | use for execution truth and review data |
| `core/consumer_surfaces` | generated common action, sensor, and plugin runtime support | use when changing published generated consumer behavior |
| `core/policy` | admission, deny, and shed decisions | use for pre-attempt gating logic |
| `core/direct_runtime` | direct provider-SDK execution | use for stateless capabilities |
| `core/runtime_asm_bridge` | authored `asm` Harness projection | use only for the ASM seam |
| `core/session_runtime` | internal `jido_session` Harness runtime | use for the in-repo session seam |
| `core/ingress` | trigger normalization and durable admission | use for webhook and polling admission |
| `core/dispatch_runtime` | async dispatch, retry, replay, recovery | use for host-controlled background execution |
| `core/webhook_router` | hosted route records and callback topology | use for persisted hosted ingress routing |
| `core/store_local` | single-node restart-safe durability | use for local development and proofs |
| `core/store_postgres` | canonical Ecto/Postgres durability | use for shared durable environments |
| `core/conformance` | reusable connector acceptance engine | use for package review and fixtures |

## Package Dependencies

- `core/contracts` is the narrowest contract layer.
- `core/platform` depends on the auth and control-plane surface, but not on
  runtime-specific implementation details.
- `core/consumer_surfaces` projects authored common publication into generated
  Jido-native runtime support.
- `core/auth` and `core/control_plane` define behaviours first, then rely on
  store implementations to persist state.
- `core/store_local` and `core/store_postgres` implement those behaviours
  without becoming public facades.
- `core/direct_runtime`, `core/ingress`, `core/policy`, `core/dispatch_runtime`,
  and `core/webhook_router` are the execution and transport layers.
- `core/runtime_asm_bridge` and `core/session_runtime` are intentionally
  narrow runtime seams and should stay that way.

The workspace root should remain orchestration only. If a change feels like it
needs new logic at the root, that is usually a sign the behavior belongs in a
child package instead.

## Editing Rules

- change `core/contracts` first when the public shape changes
- change the owning package next
- update the matching README and guide if the boundary moved
- update the package `mix.exs` docs group if a new internals guide is needed

## Boundary Rule

If a change needs more than one owner package, write down the seam before you
code it. That usually means the contract belongs in `core/contracts` and the
behavior belongs in exactly one downstream package.
