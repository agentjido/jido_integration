# Contracts Examples

These examples exercise the shared inference contract seam without depending on
live runtime integrations.

They now sit beside, not instead of, the Wave 1 lower-boundary packet carried
through the lower acceptance gateway:

- `BoundarySessionDescriptor.v1`
- `ExecutionIntentEnvelope.v1`
- `ExecutionRoute.v1`
- `ExecutionEvent.v1`
- `ExecutionOutcome.v1`

## Files

- `inference_contract_round_trip.exs`
  - builds the phase-0 inference structs
  - dumps them into their string-keyed durable map form
  - shows the JSON-safe shape that other repos should treat as authoritative

## Notes

- `TargetDescriptor` is reused separately as the durable target advertisement
  contract
- `ReqLLMCallSpec` remains a local adapter detail and does not appear here
- `HttpExecutionIntent.v1`, `ProcessExecutionIntent.v1`, and
  `JsonRpcExecutionIntent.v1` remain provisional lower-family carrier shapes
  until Wave 3 prove-out
