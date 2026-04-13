# Jido Runtime Control Telemetry Contract

`Jido.RuntimeControl.Observe` is the only supported telemetry emission boundary for runtime router flows.

## Canonical Namespaces

| Namespace | Use |
| --- | --- |
| `[:jido, :runtime_control, :workspace, ...]` | Workspace/session lifecycle events |
| `[:jido, :runtime_control, :runtime, ...]` | Shared runtime validation/bootstrapping |
| `[:jido, :runtime_control, :provider, ...]` | Provider-specific runtime and stream events |

## Required Metadata

Every emitted event must contain these keys (set to `nil` when unavailable):

- `:request_id`
- `:run_id`
- `:provider`
- `:owner`
- `:repo`
- `:issue_number`
- `:session_id`

## Sensitive Data Redaction

`Jido.RuntimeControl.Observe.sanitize_sensitive/1` recursively redacts key/value pairs for common secret names:

- exact keys like `token`, `api_key`, `client_secret`, `password`
- keys containing `secret_`
- keys ending with `_token`, `_key`, `_secret`, `_password`

Redacted values are always replaced with `"[REDACTED]"`.
