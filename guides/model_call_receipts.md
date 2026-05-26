# Model Call Receipts

Jido Integration owns model invocation request, receipt, stream fragment, and
provider-runtime posture contracts for the NSHKR stack.

## Public Packages

- `core/model_invocation_contracts`
- `core/inference_runtime`

## Invocation Inputs

Mezzanine passes only governed refs and hashes into model invocation:

- `workflow_ref`;
- `prompt_artifact_ref`;
- `provider_payload_ref`;
- `payload_hash`;
- context packet, route decision, authority, trace, budget, and credential
  lease refs.

Jido Integration does not compile context, grant authority, choose product
defaults, or promote optimization candidates. It executes the selected
governed invocation path and returns bounded receipts.

`credential_lease_ref` is required for every non-fixture runtime kind. Fixture
invocations may omit it so deterministic StackLab tests stay provider-free.
Request construction rejects raw prompt/message/provider payload fields and
common credential, token, authorization, and `raw_*` keys before an invocation
can reach runtime code.

## Receipt Outputs

Receipts include request refs, provider/model refs, token and cost summaries,
stream fragment refs when streaming is enabled, redaction posture, trace refs,
and failure reason codes. Raw provider payloads and credentials must not appear
in public receipts.

## Local QC

```bash
mix ci
```
