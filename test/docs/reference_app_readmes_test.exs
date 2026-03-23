defmodule Jido.Integration.Docs.ReferenceAppReadmesTest do
  use ExUnit.Case, async: true

  @trading_ops_readme Path.expand("../../apps/trading_ops/README.md", __DIR__)

  test "trading_ops README describes the cleaned asm target boundary without bridge-era wording" do
    readme = @trading_ops_readme |> File.read!() |> normalize_whitespace()

    assert readme =~ "target descriptors that advertise the authored Harness `asm` driver",
           "#{@trading_ops_readme} must keep the authored asm proof explicit"

    assert readme =~ "mismatched `jido_session` or mismatched-driver descriptor",
           "#{@trading_ops_readme} must describe mismatched non-direct targets explicitly"

    refute readme =~ "legacy stream bridge",
           "#{@trading_ops_readme} must not preserve legacy stream bridge wording"

    refute readme =~ "legacy session bridge",
           "#{@trading_ops_readme} must not preserve legacy session bridge wording"

    refute readme =~ "same-capability bridge",
           "#{@trading_ops_readme} must not preserve bridge-era target wording"
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")
end
