# Jido.RuntimeControl Usage Rules

## Scope
- `jido_runtime_control` is a normalization layer for CLI coding-agent adapters.
- Keep it transport-agnostic and provider-neutral.
- Do not add provider-specific execution logic here.

## Public API
- Keep the facade in `Jido.RuntimeControl` small and stable.
- Validate external inputs through schema modules.
- Return normalized `%Jido.RuntimeControl.Event{}` streams.

## Error Handling
- Use `Jido.RuntimeControl.Error` helpers for external-facing failures.
- Preserve provider errors in `details` where possible.

## Testing
- Prefer deterministic adapter stubs for unit tests.
- Keep coverage above the configured threshold.
- Run `mix quality` before release.
