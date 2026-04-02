# Reference Apps

The reference apps show how the platform is composed in real host-facing
workflows. They are proof surfaces, not the place to reintroduce platform
ownership.

## `apps/trading_ops`

This app proves one operator-visible workflow across direct, session, and
stream runtimes. It also shows how trigger admission, control-plane truth, and
public invocation compose in practice.

## `apps/devops_incident_response`

This app proves hosted webhook registration, async dispatch, dead-letter,
replay, and restart recovery while keeping the webhook behavior app-local. Its
hosted GitHub issue trigger now converges on the same generated sensor and
plugin contract layer used by the common trigger path.

## Reading Rule

Use the reference apps to understand the integration story end to end. Do not
use them as a substitute for the package boundaries that own the underlying
behavior.

Phase-0 inference baseline proof is intentionally package-local for now. It
lands in `core/contracts`, `core/control_plane`, and `core/platform` examples
and tests rather than introducing a live runtime app before the durable seam is
stable.
