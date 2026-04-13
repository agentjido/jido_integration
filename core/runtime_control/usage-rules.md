# Jido.RuntimeControl Usage Rules

## Scope

- `jido_runtime_control` is the shared Session Control seam for runtime drivers.
- Keep it runtime-driver-focused and transport-agnostic.
- Do not add platform orchestration or connector-specific logic here.

## Public API

- Keep the facade in `Jido.RuntimeControl` small and stable.
- Validate external inputs through the public IR schema modules.
- Return `ExecutionEvent`, `ExecutionResult`, `ExecutionStatus`, and related
  Session Control structs rather than package-private shapes.

## Error Handling

- Use `Jido.RuntimeControl.Error` helpers for external-facing failures.
- Prefer structured runtime-driver errors over broad fallback tuples.

## Testing

- Prefer deterministic runtime-driver stubs for unit tests.
- Keep the contract surface covered through `RuntimeDriverContract`.
- Finish with the root `mix ci` gate.
