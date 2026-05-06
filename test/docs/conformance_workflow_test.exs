defmodule Jido.Integration.Docs.ConformanceWorkflowTest do
  use ExUnit.Case, async: true

  @guide_path Path.expand("../../docs/conformance_workflow.md", __DIR__)

  test "documents conformance as a connector acceptance contract" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(guide, "## Connector Acceptance Contract")

    assert String.contains?(
             guide,
             "A connector package is not review-complete until its package-local verification, root conformance, and root acceptance gates all pass."
           )

    assert String.contains?(
             guide,
             "The companion module is the connector-owned publication point for deterministic fixtures, runtime-driver evidence, and ingress definitions."
           )

    assert String.contains?(
             guide,
             "Package-local fixtures stay package-local even though `mix jido.conformance <ConnectorModule>` runs from the workspace root."
           )

    assert String.contains?(
             guide,
             "run package-local `mix compile --warnings-as-errors`, `mix test`, and `mix docs`"
           )

    assert String.contains?(guide, "mix ci")
  end

  test "documents non-direct scaffold runtime drivers as package-local lib code" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(guide, "deterministic Runtime Control driver under `lib/`.")
    refute String.contains?(guide, "`test_support/`")
  end

  test "documents direct connector package-test responsibilities for auth-control and lease-built clients" do
    guide = @guide_path |> File.read!() |> normalize_whitespace()

    assert String.contains?(
             guide,
             "For direct provider-SDK connectors, conformance proves the published surface and lease-only runtime posture."
           )

    assert String.contains?(
             guide,
             "`install_binding` stays in install, reauth, manual-auth, or rotation flows"
           )

    assert String.contains?(
             guide,
             "runtime execution builds provider clients from credential leases only"
           )

    assert String.contains?(
             guide,
             "generated actions, plugins, and sensors remain derivative common projections"
           )
  end

  defp normalize_whitespace(text), do: text |> String.split() |> Enum.join(" ")
end
