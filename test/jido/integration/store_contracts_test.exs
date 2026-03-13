defmodule Jido.Integration.Auth.Store.ETSContractTest do
  use Jido.Integration.Test.CredentialStoreContract,
    store_module: Jido.Integration.Auth.Store.ETS
end

defmodule Jido.Integration.Auth.Store.DiskContractTest do
  use Jido.Integration.Test.CredentialStoreContract,
    store_module: Jido.Integration.Auth.Store.Disk,
    durable: true
end

defmodule Jido.Integration.Auth.ConnectionStore.ETSContractTest do
  use Jido.Integration.Test.ConnectionStoreContract,
    store_module: Jido.Integration.Auth.ConnectionStore.ETS
end

defmodule Jido.Integration.Auth.ConnectionStore.DiskContractTest do
  use Jido.Integration.Test.ConnectionStoreContract,
    store_module: Jido.Integration.Auth.ConnectionStore.Disk,
    durable: true
end

defmodule Jido.Integration.Auth.InstallSessionStore.ETSContractTest do
  use Jido.Integration.Test.InstallSessionStoreContract,
    store_module: Jido.Integration.Auth.InstallSessionStore.ETS
end

defmodule Jido.Integration.Auth.InstallSessionStore.DiskContractTest do
  use Jido.Integration.Test.InstallSessionStoreContract,
    store_module: Jido.Integration.Auth.InstallSessionStore.Disk,
    durable: true
end

defmodule Jido.Integration.Webhook.DedupeStore.ETSContractTest do
  use Jido.Integration.Test.DedupeStoreContract,
    store_module: Jido.Integration.Webhook.DedupeStore.ETS
end

defmodule Jido.Integration.Webhook.DedupeStore.DiskContractTest do
  use Jido.Integration.Test.DedupeStoreContract,
    store_module: Jido.Integration.Webhook.DedupeStore.Disk,
    durable: true
end

defmodule Jido.Integration.Dispatch.Store.ETSContractTest do
  use Jido.Integration.Test.DispatchStoreContract,
    store_module: Jido.Integration.Dispatch.Store.ETS
end

defmodule Jido.Integration.Dispatch.Store.DiskContractTest do
  use Jido.Integration.Test.DispatchStoreContract,
    store_module: Jido.Integration.Dispatch.Store.Disk,
    durable: true
end

defmodule Jido.Integration.Dispatch.RunStore.ETSContractTest do
  use Jido.Integration.Test.RunStoreContract,
    store_module: Jido.Integration.Dispatch.RunStore.ETS
end

defmodule Jido.Integration.Dispatch.RunStore.DiskContractTest do
  use Jido.Integration.Test.RunStoreContract,
    store_module: Jido.Integration.Dispatch.RunStore.Disk,
    durable: true
end
