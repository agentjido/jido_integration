defmodule Jido.Integration.V2.ControlPlane.AttemptRecoveryTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.Auth.Stores, as: AuthStores
  alias Jido.Integration.V2.ControlPlane.AttemptReconciler
  alias Jido.Integration.V2.ControlPlane.AttemptRecovery
  alias Jido.Integration.V2.ControlPlane.RunLedger
  alias Jido.Integration.V2.ControlPlane.RuntimeConfig
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Run

  @now ~U[2026-07-28 12:00:00Z]

  defmodule CompletedObserver do
    @behaviour Jido.Integration.V2.ControlPlane.AttemptObserver

    @impl true
    def status("provider-operation://one", context) do
      {:ok,
       {:completed,
        %{
          "receipt_ref" => "provider-receipt://one",
          "observed_attempt_id" => context.attempt_id
        }}}
    end

    @impl true
    def cancel(_external_operation_ref, _context), do: {:error, :unexpected_cancel}

    @impl true
    def cleanup(_external_operation_ref, _context), do: {:error, :unexpected_cleanup}
  end

  defmodule ClosedLeaseObserver do
    @behaviour Jido.Integration.V2.ControlPlane.AttemptObserver

    @impl true
    def status(_external_operation_ref, _context),
      do: raise("a closed lease must be rejected before provider observation")

    @impl true
    def cancel(_external_operation_ref, %{effect_retry: :prohibited}), do: :ok

    @impl true
    def cleanup(_external_operation_ref, %{effect_retry: :prohibited}), do: :ok
  end

  defmodule NeverObserveTerminal do
    @behaviour Jido.Integration.V2.ControlPlane.AttemptObserver

    @impl true
    def status(_external_operation_ref, _context),
      do: raise("durable terminal attempt truth must not be re-observed")

    @impl true
    def cancel(_external_operation_ref, _context),
      do: raise("durable terminal attempt truth must not be cancelled")

    @impl true
    def cleanup(_external_operation_ref, _context),
      do: raise("durable terminal attempt truth must not be cleaned")
  end

  setup do
    RunLedger.reset!()
    Auth.reset!()
    RuntimeConfig.put(:attempt_reconciliation, nil)

    on_exit(fn ->
      RuntimeConfig.put(:attempt_reconciliation, nil)
      RunLedger.reset!()
      Auth.reset!()
    end)

    :ok
  end

  test "a killed reconciler restarts, discovers durable unknown work, and reduces it once" do
    {_run, attempt} = put_attempt()

    assert :ok =
             RuntimeConfig.put(:attempt_reconciliation, %{
               observer: CompletedObserver,
               now: @now
             })

    old_pid = Process.whereis(AttemptReconciler)
    ref = Process.monitor(old_pid)
    Process.exit(old_pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^old_pid, :killed}, 1_000

    assert wait_until(fn ->
             case AttemptRecovery.tasks(%{attempt_id: attempt.attempt_id}) do
               [%{status: :resolved}] -> true
               _other -> false
             end
           end)

    assert {:ok, recovered_attempt} = RunLedger.fetch_attempt(attempt.attempt_id)
    assert recovered_attempt.status == :completed
    assert recovered_attempt.runtime_ref_id == "provider-operation://one"

    assert get_in(recovered_attempt.output, ["reconciliation", "receipt_ref"]) ==
             "provider-receipt://one"

    assert {:error, :recovery_task_terminal} =
             attempt.attempt_id
             |> recovery_task_id()
             |> AttemptRecovery.reconcile_task(CompletedObserver, now: @now)

    events = RunLedger.list_events(attempt.run_id)
    assert Enum.count(events, &(&1.type == "attempt.reconciliation.required")) == 1
    assert Enum.count(events, &(&1.type == "attempt.reconciliation.completed")) == 1
  end

  test "manual reconciliation processes only durable tasks and normalizes string options" do
    {_run, attempt} = put_attempt()

    assert :ok =
             RuntimeConfig.put(:attempt_reconciliation, %{
               "observer" => CompletedObserver,
               "now" => @now
             })

    assert {:ok, %{discovered: 0, reconciled: 0}} = AttemptReconciler.reconcile_now()
    assert [] = AttemptRecovery.tasks(%{attempt_id: attempt.attempt_id})

    assert {:ok, task} = AttemptRecovery.mark_outcome_unknown(attempt.attempt_id, %{now: @now})
    assert {:ok, %{discovered: 0, reconciled: 1}} = AttemptReconciler.reconcile_now()
    assert {:ok, %{status: :resolved}} = AttemptRecovery.task(task.task_id)
  end

  test "revocation and deadline closure cancel and clean without observing or rematerializing" do
    for {closure, attrs, expected_reason} <- [
          {:revoked, %{}, "credential_lease_revoked"},
          {:expired, %{}, "credential_lease_expired"},
          {:deadline, %{deadline_at: DateTime.add(@now, -1, :second)}, "deadline_elapsed"}
        ] do
      RunLedger.reset!()
      lease_id = "lease-#{closure}"

      credential_lease =
        LeaseRecord.new!(%{
          lease_id: lease_id,
          tenant_id: "tenant-1",
          credential_ref_id: "credential-ref-#{closure}",
          credential_id: "credential-#{closure}",
          connection_id: "connection-#{closure}",
          subject: "operator",
          scopes: ["provider:run"],
          payload_keys: ["access_token"],
          issued_at: DateTime.add(@now, -60, :second),
          expires_at:
            if(closure == :expired,
              do: DateTime.add(@now, -1, :second),
              else: DateTime.add(@now, 60, :second)
            ),
          revoked_at: if(closure == :revoked, do: DateTime.add(@now, -1, :second)),
          metadata: %{"secret_binding_ref" => "vault-secret://provider/#{closure}"}
        })

      assert :ok = AuthStores.lease_store().store_lease(credential_lease)
      {_run, attempt} = put_attempt(%{credential_lease_id: lease_id})

      assert {:ok, task} =
               AttemptRecovery.mark_outcome_unknown(
                 attempt.attempt_id,
                 Map.put(attrs, :now, @now)
               )

      assert {:ok, quarantined} =
               AttemptRecovery.reconcile_task(task.task_id, ClosedLeaseObserver, now: @now)

      assert quarantined.status == :quarantined
      assert quarantined.metadata["recovery_state"] == "operator_required"
      assert quarantined.metadata["reason"] == expected_reason
      assert quarantined.metadata["cancel"] == "completed"
      assert quarantined.metadata["cleanup"] == "completed"
      refute inspect(quarantined) =~ "access_token"

      assert {:ok, failed_attempt} = RunLedger.fetch_attempt(attempt.attempt_id)
      assert failed_attempt.status == :failed
      assert get_in(failed_attempt.output, ["reconciliation", "reason"]) == expected_reason
    end
  end

  test "a normal terminal result wins a race with recovery and is never overwritten" do
    {run, attempt} = put_attempt()

    assert {:ok, task} =
             AttemptRecovery.mark_outcome_unknown(attempt.attempt_id, %{
               now: @now,
               metadata: %{
                 :external_operation_ref => "provider-operation://substitution",
                 "effect_retry" => "allowed",
                 "safe_context" => "preserved"
               }
             })

    assert task.metadata["external_operation_ref"] == attempt.runtime_ref_id
    assert task.metadata["effect_retry"] == "prohibited"
    assert task.metadata["safe_context"] == "preserved"

    assert :ok =
             RunLedger.update_attempt(
               attempt.attempt_id,
               :completed,
               %{"provider_result" => "already-complete"},
               attempt.runtime_ref_id
             )

    assert {:ok, resolved} =
             AttemptRecovery.reconcile_task(task.task_id, NeverObserveTerminal, now: @now)

    assert resolved.status == :resolved
    assert resolved.metadata["recovery_state"] == "already_terminal"

    assert {:ok, persisted_attempt} = RunLedger.fetch_attempt(attempt.attempt_id)
    assert persisted_attempt.status == :completed
    assert persisted_attempt.output == %{"provider_result" => "already-complete"}

    assert {:ok, persisted_run} = RunLedger.fetch_run(run.run_id)
    assert persisted_run.status == :completed
    assert persisted_run.result == %{"provider_result" => "already-complete"}
  end

  defp put_attempt(attempt_attrs \\ %{}) do
    run =
      Run.new!(%{
        capability_id: "provider.operation",
        runtime_class: :session,
        status: :running,
        input: %{"prompt" => "hello"},
        credential_ref:
          CredentialRef.new!(%{
            id: "credential-ref-#{System.unique_integer([:positive])}",
            subject: "operator",
            scopes: ["provider:run"]
          })
      })

    attempt =
      Attempt.new!(
        Map.merge(
          %{
            run_id: run.run_id,
            attempt: 1,
            runtime_class: :session,
            status: :running,
            runtime_ref_id: "provider-operation://one"
          },
          attempt_attrs
        )
      )

    assert :ok = RunLedger.put_run(run)
    assert :ok = RunLedger.put_attempt(attempt)
    {run, attempt}
  end

  defp recovery_task_id(attempt_id) do
    Jido.Integration.V2.Contracts.recovery_task_id(attempt_id, "outcome_unknown")
  end

  defp wait_until(fun, attempts \\ 100)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end
end
