# Contracts Examples

These examples exercise the shared inference contract seam without depending on
live runtime integrations.

## Files

- `inference_contract_round_trip.exs`
  - builds the phase-0 inference structs
  - dumps them into their string-keyed durable map form
  - shows the JSON-safe shape that other repos should treat as authoritative

## Notes

- `TargetDescriptor` is reused separately as the durable target advertisement
  contract
- `ReqLLMCallSpec` remains a local adapter detail and does not appear here
