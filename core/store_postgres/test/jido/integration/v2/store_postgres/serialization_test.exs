defmodule Jido.Integration.V2.StorePostgres.SerializationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.StorePostgres.Serialization

  test "load restores existing atom keys recursively and preserves unknown string keys" do
    loaded =
      Serialization.load(%{
        "connector" => "github",
        "items" => [%{"seq" => 1, "venue" => "CME"}],
        "metadata" => %{
          "content_encoding" => "gzip",
          "not_preexisting_key_123" => %{"trace_id" => "trace-1"}
        }
      })

    assert loaded.connector == "github"
    assert hd(loaded.items).seq == 1
    assert hd(loaded.items).venue == "CME"
    assert loaded.metadata.content_encoding == "gzip"
    assert Map.has_key?(loaded.metadata, "not_preexisting_key_123")
    assert loaded.metadata["not_preexisting_key_123"].trace_id == "trace-1"
  end
end
