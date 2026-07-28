defmodule Jido.Integration.V2.StorePostgres.RecoveryTaskStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.RecoveryTask
  alias Jido.Integration.V2.StorePostgres.AttemptStore
  alias Jido.Integration.V2.StorePostgres.RecoveryTaskStore
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.RunStore
  alias Jido.Integration.V2.StorePostgres.TestSupport

  @now ~U[2026-07-28 12:00:00Z]

  test "persists idempotent tasks across restart and fences claims and transitions" do
    Sandbox.checkin(Repo)
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      TestSupport.reset_database!()
      Sandbox.mode(Repo, :auto)
    end)

    run = run_fixture(%{runtime_class: :session, status: :running})

    attempt =
      attempt_fixture(run, %{
        runtime_class: :session,
        status: :running,
        runtime_ref_id: "provider-operation://postgres-one"
      })

    task =
      RecoveryTask.new!(%{
        subject_ref: attempt.attempt_id,
        run_id: run.run_id,
        attempt_id: attempt.attempt_id,
        reason: "outcome_unknown",
        status: :pending,
        due_at: @now,
        metadata: %{
          "external_operation_ref" => attempt.runtime_ref_id,
          "effect_retry" => "prohibited",
          "recovery_state" => "outcome_unknown"
        },
        inserted_at: @now,
        updated_at: @now
      })

    assert :ok = RunStore.put_run(run)
    assert :ok = AttemptStore.put_attempt(attempt)
    assert {:ok, inserted, :inserted} = RecoveryTaskStore.put_task(task)
    assert inserted.task_id == task.task_id
    assert {:ok, existing, :existing} = RecoveryTaskStore.put_task(task)
    assert existing.task_id == task.task_id
    assert [%{task_id: task_id}] = RecoveryTaskStore.list_due(@now, 10)
    assert task_id == task.task_id

    claim_expires_at = DateTime.add(@now, 30, :second)

    assert {:ok, claimed} =
             RecoveryTaskStore.claim_task(
               task.task_id,
               "recovery-claim://one",
               @now,
               claim_expires_at
             )

    assert claimed.status == :running

    assert {:error, :not_claimable} =
             RecoveryTaskStore.claim_task(
               task.task_id,
               "recovery-claim://two",
               @now,
               claim_expires_at
             )

    assert {:error, :stale_recovery_claim} =
             RecoveryTaskStore.transition_task(
               task.task_id,
               "recovery-claim://stale",
               :resolved,
               @now,
               %{"recovery_state" => "completed"},
               @now
             )

    assert :ok = restart_repo!(:auto)
    assert {:ok, _restarted_run} = RunStore.fetch_run(run.run_id)
    assert {:ok, _restarted_attempt} = AttemptStore.fetch_attempt(attempt.attempt_id)
    assert {:ok, restarted_claim} = RecoveryTaskStore.fetch_task(task.task_id)
    assert restarted_claim.status == :running

    transitioned_at = DateTime.add(@now, 1, :second)

    assert {:ok, resolved} =
             RecoveryTaskStore.transition_task(
               task.task_id,
               "recovery-claim://one",
               :resolved,
               transitioned_at,
               %{"recovery_state" => "completed"},
               transitioned_at
             )

    assert resolved.status == :resolved
    assert resolved.metadata == %{"recovery_state" => "completed"}
    assert [] = RecoveryTaskStore.list_due(DateTime.add(@now, 60, :second), 10)

    assert :ok = restart_repo!(:auto)
    assert {:ok, restarted_resolved} = RecoveryTaskStore.fetch_task(task.task_id)
    assert restarted_resolved.status == :resolved
    assert restarted_resolved.metadata == %{"recovery_state" => "completed"}
  end
end
