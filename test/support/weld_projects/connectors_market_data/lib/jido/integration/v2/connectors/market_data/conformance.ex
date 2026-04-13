defmodule Jido.Integration.V2.Connectors.MarketData.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.MarketData
  alias Jido.Integration.V2.Connectors.MarketData.ConformanceRuntimeControlDriver

  @run_id "run-market-data-conformance"
  @attempt_id "#{@run_id}:1"
  @subject "desk-feed"
  @api_key "market-demo-key"

  @spec fixtures() :: [map()]
  def fixtures do
    [
      %{
        capability_id: "market.ticks.pull",
        input: %{symbol: "ES", limit: 2, venue: "CME"},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{
          run_id: @run_id,
          attempt_id: @attempt_id
        },
        expect: %{
          output: %{
            symbol: "ES",
            venue: "CME",
            cursor: 2,
            items: [
              %{seq: 1, symbol: "ES", venue: "CME", bid: 5_001, ask: 5_002},
              %{seq: 2, symbol: "ES", venue: "CME", bid: 5_002, ask: 5_003}
            ],
            auth_binding: ArtifactBuilder.digest(@api_key)
          },
          event_types: ["stream.started", "connector.market_data.batch.pulled"],
          artifact_types: [:log],
          artifact_keys: ["market_data/#{@run_id}/#{@attempt_id}/batch_2.term"]
        }
      }
    ]
  end

  @spec runtime_drivers() :: map()
  def runtime_drivers do
    %{asm: ConformanceRuntimeControlDriver}
  end

  @spec ingress_definitions() :: list()
  def ingress_definitions do
    MarketData.ingress_definitions()
  end

  defp credential_ref do
    %{
      id: "cred-market-data-conformance",
      subject: @subject,
      scopes: ["market:read"]
    }
  end

  defp credential_lease do
    %{
      lease_id: "lease-market-data-conformance",
      credential_ref_id: "cred-market-data-conformance",
      subject: @subject,
      scopes: ["market:read"],
      payload: %{api_key: @api_key},
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end
end
