defmodule Jido.Integration.Test.StoreContractSupport do
  @moduledoc false

  def start_store!(store_module, context, opts \\ []) do
    start_opts = start_opts(store_module, context, opts)
    {:ok, store} = store_module.start_link(start_opts)
    {store, start_opts}
  end

  def restart_store!(store, store_module, start_opts) do
    stop_store(store)
    {:ok, restarted} = store_module.start_link(start_opts)
    restarted
  end

  def stop_store(store) do
    ref = Process.monitor(store)
    Process.unlink(store)
    GenServer.stop(store, :normal, 5_000)

    receive do
      {:DOWN, ^ref, :process, ^store, _reason} -> :ok
    after
      5_000 -> :ok
    end
  end

  def start_opts(store_module, context, opts) do
    if Keyword.get(opts, :durable, false) do
      [
        name: nil,
        dir: context.tmp_dir,
        file: durable_file_name(store_module, context.test)
      ]
    else
      [name: nil]
    end
  end

  defp durable_file_name(store_module, test_name) do
    store_name =
      store_module
      |> Module.split()
      |> Enum.map_join("-", &Macro.underscore/1)

    test_slug =
      test_name
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")

    "#{store_name}-#{test_slug}.bin"
  end
end

defmodule Jido.Integration.Test.CredentialStoreContract do
  @moduledoc false

  alias Jido.Integration.Auth.Credential
  alias Jido.Integration.Test.StoreContractSupport

  defmacro __using__(opts) do
    store_module = Keyword.fetch!(opts, :store_module)
    durable? = Keyword.get(opts, :durable, false)

    quote bind_quoted: [store_module: store_module, durable?: durable?] do
      use ExUnit.Case, async: true

      alias Jido.Integration.Test.CredentialStoreContract
      alias Jido.Integration.Test.StoreContractSupport

      @store_module store_module
      @store_contract_durable durable?

      if @store_contract_durable do
        @moduletag :tmp_dir
      end

      setup context do
        {store, start_opts} =
          StoreContractSupport.start_store!(
            @store_module,
            context,
            durable: @store_contract_durable
          )

        %{store: store, store_module: @store_module, store_start_opts: start_opts}
      end

      test "stores and fetches credentials with scope enforcement", %{
        store: store,
        store_module: store_module
      } do
        auth_ref = "auth:github:org-123"
        credential = CredentialStoreContract.api_key_credential("sk-live")

        assert :ok = store_module.store(store, auth_ref, credential)
        assert {:ok, ^credential} = store_module.fetch(store, auth_ref)
        assert {:ok, ^credential} = store_module.fetch(store, auth_ref, connector_id: "github")

        assert {:error, :scope_violation} =
                 store_module.fetch(store, auth_ref, connector_id: "linear")
      end

      test "updates an existing credential", %{store: store, store_module: store_module} do
        auth_ref = "auth:github:org-456"
        original = CredentialStoreContract.api_key_credential("sk-old")
        updated = CredentialStoreContract.api_key_credential("sk-new")

        assert :ok = store_module.store(store, auth_ref, original)
        assert :ok = store_module.store(store, auth_ref, updated)
        assert {:ok, ^updated} = store_module.fetch(store, auth_ref)
      end

      test "lists credentials by connector type", %{store: store, store_module: store_module} do
        github_one = CredentialStoreContract.api_key_credential("sk-one")
        github_two = CredentialStoreContract.api_key_credential("sk-two")
        linear = CredentialStoreContract.api_key_credential("sk-three")

        assert :ok = store_module.store(store, "auth:github:org-1", github_one)
        assert :ok = store_module.store(store, "auth:github:org-2", github_two)
        assert :ok = store_module.store(store, "auth:linear:org-3", linear)

        refs =
          store_module.list(store, "github")
          |> Enum.map(&elem(&1, 0))
          |> Enum.sort()

        assert refs == ["auth:github:org-1", "auth:github:org-2"]
      end

      test "returns not_found for missing credentials", %{
        store: store,
        store_module: store_module
      } do
        assert {:error, :not_found} = store_module.fetch(store, "auth:github:missing")
        assert {:error, :not_found} = store_module.delete(store, "auth:github:missing")
      end

      test "enforces expiry with an allow_expired escape hatch", %{
        store: store,
        store_module: store_module
      } do
        auth_ref = "auth:github:expired"

        assert :ok =
                 store_module.store(
                   store,
                   auth_ref,
                   CredentialStoreContract.expired_oauth_credential()
                 )

        assert {:error, :expired} = store_module.fetch(store, auth_ref)
        assert {:ok, %Credential{}} = store_module.fetch(store, auth_ref, allow_expired: true)
      end

      test "deletes stored credentials", %{store: store, store_module: store_module} do
        auth_ref = "auth:github:org-delete"
        credential = CredentialStoreContract.api_key_credential("sk-delete")

        assert :ok = store_module.store(store, auth_ref, credential)
        assert :ok = store_module.delete(store, auth_ref)
        assert {:error, :not_found} = store_module.fetch(store, auth_ref)
      end

      if @store_contract_durable do
        test "recovers credentials after restart", %{
          store: store,
          store_module: store_module,
          store_start_opts: store_start_opts
        } do
          auth_ref = "auth:github:restart"
          credential = CredentialStoreContract.api_key_credential("sk-restart")

          assert :ok = store_module.store(store, auth_ref, credential)

          restarted =
            StoreContractSupport.restart_store!(store, store_module, store_start_opts)

          assert {:ok, ^credential} = store_module.fetch(restarted, auth_ref)
        end
      end
    end
  end

  def api_key_credential(key) do
    {:ok, credential} = Credential.new(%{type: :api_key, key: key})
    credential
  end

  def expired_oauth_credential do
    {:ok, credential} =
      Credential.new(%{
        type: :oauth2,
        access_token: "gho-expired",
        refresh_token: "ghr-expired",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second),
        scopes: ["repo"]
      })

    credential
  end
end

defmodule Jido.Integration.Test.ConnectionStoreContract do
  @moduledoc false

  alias Jido.Integration.Auth.Connection
  alias Jido.Integration.Test.StoreContractSupport

  defmacro __using__(opts) do
    store_module = Keyword.fetch!(opts, :store_module)
    durable? = Keyword.get(opts, :durable, false)

    quote bind_quoted: [store_module: store_module, durable?: durable?] do
      use ExUnit.Case, async: true

      alias Jido.Integration.Test.ConnectionStoreContract
      alias Jido.Integration.Test.StoreContractSupport

      @store_module store_module
      @store_contract_durable durable?

      if @store_contract_durable do
        @moduletag :tmp_dir
      end

      setup context do
        {store, start_opts} =
          StoreContractSupport.start_store!(
            @store_module,
            context,
            durable: @store_contract_durable
          )

        %{store: store, store_module: @store_module, store_start_opts: start_opts}
      end

      test "stores and fetches connections", %{store: store, store_module: store_module} do
        connection = ConnectionStoreContract.connection("conn-fetch", :installing)

        assert :ok = store_module.put(store, connection)
        assert {:ok, ^connection} = store_module.fetch(store, connection.id)
      end

      test "updates an existing connection", %{store: store, store_module: store_module} do
        original = ConnectionStoreContract.connection("conn-update", :installing)

        updated = %{
          original
          | state: :connected,
            revision: 1,
            auth_ref: "auth:github:conn-update"
        }

        assert :ok = store_module.put(store, original)
        assert :ok = store_module.put(store, updated)
        assert {:ok, ^updated} = store_module.fetch(store, original.id)
      end

      test "lists all stored connections", %{store: store, store_module: store_module} do
        first = ConnectionStoreContract.connection("conn-one", :new)
        second = ConnectionStoreContract.connection("conn-two", :connected)

        assert :ok = store_module.put(store, first)
        assert :ok = store_module.put(store, second)

        ids =
          store_module.list(store)
          |> Enum.map(& &1.id)
          |> Enum.sort()

        assert ids == ["conn-one", "conn-two"]
      end

      test "returns not_found for missing connections", %{
        store: store,
        store_module: store_module
      } do
        assert {:error, :not_found} = store_module.fetch(store, "conn-missing")
        assert {:error, :not_found} = store_module.delete(store, "conn-missing")
      end

      test "deletes stored connections", %{store: store, store_module: store_module} do
        connection = ConnectionStoreContract.connection("conn-delete", :connected)

        assert :ok = store_module.put(store, connection)
        assert :ok = store_module.delete(store, connection.id)
        assert {:error, :not_found} = store_module.fetch(store, connection.id)
      end

      if @store_contract_durable do
        test "recovers connections after restart", %{
          store: store,
          store_module: store_module,
          store_start_opts: store_start_opts
        } do
          connection = ConnectionStoreContract.connection("conn-restart", :connected)

          assert :ok = store_module.put(store, connection)

          restarted =
            StoreContractSupport.restart_store!(store, store_module, store_start_opts)

          assert {:ok, ^connection} = store_module.fetch(restarted, connection.id)
        end
      end
    end
  end

  def connection(id, state) do
    now = DateTime.utc_now()

    %Connection{
      id: id,
      connector_id: "github",
      tenant_id: "tenant-123",
      state: state,
      scopes: ["repo"],
      auth_ref: nil,
      revision: if(state == :new, do: 0, else: 1),
      actor_trail: [],
      created_at: now,
      updated_at: now
    }
  end
end

defmodule Jido.Integration.Test.InstallSessionStoreContract do
  @moduledoc false

  alias Jido.Integration.Auth.InstallSession
  alias Jido.Integration.Test.StoreContractSupport

  defmacro __using__(opts) do
    store_module = Keyword.fetch!(opts, :store_module)
    durable? = Keyword.get(opts, :durable, false)

    quote bind_quoted: [store_module: store_module, durable?: durable?] do
      use ExUnit.Case, async: true

      alias Jido.Integration.Auth.InstallSession
      alias Jido.Integration.Test.InstallSessionStoreContract
      alias Jido.Integration.Test.StoreContractSupport

      @store_module store_module
      @store_contract_durable durable?

      if @store_contract_durable do
        @moduletag :tmp_dir
      end

      setup context do
        {store, start_opts} =
          StoreContractSupport.start_store!(
            @store_module,
            context,
            durable: @store_contract_durable
          )

        %{store: store, store_module: @store_module, store_start_opts: start_opts}
      end

      test "stores and fetches pending install sessions", %{
        store: store,
        store_module: store_module
      } do
        session = InstallSessionStoreContract.session("state-fetch")

        assert :ok = store_module.put(store, session)
        assert {:ok, ^session} = store_module.fetch(store, session.state_token)
      end

      test "updates an existing install session", %{store: store, store_module: store_module} do
        original = InstallSessionStoreContract.session("state-update")
        updated = %{original | actor_id: "user-2", requested_scopes: ["repo", "read:org"]}

        assert :ok = store_module.put(store, original)
        assert :ok = store_module.put(store, updated)
        assert {:ok, ^updated} = store_module.fetch(store, original.state_token)
      end

      test "lists stored install sessions", %{store: store, store_module: store_module} do
        first = InstallSessionStoreContract.session("state-one")
        second = InstallSessionStoreContract.session("state-two")

        assert :ok = store_module.put(store, first)
        assert :ok = store_module.put(store, second)

        tokens =
          store_module.list(store)
          |> Enum.map(& &1.state_token)
          |> Enum.sort()

        assert tokens == ["state-one", "state-two"]
      end

      test "returns not_found for missing sessions", %{store: store, store_module: store_module} do
        assert {:error, :not_found} = store_module.fetch(store, "missing-state")
        assert {:error, :not_found} = store_module.delete(store, "missing-state")
        assert {:error, :not_found} = store_module.consume(store, "missing-state")
      end

      test "enforces expiry with an allow_expired escape hatch", %{
        store: store,
        store_module: store_module
      } do
        session = InstallSessionStoreContract.expired_session("state-expired")

        assert :ok = store_module.put(store, session)
        assert {:error, :expired} = store_module.fetch(store, session.state_token)

        assert {:ok, %InstallSession{}} =
                 store_module.fetch(store, session.state_token, allow_expired: true)

        assert {:error, :expired} = store_module.consume(store, session.state_token)
      end

      test "consumes a session exactly once", %{store: store, store_module: store_module} do
        session = InstallSessionStoreContract.session("state-consume")

        assert :ok = store_module.put(store, session)

        assert {:ok, %InstallSession{status: :consumed, consumed_at: %DateTime{}} = consumed} =
                 store_module.consume(store, session.state_token)

        assert consumed.state_token == session.state_token
        assert {:error, :already_consumed} = store_module.consume(store, session.state_token)

        assert {:ok, %InstallSession{status: :consumed}} =
                 store_module.fetch(store, session.state_token, allow_expired: true)
      end

      test "deletes stored install sessions", %{store: store, store_module: store_module} do
        session = InstallSessionStoreContract.session("state-delete")

        assert :ok = store_module.put(store, session)
        assert :ok = store_module.delete(store, session.state_token)
        assert {:error, :not_found} = store_module.fetch(store, session.state_token)
      end

      if @store_contract_durable do
        test "recovers install sessions after restart", %{
          store: store,
          store_module: store_module,
          store_start_opts: store_start_opts
        } do
          session = InstallSessionStoreContract.session("state-restart")

          assert :ok = store_module.put(store, session)
          assert {:ok, _consumed} = store_module.consume(store, session.state_token)

          restarted =
            StoreContractSupport.restart_store!(store, store_module, store_start_opts)

          assert {:ok, %InstallSession{status: :consumed}} =
                   store_module.fetch(restarted, session.state_token, allow_expired: true)
        end
      end
    end
  end

  def session(state_token) do
    now = DateTime.utc_now()

    {:ok, session} =
      InstallSession.new(%{
        state_token: state_token,
        connector_id: "github",
        tenant_id: "tenant-123",
        connection_id: "conn-123",
        auth_descriptor_id: "oauth2",
        auth_type: :oauth2,
        requested_scopes: ["repo"],
        nonce: "nonce-123",
        code_verifier: "verifier-123",
        code_challenge: "challenge-123",
        actor_id: "user-123",
        trace_id: "trace-123",
        span_id: "span-123",
        status: :pending,
        created_at: now,
        expires_at: DateTime.add(now, 600, :second)
      })

    session
  end

  def expired_session(state_token) do
    session(state_token)
    |> Map.put(:expires_at, DateTime.add(DateTime.utc_now(), -60, :second))
  end
end

defmodule Jido.Integration.Test.DedupeStoreContract do
  @moduledoc false

  alias Jido.Integration.Test.StoreContractSupport

  defmacro __using__(opts) do
    store_module = Keyword.fetch!(opts, :store_module)
    durable? = Keyword.get(opts, :durable, false)

    quote bind_quoted: [store_module: store_module, durable?: durable?] do
      use ExUnit.Case, async: true

      alias Jido.Integration.Test.DedupeStoreContract
      alias Jido.Integration.Test.StoreContractSupport

      @store_module store_module
      @store_contract_durable durable?

      if @store_contract_durable do
        @moduletag :tmp_dir
      end

      setup context do
        {store, start_opts} =
          StoreContractSupport.start_store!(
            @store_module,
            context,
            durable: @store_contract_durable
          )

        %{store: store, store_module: @store_module, store_start_opts: start_opts}
      end

      test "stores and fetches dedupe entries", %{store: store, store_module: store_module} do
        key = "delivery-fetch"
        expires_at_ms = DedupeStoreContract.future_timestamp_ms()

        assert :ok = store_module.put(store, key, expires_at_ms)
        assert {:ok, %{key: ^key, expires_at_ms: ^expires_at_ms}} = store_module.fetch(store, key)
      end

      test "updates an existing dedupe entry", %{store: store, store_module: store_module} do
        key = "delivery-update"
        original_expires_at_ms = DedupeStoreContract.future_timestamp_ms()
        updated_expires_at_ms = original_expires_at_ms + 1_000

        assert :ok = store_module.put(store, key, original_expires_at_ms)
        assert :ok = store_module.put(store, key, updated_expires_at_ms)

        assert {:ok, %{expires_at_ms: ^updated_expires_at_ms}} = store_module.fetch(store, key)
      end

      test "lists stored dedupe entries", %{store: store, store_module: store_module} do
        assert :ok =
                 store_module.put(
                   store,
                   "delivery-one",
                   DedupeStoreContract.future_timestamp_ms()
                 )

        assert :ok =
                 store_module.put(
                   store,
                   "delivery-two",
                   DedupeStoreContract.future_timestamp_ms()
                 )

        keys =
          store_module.list(store)
          |> Enum.map(& &1.key)
          |> Enum.sort()

        assert keys == ["delivery-one", "delivery-two"]
      end

      test "returns not_found for missing dedupe entries", %{
        store: store,
        store_module: store_module
      } do
        assert {:error, :not_found} = store_module.fetch(store, "missing-delivery")
        assert {:error, :not_found} = store_module.delete(store, "missing-delivery")
      end

      test "enforces expiry with an allow_expired escape hatch", %{
        store: store,
        store_module: store_module
      } do
        key = "delivery-expired"
        expires_at_ms = System.system_time(:millisecond) - 100

        assert :ok = store_module.put(store, key, expires_at_ms)
        assert {:error, :expired} = store_module.fetch(store, key)

        assert {:ok, %{key: ^key, expires_at_ms: ^expires_at_ms}} =
                 store_module.fetch(store, key, allow_expired: true)
      end

      test "deletes stored dedupe entries", %{store: store, store_module: store_module} do
        key = "delivery-delete"

        assert :ok = store_module.put(store, key, DedupeStoreContract.future_timestamp_ms())
        assert :ok = store_module.delete(store, key)
        assert {:error, :not_found} = store_module.fetch(store, key)
      end

      if @store_contract_durable do
        test "recovers dedupe entries after restart", %{
          store: store,
          store_module: store_module,
          store_start_opts: store_start_opts
        } do
          key = "delivery-restart"
          expires_at_ms = DedupeStoreContract.future_timestamp_ms()

          assert :ok = store_module.put(store, key, expires_at_ms)

          restarted =
            StoreContractSupport.restart_store!(store, store_module, store_start_opts)

          assert {:ok, %{key: ^key, expires_at_ms: ^expires_at_ms}} =
                   store_module.fetch(restarted, key)
        end
      end
    end
  end

  def future_timestamp_ms do
    System.system_time(:millisecond) + 60_000
  end
end

defmodule Jido.Integration.Test.DispatchStoreContract do
  @moduledoc false

  alias Jido.Integration.Dispatch.Record
  alias Jido.Integration.Test.StoreContractSupport

  defmacro __using__(opts) do
    store_module = Keyword.fetch!(opts, :store_module)
    durable? = Keyword.get(opts, :durable, false)

    quote bind_quoted: [store_module: store_module, durable?: durable?] do
      use ExUnit.Case, async: true

      alias Jido.Integration.Test.DispatchStoreContract
      alias Jido.Integration.Test.StoreContractSupport

      @store_module store_module
      @store_contract_durable durable?

      if @store_contract_durable do
        @moduletag :tmp_dir
      end

      setup context do
        {store, start_opts} =
          StoreContractSupport.start_store!(
            @store_module,
            context,
            durable: @store_contract_durable
          )

        %{store: store, store_module: @store_module, store_start_opts: start_opts}
      end

      test "stores and fetches dispatch records", %{store: store, store_module: store_module} do
        record = DispatchStoreContract.record("dispatch-fetch")

        assert :ok = store_module.put(store, record)
        assert {:ok, ^record} = store_module.fetch(store, record.dispatch_id)
      end

      test "updates an existing dispatch record", %{store: store, store_module: store_module} do
        original = DispatchStoreContract.record("dispatch-update")

        updated =
          %{original | status: :delivered, run_id: "run-123", updated_at: DateTime.utc_now()}

        assert :ok = store_module.put(store, original)
        assert :ok = store_module.put(store, updated)
        assert {:ok, ^updated} = store_module.fetch(store, original.dispatch_id)
      end

      test "lists stored dispatch records", %{store: store, store_module: store_module} do
        first = DispatchStoreContract.record("dispatch-one")
        second = DispatchStoreContract.record("dispatch-two")

        assert :ok = store_module.put(store, first)
        assert :ok = store_module.put(store, second)

        ids =
          store_module.list(store)
          |> Enum.map(& &1.dispatch_id)
          |> Enum.sort()

        assert ids == ["dispatch-one", "dispatch-two"]
      end

      test "filters dispatch records by status and scope", %{
        store: store,
        store_module: store_module
      } do
        queued =
          DispatchStoreContract.record("dispatch-queued")

        delivered =
          DispatchStoreContract.record("dispatch-delivered")
          |> Map.merge(%{
            status: :delivered,
            tenant_id: "tenant-456",
            connector_id: "slack",
            trigger_id: "slack.webhook"
          })

        assert :ok = store_module.put(store, queued)
        assert :ok = store_module.put(store, delivered)

        assert [^queued] = store_module.list(store, status: :queued)
        assert [^delivered] = store_module.list(store, tenant_id: "tenant-456")
        assert [^delivered] = store_module.list(store, connector_id: "slack")
        assert [^delivered] = store_module.list(store, trigger_id: "slack.webhook")
        assert [] = store_module.list(store, status: :dead_lettered)
      end

      test "returns not_found for missing dispatch records", %{
        store: store,
        store_module: store_module
      } do
        assert {:error, :not_found} = store_module.fetch(store, "dispatch-missing")
        assert {:error, :not_found} = store_module.delete(store, "dispatch-missing")
      end

      test "deletes stored dispatch records", %{store: store, store_module: store_module} do
        record = DispatchStoreContract.record("dispatch-delete")

        assert :ok = store_module.put(store, record)
        assert :ok = store_module.delete(store, record.dispatch_id)
        assert {:error, :not_found} = store_module.fetch(store, record.dispatch_id)
      end

      if @store_contract_durable do
        test "recovers dispatch records after restart", %{
          store: store,
          store_module: store_module,
          store_start_opts: store_start_opts
        } do
          record = DispatchStoreContract.record("dispatch-restart")

          assert :ok = store_module.put(store, record)

          restarted =
            StoreContractSupport.restart_store!(store, store_module, store_start_opts)

          assert {:ok, ^record} = store_module.fetch(restarted, record.dispatch_id)
        end
      end
    end
  end

  def record(dispatch_id) do
    Record.new(%{
      dispatch_id: dispatch_id,
      idempotency_key: "idem-#{dispatch_id}",
      tenant_id: "tenant-123",
      connector_id: "github",
      trigger_id: "github.webhook",
      event_id: "event-#{dispatch_id}",
      dedupe_key: "delivery-#{dispatch_id}",
      workflow_selector: "github.webhook",
      payload: %{"resource" => "issue"},
      status: :queued,
      attempts: 0,
      max_dispatch_attempts: 5,
      trace_context: %{trace_id: "trace-123", span_id: "span-123"}
    })
  end
end

defmodule Jido.Integration.Test.RunStoreContract do
  @moduledoc false

  alias Jido.Integration.Dispatch.Run
  alias Jido.Integration.Test.StoreContractSupport

  defmacro __using__(opts) do
    store_module = Keyword.fetch!(opts, :store_module)
    durable? = Keyword.get(opts, :durable, false)

    quote bind_quoted: [store_module: store_module, durable?: durable?] do
      use ExUnit.Case, async: true

      alias Jido.Integration.Test.RunStoreContract
      alias Jido.Integration.Test.StoreContractSupport

      @store_module store_module
      @store_contract_durable durable?

      if @store_contract_durable do
        @moduletag :tmp_dir
      end

      setup context do
        {store, start_opts} =
          StoreContractSupport.start_store!(
            @store_module,
            context,
            durable: @store_contract_durable
          )

        %{store: store, store_module: @store_module, store_start_opts: start_opts}
      end

      test "stores and fetches run records", %{store: store, store_module: store_module} do
        run = RunStoreContract.run("run-fetch")

        assert :ok = store_module.put(store, run)
        assert {:ok, ^run} = store_module.fetch(store, run.run_id)
      end

      test "fetches run records by idempotency key", %{store: store, store_module: store_module} do
        run = RunStoreContract.run("run-idem")

        assert :ok = store_module.put(store, run)
        assert {:ok, ^run} = store_module.fetch_by_idempotency(store, run.idempotency_key)
        assert {:error, :not_found} = store_module.fetch_by_idempotency(store, "idem-missing")
      end

      test "updates an existing run record", %{store: store, store_module: store_module} do
        original = RunStoreContract.run("run-update")

        updated =
          %{
            original
            | status: :succeeded,
              result: %{"ok" => true},
              finished_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
          }

        assert :ok = store_module.put(store, original)
        assert :ok = store_module.put(store, updated)
        assert {:ok, ^updated} = store_module.fetch(store, original.run_id)
      end

      test "rejects a different run_id for an existing idempotency key", %{
        store: store,
        store_module: store_module
      } do
        original = RunStoreContract.run("run-original")

        conflicting =
          RunStoreContract.run("run-conflict")
          |> Map.put(:idempotency_key, original.idempotency_key)

        assert :ok = store_module.put(store, original)

        assert {:error, {:idempotency_conflict, "run-original"}} =
                 store_module.put(store, conflicting)
      end

      test "lists stored run records", %{store: store, store_module: store_module} do
        first = RunStoreContract.run("run-one")
        second = RunStoreContract.run("run-two")

        assert :ok = store_module.put(store, first)
        assert :ok = store_module.put(store, second)

        ids =
          store_module.list(store)
          |> Enum.map(& &1.run_id)
          |> Enum.sort()

        assert ids == ["run-one", "run-two"]
      end

      test "filters run records by status and scope", %{store: store, store_module: store_module} do
        accepted = RunStoreContract.run("run-accepted")

        dead_lettered =
          RunStoreContract.run("run-dead")
          |> Map.merge(%{
            status: :dead_lettered,
            tenant_id: "tenant-456",
            connector_id: "slack",
            trigger_id: "slack.webhook",
            callback_id: "Slack.Handler"
          })

        assert :ok = store_module.put(store, accepted)
        assert :ok = store_module.put(store, dead_lettered)

        assert [^accepted] = store_module.list(store, status: :accepted)
        assert [^dead_lettered] = store_module.list(store, status: :dead_lettered)
        assert [^dead_lettered] = store_module.list(store, tenant_id: "tenant-456")
        assert [^dead_lettered] = store_module.list(store, connector_id: "slack")
        assert [^dead_lettered] = store_module.list(store, trigger_id: "slack.webhook")
        assert [^dead_lettered] = store_module.list(store, callback_id: "Slack.Handler")

        assert [^dead_lettered] =
                 store_module.list(store, idempotency_key: dead_lettered.idempotency_key)

        assert [] = store_module.list(store, status: :running)
      end

      test "returns not_found for missing run records", %{
        store: store,
        store_module: store_module
      } do
        assert {:error, :not_found} = store_module.fetch(store, "run-missing")
        assert {:error, :not_found} = store_module.delete(store, "run-missing")
      end

      test "deletes stored run records", %{store: store, store_module: store_module} do
        run = RunStoreContract.run("run-delete")

        assert :ok = store_module.put(store, run)
        assert :ok = store_module.delete(store, run.run_id)
        assert {:error, :not_found} = store_module.fetch(store, run.run_id)
      end

      if @store_contract_durable do
        test "recovers run records after restart", %{
          store: store,
          store_module: store_module,
          store_start_opts: store_start_opts
        } do
          run = RunStoreContract.run("run-restart")

          assert :ok = store_module.put(store, run)

          restarted =
            StoreContractSupport.restart_store!(store, store_module, store_start_opts)

          assert {:ok, ^run} = store_module.fetch(restarted, run.run_id)
          assert {:ok, ^run} = store_module.fetch_by_idempotency(restarted, run.idempotency_key)
        end
      end
    end
  end

  def run(run_id) do
    now = DateTime.utc_now()

    %Run{
      run_id: run_id,
      attempt_id: "#{run_id}:1",
      dispatch_id: "dispatch-#{run_id}",
      idempotency_key: "idem-#{run_id}",
      tenant_id: "tenant-123",
      connector_id: "github",
      trigger_id: "github.webhook",
      callback_id: "Callback.Handler",
      status: :accepted,
      attempt: 1,
      max_attempts: 5,
      result: nil,
      error_class: nil,
      error_context: nil,
      trace_context: %{trace_id: "trace-123", span_id: "span-123"},
      accepted_at: now,
      started_at: nil,
      finished_at: nil,
      updated_at: now,
      payload: %{"resource" => "issue"}
    }
  end
end
