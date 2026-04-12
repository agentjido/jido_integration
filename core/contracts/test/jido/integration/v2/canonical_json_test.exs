defmodule Jido.Integration.V2.CanonicalJsonTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.CanonicalJson

  test "normalizes atoms, nils, and nested maps into stable canonical bytes" do
    payload = %{
      b: nil,
      a: 1,
      c: %{
        z: true,
        a: "two"
      }
    }

    assert CanonicalJson.normalize!(payload) == %{
             "a" => 1,
             "b" => nil,
             "c" => %{"a" => "two", "z" => true}
           }

    assert CanonicalJson.encode!(payload) == ~s({"a":1,"b":null,"c":{"a":"two","z":true}})

    assert CanonicalJson.checksum!(payload) ==
             "sha256:b37e7c71ea789163f81df81b46ec65a5294409c7776c659a6ecee200ecfbf224"
  end

  test "rejects structs until callers dump them into packet-owned maps" do
    assert_raise ArgumentError, ~r/unsupported struct/, fn ->
      CanonicalJson.encode!(Date.utc_today())
    end
  end
end
