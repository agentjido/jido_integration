defmodule Jido.Integration.V2.RedactionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Redaction

  test "keeps token usage telemetry while redacting secret-bearing keys" do
    payload = %{
      usage: %{
        input_tokens: 12,
        output_tokens: 34,
        total_tokens: 46
      },
      authorization: "Bearer secret",
      refresh_token: "refresh-secret"
    }

    assert Redaction.redact(payload) == %{
             usage: %{
               input_tokens: 12,
               output_tokens: 34,
               total_tokens: 46
             },
             authorization: Redaction.redacted(),
             refresh_token: Redaction.redacted()
           }
  end
end
