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

## `apps/inference_ops`

This app proves the first live `:inference` runtime family.

- cloud provider calls stay `runtime_kind: :client`
- self-hosted `llama_cpp_ex` calls stay `runtime_kind: :service`
- both routes execute through `req_llm`
- both routes remain reviewable through durable control-plane records

## Reading Rule

Use the reference apps to understand the integration story end to end. Do not
use them as a substitute for the package boundaries that own the underlying
behavior.
