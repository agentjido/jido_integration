defmodule Jido.Integration.Docs.ConformanceWorkflowTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/conformance_workflow.md", __DIR__)

  test "documents conformance as a connector acceptance contract" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~ "## Connector Acceptance Contract"

    assert guide =~
             "A connector package is not review-complete until its package-local verification, root conformance, and root acceptance gates all pass."

    assert guide =~
             "The companion module is the connector-owned publication point for deterministic fixtures, runtime-driver evidence, and ingress definitions."

    assert guide =~
             "Package-local fixtures stay package-local even though `mix jido.conformance <ConnectorModule>` runs from the workspace root."

    assert guide =~
             "run package-local `mix compile --warnings-as-errors`, `mix test`, and `mix docs`"

    assert guide =~ "mix ci"
  end

  test "documents non-direct scaffold runtime drivers as package-local lib code" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~ "deterministic Runtime Control driver under `lib/`."
    refute guide =~ "`test_support/`"
  end

  test "documents direct connector package-test responsibilities for auth-control and lease-built clients" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert guide =~
             "For direct provider-SDK connectors, conformance proves the published surface and lease-only runtime posture."

    assert guide =~ "`install_binding` stays in install, reauth, manual-auth, or rotation flows"

    assert guide =~ "runtime execution builds provider clients from credential leases only"

    assert guide =~ "generated actions, plugins, and sensors remain derivative common projections"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
