# Jido Integration V2 Linear Connector

Thin direct Linear connector package backed by `linear_sdk`, with deterministic
offline tests and no default live-proof dependency.

This connector stays on the direct provider-SDK path and does not inherit
session or stream runtime-kernel coupling merely because the repo also ships
non-direct capability families.

## Runtime And Auth Posture

- runtime family: `:direct`
- public auth binding is `connection_id`
- supported auth profiles:
  - `api_key_user` as the default manual or external-secret profile
  - `oauth_user` as the browser OAuth profile
- the manifest is the authored source of truth for `supported_profiles`,
  install modes, and reauth posture; nothing is inferred from `linear_sdk`
  helper defaults
- connector-wide management modes: `[:external_secret, :hosted, :manual]`
- durable secret fields union:
  `["access_token", "api_key", "refresh_token"]`
- lease fields union:
  `["access_token", "api_key"]`
- install posture is explicit by profile:
  - `api_key_user` supports manual API key entry or external-secret
    completion with no callback
  - `oauth_user` supports browser OAuth plus hosted or manual callback
    completion with state correlation
- reauth is published only for `oauth_user`
- the connector mints short-lived credential leases and builds
  `LinearSDK.Client` instances from those leases only
- `install_binding` remains connector-local and only feeds install, reauth,
  manual-auth, or rotation completion flows
- the live execution path is
  `Jido.Integration.V2 -> DirectRuntime -> connector -> linear_sdk -> prismatic`
- the current authored capability slice requires the Linear `read` and `write`
  scopes
- OAuth control endpoints stay in the install/auth flow rather than widening
  the invoke surface

## Capability Surface

The connector publishes the narrow A0 issue-workflow slice:

- `linear.users.get_self`
- `linear.issues.list`
- `linear.issues.retrieve`
- `linear.comments.create`
- `linear.issues.update`

These runtime capability ids stay provider-facing on purpose. They are the
stable internal routing ids used by the control plane, conformance layer, and
connector review surface.

The generated consumer surface is a separate, curated common layer. The same
authored operation specs project into these normalized action names:

- `users_get_self`
- `work_item_list`
- `work_item_fetch`
- `comment_create`
- `work_item_update`

That common layer currently projects into:

- the derived executable entry catalog used by the runtime and conformance seam
- generated actions under
  `lib/jido/integration/v2/connectors/linear/generated/actions.ex`
- a generated plugin bundle at
  `lib/jido/integration/v2/connectors/linear/generated/plugin.ex`

Those generated actions and plugin exports are derivative only. They stay
pinned to the authored common operation specs and do not become a second
authoring plane for Linear inventory, OAuth control behavior, or auth posture.

The generated plugin publishes only the curated action bundle. It does not
publish subscriptions because this connector does not expose triggers in the
initial A0 slice.

This package does not auto-project arbitrary GraphQL documents or `linear_sdk`
helpers. The current common surface is intentionally limited to the first issue
workflow slice.

## Package Verification

Default package tests stay offline and deterministic through the `linear_sdk`
transport seam. There is no second handwritten Linear HTTP client inside
`jido_integration`.

```bash
cd connectors/linear
mix deps.get
mix compile --warnings-as-errors
mix test
mix docs
```

For local multi-repo development, the connector resolves `linear_sdk` from a
sibling checkout when it exists and falls back to Hex otherwise. The package
does not carry Git fallback wiring for that SDK or a connector-local vendored
`deps/` tree.

From the workspace root, the connector should also pass the root acceptance
surface:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.Linear
mix ci
```

## Live Proof Status

No package-local live proof exists yet. Any future live acceptance should stay
package-local and continue to run through the public auth and direct-runtime
surface instead of publishing OAuth control helpers as runtime capabilities.

## SDK Boundary

Runtime requests build `LinearSDK.Client` instances only from Jido-issued
credential leases.

The connector owns:

- authored operation-spec publication and derived executable entry projection
- install-binding normalization for API key and OAuth installs
- lease-bound client construction
- GraphQL document execution, normalized runtime output, review events, and
  deterministic conformance fixtures

`linear_sdk` owns:

- provider HTTP execution
- GraphQL request construction
- OAuth helper functions and token exchange helpers built on `Prismatic.OAuth2`
- provider error envelopes and transport behavior

This connector depends on `prismatic` directly only for token-struct
normalization inside `install_binding`; the runtime invoke path still stays
lease-bound through `LinearSDK.Client`.

Offline tests override the SDK transport with deterministic fixture responses.
That seam keeps provider HTTP behavior in `linear_sdk` instead of recreating it
inside `jido_integration`.

## Package Boundary

This package owns direct Linear capability execution only.

It does not own:

- hosted OAuth callback endpoints
- dispatch-runtime handlers
- reference-app proof composition

Those higher-level concerns stay above the connector so this package remains a
thin, reviewable direct integration deliverable.

## Files

- authored operation specs and derived executable catalog:
  `lib/jido/integration/v2/connectors/linear/operation_catalog.ex`
- lease-bound client factory:
  `lib/jido/integration/v2/connectors/linear/client_factory.ex`
- install/auth normalization:
  `lib/jido/integration/v2/connectors/linear/install_binding.ex`
- generic SDK operation handler:
  `lib/jido/integration/v2/connectors/linear/operation.ex`
- deterministic fixture seam:
  `lib/jido/integration/v2/connectors/linear/fixtures.ex`
- deterministic conformance publication:
  `lib/jido/integration/v2/connectors/linear/conformance.ex`
