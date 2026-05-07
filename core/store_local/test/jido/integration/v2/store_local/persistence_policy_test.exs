defmodule Jido.Integration.V2.StoreLocal.PersistencePolicyTest do
  use Jido.Integration.V2.StoreLocal.Case

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.CredentialStore
  alias Jido.Integration.V2.StoreLocal.RunStore

  test "configures local restart safe stores through explicit persistence policy" do
    assert {:ok, capability} = StoreLocal.store_capability()
    assert capability.tier == :local_restart_safe
    assert capability.restart_safe?
    assert capability.durable?

    assert :ok = StoreLocal.configure_defaults!(persistence_profile: :local_restart_safe)

    assert Auth.Stores.credential_store() == CredentialStore
    assert ControlPlane.Stores.run_store() == RunStore
  end
end
