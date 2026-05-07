defmodule Jido.Integration.StoreDescriptorsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Store.Local
  alias Jido.Integration.Store.Memory
  alias Jido.Integration.Store.Null
  alias Jido.Integration.Store.Postgres

  test "defines stable descriptor modules for all Jido store classes" do
    assert Memory.descriptor().tier == :memory_ephemeral
    assert Memory.descriptor().default?
    assert Memory.descriptor().durable? == false

    assert Null.descriptor().tier == :off
    assert Null.descriptor().default? == false
    assert Null.descriptor().durable? == false

    assert Local.descriptor().tier == :local_restart_safe
    assert Local.descriptor().durable?
    assert Local.descriptor().restart_safe?

    assert Postgres.descriptor().tier == :postgres_shared
    assert Postgres.descriptor().durable?
    assert Postgres.descriptor().shared?
  end
end
