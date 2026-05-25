# Model Call Receipts

Jido Integration owns model invocation request, receipt, stream fragment, and
provider-runtime posture contracts for the NSHKR stack.

## Public Packages

- `core/model_invocation_contracts`
- `core/inference_runtime`

## Invocation Inputs

Mezzanine passes only governed refs and hashes into model invocation:

- `prompt_artifact_ref`;
- `provider_payload_ref`;
- `payload_hash`;
- context packet, route decision, authority, trace, budget, and credential
  lease refs.

Jido Integration does not compile context, grant authority, choose product
defaults, or promote optimization candidates. It executes the selected
governed invocation path and returns bounded receipts.

## Receipt Outputs

Receipts include request refs, provider/model refs, token and cost summaries,
stream fragment refs when streaming is enabled, redaction posture, trace refs,
and failure reason codes. Raw provider payloads and credentials must not appear
in public receipts.

## Local QC

```bash
mix ci
```
