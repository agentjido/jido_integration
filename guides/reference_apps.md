# Reference Apps

The reference apps are proof surfaces, not the place to reintroduce runtime
ownership.

## `apps/trading_ops`

This app proves one operator-visible workflow across direct, session, and
stream runtimes. It also shows how trigger admission, control-plane truth, and
public invocation compose in practice.

## `apps/devops_incident_response`

This app proves hosted webhook registration, async dispatch, dead-letter,
replay, and restart recovery while keeping the webhook behavior app-local.

## Reading Rule

Use the reference apps to understand the integration story end to end. Do not
use them as a substitute for the package boundaries that own the underlying
behavior.
